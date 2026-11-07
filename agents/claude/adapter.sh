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

CLAUDE_OFFICIAL_MARKETPLACE=claude-plugins-official
CLAUDE_OFFICIAL_REPO=anthropics/claude-plugins-official

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

# Turn off auto-update for marketplace MARKET (from GitHub REPO): the
# documented "autoUpdate": false on its extraKnownMarketplaces entry in user
# settings, which wins over the default (on for claude-plugins-official) and
# the /plugin toggle. Claude Code drops the field whenever it re-adds the
# marketplace, so this runs after any add.
claude_no_auto_update() {
  json_merge "$HOME/.claude/settings.json" --arg m "$1" --arg r "$2" '
    .extraKnownMarketplaces[$m] = ((.extraKnownMarketplaces[$m] // {source: {source: "github", repo: $r}}) + {autoUpdate: false})'
}

# The commit Claude Code recorded for the user-scope install of plugin ID.
claude_installed_sha() { claude_installed_ref "$1" | awk '{ print $2 }'; }

# _claude_update MARKET ID: refresh the marketplace and reinstall the plugin
# from it (a reinstall, because Claude Code's own update skips commits that
# keep the plugin's version string). Plugin data is kept.
_claude_update() {
  claude plugin marketplace update "$1" </dev/null >/dev/null &&
    claude plugin uninstall --keep-data "$2" </dev/null >/dev/null &&
    claude plugin install "$2" </dev/null
}

# claude_settle ID ITEM: after an install, the approved version must be what
# Claude Code installed (the marketplace offers only its current commit). If
# it differs (upstream moved since the check), that commit becomes the
# approved one, with a warning.
claude_settle() {
  local cur want
  [ "$DRY_RUN" != 1 ] || return 0
  cur=$(claude_installed_sha "$1")
  want=$(approved "$2")
  _is_sha "$cur" && [ "$cur" != "$want" ] || return 0
  set_approved "$2" "$cur" ""
  warn "claude: the marketplace installed $1 at ${cur:0:12}, not ${want:0:12} (it moved since the check); ${cur:0:12} is now the approved version of $2 (the other agents follow on the next run)"
}

# Install every core/plugins.lock plugin with a claude= entry from the
# author's marketplace, with auto-update off. An installed plugin is left at
# its version; only `install.sh --update <item>` moves it to the newly
# approved commit. A plugin already installed from another marketplace is not
# installed a second time: that is a warning, and with --fix-duplicates the
# other copy is uninstalled first.
claude_plugins() {
  local markets installed name repo id mkt mrepo cur others o om dup lock_mkts item want
  markets=$(claude plugin marketplace list --json 2>/dev/null) &&
    printf '%s' "$markets" | jq -e 'type == "array"' >/dev/null 2>&1 || { warn "claude: 'plugin marketplace list --json' failed; plugins skipped"; return 0; }
  installed=$(claude plugin list --json 2>/dev/null) &&
    printf '%s' "$installed" | jq -e 'type == "array"' >/dev/null 2>&1 || { warn "claude: 'plugin list --json' failed; plugins skipped"; return 0; }
  lock_mkts=$'\n'$(plugin_ids claude | cut -f3 | sed 's/.*@//')$'\n'
  while IFS=$'\t' read -r name repo id <&3; do
    [ -n "$name" ] || continue
    mkt=${id#*@} item=$(repo_item "$repo")

    # 1. The marketplace, from the author's source, with auto-update off.
    if [ "$mkt" = "$CLAUDE_OFFICIAL_MARKETPLACE" ]; then
      mrepo=$CLAUDE_OFFICIAL_REPO
      if ! printf '%s' "$markets" | jq -e --arg m "$mkt" 'any(.[]; .name == $m)' >/dev/null; then
        act "claude: add plugin marketplace $CLAUDE_OFFICIAL_REPO" claude plugin marketplace add "$CLAUDE_OFFICIAL_REPO"
      fi
    else
      mrepo=$repo
      cur=$(printf '%s' "$markets" | jq -r --arg m "$mkt" '.[] | select(.name == $m) | "\(.source) \(.repo // .path // .url // "")"' | tr -d '\r')
      if [ -z "$cur" ]; then
        act "claude: add plugin marketplace $mkt from $repo" claude plugin marketplace add "$repo"
      elif [ "$(printf '%s' "$cur" | tr 'A-Z' 'a-z')" != "github $(printf '%s' "$repo" | tr 'A-Z' 'a-z')" ]; then
        claude_backup_plugins
        act "claude: point plugin marketplace $mkt at $repo (was ${cur#* }); its plugins stay installed" _claude_repoint "$mkt" "$repo"
      fi
    fi
    claude_no_auto_update "$mkt" "$mrepo"

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

    # 3. The plugin itself, at the approved version.
    want=$(approved "$item")
    if ! printf '%s' "$installed" | jq -e --arg id "$id" 'any(.[]; .id == $id)' >/dev/null; then
      [ "$dup" = 0 ] || continue
      if [ -z "$want" ]; then warn "claude: $item has no approved version; $id not installed"; continue; fi
      act "claude: install plugin $id" claude plugin install "$id"
      claude_settle "$id" "$item"
      continue
    fi
    cur=$(claude_installed_sha "$id")
    [ -n "$want" ] && _is_sha "$cur" && [ "$cur" != "$want" ] || continue
    if updating "$item"; then
      claude_backup_plugins
      act "claude: update plugin $id: ${cur:0:12} -> ${want:0:12} (restart Claude Code or run /reload-plugins)" _claude_update "$mkt" "$id"
      claude_settle "$id" "$item"
    else
      warn "claude: $id is installed at ${cur:0:12}, but ${want:0:12} is approved on this machine; it was left as it is (install.sh --update $item installs the newest after asking)"
    fi
  done 3< <(plugin_ids claude)

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
