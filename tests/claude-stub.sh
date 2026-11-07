#!/usr/bin/env bash
# A stand-in for the claude CLI, used by tests/install-test.sh: it keeps the
# MCP and plugin state the installer reads in the sandbox HOME, and logs every
# command that changes it to ~/.claude-stub.log. Only the commands the
# installer runs are implemented. Like Claude Code, `plugin marketplace add`
# writes the marketplace into extraKnownMarketplaces in user settings (without
# autoUpdate) and refuses a source that disagrees with that entry.
# STUB_VERSION (default 1.0.0) is the version every marketplace offers when it
# is added or updated.
set -euo pipefail
p="$HOME/.claude/plugins" known="$HOME/.claude/plugins/known_marketplaces.json" inst="$HOME/.claude/plugins/installed_plugins.json"
settings="$HOME/.claude/settings.json" mcp="$HOME/.claude.json"
# Read-only commands never create files (dry runs must change nothing).
state() { cat "$1" 2>/dev/null || case $1 in "$inst") printf '{"version":2,"plugins":{}}' ;; *) printf '{}' ;; esac; }
save() { local f=$1; shift; mkdir -p "$(dirname "$f")"; state "$f" | jq "$@" >"$f.tmp" && mv "$f.tmp" "$f"; }
logcmd() { printf '%s\n' "$*" >>"$HOME/.claude-stub.log"; }
lock="$HOME/.agent-setup/core/plugins.lock"

# catalog NAME LOC: write the marketplace catalog: every core/plugins.lock
# plugin whose claude= id is in marketplace NAME, at STUB_VERSION.
catalog() {
  mkdir -p "$2/.claude-plugin"
  grep -v '^#' "$lock" | awk -F '\t' -v m="$1" '{ if (match($3, "claude=[^ ]*@" m "( |$)")) { s = substr($3, RSTART + 7, RLENGTH - 7); sub(/@.*/, "", s); print s "\t" $2 } }' |
    jq -Rn --arg n "$1" --arg v "${STUB_VERSION:-1.0.0}" \
      '{name: $n, plugins: [inputs | split("\t") | {name: .[0], version: $v, source: {source: "github", repo: .[1]}}]}' >"$2/.claude-plugin/marketplace.json"
}

case "$1 $2" in
  "mcp get") state "$mcp" | jq -e --arg n "$3" '.mcpServers | has($n)' >/dev/null ;;
  "mcp add")
    logcmd "$@"
    name=$5; shift 6
    args=$(if [ $# -gt 1 ]; then printf '%s\n' "${@:2}"; fi | jq -Rsc 'split("\n") | map(select(. != ""))')
    save "$mcp" --arg n "$name" --arg c "$1" --argjson a "$args" '.mcpServers[$n] = {type: "stdio", command: $c, args: $a, env: {}}' ;;
  "mcp remove") logcmd "$@"; save "$mcp" --arg n "${!#}" 'del(.mcpServers[$n])' ;;
  "plugin list") state "$inst" | jq '[.plugins | to_entries[] | .key as $id | .value[] | {id: $id, version, scope, enabled: true, installPath}]' ;;
  "plugin marketplace")
    case $3 in
      list) state "$known" | jq '[to_entries[] | {name: .key, source: .value.source.source, installLocation: .value.installLocation} + (.value.source | del(.source))]' ;;
      add)
        logcmd "$@"
        if [ -d "$4" ]; then
          name=$(jq -r .name "$4/.claude-plugin/marketplace.json") src=$(jq -n --arg d "$4" '{source: "directory", path: $d}') loc=$4
        else
          if [ "$4" = anthropics/claude-plugins-official ]; then name=claude-plugins-official; else
            name=$(grep -v '^#' "$lock" | awk -F '\t' -v r="$4" '$2 == r { s = $3; sub(/.*claude=[^@]*@/, "", s); sub(/ .*/, "", s); print s; exit }')
          fi
          src=$(jq -n --arg r "$4" '{source: "github", repo: $r}') loc="$p/marketplaces/$name"
        fi
        if state "$settings" | jq -e --arg n "$name" --argjson s "$src" '.extraKnownMarketplaces[$n] and .extraKnownMarketplaces[$n].source != $s' >/dev/null; then
          echo "Cannot add marketplace \"$name\": its source doesn't match its extraKnownMarketplaces entry" >&2
          exit 1
        fi
        [ -d "$4" ] || catalog "$name" "$loc"
        save "$known" --arg n "$name" --argjson s "$src" --arg l "$loc" '.[$n] = {source: $s, installLocation: $l}'
        # Official marketplaces are known by name and get no settings entry.
        [ "$name" = claude-plugins-official ] || save "$settings" --arg n "$name" --argjson s "$src" '.extraKnownMarketplaces[$n] = {source: $s}' ;;
      update)
        logcmd "$@"
        loc=$(state "$known" | jq -r --arg m "$4" '.[$m].installLocation // empty')
        [ -n "$loc" ] || { echo "Marketplace '$4' not found" >&2; exit 1; }
        catalog "$4" "$loc" ;;
      remove)
        logcmd "$@"
        save "$known" --arg n "$4" 'del(.[$n])'
        save "$settings" --arg n "$4" 'del(.extraKnownMarketplaces[$n])'
        save "$inst" --arg m "@$4" '.plugins |= with_entries(select(.key | endswith($m) | not))' ;;
      *) exit 2 ;;
    esac ;;
  "plugin install" | "plugin update")
    id=$3 name=${3%@*} mkt=${3#*@}
    loc=$(state "$known" | jq -r --arg m "$mkt" '.[$m].installLocation // empty')
    entry=$(jq -c --arg n "$name" '.plugins[] | select(.name == $n)' "$loc/.claude-plugin/marketplace.json" 2>/dev/null) || true
    [ -n "$entry" ] || { echo "Plugin \"$name\" not found in marketplace \"$mkt\"" >&2; exit 1; }
    ver=$(printf '%s' "$entry" | jq -r '.version // "1.0.0"')
    if [ "$2" = update ]; then
      cur=$(state "$inst" | jq -r --arg id "$id" '.plugins[$id][0].version // empty')
      [ -n "$cur" ] || { echo "Plugin \"$id\" is not installed" >&2; exit 1; }
      [ "$cur" != "$ver" ] || { echo "$name is already at the latest version ($ver)."; exit 0; }
    fi
    logcmd "$@"
    dir="$p/cache/$mkt/$name/$ver"
    mkdir -p "$dir/skills/$name" && printf -- '---\nname: %s\n---\n' "$name" >"$dir/skills/$name/SKILL.md"
    save "$inst" --arg id "$id" --arg d "$dir" --arg v "$ver" --arg s "$(printf '%s' "$id$ver" | cksum | cut -d' ' -f1)" \
      '.plugins[$id] = [{scope: "user", installPath: $d, version: $v, gitCommitSha: $s}]'
    save "$settings" --arg id "$id" '.enabledPlugins[$id] = true' ;;
  "plugin uninstall")
    logcmd "$@"
    id=${!#}
    save "$inst" --arg id "$id" 'del(.plugins[$id])' ;;
  *) echo "claude stub: unsupported: $*" >&2; exit 2 ;;
esac
