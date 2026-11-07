# shellcheck shell=bash
# JSON editing and MCP server iteration (needs jq).

_write_file() {
  local file=$1 content=$2 tmp mode
  mkdir -p "$(dirname "$file")" || return 1
  if [ -L "$file" ]; then
    # Keep the user's symlink: write through it.
    printf '%s\n' "$content" >"$file"
    return
  fi
  tmp=$(mktemp "$file.XXXXXX") || return 1
  if [ -e "$file" ]; then
    # GNU stat first: BSD stat rejects -c without printing anything.
    mode=$(stat -c %a "$file" 2>/dev/null || stat -f %Lp "$file") && chmod "$mode" "$tmp"
  else
    chmod "${NEW_FILE_MODE:-644}" "$tmp"
  fi
  printf '%s\n' "$content" >"$tmp" && mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
}

# json_merge FILE JQ_ARGS...: apply jq (args and filter) to FILE.
# Creates {} if missing, backs up once per run, writes atomically, and leaves
# the file untouched if it is not plain JSON (e.g. JSONC) or jq fails.
json_merge() {
  local file=$1 cur new; shift
  if [ -e "$file" ]; then
    if [ ! -s "$file" ]; then
      cur='{}'
    elif ! jq -e 'type == "object"' "$file" >/dev/null 2>&1; then
      warn "$(pretty "$file") is not a plain JSON object (comments?); not edited, update it by hand"
      return 0
    else
      cur=$(cat "$file")
    fi
  else
    cur='{}'
  fi
  if ! new=$(printf '%s' "$cur" | jq "$@" 2>&1); then
    warn "jq failed on $(pretty "$file"), left unchanged: $new"
    return 0
  fi
  if [ -e "$file" ] && [ "$(printf '%s' "$cur" | jq -cS .)" = "$(printf '%s' "$new" | jq -cS .)" ]; then
    return 0
  fi
  backup_copy_once "$file"
  act "update $(pretty "$file")" _write_file "$file" "$new"
}

# mcp_each CALLBACK: call CALLBACK NAME COMMAND ARGS_JSON ENV_JSON for each
# server in core/mcp.json. Also sets, for the callback's convenience:
#   MCP_ARGS  bash array of args
#   MCP_ENV   bash array of KEY=VALUE strings
#   MCP_ENV_KEYS  comma-separated env keys (safe to print; values never are)
#   MCP_OLD_ARGS  JSON array of the args older agent-setup versions wrote
#                 ("oldArgs"); a server with exactly those args is replaced
mcp_each() {
  local cb=$1 line name cmd args env a
  local file="$MCP_JSON"
  [ -f "$file" ] || return 0
  # fd 3, not stdin: an agent CLI that reads stdin must not eat the remaining servers.
  while IFS= read -r line <&3; do
    [ -n "$line" ] || continue
    name=$(jq -r '.key' <<<"$line")
    cmd=$(jq -r '.value.command' <<<"$line")
    args=$(jq -c '.value.args // []' <<<"$line")
    env=$(jq -c '.value.env // {}' <<<"$line")
    MCP_ARGS=()
    while IFS= read -r a; do MCP_ARGS+=("$a"); done < <(jq -r '.[]' <<<"$args")
    MCP_ENV=()
    while IFS= read -r a; do MCP_ENV+=("$a"); done < <(jq -r 'to_entries[] | "\(.key)=\(.value)"' <<<"$env")
    MCP_ENV_KEYS=$(jq -r 'keys | join(",")' <<<"$env")
    MCP_OLD_ARGS=$(jq -c '.value.oldArgs // []' <<<"$line")
    "$cb" "$name" "$cmd" "$args" "$env"
  done 3< <(jq -c '.servers // {} | to_entries[]' "$file")
}

# mcp_merge_file FILE JQ_PATH TEMPLATE: add every core/mcp.json server that is
# missing under JQ_PATH (e.g. .mcpServers) in FILE. TEMPLATE is a jq expression
# that may use $c (command), $a (args array) and $e (env object).
# Existing entries are never overwritten, except one that is exactly what an
# older agent-setup wrote (TEMPLATE with one of the server's "oldArgs").
mcp_merge_file() {
  local file=$1 path=$2 tmpl=$3 todo
  [ -f "$MCP_JSON" ] || return 0
  # shellcheck disable=SC2016
  local upd='($s.value.command as $c | ($s.value.env // {}) as $e
      | (($s.value.args // []) as $a | '"$tmpl"') as $new
      | [($s.value.oldArgs // [])[] as $a | '"$tmpl"'] as $old
      | ((('"$path"') // {})[$s.key]) as $have
      | if $have == null then $new elif any($old[]; . == $have) then $new else $have end)'
  if [ -e "$file" ] && [ -s "$file" ] && jq -e 'type == "object"' "$file" >/dev/null 2>&1; then
    if ! todo=$(jq -r --slurpfile m "$MCP_JSON" \
      ". as \$r | \$m[0].servers // {} | to_entries[] as \$s | \$r | select(((($path) // {})[\$s.key]) != $upd) | \$s.key" "$file" 2>&1); then
      warn "$(pretty "$file"): cannot read $path ($todo); MCP servers not added"
      return 0
    fi
  else
    todo=$(jq -r '.servers // {} | keys[]' "$MCP_JSON")
  fi
  [ -n "$todo" ] || return 0
  log "MCP servers to add or update in $(pretty "$file"): $(printf '%s' "$todo" | tr '\n' ' ')"
  json_merge "$file" --slurpfile m "$MCP_JSON" "
    reduce ((\$m[0].servers // {}) | to_entries[]) as \$s (.; ($path)[\$s.key] = $upd)"
}

# mcp_listed NAME CMD...: run a list command; 0 = NAME appears in its output,
# 1 = not listed, 2 = the command failed.
mcp_listed() {
  local name=$1 out; shift
  out=$("$@" 2>&1) || return 2
  printf '%s\n' "$out" | grep -Eq "(^|[^A-Za-z0-9_.-])$(re_escape "$name")([^A-Za-z0-9_.-]|$)"
}

# mcp_cli_add AGENT NAME LIST_CMD -- ADD_CMD...: add an MCP server through an
# agent CLI unless the list command already shows it.
mcp_cli_add() {
  local agent=$1 name=$2 list=() rc=0; shift 2
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do list+=("$1"); shift; done
  shift
  mcp_listed "$name" "${list[@]}" || rc=$?
  case $rc in
    0) return 0 ;;
    2) warn "$agent: '${list[*]}' failed; MCP server $name skipped"; return 0 ;;
  esac
  local note=""
  [ -n "$MCP_ENV_KEYS" ] && note=" (env: $MCP_ENV_KEYS)"
  act "$agent: add MCP server $name$note" "$@"
}

# Warn when a CLI cannot receive the server's env vars.
mcp_env_unsupported() {
  [ -z "$MCP_ENV_KEYS" ] || warn "$1: MCP server $2 needs env ($MCP_ENV_KEYS) which this CLI cannot set; add it by hand"
}

# mcp_auto_approve JQ_STRING: a JSON array with JQ_STRING (a jq expression
# using $n, the server name) for every core/mcp.json server marked
# "autoApprove": true. Example: mcp_auto_approve '"mcp__\($n)__*"'
mcp_auto_approve() {
  jq -c "[.servers // {} | to_entries[] | select(.value.autoApprove == true) | .key as \$n | $1]" "$MCP_JSON"
}
