# shellcheck shell=bash
# GitHub Copilot CLI. Never touches ~/.copilot/config.json (it holds login data).

detect() { has_cmd copilot || [ -d "$HOME/.copilot" ]; }

install() {
  link_instructions "$HOME/.copilot/copilot-instructions.md"
  shared_skills
  mcp_merge_file "$HOME/.copilot/mcp-config.json" '.mcpServers' '{type: "local", command: $c, args: $a, env: $e, tools: ["*"]}'
}
