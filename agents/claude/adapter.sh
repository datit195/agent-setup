# shellcheck shell=bash
# Claude Code: CLAUDE.md import stub, rules, skills, hooks, settings, MCP, plugins.

detect() { has_cmd claude || [ -d "$HOME/.claude" ]; }

install() {
  local here="$ROOT/agents/claude"
  link "$here/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  link_each "$HOME/.claude/rules" "$ROOT"/core/rules/*.md "$here"/rules/*.md
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
  if claude mcp get "$name" >/dev/null 2>&1; then return 0; fi
  local add=(claude mcp add --scope user "$name")
  for kv in ${MCP_ENV[@]+"${MCP_ENV[@]}"}; do add+=(-e "$kv"); done
  add+=(-- "$cmd" ${MCP_ARGS[@]+"${MCP_ARGS[@]}"})
  local note=""
  [ -n "$MCP_ENV_KEYS" ] && note=" (env: $MCP_ENV_KEYS)"
  act "claude: add MCP server $name$note" "${add[@]}"
}

# Where Claude Code keeps its plugin records.
claude_plugins_dir() { printf '%s/plugins' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; }

# The commit recorded for the user-scope install of plugin ID, or "".
claude_installed_sha() {
  jq -r --arg id "$1" '[.plugins[$id][]? | select(.scope == "user") | .gitCommitSha // empty][0] // empty' \
    "$(claude_plugins_dir)/installed_plugins.json" 2>/dev/null | tr -d '\r' || true
}

# claude_catalog MARKET NAME REPO SHA: write build/claude-marketplaces/MARKET/,
# a local marketplace named like the author's whose only entry is the author's
# entry for NAME (read from the vendored commit) with its source fixed to SHA.
claude_catalog() {
  local mkt=$1 name=$2 repo=$3 sha=$4 src out tmp
  src="$ROOT/vendor/${repo%%/*}__${repo#*/}@$sha/.claude-plugin/marketplace.json"
  out="$ROOT/build/claude-marketplaces/$mkt/.claude-plugin/marketplace.json"
  if [ ! -f "$src" ]; then
    if [ "$DRY_RUN" = 1 ]; then act "write build/claude-marketplaces/$mkt (pinned to ${sha:0:12})"; return 0; fi
    warn "claude: $repo@${sha:0:12} has no .claude-plugin/marketplace.json in vendor/ (skills.lock needs a skip=claude entry on that commit); $name@$mkt skipped"
    return 1
  fi
  tmp="$TMP_DIR/catalog-$mkt.json"
  if ! jq --arg m "$mkt" --arg n "$name" --arg repo "$repo" --arg sha "$sha" '
      select(.name == $m) | {name, owner, description: "\(.description // $m) (pinned by agent-setup to \($repo)@\($sha[0:12]))",
        plugins: [.plugins[] | select(.name == $n) | .source |= (
          if type == "string" then
            (ltrimstr("./") | rtrimstr("/")) as $p
            | if $p == "" or $p == "." then {source: "github", repo: $repo, sha: $sha}
              else {source: "git-subdir", url: $repo, path: $p, sha: $sha} end
          else . + {sha: $sha} end)]}
      | select(.plugins | length == 1)' "$src" >"$tmp" 2>/dev/null || [ ! -s "$tmp" ]; then
    warn "claude: the marketplace in $repo@${sha:0:12} is not '$mkt' with a plugin '$name'; $name@$mkt skipped"
    return 1
  fi
  if [ -f "$out" ] && cmp -s "$tmp" "$out"; then return 0; fi
  act "write build/claude-marketplaces/$mkt (pinned to ${sha:0:12})" _install_file "$tmp" "$out"
}

# claude_catalog_sha MARKETS_JSON MARKET NAME: the commit MARKET's local
# catalog pins plugin NAME to, or "".
claude_catalog_sha() {
  local loc f
  loc=$(printf '%s' "$1" | jq -r --arg m "$2" '.[] | select(.name == $m) | .installLocation // empty' | tr -d '\r')
  f="$loc/.claude-plugin/marketplace.json"
  [ -n "$loc" ] && [ -f "$f" ] || f="$(claude_plugins_dir)/marketplaces/$2/.claude-plugin/marketplace.json"
  jq -r --arg n "$3" '.plugins[] | select(.name == $n) | .source.sha // empty' "$f" 2>/dev/null | tr -d '\r' || true
}

_claude_reinstall() { claude plugin uninstall --keep-data "$1" >/dev/null && claude plugin install "$1"; }

# Save Claude's plugin records before uninstalling anything.
claude_backup_plugins() {
  local f
  for f in "$HOME/.claude/settings.json" "$(claude_plugins_dir)/installed_plugins.json" "$(claude_plugins_dir)/known_marketplaces.json"; do
    backup_copy_once "$f"
  done
}

