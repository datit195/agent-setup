# shellcheck shell=bash
# Google Antigravity. Shares ~/.gemini/GEMINI.md with Gemini CLI.

detect() { has_cmd agy || [ -d /Applications/Antigravity.app ] || [ -d "$HOME/.gemini/config" ]; }

install() {
  link_instructions "$HOME/.gemini/GEMINI.md"
  link_skills "$HOME/.gemini/config/skills"
  mcp_merge_file "$HOME/.gemini/config/mcp_config.json" '.mcpServers' '{command: $c, args: $a, env: $e}'
}
