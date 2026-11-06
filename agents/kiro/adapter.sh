# shellcheck shell=bash
# Kiro (IDE and kiro-cli).

detect() { has_cmd kiro-cli || [ -d /Applications/Kiro.app ] || [ -d "$HOME/.kiro" ]; }

install() {
  link_instructions "$HOME/.kiro/steering/AGENTS.md"
  link_skills "$HOME/.kiro/skills"
  mcp_merge_file "$HOME/.kiro/settings/mcp.json" '.mcpServers' '{command: $c, args: $a, env: $e}'
}
