# shellcheck shell=bash
# OpenAI Codex CLI: instructions, skills, config.toml (MCP servers,
# permissions, env) and hooks.

detect() { has_cmd codex || [ -d "$HOME/.codex" ]; }

install() {
  link_instructions "$HOME/.codex/AGENTS.md"
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
