# shellcheck shell=bash
# Amp.

detect() { has_cmd amp || [ -d "$HOME/.config/amp" ]; }

install() {
  link_instructions "$HOME/.config/amp/AGENTS.md"
  shared_skills
  mcp_merge_file "$HOME/.config/amp/settings.json" '.["amp.mcpServers"]' '{command: $c, args: $a, env: $e}'
}
