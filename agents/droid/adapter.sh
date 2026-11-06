# shellcheck shell=bash
# Factory Droid. The global instructions path is unconfirmed.

detect() { has_cmd droid || [ -d "$HOME/.factory" ]; }

install() {
  link_instructions "$HOME/.factory/AGENTS.md"
  shared_skills
  if has_cmd droid; then mcp_each droid_mcp; else warn "droid: CLI not found; MCP servers skipped"; fi
}

# droid takes the whole command line as one string.
droid_mcp() {
  local line=$2 a
  for a in ${MCP_ARGS[@]+"${MCP_ARGS[@]}"}; do line="$line $(printf '%q' "$a")"; done
  mcp_env_unsupported droid "$1"
  mcp_cli_add droid "$1" droid mcp list -- droid mcp add "$1" "$line"
}
