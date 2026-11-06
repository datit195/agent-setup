# shellcheck shell=bash
# Zed. settings.json is often JSONC; json_merge then skips it with a warning.

# Zed's config dir: %APPDATA%\Zed on Windows, ~/.config/zed elsewhere.
zed_dir() {
  if [ "$OS" = windows ] && [ -n "${APPDATA:-}" ]; then
    printf '%s/Zed' "$(cygpath -u "$APPDATA")"
  else
    printf '%s/.config/zed' "$HOME"
  fi
}

detect() { [ -d /Applications/Zed.app ] || [ -d "$(zed_dir)" ]; }

install() {
  link_instructions "$(zed_dir)/AGENTS.md"
  shared_skills
  mcp_merge_file "$(zed_dir)/settings.json" '.context_servers' '{command: $c, args: $a, env: $e}'
}
