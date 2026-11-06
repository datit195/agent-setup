# shellcheck shell=bash
# Gemini CLI. Shares ~/.gemini/GEMINI.md with Antigravity.

detect() { has_cmd gemini || [ -f "$HOME/.gemini/settings.json" ]; }

install() {
  link_instructions "$HOME/.gemini/GEMINI.md"
  shared_skills
  if has_cmd gemini; then mcp_each gemini_mcp; else warn "gemini: CLI not found; MCP servers skipped"; fi
}

# Options go between the positionals and "--" so args such as "-y" are not
# parsed as gemini flags.
gemini_mcp() {
  local add=(gemini mcp add -s user "$1" "$2") kv
  for kv in ${MCP_ENV[@]+"${MCP_ENV[@]}"}; do add+=(-e "$kv"); done
  [ ${#MCP_ARGS[@]} -eq 0 ] || add+=(-- "${MCP_ARGS[@]}")
  mcp_cli_add gemini "$1" gemini mcp list -- "${add[@]}"
}
