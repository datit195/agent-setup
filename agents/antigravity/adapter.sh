# shellcheck shell=bash
# Google Antigravity (app, IDE and `agy` CLI). Shares ~/.gemini/GEMINI.md with
# Gemini CLI; everything else lives under ~/.gemini/.

detect() {
  has_cmd agy || [ -d /Applications/Antigravity.app ] || [ -d "$HOME/.gemini/config" ] ||
    [ -d "$HOME/.gemini/antigravity-cli" ]
}

install() {
  link_instructions "$HOME/.gemini/GEMINI.md"
  link_skills "$HOME/.gemini/config/skills"
  mcp_merge_file "$HOME/.gemini/config/mcp_config.json" '.mcpServers' '{command: $c, args: $a, env: $e}'
  antigravity_hooks
  antigravity_cli_settings
}

# The "agent-setup" group in ~/.gemini/config/hooks.json, rebuilt from
# core/hooks.json; other groups are left alone. Needs Python for the shim.
antigravity_hooks() {
  local py hooks dir
  if ! py=$(python_cmd); then
    warn "antigravity: no Python 3 found; hooks not installed"
    return 0
  fi
  dir="$(native_path "$ROOT")/core/hooks"
  hooks=$(antigravity_hooks_json "$dir/antigravity-shim.py" "$dir" "$py" "$(hook_wrap)")
  json_merge "$HOME/.gemini/config/hooks.json" --argjson g "$hooks" '.["agent-setup"] = $g'
}

# CLI permissions (the app and IDE keep theirs in the UI): agentMode "auto"
# unless set, and allow the auto-approved MCP servers. The CLI rewrites this
# file, so it is merged (never linked) and a new file is private (0600).
antigravity_cli_settings() {
  NEW_FILE_MODE=600 json_merge "$HOME/.gemini/antigravity-cli/settings.json" \
    --argjson allow "$(mcp_auto_approve '"mcp(\($n)/*)"')" '
    .agentMode //= "auto"
    | .permissions.allow = (reduce $allow[] as $x ((.permissions.allow // []); if index([$x]) then . else . + [$x] end))'
}
