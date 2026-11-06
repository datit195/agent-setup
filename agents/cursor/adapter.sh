# shellcheck shell=bash
# Cursor (app and `agent` CLI). User rules live in the app UI only.

detect() { [ -d /Applications/Cursor.app ] || [ -d "$HOME/.cursor" ] || has_cmd agent; }

install() {
  local rules="$ROOT/build/AGENTS.full.md"
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] copy build/AGENTS.full.md to the clipboard for Cursor User Rules"
  elif has_cmd pbcopy && [ -f "$rules" ]; then
    pbcopy <"$rules"
    log "Copied build/AGENTS.full.md to the clipboard. Paste into Cursor → Settings → Rules → User Rules"
  fi
  shared_skills
  mcp_merge_file "$HOME/.cursor/mcp.json" '.mcpServers' '{type: "stdio", command: $c, args: $a, env: $e}'
}
