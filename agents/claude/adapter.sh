# shellcheck shell=bash
# Claude Code: CLAUDE.md import stub, rules, skills, hooks, settings, MCP, plugins.

detect() { has_cmd claude || [ -d "$HOME/.claude" ]; }

install() {
  local here="$ROOT/agents/claude"
  link "$here/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
  link_each "$HOME/.claude/rules" "$ROOT"/core/rules/*.md "$here"/rules/*.md
  link_skills "$HOME/.claude/skills"
  link_each "$HOME/.claude/hooks" "$here"/hooks/*
  claude_settings
  if has_cmd claude; then
    mcp_each claude_mcp
    claude_plugins
  else
    warn "claude: CLI not found; MCP servers and plugins skipped"
  fi
}

# Merge settings.base.json into ~/.claude/settings.json: objects deep-merged
# (base wins on scalars), arrays unioned, hook entries added only when none of
# their commands is already registered for that event.
claude_settings() {
  local base="$ROOT/agents/claude/settings.base.json"
  [ -f "$base" ] || return 0
  if ! jq -e 'type == "object"' "$base" >/dev/null 2>&1; then
    warn "claude: settings.base.json is not valid JSON; skipped"
    return 0
  fi
  json_merge "$HOME/.claude/settings.json" --slurpfile basefile "$base" --arg home "$HOME" '
    def merge($a; $b):
      if ($a | type) == "object" and ($b | type) == "object" then
        reduce ($b | keys_unsorted[]) as $k ($a; .[$k] = merge($a[$k]; $b[$k]))
      elif ($a | type) == "array" and ($b | type) == "array" then
        reduce $b[] as $x ($a; if any(.[]; . == $x) then . else . + [$x] end)
      elif $b == null then $a
      else $b end;
    def cmds: [.[]?.hooks[]?.command];
    ($basefile[0] | walk(if type == "string" then gsub("__HOME__"; $home) else . end)) as $base
    | merge(.; $base | del(.hooks))
    | reduce (($base.hooks // {}) | to_entries[]) as $ev (.;
        .hooks[$ev.key] = reduce $ev.value[] as $entry ((.hooks[$ev.key] // []);
          if ([$entry.hooks[]?.command] - cmds | length) < ([$entry.hooks[]?.command] | length)
          then . else . + [$entry] end))'
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
