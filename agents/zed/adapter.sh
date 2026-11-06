# shellcheck shell=bash
# Zed. settings.json is often JSONC; json_merge then skips it with a warning.

detect() { [ -d /Applications/Zed.app ] || [ -d "$HOME/.config/zed" ]; }

install() {
  link_instructions "$HOME/.config/zed/AGENTS.md"
  shared_skills
  mcp_merge_file "$HOME/.config/zed/settings.json" '.context_servers' '{command: $c, args: $a, env: $e}'
}
