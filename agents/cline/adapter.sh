# shellcheck shell=bash
# Cline CLI. Its MCP settings file also stores OAuth data, so it is only
# changed through the CLI, never edited directly.

detect() { has_cmd cline || [ -d "$HOME/.cline" ]; }

install() {
  link_instructions "$HOME/.agents/AGENTS.md"
  shared_skills
  if has_cmd cline; then mcp_each cline_mcp; else warn "cline: CLI not found; MCP servers skipped (add them in Cline)"; fi
}

cline_mcp() {
  mcp_env_unsupported cline "$1"
  mcp_cli_add cline "$1" cline mcp list -- cline mcp add "$1" --yes -- "$2" ${MCP_ARGS[@]+"${MCP_ARGS[@]}"}
}
