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

_agy_reinstall() { agy plugin uninstall "$1" </dev/null >/dev/null; agy plugin install "$2" </dev/null; }

# Install every core/plugins.lock plugin with antigravity=github natively
# from its vendor checkout, which is at the approved commit:
# `agy plugin install <dir>` (agy installs from GitHub only at the default
# branch head, and does not auto-update plugins installed by the CLI). The
# plugin is reinstalled only when the approved commit has another version
# than the installed one. A plugin installed from another source (such as the
# app) is not replaced (warning; --fix-duplicates uninstalls it first). A
# plugin agy cannot install keeps its vendored copy.
antigravity_plugins() {
  local list name repo how dir path src have want
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
    dir="$ROOT/vendor/${repo%%/*}__${repo#*/}"
    path=$(native_path "$dir")
    if [ "$DRY_RUN" != 1 ] && [ ! -d "$dir/.git" ]; then
      warn "antigravity: no checkout of $repo at an approved commit; Antigravity gets the vendored copy of $name"
      continue
    fi
    want=$(jq -r '.version // empty' "$dir/.antigravity-plugin/plugin.json" "$dir/plugin.json" 2>/dev/null | head -n 1 | tr -d '\r' || true)
    src=$(printf '%s' "$list" | jq -r --arg n "$name" '[.[] | select(.name == $n) | .source | tostring][0] // empty')
    have=$(printf '%s' "$list" | jq -r --arg n "$name" '[.[] | select(.name == $n) | .version // ""][0] // empty')
    if [ -n "$src" ]; then
      case $(printf '%s' "$src" | tr 'A-Z\\' 'a-z/') in
        "$(printf '%s' "$path" | tr 'A-Z\\' 'a-z/')"* | *"$(printf '%s' "$repo" | tr 'A-Z' 'a-z')"*)
          native_add antigravity "$name"
          [ -n "$want" ] && [ "$have" != "$want" ] || continue
          act "antigravity: reinstall plugin $name at the approved commit ($have -> $want)" _agy_reinstall "$name" "$path"
          continue ;;
      esac
      if [ "$FIX_DUPLICATES" != 1 ]; then
        native_add antigravity "$name"
        warn "antigravity: $name is already installed from $src, so it was not installed from $(pretty "$dir") as well. Switch with: agy plugin uninstall $name && agy plugin install $path (or re-run install.sh --fix-duplicates)"
        continue
      fi
      act "antigravity: uninstall plugin $name (installed from $src)" agy plugin uninstall "$name"
    fi
    act "antigravity: install plugin $name from $(pretty "$dir")${want:+ ($want)}" agy plugin install "$path"
    if [ "$DRY_RUN" = 1 ] || _agy_plugins | jq -e --arg n "$name" 'any(.[]; .name == $n)' >/dev/null 2>&1; then
      native_add antigravity "$name"
    else
      warn "antigravity: could not install $name; Antigravity gets the vendored copy instead"
    fi
  done 3< <(plugin_ids antigravity)
}
