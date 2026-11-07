#!/usr/bin/env bash
# SessionStart hook: when newer versions of items agent-setup installed are
# waiting for the user's approval, add a notice to the session's context that
# asks the agent to tell the user and ask: update now, later, or skip.
# Reads the cache in ~/.agent-setup/state/ (upstream is checked at most once a
# day, with short timeouts). Prints nothing when nothing is pending. Fails
# open: never blocks and exits 0 on any error.
#   Claude Code, Codex: hookSpecificOutput.additionalContext
#   Cursor (runs the Claude Code hook as sessionStart): additional_context
#   Antigravity: through antigravity-shim.py ("session" mode -> injectSteps)
set -u
input=$(cat 2>/dev/null) || input=""
text=$(bash "$HOME/.agent-setup/install.sh" --notice </dev/null 2>/dev/null) || exit 0
[ -n "$text" ] || exit 0
jq=/usr/bin/jq
[ -x "$jq" ] || jq=jq
case $input in
  *'"cursor_version"'*) "$jq" -n --arg t "$text" '{additional_context: $t}' 2>/dev/null ;;
  *) "$jq" -n --arg t "$text" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $t}}' 2>/dev/null ;;
esac
exit 0
