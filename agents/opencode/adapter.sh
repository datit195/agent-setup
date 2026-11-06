# shellcheck shell=bash
# OpenCode.

detect() { has_cmd opencode || [ -d "$HOME/.config/opencode" ]; }

install() {
  local major=""
  link_instructions "$HOME/.config/opencode/AGENTS.md"
  shared_skills
  if has_cmd opencode; then
    major=$(opencode --version 2>/dev/null | grep -Eo '[0-9]+' | head -n 1 || true)
  fi
  if [ -n "$major" ] && [ "$major" -ge 2 ]; then
    warn "opencode: OpenCode V2 MCP not handled; add the core/mcp.json servers manually"
    return 0
  fi
  mcp_merge_file "$HOME/.config/opencode/opencode.json" '.mcp' '{type: "local", command: ([$c] + $a), environment: $e, enabled: true}'
}
