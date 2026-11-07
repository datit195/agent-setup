# shellcheck shell=bash
# core/plugins.lock: the plugins each agent installs natively, and which
# agents have which plugin natively (their vendored copies are then skipped).

PLUGINS_LOCK="$ROOT/core/plugins.lock"

# plugin_ids AGENT: "name<TAB>repo<TAB>how" for every plugin with an AGENT= entry.
plugin_ids() {
  local name repo opts how
  while IFS=$'\t' read -r name repo opts; do
    [ -n "$name" ] || continue
    how=$(opt_value "$opts" "$1")
    [ -z "$how" ] || printf '%s\t%s\t%s\n' "$name" "$repo" "$how"
  done < <(lock_lines "$PLUGINS_LOCK")
}

# plugin_for_repo REPO: the plugin whose repo is REPO, or "".
plugin_for_repo() { lock_lines "$PLUGINS_LOCK" | awk -F '\t' -v r="$1" '$2 == r { print $1; exit }'; }

# Agents that have a plugin natively this run: lines "agent<TAB>plugin".
NATIVE_PLUGINS=$'\n'
native_add() { in_list "$NATIVE_PLUGINS" "$1"$'\t'"$2" || NATIVE_PLUGINS="$NATIVE_PLUGINS$1"$'\t'"$2"$'\n'; }
native_has() { in_list "$NATIVE_PLUGINS" "$1"$'\t'"$2"; }

# The installed Codex plugins (`codex plugin list --json`), or "" when the CLI
# is missing or fails.
codex_installed() {
  has_cmd codex || return 0
  codex plugin list --json </dev/null 2>/dev/null | jq -c '[.installed[]? | select(.installed != false)]' 2>/dev/null | tr -d '\r' || true
}

# Record the plugins Codex already has (any marketplace), so the shared skills
# dir, which Codex reads, skips their vendored copies. Once per run; the Codex
# adapter records its installs itself.
CODEX_SCANNED=0
codex_scan_native() {
  local installed name
  [ "$CODEX_SCANNED" = 0 ] || return 0
  CODEX_SCANNED=1
  installed=$(codex_installed)
  [ -n "$installed" ] || return 0
  while IFS=$'\t' read -r name _; do
    [ -n "$name" ] || continue
    if printf '%s' "$installed" | jq -e --arg n "$name" 'any(.[]; .name == $n)' >/dev/null 2>&1; then
      native_add codex "$name"
    fi
  done < <(plugin_ids codex)
}

# Where Claude Code keeps its plugin records.
claude_plugins_dir() { printf '%s/plugins' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; }

# "version commit" of the user-scope Claude Code install of plugin ID, or "".
claude_installed_ref() {
  jq -r --arg id "$1" '[.plugins[$id][]? | select(.scope == "user") | "\(.version // "") \(.gitCommitSha // "")"][0] // empty' \
    "$(claude_plugins_dir)/installed_plugins.json" 2>/dev/null | tr -d '\r' || true
}
