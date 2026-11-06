# shellcheck shell=bash
# OpenAI Codex CLI.

detect() { has_cmd codex || [ -d "$HOME/.codex" ]; }

install() {
  link_instructions "$HOME/.codex/AGENTS.md"
  shared_skills
  if has_cmd codex; then mcp_each codex_mcp; else warn "codex: CLI not found; MCP servers skipped"; fi
}

codex_mcp() {
  local add=(codex mcp add "$1") kv
  for kv in ${MCP_ENV[@]+"${MCP_ENV[@]}"}; do add+=(--env "$kv"); done
  add+=(-- "$2" ${MCP_ARGS[@]+"${MCP_ARGS[@]}"})
  mcp_cli_add codex "$1" codex mcp list -- "${add[@]}"
}