# After an install: warn when the installed commit is not the locked one.
claude_check_pin() {
  local cur
  [ "$DRY_RUN" = 1 ] && return 0
  cur=$(claude_installed_sha "$1")
  [ -z "$cur" ] || [ "$cur" = "$2" ] ||
    warn "claude: $1 is installed at ${cur:0:12}, but plugins.lock pins ${2:0:12}$3"
}

# Install every plugin in plugins.lock at its locked commit. A plugin already
# installed from another marketplace is not installed a second time: that is
# a warning, and with --fix-duplicates the other copy is uninstalled first.
claude_plugins() {
  local markets installed id repo sha ver how name mkt dir others o om dup cur offered lock_mkts
  markets=$(claude plugin marketplace list --json 2>/dev/null) &&
    printf '%s' "$markets" | jq -e 'type == "array"' >/dev/null 2>&1 || { warn "claude: 'plugin marketplace list --json' failed; plugins skipped"; return 0; }
  installed=$(claude plugin list --json 2>/dev/null) &&
    printf '%s' "$installed" | jq -e 'type == "array"' >/dev/null 2>&1 || { warn "claude: 'plugin list --json' failed; plugins skipped"; return 0; }
  lock_mkts=$'\n'$(lock_lines "$ROOT/agents/claude/plugins.lock" | cut -f1 | sed 's/.*@//')$'\n'
  while IFS=$'\t' read -r id repo sha ver how <&3; do
    [ -n "$id" ] || continue
    name=${id%@*} mkt=${id#*@}
    if ! printf '%s' "$sha" | grep -Eq '^[0-9a-f]{40}$'; then warn "plugins.lock: bad entry for '$id'; skipped"; continue; fi

    # 1. The marketplace: a pinned local catalog, or the official one.
    if [ "$how" = official ]; then
      if ! printf '%s' "$markets" | jq -e --arg m "$mkt" 'any(.[]; .name == $m)' >/dev/null; then
        act "claude: add plugin marketplace $OFFICIAL_MARKETPLACE_REPO" claude plugin marketplace add "$OFFICIAL_MARKETPLACE_REPO"
      fi
    else
      claude_catalog "$mkt" "$name" "$repo" "$sha" || continue
      dir=$(native_path "$ROOT/build/claude-marketplaces/$mkt")
      if ! printf '%s' "$markets" | jq -e --arg m "$mkt" --arg p "$dir" \
        'any(.[]; .name == $m and .source == "directory" and ((.path // "") | gsub("\\\\"; "/")) == $p)' >/dev/null; then
        # Re-points a marketplace of the same name in place; its plugins stay installed.
        act "claude: add plugin marketplace $mkt (pinned catalog)" claude plugin marketplace add "$dir"
      fi
    fi

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

    # 3. The plugin itself, at the locked commit.
    if ! printf '%s' "$installed" | jq -e --arg id "$id" 'any(.[]; .id == $id)' >/dev/null; then
      [ "$dup" = 1 ] && continue
      act "claude: install plugin $id ($ver, ${sha:0:12})" claude plugin install "$id"
      claude_check_pin "$id" "$sha" ""
      continue
    fi
    cur=$(claude_installed_sha "$id")
    [ -z "$cur" ] || [ "$cur" = "$sha" ] && continue
    offered=$sha
    if [ "$how" = official ]; then
      offered=$(claude_catalog_sha "$markets" "$mkt" "$name")
    fi
    if [ "$offered" = "$sha" ]; then
      act "claude: reinstall plugin $id at ${sha:0:12} (installed: ${cur:0:12})" _claude_reinstall "$id"
      claude_check_pin "$id" "$sha" ""
    else
      warn "claude: $id is installed at ${cur:0:12}, plugins.lock pins ${sha:0:12}, and the $mkt marketplace offers ${offered:+${offered:0:12}}${offered:-an unknown commit}. Review the new version with install.sh --update, or run: claude plugin marketplace update $mkt && claude plugin update $id"
    fi
  done 3< <(lock_lines "$ROOT/agents/claude/plugins.lock")
}

# Claude plugin skills as check_skill_dups extra lines: "name<TAB>dir<TAB>1p"
# for plugins in plugins.lock, "0p" for other user-scope plugins.
claude_plugin_skills() {
  local id path d flag ids
  ids=$'\n'$(lock_lines "$ROOT/agents/claude/plugins.lock" | cut -f1)$'\n'
  jq -r '.plugins | to_entries[] | .key as $id | .value[] | select(.scope == "user") | "\($id)\t\(.installPath)"' \
    "$(claude_plugins_dir)/installed_plugins.json" 2>/dev/null | tr -d '\r' |
    while IFS=$'\t' read -r id path; do
      if in_list "$ids" "$id"; then flag=1p; else flag=0p; fi
      for d in "$path"/skills/*/; do
        [ -f "$d/SKILL.md" ] && printf '%s\t%s\t%s\n' "$(basename "$d")" "${d%/}" "$flag"
      done
    done
}
