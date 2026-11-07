#!/usr/bin/env bash
# A stand-in for the codex CLI, used by tests/install-test.sh: the plugin and
# MCP commands the installer runs, with state in ~/.codex/stub-state.json and
# every changing command logged to ~/.codex-stub.log. A marketplace added from
# a local dir is named by its .agents/plugins/marketplace.json; one added from
# owner/repo is named like the codex= ids in core/plugins.lock. A plugin from
# a local catalog is installed at the commit its source pins (its version is
# that commit); other plugins at STUB_VERSION (default 1.0.0). `plugin add`
# of the id in STUB_FAIL_ADD fails.
set -euo pipefail
f="$HOME/.codex/stub-state.json" lock="$HOME/.agent-setup/core/plugins.lock"
state() { cat "$f" 2>/dev/null || printf '{"marketplaces":{},"plugins":{},"mcp":[]}'; }
save() { mkdir -p "$(dirname "$f")"; state | jq "$@" >"$f.tmp" && mv "$f.tmp" "$f"; }
logcmd() { printf '%s\n' "$*" >>"$HOME/.codex-stub.log"; }
ver=${STUB_VERSION:-1.0.0}

case "$1 $2" in
  "mcp list") state | jq -r '.mcp[]' ;;
  "mcp add") logcmd "$@"; save --arg n "$3" '.mcp += [$n]' ;;
  "plugin list")
    state | jq '{installed: [.plugins | to_entries[] | {pluginId: .key, name: (.key | sub("@.*"; "")), marketplaceName: (.key | sub(".*@"; "")), version: .value, installed: true, enabled: true}],
      available: []}' ;;
  "plugin add")
    logcmd "$@"
    id=$3 mkt=${3#*@}
    [ "$id" != "${STUB_FAIL_ADD:-}" ] || { echo "Error: failed to install $id" >&2; exit 1; }
    src=$(state | jq -r --arg m "$mkt" '.marketplaces[$m] // empty')
    [ -n "$src" ] || { echo "Error: marketplace \`$mkt\` not found" >&2; exit 1; }
    v=$ver
    if [ -d "$src" ]; then
      v=$(jq -r --arg n "${id%@*}" '.plugins[] | select(.name == $n) | .source.sha' "$src/.agents/plugins/marketplace.json")
      [ -n "$v" ] || { echo "Error: plugin not in $mkt" >&2; exit 1; }
    fi
    save --arg id "$id" --arg v "$v" '.plugins[$id] = $v' ;;
  "plugin remove") logcmd "$@"; save --arg id "$3" 'del(.plugins[$id])' ;;
  "plugin marketplace")
    case $3 in
      list) state | jq '{marketplaces: [.marketplaces | to_entries[] | {name: .key, root: "/x", marketplaceSource: {sourceType: (if (.value | test("^https?:")) then "git" else "local" end), source: .value}}]}' ;;
      add)
        logcmd "$@"
        if [ -d "$4" ]; then
          name=$(jq -r .name "$4/.agents/plugins/marketplace.json") src=$4
        else
          name=$(grep -v '^#' "$lock" | awk -F '\t' -v r="$4" '$2 == r { s = $3; sub(/.*codex=[^@]*@/, "", s); sub(/ .*/, "", s); print s; exit }')
          src="https://github.com/$4.git"
        fi
        cur=$(state | jq -r --arg n "$name" '.marketplaces[$n] // empty')
        [ -z "$cur" ] || [ "$cur" = "$src" ] || { echo "Error: marketplace '$name' is already added from a different source; remove it before adding this source" >&2; exit 1; }
        save --arg n "$name" --arg s "$src" '.marketplaces[$n] = $s' ;;
      remove) logcmd "$@"; save --arg n "$4" 'del(.marketplaces[$n])' ;;
      *) exit 2 ;;
    esac ;;
  *) echo "codex stub: unsupported: $*" >&2; exit 2 ;;
esac
