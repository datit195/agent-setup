# shellcheck shell=bash
# Cursor (app and `agent` CLI). User rules live in the app UI only. Hooks come
# from ~/.claude/settings.json, which Cursor imports (third-party hooks).

detect() {
  [ -d /Applications/Cursor.app ] || [ -d "$HOME/.cursor" ] || has_cmd agent || has_cmd cursor ||
    [ -n "${CURSOR_CONFIG_DIR:-}" ]
}

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
  check_skill_dups cursor "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.codex/skills" "$HOME/.cursor/skills"
  mcp_merge_file "$HOME/.cursor/mcp.json" '.mcpServers' '{type: "stdio", command: $c, args: $a, env: $e}'
  cursor_cli_config
}

# The CLI config: $CURSOR_CONFIG_DIR, else $XDG_CONFIG_HOME/cursor on Linux
# when XDG_CONFIG_HOME is set, else ~/.cursor.
cursor_cli_config_path() {
  if [ -n "${CURSOR_CONFIG_DIR:-}" ]; then
    printf '%s/cli-config.json' "$CURSOR_CONFIG_DIR"
  elif { [ "$OS" = linux ] || [ "$OS" = wsl ]; } && [ -n "${XDG_CONFIG_HOME:-}" ]; then
    printf '%s/cursor/cli-config.json' "$XDG_CONFIG_HOME"
  else
    printf '%s/.cursor/cli-config.json' "$HOME"
  fi
}

# CLI permissions: auto-review approvals (like Claude Code's auto mode) unless
# an approval mode is set, and allow the auto-approved MCP servers. A missing
# file is created with the minimal fields the CLI writes itself.
cursor_cli_config() {
  json_merge "$(cursor_cli_config_path)" --argjson allow "$(mcp_auto_approve '"Mcp(\($n):*)"')" '
    .version //= 1
    | .editor //= {vimMode: false}
    | .approvalMode //= "auto-review"
    | .permissions.deny //= []
    | .permissions.allow = (reduce $allow[] as $x ((.permissions.allow // []); if index([$x]) then . else . + [$x] end))'
}

# clipboard_copy FILE: copy FILE with the first clipboard tool that works.
clipboard_copy() {
  { has_cmd pbcopy && pbcopy <"$1"; } ||
    { [ -n "${WAYLAND_DISPLAY:-}" ] && has_cmd wl-copy && wl-copy <"$1"; } ||
    { has_cmd xclip && xclip -selection clipboard <"$1"; } ||
    { has_cmd xsel && xsel --clipboard --input <"$1"; } ||
    { has_cmd clip.exe && clip.exe <"$1"; }
}
