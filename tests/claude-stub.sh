#!/usr/bin/env bash
# A stand-in for the claude CLI, used by tests/install-test.sh: it keeps the
# MCP and plugin state the installer reads in the sandbox HOME, and logs every
# command that changes it to ~/.claude-stub.log. Only the commands the
# installer runs are implemented.
set -euo pipefail
p="$HOME/.claude/plugins" known="$HOME/.claude/plugins/known_marketplaces.json" inst="$HOME/.claude/plugins/installed_plugins.json"
# Read-only commands never create files (dry runs must change nothing).
state() { cat "$1" 2>/dev/null || if [ "$1" = "$known" ]; then printf '{}'; else printf '{"version":2,"plugins":{}}'; fi; }
save() { local f=$1; shift; mkdir -p "$p"; state "$f" | jq "$@" >"$f.tmp" && mv "$f.tmp" "$f"; }
logcmd() { printf '%s\n' "$*" >>"$HOME/.claude-stub.log"; }

case "$1 $2" in
  "mcp get") grep -qx "$3" "$HOME/.claude-stub-mcp" 2>/dev/null ;;
  "mcp add") logcmd "$@"; printf '%s\n' "$5" >>"$HOME/.claude-stub-mcp" ;;
  "plugin list") state "$inst" | jq '[.plugins | to_entries[] | .key as $id | .value[] | {id: $id, version, scope, enabled: true, installPath}]' ;;
  "plugin marketplace")
    case $3 in
      list) state "$known" | jq '[to_entries[] | {name: .key, source: .value.source.source, installLocation: .value.installLocation} + (.value.source | del(.source))]' ;;
      add)
        logcmd "$@"
        if [ -d "$4" ]; then
          name=$(jq -r .name "$4/.claude-plugin/marketplace.json")
          save "$known" --arg n "$name" --arg d "$4" '.[$n] = {source: {source: "directory", path: $d}, installLocation: $d}'
        else
          # Only the official marketplace is added from GitHub; it offers the
          # commit in plugins.lock unless STUB_OFFICIAL_SHA says otherwise.
          name=${4#*/} loc="$p/marketplaces/${4#*/}"
          sha=${STUB_OFFICIAL_SHA:-$(awk -F '\t' '$5 == "official" { print $3; exit }' "$HOME/.agent-setup/agents/claude/plugins.lock")}
          mkdir -p "$loc/.claude-plugin"
          jq -n --arg n "$name" --arg s "$sha" '{name: $n, plugins: [{name: "superpowers", version: "7.0.0", source: {source: "url", url: "https://github.com/obra/superpowers.git", sha: $s}}]}' \
            >"$loc/.claude-plugin/marketplace.json"
          save "$known" --arg n "$name" --arg r "$4" --arg l "$loc" '.[$n] = {source: {source: "github", repo: $r}, installLocation: $l}'
        fi ;;
      remove)
        logcmd "$@"
        save "$known" --arg n "$4" 'del(.[$n])'
        save "$inst" --arg m "@$4" '.plugins |= with_entries(select(.key | endswith($m) | not))' ;;
      *) exit 2 ;;
    esac ;;
  "plugin install")
    logcmd "$@"
    id=$3 name=${3%@*} mkt=${3#*@}
    loc=$(state "$known" | jq -r --arg m "$mkt" '.[$m].installLocation // empty')
    entry=$(jq -c --arg n "$name" '.plugins[] | select(.name == $n)' "$loc/.claude-plugin/marketplace.json" 2>/dev/null) || true
    [ -n "$entry" ] || { echo "Plugin \"$name\" not found in marketplace \"$mkt\"" >&2; exit 1; }
    sha=$(printf '%s' "$entry" | jq -r .source.sha) ver=$(printf '%s' "$entry" | jq -r '.version // "1.0.0"')
    dir="$p/cache/$mkt/$name/$ver"
    mkdir -p "$dir/skills/$name" && printf -- '---\nname: %s\n---\n' "$name" >"$dir/skills/$name/SKILL.md"
    save "$inst" --arg id "$id" --arg d "$dir" --arg v "$ver" --arg s "$sha" \
      '.plugins[$id] = [{scope: "user", installPath: $d, version: $v, gitCommitSha: $s}]' ;;
  "plugin uninstall")
    logcmd "$@"
    id=${!#}
    save "$inst" --arg id "$id" 'del(.plugins[$id])' ;;
  *) echo "claude stub: unsupported: $*" >&2; exit 2 ;;
esac
