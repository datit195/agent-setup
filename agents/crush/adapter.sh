# shellcheck shell=bash
# Crush (Charm).

detect() { has_cmd crush || [ -d "$HOME/.config/crush" ]; }

install() {
  link_instructions "$HOME/.config/crush/CRUSH.md"
  shared_skills
  log "NOTE: crush MCP servers are not handled; add the core/mcp.json servers to ~/.config/crush/crush.json by hand"
}
