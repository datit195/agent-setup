#!/usr/bin/env bash
# Run install.sh in a sandbox HOME and check the results. Used by CI
# (.github/workflows/install-test.yml); safe to run locally, it never touches
# the real HOME. Extra arguments go to every install.sh run.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
os=$(. "$repo/lib/common.sh" && printf '%s' "$OS")
agents="claude,codex,cursor,gemini,antigravity,copilot,opencode,devin,amp,kiro,cline,droid,zed,crush"

HOME=$(mktemp -d "${TMPDIR:-/tmp}/agent-setup-home.XXXXXX")
HOME=$(cd "$HOME" && pwd -P)
export HOME
if [ "$os" = windows ]; then
  export APPDATA="$HOME/AppData/Roaming"
  HOME_NATIVE=$(cygpath -m "$HOME")
else
  HOME_NATIVE=$HOME
fi
echo "OS: $os  sandbox HOME: $HOME"

# Copy the work tree without generated dirs.
mkdir -p "$HOME/.agent-setup"
(cd "$repo" && tar -cf - --exclude=./build --exclude=./vendor .) | (cd "$HOME/.agent-setup" && tar -xf -)

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }
out="$HOME/.install-test-out"
run() { "$HOME/.agent-setup/install.sh" --agents "$agents" "$@" >"$out" 2>&1 || { cat "$out"; fail "install.sh $* exited non-zero"; }; cat "$out"; }
# Every path under HOME with a checksum, except the repo's .git, the test
# output and the macOS Python cache (~/Library/Caches).
snapshot() {
  (cd "$HOME" && find . \( -path ./.agent-setup/.git -o -path ./.install-test-out -o -path ./Library \) -prune -o -print | LC_ALL=C sort |
    while IFS= read -r p; do if [ -f "$p" ] && [ ! -L "$p" ]; then printf '%s %s\n' "$p" "$(cksum <"$p")"; else printf '%s\n' "$p"; fi; done)
}

echo "== dry run on a fresh HOME"
before=$(snapshot)
run --dry-run --skip-tools "$@"
[ "$before" = "$(snapshot)" ] || fail "--dry-run changed files on a fresh HOME"
pass "dry run on a fresh HOME changed nothing"

echo "== first run"
run --yes --skip-tools "$@"
grep -q 'change(s) made' "$out" || fail "no summary in first run"
pass "first run succeeded"

echo "== second run"
run --yes --skip-tools "$@"
grep -q '^0 change(s) made' "$out" || fail "second run made changes"
pass "second run made 0 changes"

echo "== dry run after install"
before=$(snapshot)
run --dry-run --skip-tools "$@"
grep -q '^Dry run: 0 change(s) would be made' "$out" || fail "dry run after install would make changes"
[ "$before" = "$(snapshot)" ] || fail "--dry-run changed files"
pass "dry run after install: 0 changes, nothing changed"

echo "== results"
for f in .claude/CLAUDE.md .claude/rules/language.md .claude/rules/claude-extras.md .claude/hooks/issue-branch-guard.sh \
  .claude/hooks/english-only-warn.py .claude/skills/anatomy/SKILL.md .agents/skills/anatomy/SKILL.md \
  .agents/skills/impeccable/SKILL.md .codex/AGENTS.md .gemini/GEMINI.md .config/opencode/AGENTS.md; do
  [ -f "$HOME/$f" ] || fail "missing ~/$f"
done
grep -q '^@~/.agent-setup/core/AGENTS.md' "$HOME/.claude/CLAUDE.md" || fail "~/.claude/CLAUDE.md is not the import stub"
if [ "$os" = windows ]; then zed="$APPDATA/Zed"; else zed="$HOME/.config/zed"; fi
[ -f "$zed/AGENTS.md" ] || fail "missing Zed AGENTS.md in $zed"
if [ "$os" = macos ]; then rc=.zshrc; else rc=.bashrc; fi
grep -Fq '.agent-setup/shell/env.sh' "$HOME/$rc" || fail "~/$rc does not source shell/env.sh"
pass "key files exist (shell rc: ~/$rc)"

settings="$HOME/.claude/settings.json"
py_cmd=$(jq -r '.hooks.PreToolUse[].hooks[].command | select(test("english-only-warn"))' "$settings")
guard_cmd=$(jq -r '.hooks.PreToolUse[].hooks[].command | select(test("issue-branch-guard"))' "$settings")
echo "english-only hook: $py_cmd"
echo "guard hook:        $guard_cmd"
[ -n "$py_cmd" ] && [ -n "$guard_cmd" ] || fail "hooks missing in settings.json"
case "$py_cmd $guard_cmd" in *__PYTHON__* | *__HOME__*) fail "unresolved placeholder in hook commands" ;; esac
case "$py_cmd" in *"$HOME_NATIVE/.claude/hooks/english-only-warn.py") ;; *) fail "english-only hook path is not under HOME" ;; esac
pass "settings.json hooks resolved"

echo "== hook commands (run with bash, as Claude Code does)"
res=$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x.md","content":"Xin chào thế giới"}}' | bash -c "$py_cmd")
case "$res" in *additionalContext*) ;; *) fail "english-only hook gave no warning: $res" ;; esac
pass "english-only hook warns on Vietnamese"

proj="$HOME/proj"
mkdir -p "$proj"
git -C "$proj" init -q -b master
git -C "$proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$proj" remote add origin https://github.com/example/proj.git
input=$(printf '{"tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s/a.txt"}}' "$HOME_NATIVE/proj" "$HOME_NATIVE/proj")
rc=0
printf '%s' "$input" | bash -c "$guard_cmd" 2>/dev/null || rc=$?
[ "$rc" = 2 ] || fail "guard hook should block on master (exit $rc)"
git -C "$proj" switch -q -c feat/1-x
rc=0
printf '%s' "$input" | bash -c "$guard_cmd" || rc=$?
[ "$rc" = 0 ] || fail "guard hook should allow a feature branch (exit $rc)"
pass "guard hook blocks master, allows feature branch"

echo "ALL CHECKS PASSED ($os)"
