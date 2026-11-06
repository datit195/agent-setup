# shellcheck shell=bash
# Claude Code: CLAUDE.md import stub, rules, skills, hooks, settings, MCP, plugins.

detect() { has_cmd claude || [ -d "$HOME/.claude" ]; }

install() {
  local here="$ROOT/agents/claude"
  link "$here/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  link_each "$HOME/.claude/rules" "$ROOT"/core/rules/*.md "$here"/rules/*.md
  link_skills "$HOME/.claude/skills" claude
  local s
  while IFS= read -r s; do link "$ROOT/core/hooks/$s" "$HOME/.claude/hooks/$s"; done < <(hook_scripts)
  claude_settings
  if has_cmd claude; then
    mcp_each claude_mcp
    claude_plugins
  else
    warn "claude: CLI not found; MCP servers and plugins skipped"
  fi
}

# Merge settings.base.json plus the shared parts into ~/.claude/settings.json:
# objects deep-merged (base wins on scalars), arrays unioned. Shared parts:
# env from shell/env.sh, permissions.allow for auto-approved MCP servers, and
# the hooks from core/hooks.json (an older command for the same hook script is
# replaced, see add_hooks in lib/hooks.sh).
claude_settings() {
  local base="$ROOT/agents/claude/settings.base.json" py hooks
  [ -f "$base" ] || return 0
  if ! jq -e 'type == "object"' "$base" >/dev/null 2>&1; then
    warn "claude: settings.base.json is not valid JSON; skipped"
    return 0
  fi
  if ! py=$(python_cmd); then
    py=""
    warn "claude: no Python 3 found (python3, python, py -3); the English-only hook is not registered"
  fi
  hooks=$(hooks_json claude "$(native_path "$HOME")/.claude/hooks" "$py" 1)
  json_merge "$HOME/.claude/settings.json" --slurpfile basefile "$base" --argjson hooks "$hooks" \
    --argjson env "$(shared_env_json)" --argjson allow "$(mcp_auto_approve '"mcp__\($n)__*"')" "$HOOKS_MERGE_JQ"'
    def merge($a; $b):
      if ($a | type) == "object" and ($b | type) == "object" then
        reduce ($b | keys_unsorted[]) as $k ($a; .[$k] = merge($a[$k]; $b[$k]))
      elif ($a | type) == "array" and ($b | type) == "array" then
        reduce $b[] as $x ($a; if any(.[]; . == $x) then . else . + [$x] end)
      elif $b == null then $a
      else $b end;
    ($basefile[0] | del(.hooks) | .env = ((.env // {}) + $env)
      | .permissions.allow = ((.permissions.allow // []) + $allow)) as $base
    | merge(.; $base)
    | add_hooks($hooks)'
}

claude_mcp() {
  local name=$1 cmd=$2 kv
  if claude mcp get "$name" >/dev/null 2>&1; then return 0; fi
  local add=(claude mcp add --scope user "$name")
  for kv in ${MCP_ENV[@]+"${MCP_ENV[@]}"}; do add+=(-e "$kv"); done
  add+=(-- "$cmd" ${MCP_ARGS[@]+"${MCP_ARGS[@]}"})
  local note=""
  [ -n "$MCP_ENV_KEYS" ] && note=" (env: $MCP_ENV_KEYS)"
  act "claude: add MCP server $name$note" "${add[@]}"
}

claude_plugins() {
  local markets plugins repo plugin mkt
  markets=$(claude plugin marketplace list 2>&1) || { warn "claude: 'plugin marketplace list' failed; plugins skipped"; return 0; }
  plugins=$(claude plugin list 2>&1) || { warn "claude: 'plugin list' failed; plugins skipped"; return 0; }
  while IFS=$'\t' read -r repo plugin <&3; do
    [ -n "$plugin" ] || continue
    mkt=${plugin#*@}
    if ! printf '%s\n' "$markets" | grep -Fq "($repo)" &&
      ! printf '%s\n' "$markets" | grep -Eq "[[:space:]]$(re_escape "$mkt")[[:space:]]*$"; then
      act "claude: add plugin marketplace $repo" claude plugin marketplace add "$repo"
    fi
    if ! printf '%s\n' "$plugins" | grep -Eq "[[:space:]]$(re_escape "$plugin")[[:space:]]*$"; then
      act "claude: install plugin $plugin" claude plugin install "$plugin"
    fi
  done 3< <(lock_lines "$ROOT/agents/claude/plugins.lock")
}
