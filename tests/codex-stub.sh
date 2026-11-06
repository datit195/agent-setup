#!/usr/bin/env bash
# A stand-in for the codex CLI, used by tests/install-test.sh: the plugin and
# MCP commands the installer runs, with state in ~/.codex/stub-state.json and
# every changing command logged to ~/.codex-stub.log. A marketplace added from
# owner/repo is named like the codex= ids in core/plugins.lock. The built-in
# openai-curated marketplace is empty unless STUB_CODEX_CURATED=1 (as before
# Codex has synced it). Plugins install at STUB_VERSION (default 1.0.0), and
# `plugin marketplace upgrade` moves installed plugins to it.
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
    state | jq --arg c "${STUB_CODEX_CURATED:-0}" '{installed: [.plugins | to_entries[] | {pluginId: .key, name: (.key | sub("@.*"; "")), marketplaceName: (.key | sub(".*@"; "")), version: .value, installed: true, enabled: true}],
      available: (if $c == "1" then [{pluginId: "superpowers@openai-curated", name: "superpowers", marketplaceName: "openai-curated", installed: false}] else [] end)}' ;;
  "plugin add")
    logcmd "$@"
    id=$3 mkt=${3#*@}
    if [ "$mkt" = openai-curated ]; then
      [ "${STUB_CODEX_CURATED:-0}" = 1 ] || { echo "Error: plugin \`${id%@*}\` was not found in marketplace \`$mkt\`" >&2; exit 1; }
    else
      state | jq -e --arg m "$mkt" '.marketplaces | has($m)' >/dev/null || { echo "Error: marketplace \`$mkt\` not found" >&2; exit 1; }
    fi
    save --arg id "$id" --arg v "$ver" '.plugins[$id] = $v' ;;
  "plugin remove") logcmd "$@"; save --arg id "$3" 'del(.plugins[$id])' ;;
  "plugin marketplace")
    case $3 in
      list) state | jq '{marketplaces: [.marketplaces | to_entries[] | {name: .key, root: "/x", marketplaceSource: {sourceType: "git", source: .value}}]}' ;;
      add)
        logcmd "$@"
        name=$(grep -v '^#' "$lock" | awk -F '\t' -v r="$4" '$2 == r { s = $3; sub(/.*codex=[^@]*@/, "", s); sub(/ .*/, "", s); print s; exit }')
        save --arg n "$name" --arg s "https://github.com/$4.git" '.marketplaces[$n] = $s' ;;
      upgrade) logcmd "$@"; save --arg v "$ver" '.plugins |= with_entries(if (.key | endswith("@openai-curated")) then . else .value = $v end)' ;;
      *) exit 2 ;;
    esac ;;
  *) echo "codex stub: unsupported: $*" >&2; exit 2 ;;
esac
