# shellcheck shell=bash
# Claude Code: CLAUDE.md import stub, rules, skills, hooks, settings, MCP, plugins.

detect() { has_cmd claude || [ -d "$HOME/.claude" ]; }

install() {
  local here="$ROOT/agents/claude"
  link "$here/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  link_each "$HOME/.claude/rules" "$ROOT"/core/rules/*.md "$here"/rules/*.md
  # Claude Code gets every core/plugins.lock plugin with a claude= entry as a
  # plugin, never as vendored skills.
  local name
  while IFS=$'\t' read -r name _; do native_add claude "$name"; done < <(plugin_ids claude)
  link_skills "$HOME/.claude/skills" claude
  local s
  while IFS= read -r s; do link "$ROOT/core/hooks/$s" "$HOME/.claude/hooks/$s"; done < <(hook_scripts)
  claude_settings
  if has_cmd claude; then
    mcp_each claude_mcp
    claude_plugins
  else
    warn "claude: CLI not found; MCP servers and plugins skipped"
  fi
  EXTRA_SKILLS=$(claude_plugin_skills)$'\n' check_skill_dups claude "$HOME/.claude/skills"
}

# Merge settings.base.json plus the shared parts into ~/.claude/settings.json:
# objects deep-merged (base wins on scalars), arrays unioned. Shared parts:
# env from shell/env.sh, permissions.allow for auto-approved MCP servers, and
# the hooks from core/hooks.json (an older command for the same hook script is
# replaced, see add_hooks in lib/hooks.sh).
claude_settings() {
  local base="$ROOT/agents/claude/settings.base.json" py hooks
  [ -f "$base" ] || return 0
  if ! jq -e 'type == "object"' "$base" >/dev/null 2>&1; then
    warn "claude: settings.base.json is not valid JSON; skipped"
    return 0
  fi
  if ! py=$(python_cmd); then
    py=""
    warn "claude: no Python 3 found (python3, python, py -3); the English-only hook is not registered"
  fi
  hooks=$(hooks_json claude "$(native_path "$HOME")/.claude/hooks" "$py" 1)
  json_merge "$HOME/.claude/settings.json" --slurpfile basefile "$base" --argjson hooks "$hooks" \
    --argjson env "$(shared_env_json)" --argjson allow "$(mcp_auto_approve '"mcp__\($n)__*"')" "$HOOKS_MERGE_JQ"'
    def merge($a; $b):
      if ($a | type) == "object" and ($b | type) == "object" then
        reduce ($b | keys_unsorted[]) as $k ($a; .[$k] = merge($a[$k]; $b[$k]))
      elif ($a | type) == "array" and ($b | type) == "array" then
        reduce $b[] as $x ($a; if any(.[]; . == $x) then . else . + [$x] end)
      elif $b == null then $a
      else $b end;
    ($basefile[0] | del(.hooks) | .env = ((.env // {}) + $env)
      | .permissions.allow = ((.permissions.allow // []) + $allow)) as $base
    | merge(.; $base)
    | add_hooks($hooks)'
}

claude_mcp() {
  local name=$1 cmd=$2 kv
  local add=(claude mcp add --scope user "$name")
  for kv in ${MCP_ENV[@]+"${MCP_ENV[@]}"}; do add+=(-e "$kv"); done
  add+=(-- "$cmd" ${MCP_ARGS[@]+"${MCP_ARGS[@]}"})
  if claude mcp get "$name" >/dev/null 2>&1; then
    if claude_mcp_old "$name" "$cmd"; then
      act "claude: replace MCP server $name (an older agent-setup value) with: $cmd ${MCP_ARGS[*]-}" _claude_mcp_replace "$name" "${add[@]}"
    fi
    return 0
  fi
  local note=""
  [ -n "$MCP_ENV_KEYS" ] && note=" (env: $MCP_ENV_KEYS)"
  act "claude: add MCP server $name$note" "${add[@]}"
}

# claude_mcp_old NAME CMD: is the user-scope server NAME exactly what an older
# agent-setup wrote (CMD with one of the server's "oldArgs")?
claude_mcp_old() {
  [ "$MCP_OLD_ARGS" != "[]" ] || return 1
  jq -e --arg n "$1" --arg c "$2" --argjson old "$MCP_OLD_ARGS" \
    '.mcpServers[$n] as $s | $s != null and $s.command == $c and any($old[]; . == $s.args)' \
    "${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json" >/dev/null 2>&1
}

_claude_mcp_replace() { local name=$1; shift; claude mcp remove --scope user "$name" >/dev/null && "$@"; }

# Where Claude Code keeps its plugin records.
claude_plugins_dir() { printf '%s/plugins' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; }

CLAUDE_OFFICIAL_MARKETPLACE=claude-plugins-official
CLAUDE_OFFICIAL_REPO=anthropics/claude-plugins-official

# "version commit" of the user-scope install of plugin ID, or "".
claude_installed_ref() {
  jq -r --arg id "$1" '[.plugins[$id][]? | select(.scope == "user") | "\(.version // "") \(.gitCommitSha // "")"][0] // empty' \
    "$(claude_plugins_dir)/installed_plugins.json" 2>/dev/null | tr -d '\r' || true
}

# Save Claude's plugin records before changing a marketplace or uninstalling.
claude_backup_plugins() {
  local f
  for f in "$HOME/.claude/settings.json" "$(claude_plugins_dir)/installed_plugins.json" "$(claude_plugins_dir)/known_marketplaces.json"; do
    backup_copy_once "$f"
  done
}

# _claude_repoint MARKET REPO: point marketplace MARKET (added from another
# source, such as the old pinned catalogs in build/) at GitHub REPO in place.
# Claude Code refuses a new source that disagrees with the settings entry, so
# the entry is changed first; installed plugins and their data stay.
_claude_repoint() {
  local f="$HOME/.claude/settings.json" new
  if [ -f "$f" ]; then
    new=$(jq --arg m "$1" --arg r "$2" 'if .extraKnownMarketplaces[$m] then .extraKnownMarketplaces[$m].source = {source: "github", repo: $r} else . end' "$f") &&
      _write_file "$f" "$new" || return 1
  fi
  claude plugin marketplace add "$2" </dev/null >/dev/null
}

# Turn on auto-update for marketplace MARKET (from GitHub REPO): the documented
# "autoUpdate": true on its extraKnownMarketplaces entry in user settings.
# Claude Code drops that field whenever it re-adds the marketplace, so this
# runs after any add.
claude_auto_update() {
  json_merge "$HOME/.claude/settings.json" --arg m "$1" --arg r "$2" '
    .extraKnownMarketplaces[$m] = ((.extraKnownMarketplaces[$m] // {source: {source: "github", repo: $r}}) + {autoUpdate: true})'
}

# claude_refresh MARKETS IDS: update the marketplaces, then the plugins, with
# Claude Code's own commands (the same as its auto-update). A plugin counts as
# changed only when its installed version or commit moved.
claude_refresh() {
  local m id before after
  [ -n "$2" ] || return 0
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] claude: would update the plugin marketplaces and plugins:$(printf ' %s' $2)"
    return 0
  fi
  for m in $1; do
    claude plugin marketplace update "$m" </dev/null >/dev/null 2>&1 || warn "claude: 'plugin marketplace update $m' failed; its plugins keep their installed version"
  done
  for id in $2; do
    before=$(claude_installed_ref "$id")
    claude plugin update "$id" </dev/null >/dev/null 2>&1 || { warn "claude: 'plugin update $id' failed; kept ${before%% *}"; continue; }
    after=$(claude_installed_ref "$id")
    [ "$before" = "$after" ] || changed "claude: updated plugin $id: ${before%% *} -> ${after%% *} (restart Claude Code or run /reload-plugins)"
  done
}

# Install every core/plugins.lock plugin with a claude= entry from the
# author's marketplace, with auto-update on for third-party marketplaces, and
# update them. A plugin already installed from another marketplace is not
# installed a second time: that is a warning, and with --fix-duplicates the
# other copy is uninstalled first.
claude_plugins() {
  local markets installed name repo id mkt cur others o om dup lock_mkts refresh_m="" refresh_ids=""
  markets=$(claude plugin marketplace list --json 2>/dev/null) &&
    printf '%s' "$markets" | jq -e 'type == "array"' >/dev/null 2>&1 || { warn "claude: 'plugin marketplace list --json' failed; plugins skipped"; return 0; }
  installed=$(claude plugin list --json 2>/dev/null) &&
    printf '%s' "$installed" | jq -e 'type == "array"' >/dev/null 2>&1 || { warn "claude: 'plugin list --json' failed; plugins skipped"; return 0; }
  lock_mkts=$'\n'$(plugin_ids claude | cut -f3 | sed 's/.*@//')$'\n'
  while IFS=$'\t' read -r name repo id <&3; do
    [ -n "$name" ] || continue
    mkt=${id#*@}

    # 1. The marketplace, from the author's source.
    if [ "$mkt" = "$CLAUDE_OFFICIAL_MARKETPLACE" ]; then
      if ! printf '%s' "$markets" | jq -e --arg m "$mkt" 'any(.[]; .name == $m)' >/dev/null; then
        act "claude: add plugin marketplace $CLAUDE_OFFICIAL_REPO" claude plugin marketplace add "$CLAUDE_OFFICIAL_REPO"
      fi
    else
      cur=$(printf '%s' "$markets" | jq -r --arg m "$mkt" '.[] | select(.name == $m) | "\(.source) \(.repo // .path // .url // "")"' | tr -d '\r')
      if [ -z "$cur" ]; then
        act "claude: add plugin marketplace $mkt from $repo" claude plugin marketplace add "$repo"
      elif [ "$(printf '%s' "$cur" | tr 'A-Z' 'a-z')" != "github $(printf '%s' "$repo" | tr 'A-Z' 'a-z')" ]; then
        claude_backup_plugins
        act "claude: point plugin marketplace $mkt at $repo (was ${cur#* }); its plugins stay installed" _claude_repoint "$mkt" "$repo"
      fi
      claude_auto_update "$mkt" "$repo"
    fi
    case " $refresh_m " in *" $mkt "*) ;; *) refresh_m="$refresh_m $mkt" ;; esac

    # 2. Copies of the same plugin from other marketplaces.
    others=$(printf '%s' "$installed" | jq -r --arg n "$name" --arg id "$id" \
      '[.[] | select((.scope // "user") == "user") | .id | select(startswith($n + "@") and . != $id)] | unique[]')
    dup=0
    for o in $others; do
      om=${o#*@}
      if [ "$FIX_DUPLICATES" = 1 ]; then
        claude_backup_plugins
        act "claude: uninstall $o (another copy of $name; plugins.lock uses $id)" claude plugin uninstall "$o"
        if ! in_list "$lock_mkts" "$om" && ! printf '%s' "$installed" |
          jq -e --arg m "@$om" --arg o "$o" 'any(.[]; (.id | endswith($m)) and .id != $o)' >/dev/null; then
          act "claude: remove plugin marketplace $om (no plugins left in it)" claude plugin marketplace remove "$om"
        fi
      else
        warn "claude: $name is already installed as $o, so $id was not installed as a second copy. Switch with: claude plugin uninstall $o && claude plugin install $id (or re-run install.sh --fix-duplicates)"
        dup=1
      fi
    done

    # 3. The plugin itself.
    if printf '%s' "$installed" | jq -e --arg id "$id" 'any(.[]; .id == $id)' >/dev/null; then
      refresh_ids="$refresh_ids $id"
    elif [ "$dup" = 0 ]; then
      act "claude: install plugin $id" claude plugin install "$id"
    fi
  done 3< <(plugin_ids claude)
  claude_refresh "$refresh_m" "$refresh_ids"

  # The local pinned catalogs of earlier versions, once no marketplace uses them.
  local old="$ROOT/build/claude-marketplaces"
  if [ -d "$old" ] && [ "$DRY_RUN" != 1 ] &&
    ! claude plugin marketplace list --json 2>/dev/null | grep -q 'claude-marketplaces'; then
    act "remove build/claude-marketplaces (old pinned catalogs)" rm -rf "$old"
  fi
}

# Claude plugin skills as check_skill_dups extra lines: "name<TAB>dir<TAB>1p"
# for plugins in core/plugins.lock, "0p" for other user-scope plugins.
claude_plugin_skills() {
  local id path d flag ids
  ids=$'\n'$(plugin_ids claude | cut -f3)$'\n'
  jq -r '.plugins | to_entries[] | .key as $id | .value[] | select(.scope == "user") | "\($id)\t\(.installPath)"' \
    "$(claude_plugins_dir)/installed_plugins.json" 2>/dev/null | tr -d '\r' |
    while IFS=$'\t' read -r id path; do
      if in_list "$ids" "$id"; then flag=1p; else flag=0p; fi
      for d in "$path"/skills/*/; do
        [ -f "$d/SKILL.md" ] && printf '%s\t%s\t%s\n' "$(basename "$d")" "${d%/}" "$flag"
      done
    done
}
