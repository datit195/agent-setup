# shellcheck shell=bash
# Cursor (app and `agent` CLI). User rules live in the app UI only.

detect() { [ -d /Applications/Cursor.app ] || [ -d "$HOME/.cursor" ] || has_cmd agent; }

install() {
  local rules="$ROOT/build/AGENTS.full.md"
  if [ "$DRY_RUN" = 1 ]; then
    log "[dry-run] copy build/AGENTS.full.md to the clipboard for Cursor User Rules"
  elif [ -f "$rules" ]; then
    if clipboard_copy "$rules"; then
      log "Copied build/AGENTS.full.md to the clipboard. Paste into Cursor → Settings → Rules → User Rules"
    else
      log "NOTE: no clipboard tool worked; paste build/AGENTS.full.md into Cursor → Settings → Rules → User Rules by hand"
    fi
  fi
  shared_skills
  mcp_merge_file "$HOME/.cursor/mcp.json" '.mcpServers' '{type: "stdio", command: $c, args: $a, env: $e}'
}

# clipboard_copy FILE: copy FILE with the first clipboard tool that works.
clipboard_copy() {
  { has_cmd pbcopy && pbcopy <"$1"; } ||
    { [ -n "${WAYLAND_DISPLAY:-}" ] && has_cmd wl-copy && wl-copy <"$1"; } ||
    { has_cmd xclip && xclip -selection clipboard <"$1"; } ||
    { has_cmd xsel && xsel --clipboard --input <"$1"; } ||
    { has_cmd clip.exe && clip.exe <"$1"; }
}
