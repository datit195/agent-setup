#!/usr/bin/env bash
# A stand-in for the agy (Antigravity) CLI, used by tests/install-test.sh: the
# plugin commands the installer runs, with state in
# ~/.gemini/stub-plugins.json and every changing command logged to
# ~/.agy-stub.log. `plugin install <dir>` installs the plugin its manifest
# (.antigravity-plugin/plugin.json or plugin.json) names, at its version;
# `plugin install <GitHub URL>` the core/plugins.lock plugin of that repo at
# STUB_VERSION (default 1.0.0).
set -euo pipefail
f="$HOME/.gemini/stub-plugins.json" lock="$HOME/.agent-setup/core/plugins.lock"
state() { cat "$f" 2>/dev/null || printf '{}'; }
save() { mkdir -p "$(dirname "$f")"; state | jq "$@" >"$f.tmp" && mv "$f.tmp" "$f"; }
logcmd() { printf '%s\n' "$*" >>"$HOME/.agy-stub.log"; }

case "$1 $2" in
  "plugin list") state | jq '{plugins: [to_entries[] | {name: .key, enabled: true, version: .value.version, source: .value.source, path: "/x"}]}' ;;
  "plugin install")
    logcmd "$@"
    if [ -d "$3" ]; then
      m=$({ cat "$3/.antigravity-plugin/plugin.json" "$3/plugin.json" 2>/dev/null || true; } | jq -s '.[0] // empty')
      [ -n "$m" ] || { echo "no plugin.json in $3" >&2; exit 1; }
      name=$(printf '%s' "$m" | jq -r .name) v=$(printf '%s' "$m" | jq -r '.version // "0"')
    else
      repo=${3#https://github.com/}
      name=$(grep -v '^#' "$lock" | awk -F '\t' -v r="$repo" '$2 == r { print $1; exit }') v=${STUB_VERSION:-1.0.0}
      [ -n "$name" ] || { echo "no plugin.json in $3" >&2; exit 1; }
    fi
    save --arg n "$name" --arg s "$3" --arg v "$v" '.[$n] = {source: $s, version: $v}' ;;
  "plugin uninstall") logcmd "$@"; save --arg n "$3" 'del(.[$n])' ;;
  *) echo "agy stub: unsupported: $*" >&2; exit 2 ;;
esac
