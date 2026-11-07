# shellcheck shell=bash
# Google Antigravity (app, IDE and `agy` CLI). Shares ~/.gemini/GEMINI.md with
# Gemini CLI; everything else lives under ~/.gemini/. Plugins: agy plugin.

detect() {
  has_cmd agy || [ -d /Applications/Antigravity.app ] || [ -d "$HOME/.gemini/config" ] ||
    [ -d "$HOME/.gemini/antigravity-cli" ]
}

install() {
  link_instructions "$HOME/.gemini/GEMINI.md"
  antigravity_plugins
  link_skills "$HOME/.gemini/config/skills" antigravity
  check_skill_dups antigravity "$HOME/.gemini/config/skills" "$HOME/.gemini/antigravity/skills"
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

# The installed agy plugins as a JSON array of objects with a name (the shape
# of `agy plugin list --json` is read loosely), or "" when the CLI fails.
_agy_plugins() {
  agy plugin list --json </dev/null 2>/dev/null |
    jq -c '[.. | objects | select((.name | type) == "string" and has("source"))]' 2>/dev/null | tr -d '\r' || true
}

# Install every core/plugins.lock plugin with antigravity=github natively with
# `agy plugin install https://github.com/<repo>`. agy has no update command and
# does not auto-update plugins installed from GitHub, so each run reinstalls
# them (the author's documented update); a change counts only when the
# version moved. A plugin installed from another source is not replaced
# (warning; --fix-duplicates uninstalls it first). A plugin agy cannot install
# keeps its vendored copy.
antigravity_plugins() {
  local list name repo how url src before after
  if ! has_cmd agy; then
    log "NOTE: agy CLI not found; plugins come as vendored skills in ~/.gemini/config/skills"
    return 0
  fi
  list=$(_agy_plugins)
  if [ -z "$list" ]; then
    warn "antigravity: 'agy plugin list --json' failed; plugins come as vendored skills"
    return 0
  fi
  while IFS=$'\t' read -r name repo how <&3; do
    [ -n "$name" ] || continue
    [ "$how" = github ] || { warn "plugins.lock: unknown antigravity=$how for $name; skipped"; continue; }
    url="https://github.com/$repo"
    src=$(printf '%s' "$list" | jq -r --arg n "$name" '[.[] | select(.name == $n) | .source | tostring][0] // empty')
    if [ -n "$src" ]; then
      native_add antigravity "$name"
      case $(printf '%s' "$src" | tr 'A-Z' 'a-z') in
        *"$(printf '%s' "$repo" | tr 'A-Z' 'a-z')"*)
          if [ "$DRY_RUN" = 1 ]; then
            log "[dry-run] antigravity: would reinstall plugin $name from $url to update it"
            continue
          fi
          before=$(printf '%s' "$list" | jq -r --arg n "$name" '[.[] | select(.name == $n) | .version // ""][0]')
          agy plugin install "$url" </dev/null >/dev/null 2>&1 || { warn "antigravity: reinstalling $name from $url failed; kept ${before:-the installed copy}"; continue; }
          after=$(_agy_plugins | jq -r --arg n "$name" '[.[] | select(.name == $n) | .version // ""][0]')
          [ "$before" = "$after" ] || changed "antigravity: updated plugin $name: $before -> $after"
          continue ;;
      esac
      if [ "$FIX_DUPLICATES" != 1 ]; then
        warn "antigravity: $name is already installed from $src, so it was not installed from $url as well. Switch with: agy plugin uninstall $name && agy plugin install $url (or re-run install.sh --fix-duplicates)"
        continue
      fi
      act "antigravity: uninstall plugin $name (installed from $src; plugins.lock uses $url)" agy plugin uninstall "$name"
    fi
    act "antigravity: install plugin $name from $url" agy plugin install "$url"
    if [ "$DRY_RUN" = 1 ] || _agy_plugins | jq -e --arg n "$name" 'any(.[]; .name == $n)' >/dev/null 2>&1; then
      native_add antigravity "$name"
    else
      warn "antigravity: could not install $name from $url; Antigravity gets the vendored copy instead"
    fi
  done 3< <(plugin_ids antigravity)
}
