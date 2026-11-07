# shellcheck shell=bash
# OpenAI Codex CLI: instructions, plugins, skills, config.toml (MCP servers,
# permissions, env) and hooks.

detect() { has_cmd codex || [ -d "$HOME/.codex" ]; }

install() {
  link_instructions "$HOME/.codex/AGENTS.md"
  codex_plugins
  shared_skills
  check_skill_dups codex "$HOME/.agents/skills" "$HOME/.codex/skills"
  codex_config
  codex_hooks
}

# Add what is missing to ~/.codex/config.toml; existing values are never
# changed. Approval and sandbox settings match Claude Code's auto mode
# (on-request approvals reviewed by the auto reviewer, workspace-write sandbox
# without network). env comes from shell/env.sh; MCP servers from
# core/mcp.json ("autoApprove" -> default_tools_approval_mode = "auto").
# The vendored copies in ~/.agents/skills of the plugins Codex has natively
# are turned off with [[skills.config]] entries marked "# agent-setup", which
# the installer adds and removes itself (other entries are never touched).
codex_config() {
  local file="$HOME/.codex/config.toml" py spec cur="" new
  if ! py=$(python_cmd); then
    warn "codex: no Python 3 found; config.toml not edited (permissions, env, MCP approval)"
    if has_cmd codex; then mcp_each codex_mcp; else warn "codex: CLI not found; MCP servers skipped"; fi
    return 0
  fi
  spec=$(jq -n --slurpfile m "$MCP_JSON" --argjson env "$(shared_env_json)" --argjson dups "$(codex_dup_skills)" '
    [{table: [], key: "approval_policy", value: "on-request"},
     {table: [], key: "sandbox_mode", value: "workspace-write"},
     {table: [], key: "approvals_reviewer", value: "auto_review"}]
    + [$env | to_entries[] | {table: ["shell_environment_policy", "set"], key: .key, value: .value}]
    + [$m[0].servers // {} | to_entries[] | .key as $n | .value as $s | ["mcp_servers", $n] as $t
        | ({table: $t, key: "command", value: $s.command, new_table: true},
           {table: $t, key: "args", value: ($s.args // []), new_table: true},
           (select(($s.oldArgs // []) != []) | {table: $t, key: "args", value: ($s.args // []), old: $s.oldArgs}),
           (select(($s.env // {}) != {}) | {table: $t, key: "env", value: $s.env, new_table: true}),
           (select($s.autoApprove == true) | {table: $t, key: "default_tools_approval_mode", value: "auto"}))]
    + [{array: ["skills", "config"], marker: "agent-setup", entries: [$dups[] | {path: ., enabled: false}]}]')
  # shellcheck disable=SC2086
  if ! new=$(printf '%s' "$spec" | $py -I "$(native_path "$ROOT/lib/toml_set.py")" "$(native_path "$file")"); then
    warn "codex: could not update $(pretty "$file") (see the error above); left unchanged"
    return 0
  fi
  [ -f "$file" ] && cur=$(cat "$file")
  [ "$cur" = "$new" ] && return 0
  backup_copy_once "$file"
  act "update $(pretty "$file") (permissions, env, MCP servers, skills)" _write_file "$file" "$new"
}

# The SKILL.md paths in ~/.agents/skills of the vendored copies of plugins
# Codex has natively, as a sorted JSON array. Codex resolves symlinks in both
# a [[skills.config]] path and a loaded skill's path before it compares them
# (codex-rs/config/src/skills_config.rs, ext/skills/src/loader/host.rs), so
# the path through the link matches; the plugin's own copy has another path.
codex_dup_skills() {
  local name src skip plugin
  while IFS=$'\t' read -r name src skip plugin; do
    [ -n "$name" ] && [ -n "$plugin" ] || continue
    case ",$skip," in *",shared,"*) continue ;; esac
    [ ! -d "$ROOT/core/skills/$name" ] && native_has codex "$plugin" || continue
    native_path "$HOME/.agents/skills/$name/SKILL.md"
    printf '\n'
  done <<EOF | jq -R -s -c 'split("\n") | map(select(. != "")) | sort'
$VENDORED_SKILLS
EOF
}

# Used only without Python (config.toml is edited directly otherwise).
codex_mcp() {
  local add=(codex mcp add "$1") kv
  for kv in ${MCP_ENV[@]+"${MCP_ENV[@]}"}; do add+=(--env "$kv"); done
  add+=(-- "$2" ${MCP_ARGS[@]+"${MCP_ARGS[@]}"})
  mcp_cli_add codex "$1" codex mcp list -- "${add[@]}"
}

# Merge the core/hooks.json hooks into ~/.codex/hooks.json (same schema as
# Claude Code). The scripts run from the repo.
codex_hooks() {
  local py hooks
  py=$(python_cmd) || py=""
  hooks=$(hooks_json codex "$(native_path "$ROOT")/core/hooks" "$py" "$(hook_wrap)")
  json_merge "$HOME/.codex/hooks.json" --argjson new "$hooks" "$HOOKS_MERGE_JQ add_hooks(\$new)"
  log "NOTE: Codex runs new or changed hooks only after you trust them once: run /hooks in Codex"
}

# _codex_catalog MARKET NAME REPO SHA: the local marketplace catalog that
# pins plugin NAME to commit SHA of REPO (a Codex "url" plugin source with a
# sha), as JSON.
_codex_catalog() {
  jq -n --arg m "$1" --arg n "$2" --arg u "$(gh_url "$3")" --arg s "$4" \
    '{name: $m, plugins: [{name: $n, source: {source: "url", url: $u, sha: $s}}]}'
}

# _codex_repoint MARKET DIR: replace marketplace MARKET (added from another
# source, such as the author's Git repo) with the local catalog DIR.
_codex_repoint() { codex plugin marketplace remove "$1" </dev/null >/dev/null && codex plugin marketplace add "$2" </dev/null >/dev/null; }
_codex_reinstall() { codex plugin remove "$1" </dev/null >/dev/null; codex plugin add "$1" </dev/null; }

# A pinned local catalog in build/codex-marketplaces/ for a marketplace that
# core/plugins.lock no longer uses (superpowers-dev, renamed superpowers) is
# the installer's own: its plugins, the marketplace and the catalog are
# removed, so the new id is installed without a duplicate. Updates the
# installed and mkts lists of codex_plugins.
_codex_drop_old_catalogs() {
  local wanted base m s o
  wanted=$(plugin_ids codex | cut -f3 | sed 's/.*@//')
  base="$ROOT/build/codex-marketplaces"
  while IFS=$'\t' read -r m s <&3; do
    [ -n "$m" ] || continue
    case $s in "$base"/* | "$(native_path "$base")"/*) ;; *) continue ;; esac
    ! printf '%s\n' "$wanted" | grep -qx "$m" || continue
    for o in $(printf '%s' "$installed" | jq -r --arg m "$m" '.[] | select((.pluginId | sub(".*@"; "")) == $m) | .pluginId' | tr -d '\r'); do
      act "codex: remove plugin $o (from the old pinned catalog $m)" codex plugin remove "$o"
    done
    act "codex: remove plugin marketplace $m (old pinned catalog)" codex plugin marketplace remove "$m"
    act "remove build/codex-marketplaces/$m (old pinned catalog)" rm -rf "$base/$m"
    installed=$(printf '%s' "$installed" | jq -c --arg m "$m" 'map(select((.pluginId | sub(".*@"; "")) != $m))')
    mkts=$(printf '%s\n' "$mkts" | awk -F '\t' -v m="$m" '$1 != m')
  done 3<<EOF
$mkts
EOF
}

# Install every core/plugins.lock plugin with a codex= entry natively, from a
# local catalog in build/codex-marketplaces/<marketplace>/ that pins it to
# the approved commit. Local marketplaces are never upgraded by Codex (it
# upgrades only Git marketplaces at startup), so nothing moves until the
# approved commit does; the plugin is then reinstalled. A plugin Codex cannot
# install keeps its vendored copy in the shared skills dir. A plugin already
# installed from another marketplace is not installed twice (warning;
# --fix-duplicates removes the other copy).
codex_plugins() {
  local installed mkts name repo id mkt others o sha dir file cat src fresh
  if ! has_cmd codex; then
    log "NOTE: codex CLI not found; plugins come as vendored skills in ~/.agents/skills"
    return 0
  fi
  installed=$(codex_installed)
  if [ -z "$installed" ]; then
    warn "codex: 'plugin list --json' failed; plugins come as vendored skills"
    return 0
  fi
  mkts=$(codex plugin marketplace list --json </dev/null 2>/dev/null |
    jq -r '.marketplaces[]? | "\(.name)\t\(.marketplaceSource.source // .source // .root // "")"' 2>/dev/null | tr -d '\r' || true)
  _codex_drop_old_catalogs
  while IFS=$'\t' read -r name repo id <&3; do
    [ -n "$name" ] || continue
    mkt=${id#*@}
    sha=$(approved "$(repo_item "$repo")")
    if [ -z "$sha" ]; then
      warn "codex: $(repo_item "$repo") has no approved version; Codex gets the vendored copy of $name"
      continue
    fi
    others=$(printf '%s' "$installed" | jq -r --arg n "$name" --arg id "$id" '.[] | select(.name == $n and .pluginId != $id) | .pluginId' | tr -d '\r')
    if [ -n "$others" ]; then
      if [ "$FIX_DUPLICATES" != 1 ]; then
        native_add codex "$name"
        warn "codex: $name is already installed as $(printf '%s' "$others" | tr '\n' ' ' | sed 's/ $//'), so $id was not installed as a second copy. Switch with: codex plugin remove <that id> && codex plugin add $id (or re-run install.sh --fix-duplicates)"
        continue
      fi
      for o in $others; do
        act "codex: remove plugin $o (another copy of $name; plugins.lock uses $id)" codex plugin remove "$o"
      done
    fi

    # The pinned local catalog and the marketplace that reads it.
    dir="$ROOT/build/codex-marketplaces/$mkt"
    file="$dir/.agents/plugins/marketplace.json"
    cat=$(_codex_catalog "$mkt" "$name" "$repo" "$sha")
    fresh=0
    if [ ! -f "$file" ] || [ "$(jq -c . "$file" 2>/dev/null)" != "$(printf '%s' "$cat" | jq -c .)" ]; then
      act "write build/codex-marketplaces/$mkt (pins $name to ${sha:0:12})" _write_file "$file" "$cat"
      fresh=1
    fi
    src=$(printf '%s\n' "$mkts" | awk -F '\t' -v m="$mkt" '$1 == m { print $2; exit }')
    if ! printf '%s\n' "$mkts" | cut -f1 | grep -qx "$mkt"; then
      act "codex: add plugin marketplace $mkt (pinned local catalog)" codex plugin marketplace add "$(native_path "$dir")"
    elif [ "$src" != "$(native_path "$dir")" ] && [ "$src" != "$dir" ]; then
      backup_copy_once "$HOME/.codex/config.toml"
      act "codex: point plugin marketplace $mkt at the pinned local catalog (was ${src:-unknown})" _codex_repoint "$mkt" "$(native_path "$dir")"
      fresh=1
    fi

    # The plugin, reinstalled when its pinned commit moved.
    if ! printf '%s' "$installed" | jq -e --arg id "$id" 'any(.[]; .pluginId == $id)' >/dev/null; then
      act "codex: install plugin $id (${sha:0:12})" codex plugin add "$id"
    elif [ "$fresh" = 1 ]; then
      act "codex: reinstall plugin $id at ${sha:0:12} (restart Codex to load it)" _codex_reinstall "$id"
    fi
    if [ "$DRY_RUN" = 1 ] || codex_installed | jq -e --arg id "$id" 'any(.[]; .pluginId == $id)' >/dev/null 2>&1; then
      native_add codex "$name"
    else
      warn "codex: could not install $id; Codex gets the vendored copy of $name instead"
    fi
  done 3< <(plugin_ids codex)
}
