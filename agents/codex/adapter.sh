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
codex_config() {
  local file="$HOME/.codex/config.toml" py spec cur="" new
  if ! py=$(python_cmd); then
    warn "codex: no Python 3 found; config.toml not edited (permissions, env, MCP approval)"
    if has_cmd codex; then mcp_each codex_mcp; else warn "codex: CLI not found; MCP servers skipped"; fi
    return 0
  fi
  spec=$(jq -n --slurpfile m "$ROOT/core/mcp.json" --argjson env "$(shared_env_json)" '
    [{table: [], key: "approval_policy", value: "on-request"},
     {table: [], key: "sandbox_mode", value: "workspace-write"},
     {table: [], key: "approvals_reviewer", value: "auto_review"}]
    + [$env | to_entries[] | {table: ["shell_environment_policy", "set"], key: .key, value: .value}]
    + [$m[0].servers // {} | to_entries[] | .key as $n | .value as $s | ["mcp_servers", $n] as $t
        | ({table: $t, key: "command", value: $s.command, new_table: true},
           {table: $t, key: "args", value: ($s.args // []), new_table: true},
           (select(($s.oldArgs // []) != []) | {table: $t, key: "args", value: ($s.args // []), old: $s.oldArgs}),
           (select(($s.env // {}) != {}) | {table: $t, key: "env", value: $s.env, new_table: true}),
           (select($s.autoApprove == true) | {table: $t, key: "default_tools_approval_mode", value: "auto"}))]')
  # shellcheck disable=SC2086
  if ! new=$(printf '%s' "$spec" | $py -I "$(native_path "$ROOT/lib/toml_set.py")" "$(native_path "$file")"); then
    warn "codex: could not update $(pretty "$file") (see the error above); left unchanged"
    return 0
  fi
  [ -f "$file" ] && cur=$(cat "$file")
  [ "$cur" = "$new" ] && return 0
  backup_copy_once "$file"
  act "update $(pretty "$file") (permissions, env, MCP servers)" _write_file "$file" "$new"
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

CODEX_OFFICIAL_MARKETPLACE=openai-curated

# _codex_versions: "id version" per installed plugin, for change detection.
_codex_versions() { codex_installed | jq -r '.[] | "\(.pluginId) \(.version // "")"' 2>/dev/null | LC_ALL=C sort; }

# Install every core/plugins.lock plugin with a codex= entry natively: its
# marketplace added from the author's repo (openai-curated is built in), then
# `codex plugin add`. Codex upgrades configured Git marketplaces and the
# plugins installed from them on its own at startup; this run also upgrades
# them now. A plugin Codex cannot install keeps its vendored copy in the
# shared skills dir. A plugin already installed from another marketplace is
# not installed twice (warning; --fix-duplicates removes the other copy).
codex_plugins() {
  local installed mkts name repo id mkt others o before after any=0
  CODEX_SCANNED=1
  if ! has_cmd codex; then
    log "NOTE: codex CLI not found; plugins come as vendored skills in ~/.agents/skills"
    return 0
  fi
  installed=$(codex_installed)
  if [ -z "$installed" ]; then
    warn "codex: 'plugin list --json' failed; plugins come as vendored skills"
    return 0
  fi
  mkts=$(codex plugin marketplace list --json </dev/null 2>/dev/null | jq -r '.marketplaces[]?.name' 2>/dev/null | tr -d '\r' || true)
  while IFS=$'\t' read -r name repo id <&3; do
    [ -n "$name" ] || continue
    mkt=${id#*@}
    if printf '%s' "$installed" | jq -e --arg id "$id" 'any(.[]; .pluginId == $id)' >/dev/null; then
      native_add codex "$name"
      any=1
      continue
    fi
    others=$(printf '%s' "$installed" | jq -r --arg n "$name" '.[] | select(.name == $n) | .pluginId')
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
    if [ "$mkt" = "$CODEX_OFFICIAL_MARKETPLACE" ] && ! codex plugin list --json --available </dev/null 2>/dev/null |
      jq -e --arg id "$id" 'any(.available[]?; .pluginId == $id)' >/dev/null 2>&1; then
      log "NOTE: codex: $id is not available yet (Codex syncs $mkt when it starts); Codex gets the vendored copy of $name until then"
      continue
    fi
    if [ "$mkt" != "$CODEX_OFFICIAL_MARKETPLACE" ] && ! in_list $'\n'"$mkts"$'\n' "$mkt"; then
      act "codex: add plugin marketplace $mkt from $repo" codex plugin marketplace add "$repo"
      mkts="$mkts"$'\n'"$mkt"
    fi
    act "codex: install plugin $id" codex plugin add "$id"
    if [ "$DRY_RUN" = 1 ] || codex_installed | jq -e --arg id "$id" 'any(.[]; .pluginId == $id)' >/dev/null 2>&1; then
      native_add codex "$name"
    else
      warn "codex: could not install $id; Codex gets the vendored copy of $name instead"
    fi
  done 3< <(plugin_ids codex)
  [ "$any" = 1 ] || return 0
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] codex: would upgrade the plugin marketplaces (codex plugin marketplace upgrade)"
    return 0
  fi
  before=$(_codex_versions)
  codex plugin marketplace upgrade </dev/null >/dev/null 2>&1 || warn "codex: 'plugin marketplace upgrade' failed; plugins keep their installed version"
  after=$(_codex_versions)
  [ "$before" = "$after" ] || changed "codex: plugins updated: $(printf '%s' "$after" | tr '\n' ' ')(restart Codex to load them)"
}
