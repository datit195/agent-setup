# shellcheck shell=bash
# Devin (CLI or desktop app).

detect() { has_cmd devin || [ -d /Applications/Devin.app ] || [ -d "$HOME/.config/devin" ]; }

install() {
  link_instructions "$HOME/.config/devin/AGENTS.md"
  shared_skills
  log "NOTE: Devin also imports Claude Code's config by default, so instructions may appear twice."
  if has_cmd devin; then
    mcp_each devin_mcp
  else
    mcp_merge_file "$HOME/.config/devin/mcp_config.json" '.mcpServers' '{command: $c, args: $a, env: $e}'
  fi
}

devin_mcp() {
  mcp_env_unsupported devin "$1"
  mcp_cli_add devin "$1" devin mcp list -- devin mcp add "$1" -s user -- "$2" ${MCP_ARGS[@]+"${MCP_ARGS[@]}"}
}
