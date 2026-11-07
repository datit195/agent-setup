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
export GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
git config --global user.name t
git config --global user.email t@t
git config --global init.defaultBranch master
git config --global protocol.file.allow always
gitc() { git -c core.autocrlf=false "$@"; }

# Copy the work tree without generated dirs and the local state.
A="$HOME/.agent-setup"
mkdir -p "$A"
(cd "$repo" && tar -cf - --exclude=./build --exclude=./vendor --exclude=./state --exclude=./.git .) | (cd "$A" && tar -xf -)

# Fake upstream repos (https://github.com/fake/<name> is a local bare repo):
# skills repos "one" and "two", and "plug", a plugin for Claude Code and Codex.
up="$HOME/upstream"
git config --global url."file:///${HOME_NATIVE#/}/upstream/".insteadOf https://github.com/fake/
# commit_to NAME: add a commit to upstream NAME; prints the new commit.
commit_to() {
  local w="$HOME/work-$1"
  [ -d "$w" ] || gitc clone -q "$up/$1.git" "$w" 2>/dev/null
  date +%s%N >>"$w/changes" && gitc -C "$w" add -A && gitc -C "$w" commit -q -m change && gitc -C "$w" push -q origin HEAD:master
  gitc -C "$w" rev-parse HEAD
}
for n in one two plug; do
  w="$HOME/work-$n"
  mkdir -p "$w/skills/fake-$n"
  printf -- '---\nname: fake-%s\ndescription: test skill\n---\n' "$n" >"$w/skills/fake-$n/SKILL.md"
  if [ "$n" = plug ]; then mkdir -p "$w/.claude-plugin" && printf '{"name":"fakeplug","version":"1.0.0"}\n' >"$w/.claude-plugin/plugin.json"; fi
  gitc -C "$w" init -q && gitc -C "$w" add -A && gitc -C "$w" commit -q -m init
  gitc clone -q --bare "$w" "$up/$n.git"
  gitc -C "$up/$n.git" config uploadpack.allowFilter true
  gitc -C "$up/$n.git" config uploadpack.allowAnySHA1InWant true
  gitc -C "$w" remote add origin "$up/$n.git"
done
printf 'fake-one\tfake/one\tskills/fake-one\nfake-two\tfake/two\tskills/fake-two\nfake-plug\tfake/plug\tskills/fake-plug\n' >>"$A/core/skills.lock"
printf 'fakeplug\tfake/plug\tclaude=fakeplug@fakeplug codex=fakeplug@fakeplug\n' >>"$A/core/plugins.lock"

# The sandbox repo is a git checkout whose origin is a local bare repo, so the
# "origin has new commits" notice can be tested.
gitc -C "$A" init -q && gitc -C "$A" add -A && gitc -C "$A" commit -q -m sandbox
gitc clone -q --bare "$A" "$HOME/self.git"
gitc -C "$A" remote add origin "$HOME/self.git" && gitc -C "$A" fetch -q origin && gitc -C "$A" remote set-head origin master >/dev/null
gitc -C "$A" branch -q -u origin/master

# Stub claude, codex and agy CLIs on PATH, so the MCP and native plugin steps
# run (tests/*-stub.sh).
mkdir -p "$HOME/stub-bin"
for c in claude codex agy; do
  cp "$repo/tests/$c-stub.sh" "$HOME/stub-bin/$c"
  chmod +x "$HOME/stub-bin/$c"
done
export PATH="$HOME/stub-bin:$PATH"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }
out="$HOME/.install-test-out"
inst() { "$A/install.sh" "$@" >"$out" 2>&1 || { cat "$out"; fail "install.sh $* exited non-zero"; }; cat "$out"; }
run() { inst --agents "$agents" "$@"; }
# Every path under HOME with a checksum, except git dirs, the test output,
# the fake upstream and the macOS Python cache (~/Library/Caches).
snapshot() {
  (cd "$HOME" && find . \( -path ./.agent-setup/.git -o -path ./.install-test-out -o -path ./Library -o -path ./upstream -o -path ./self.git -o -name 'work-*' \) -prune -o -print | LC_ALL=C sort |
    while IFS= read -r p; do if [ -f "$p" ] && [ ! -L "$p" ]; then printf '%s %s\n' "$p" "$(cksum <"$p")"; else printf '%s\n' "$p"; fi; done)
}
approved() { jq -r --arg n "$1" '.[$n].version // empty' "$A/state/approved.json"; }
vendor_head() { git -C "$A/vendor/$1" rev-parse HEAD; }

# User values that the installer must keep, and an old-style Claude hook entry
# that it must replace (not duplicate).
# Keep XDG paths inside the sandbox (the Cursor CLI config honours it on Linux).
export XDG_CONFIG_HOME="$HOME/.xdg-config"
if [ "$os" = linux ]; then cursor_cfg="$XDG_CONFIG_HOME/cursor/cli-config.json"; else cursor_cfg="$HOME/.cursor/cli-config.json"; fi
mkdir -p "$HOME/.codex" "$(dirname "$cursor_cfg")" "$HOME/.gemini/antigravity-cli" "$HOME/.claude"
printf '# mine\nmodel = "o3"\nsandbox_mode = "read-only"\n\n[[skills.config]]\nname = "mine"\nenabled = false\n\n[mcp_servers.codegraph]\ncommand = "my-codegraph"\n' >"$HOME/.codex/config.toml"
printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo user-hook"}]}]}}' >"$HOME/.codex/hooks.json"
printf '%s\n' '{"approvalMode":"allowlist","permissions":{"allow":["Shell(ls)"]}}' >"$cursor_cfg"
printf '%s\n' '{"agentMode":"manual","theme":"mine"}' >"$HOME/.gemini/antigravity-cli/settings.json"
chmod 600 "$HOME/.gemini/antigravity-cli/settings.json"
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/bin/python3 -I %s/.claude/hooks/english-only-warn.py"}]}]}}\n' "$HOME_NATIVE" >"$HOME/.claude/settings.json"

# What earlier agent-setup versions left behind, to be migrated: playwright
# pinned to 0.0.83 (Claude Code, Cursor) or at @latest (Codex); harness
# installed from a local pinned catalog in build/claude-marketplaces/ (with
# plugin data); taste-skill in Codex from the author's Git marketplace;
# superpowers in Codex as superpowers@superpowers-dev from an old pinned
# local catalog in build/codex-marketplaces/superpowers-dev/; a
# skill link into an old vendor/<repo>@<sha> dir; and a link in ~/.cursor/skills
# to a skill of a plugin Codex has natively (now in ~/.agents/skills).
old_pw='["-y","@playwright/mcp@0.0.83"]'
printf '{"mcpServers":{"playwright":{"type":"stdio","command":"npx","args":%s,"env":{}}}}\n' "$old_pw" >"$HOME/.claude.json"
printf '\n[mcp_servers.playwright]\ncommand = "npx"\nargs = ["-y", "@playwright/mcp@latest"]\n' >>"$HOME/.codex/config.toml"
mkdir -p "$HOME/.cursor"
printf '{"mcpServers":{"playwright":{"type":"stdio","command":"npx","args":%s,"env":{}}}}\n' "$old_pw" >"$HOME/.cursor/mcp.json"
catalog="$A/build/claude-marketplaces/harness-marketplace"
mkdir -p "$catalog/.claude-plugin"
harness_head=$(git ls-remote https://github.com/revfactory/harness.git HEAD | cut -f1)
printf '{"name":"harness-marketplace","plugins":[{"name":"harness","version":"1.0.0","source":{"source":"github","repo":"revfactory/harness","sha":"%s"}}]}\n' "$harness_head" >"$catalog/.claude-plugin/marketplace.json"
claude plugin marketplace add "$catalog" >/dev/null
claude plugin install harness@harness-marketplace >/dev/null
mkdir -p "$HOME/.claude/plugins/data/harness-harness-marketplace" && echo mine >"$HOME/.claude/plugins/data/harness-harness-marketplace/keep"
codex plugin marketplace add Leonxlnx/taste-skill >/dev/null
codex plugin add taste-skill@taste-skill >/dev/null
oldcat="$A/build/codex-marketplaces/superpowers-dev"
mkdir -p "$oldcat/.agents/plugins"
printf '{"name":"superpowers-dev","plugins":[{"name":"superpowers","source":{"source":"url","url":"https://github.com/obra/superpowers.git","sha":"22f0b463e7a5e579904dd6211a520321035526f7"}}]}\n' >"$oldcat/.agents/plugins/marketplace.json"
codex plugin marketplace add "$(if [ "$os" = windows ]; then cygpath -m "$oldcat"; else printf '%s' "$oldcat"; fi)" >/dev/null
codex plugin add superpowers@superpowers-dev >/dev/null
oldvendor="$A/vendor/wheresryan22__anatomy@1482e8469b0a9e0d8cc18ea2740a01423d29ae80"
mkdir -p "$oldvendor" "$HOME/.agents/skills" && printf -- '---\nname: anatomy\n---\n' >"$oldvendor/SKILL.md"
ln -s "$oldvendor" "$HOME/.agents/skills/anatomy"
if [ "$os" != windows ]; then
  mkdir -p "$HOME/.cursor/skills" && ln -s "$A/vendor/obra__superpowers/skills/brainstorming" "$HOME/.cursor/skills/brainstorming"
fi
rm -f "$HOME/.claude-stub.log" "$HOME/.codex-stub.log"

echo "== dry run on a fresh HOME"
before=$(snapshot)
run --dry-run --skip-tools "$@"
after=$(snapshot)
[ "$before" = "$after" ] || { diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true; fail "--dry-run changed files on a fresh HOME"; }
grep -q 'fetch wheresryan22/anatomy at [0-9a-f]\{12\}' "$out" || fail "dry run does not say it fetches anatomy at the approved commit"
grep -q '^approve one [0-9a-f]\{12\} (newest upstream)' "$out" || fail "dry run does not show the first approval"
pass "dry run on a fresh HOME changed nothing"

echo "== first run"
run --yes --skip-tools "$@"
grep -q 'change(s) made' "$out" || fail "no summary in first run"
[ "$(approved one)" = "$(git -C "$up/one.git" rev-parse HEAD)" ] || fail "one is not approved at its upstream head"
[ "$(approved harness)" = "$harness_head" ] || fail "harness: the installed Claude plugin commit was not approved"
case $(approved playwright) in [0-9]*.[0-9]*) ;; *) fail "playwright not approved at a version: $(approved playwright)" ;; esac
[ "$(vendor_head fake__one)" = "$(approved one)" ] || fail "vendor/fake__one is not at the approved commit"
grep -q 'WARN: codex: superpowers is already installed' "$out" && fail "codex: the old superpowers-dev catalog was reported as a duplicate"
grep -q '^plugin remove superpowers@superpowers-dev' "$HOME/.codex-stub.log" && grep -q '^plugin marketplace remove superpowers-dev' "$HOME/.codex-stub.log" ||
  fail "codex: superpowers@superpowers-dev and its old pinned catalog were not removed"
[ ! -e "$oldcat" ] || fail "build/codex-marketplaces/superpowers-dev was not removed"
pass "first run: approves the installed versions, else the newest upstream (state/approved.json)"

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
for f in .claude/CLAUDE.md .claude/rules/language.md .claude/rules/claude-extras.md .claude/rules/coordinator-mode.md \
  .claude/hooks/issue-branch-guard.sh .claude/hooks/english-only-warn.py .claude/hooks/update-notice.sh .claude/skills/anatomy/SKILL.md \
  .agents/skills/anatomy/SKILL.md .agents/skills/impeccable/SKILL.md .agents/skills/fake-one/SKILL.md \
  .gemini/config/skills/evolve/SKILL.md .gemini/config/skills/gsap-core/SKILL.md .kiro/skills/brainstorming/SKILL.md \
  .kiro/skills/taste-skill/SKILL.md .codex/AGENTS.md .gemini/GEMINI.md .config/opencode/AGENTS.md \
  .agents/skills/taste-skill/SKILL.md .agents/skills/gsap-core/SKILL.md .agents/skills/harness/SKILL.md \
  .agents/skills/evolve/SKILL.md .agents/skills/brainstorming/SKILL.md .agents/skills/fake-plug/SKILL.md; do
  [ -f "$HOME/$f" ] || fail "missing ~/$f"
done
# No agent gets a skill twice: not from its native plugin and a vendored copy
# (Codex turns its copies in ~/.agents/skills off in config.toml, checked
# below), and Cursor gets the shared skills only from ~/.agents/skills.
for f in .claude/skills/taste-skill .claude/skills/brainstorming .claude/skills/harness .claude/skills/fake-plug \
  .gemini/config/skills/brainstorming .cursor/skills/anatomy .cursor/skills/brainstorming .cursor/skills/gsap-core \
  .cursor/skills/fake-plug; do
  [ ! -e "$HOME/$f" ] && [ ! -L "$HOME/$f" ] || fail "~/$f exists; that agent would have the skill twice"
done
if [ -L "$HOME/.agents/skills/anatomy" ]; then
  case $(readlink "$HOME/.agents/skills/anatomy") in */vendor/wheresryan22__anatomy) ;; *) fail "anatomy link not moved to the per-repo vendor dir" ;; esac
fi
[ ! -e "$oldvendor" ] || fail "the old pinned vendor dir was not removed"
for d in "$A"/vendor/*; do
  case $(basename "$d") in *@*) fail "old pinned vendor dir left: $d" ;; esac
done
grep -q "skill 'gsap-core'\|skill 'brainstorming'" "$out" && fail "a skill duplicate was reported"
pass "skills: per-repo vendor dirs, every vendored skill in ~/.agents/skills, no skill twice per agent"
grep -q 'allow_implicit_invocation: false' "$HOME/.agents/skills/impeccable/agents/openai.yaml" || fail "impeccable is not explicit-only for Codex"
grep -q '^@~/.agent-setup/core/AGENTS.md' "$HOME/.claude/CLAUDE.md" || fail "~/.claude/CLAUDE.md is not the import stub"
size=$(wc -c <"$A/build/AGENTS.full.md" | tr -d ' ')
[ "$size" -lt 24000 ] || fail "build/AGENTS.full.md is $size bytes (Antigravity limit 24,000)"
if [ "$os" = windows ]; then zed="$APPDATA/Zed"; else zed="$HOME/.config/zed"; fi
[ -f "$zed/AGENTS.md" ] || fail "missing Zed AGENTS.md in $zed"
if [ "$os" = macos ]; then rc=.zshrc; else rc=.bashrc; fi
grep -Fq '.agent-setup/shell/env.sh' "$HOME/$rc" || fail "~/$rc does not source shell/env.sh"
pass "key files exist (shell rc: ~/$rc, AGENTS.full.md: $size bytes)"

settings="$HOME/.claude/settings.json"
py_cmd=$(jq -r '.hooks.PreToolUse[].hooks[].command | select(test("english-only-warn"))' "$settings")
guard_cmd=$(jq -r '.hooks.PreToolUse[].hooks[].command | select(test("issue-branch-guard"))' "$settings")
notice_cmd=$(jq -r '.hooks.SessionStart[].hooks[].command | select(test("update-notice"))' "$settings")
echo "english-only hook: $py_cmd"
echo "guard hook:        $guard_cmd"
echo "notice hook:       $notice_cmd"
[ -n "$py_cmd" ] && [ -n "$guard_cmd" ] && [ -n "$notice_cmd" ] || fail "hooks missing in settings.json"
[ "$(printf '%s\n' "$py_cmd" | wc -l | tr -d ' ')" = 1 ] || fail "the old english-only hook entry was not replaced"
case "$py_cmd" in *"$HOME_NATIVE/.claude/hooks/english-only-warn.py"*) ;; *) fail "english-only hook path is not under HOME" ;; esac
jq -e '.permissions.allow | index("mcp__codegraph__*")' "$settings" >/dev/null || fail "mcp__codegraph__* not allowed"
jq -e '.env.IMPECCABLE_NO_TELEMETRY == "1" and .permissions.defaultMode == "auto"' "$settings" >/dev/null || fail "Claude env/defaultMode missing"
pass "Claude settings: hooks replaced, MCP auto-approval, env"

pw=$(approved playwright)
# Codex config.toml: parsed with tomllib when some Python has it.
toml_py=""
for c in python3 python "py -3"; do
  # shellcheck disable=SC2086
  if $c -c 'import tomllib' >/dev/null 2>&1; then toml_py=$c; break; fi
done
toml="$HOME/.codex/config.toml"
cat "$toml"
# The vendored skills of the plugins Codex has natively (every codex= plugin
# here), which config.toml must turn off for Codex.
codex_dups=$(awk -F '\t' 'NR == FNR { if ($0 !~ /^#/ && $3 ~ /codex=/) r[$2] = 1; next } $0 !~ /^#/ && ($2 in r) { print $1 }' \
  "$A/core/plugins.lock" "$A/core/skills.lock" | LC_ALL=C sort)
# check_codex_skills SKIP: config.toml turns off exactly those skills but SKIP
# (a name or ""), in marked entries; the user's entry is kept.
check_codex_skills() {
  local want n
  want=$(printf '%s\n' "$codex_dups" | grep -vx "${1:-none}" | sed "s|.*|$HOME_NATIVE/.agents/skills/&/SKILL.md|")
  n=$(printf '%s\n' "$want" | grep -c .)
  [ "$(grep -c '^\[\[skills\.config\]\] # agent-setup$' "$toml")" = "$n" ] || fail "codex config.toml: not $n marked [[skills.config]] entries"
  [ "$(grep '^path = ' "$toml" | sed 's/^path = "\(.*\)"$/\1/' | LC_ALL=C sort)" = "$(printf '%s\n' "$want" | LC_ALL=C sort)" ] || fail "codex config.toml: wrong [[skills.config]] paths"
  grep -q '^name = "mine"$' "$toml" || fail "codex config.toml: the user's [[skills.config]] entry was lost"
}
check_codex_skills ""
if [ -n "$toml_py" ]; then
  # shellcheck disable=SC2086
  $toml_py - "$(if [ "$os" = windows ]; then cygpath -m "$toml"; else printf '%s' "$toml"; fi)" "$pw" "$(printf '%s\n' "$codex_dups" | grep -c .)" <<'EOF' || fail "codex config.toml check failed"
import sys, tomllib
c = tomllib.load(open(sys.argv[1], "rb"))
assert c["model"] == "o3", "user model lost"
assert c["sandbox_mode"] == "read-only", "user sandbox_mode changed"
assert c["approval_policy"] == "on-request" and c["approvals_reviewer"] == "auto_review"
assert c["shell_environment_policy"]["set"]["IMPECCABLE_NO_TELEMETRY"] == "1"
cg = c["mcp_servers"]["codegraph"]
assert cg["command"] == "my-codegraph" and "args" not in cg, "user MCP server changed"
assert cg["default_tools_approval_mode"] == "auto"
assert c["mcp_servers"]["playwright"]["args"] == ["-y", "@playwright/mcp@" + sys.argv[2]], "playwright @latest not moved to the approved version"
assert "default_tools_approval_mode" not in c["mcp_servers"]["playwright"]
sc = c["skills"]["config"]
assert sc[0] == {"name": "mine", "enabled": False}, "user skills.config entry changed"
assert len(sc) == 1 + int(sys.argv[3]) and all(e["enabled"] is False and e["path"].endswith("/SKILL.md") for e in sc[1:])
EOF
  pass "codex config.toml parses (tomllib via $toml_py), user values kept, keys and skills.config entries added"
else
  grep -q '^approval_policy = "on-request"' "$toml" && grep -q '^model = "o3"' "$toml" || fail "codex config.toml keys"
  echo "note: no Python with tomllib; config.toml checked with grep only"
fi

jq -e '(.hooks.Stop | length) == 1 and (.hooks.PreToolUse | length) == 2 and (.hooks.UserPromptSubmit | length) == 1
  and (.hooks.SessionStart | length) == 1 and (.hooks.PreToolUse[0].matcher == "^apply_patch$")' "$HOME/.codex/hooks.json" >/dev/null || fail "codex hooks.json"
jq -e '.approvalMode == "allowlist" and .permissions.allow == ["Shell(ls)", "Mcp(codegraph:*)"]' "$cursor_cfg" >/dev/null || fail "cursor cli-config.json"
ag="$HOME/.gemini/antigravity-cli/settings.json"
jq -e '.agentMode == "manual" and .theme == "mine" and .permissions.allow == ["mcp(codegraph/*)"]' "$ag" >/dev/null || fail "antigravity settings.json"
if [ "$os" != windows ]; then
  mode=$(stat -c %a "$ag" 2>/dev/null || stat -f %Lp "$ag")
  [ "$mode" = 600 ] || fail "antigravity settings.json mode is $mode, not 600"
fi
agh="$HOME/.gemini/config/hooks.json"
jq -e '(.["agent-setup"].PreToolUse | length) == 2 and (.["agent-setup"].PreInvocation | length) == 1 and (.["agent-setup"].SessionStart | length) == 1' "$agh" >/dev/null || fail "antigravity hooks.json"
pass "codex hooks.json, cursor cli-config, antigravity settings and hooks.json (user values kept)"

echo "== hook commands (run with bash, as Claude Code does)"
proj="$HOME/proj"
mkdir -p "$proj"
git -C "$proj" init -q -b master
git -C "$proj" commit -q --allow-empty -m init
git -C "$proj" remote add origin https://github.com/example/proj.git
P="$HOME_NATIVE/proj"
vi='Xin chào thế giới'   # JSON escapes keep this file ASCII
codex_guard=$(jq -r '.hooks.PreToolUse[].hooks[].command | select(test("issue-branch-guard"))' "$HOME/.codex/hooks.json")
codex_py=$(jq -r '.hooks.PreToolUse[].hooks[].command | select(test("english-only-warn"))' "$HOME/.codex/hooks.json")
codex_notice=$(jq -r '.hooks.SessionStart[].hooks[].command' "$HOME/.codex/hooks.json")
ag_guard=$(jq -r '.["agent-setup"].PreToolUse[].hooks[].command | select(test("issue-branch-guard"))' "$agh")
ag_py=$(jq -r '.["agent-setup"].PreToolUse[].hooks[].command | select(test("english-only-warn"))' "$agh")
ag_prompt=$(jq -r '.["agent-setup"].PreInvocation[0].command' "$agh")
ag_session=$(jq -r '.["agent-setup"].SessionStart[0].command' "$agh")

# expect_rc RC CMD INPUT: run CMD with INPUT on stdin; its exit code must be RC.
expect_rc() {
  local rc=0
  printf '%s' "$3" | bash -c "$2" >"$HOME/.hook-out" 2>/dev/null || rc=$?
  [ "$rc" = "$1" ] || fail "exit $rc (want $1) from: $2 <<< $3"
}
claude_edit=$(printf '{"tool_name":"Edit","cwd":"%s","tool_input":{"file_path":"%s/a.txt"}}' "$P" "$P")
codex_patch=$(printf '{"tool_name":"apply_patch","cwd":"%s","tool_input":{"command":"*** Begin Patch\\n*** Add File: a.txt\\n+hi\\n*** End Patch"}}' "$P")
cursor_write=$(printf '{"tool_name":"Write","workspace_roots":["%s"],"tool_input":{"file_path":"%s/a.txt","content":"hi"}}' "$P" "$P")
ag_write=$(printf '{"conversationId":"c1","workspacePaths":["%s"],"toolCall":{"name":"write_to_file","args":{"TargetFile":"%s/a.txt","CodeContent":"hi"}}}' "$P" "$P")

expect_rc 2 "$guard_cmd" "$claude_edit"
expect_rc 2 "$codex_guard" "$codex_patch"
expect_rc 2 "$guard_cmd" "$cursor_write"
expect_rc 0 "$ag_guard" "$ag_write"
jq -e '.decision == "deny" and (.reason | test("issue workflow"))' "$HOME/.hook-out" >/dev/null || fail "antigravity guard did not deny: $(cat "$HOME/.hook-out")"
pass "guard blocks on master: Claude Edit, Codex apply_patch, Cursor Write, Antigravity write_to_file"
git -C "$proj" switch -q -c feat/1-x
expect_rc 0 "$guard_cmd" "$claude_edit"
expect_rc 0 "$codex_guard" "$codex_patch"
expect_rc 0 "$guard_cmd" "$cursor_write"
expect_rc 0 "$ag_guard" "$ag_write"
jq -e '.decision == "allow"' "$HOME/.hook-out" >/dev/null || fail "antigravity guard on a branch: $(cat "$HOME/.hook-out")"
pass "guard allows a feature branch for every agent"

expect_rc 0 "$py_cmd" "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/tmp/x.md\",\"content\":\"$vi\"}}"
grep -q additionalContext "$HOME/.hook-out" || fail "english-only (Claude) gave no warning"
expect_rc 0 "$codex_py" "{\"tool_name\":\"apply_patch\",\"tool_input\":{\"command\":\"*** Begin Patch\\n*** Add File: x.md\\n+$vi\\n*** End Patch\"}}"
grep -q additionalContext "$HOME/.hook-out" || fail "english-only (Codex) gave no warning"
expect_rc 0 "$py_cmd" "{\"tool_name\":\"Shell\",\"workspace_roots\":[\"$P\"],\"tool_input\":{\"command\":\"echo $vi\"}}"
grep -q agent_message "$HOME/.hook-out" || fail "english-only (Cursor) gave no warning"
expect_rc 0 "$ag_py" "{\"conversationId\":\"c2\",\"toolCall\":{\"name\":\"run_command\",\"args\":{\"CommandLine\":\"echo $vi\"}}}"
jq -e '.decision == "allow"' "$HOME/.hook-out" >/dev/null || fail "antigravity english-only pretool: $(cat "$HOME/.hook-out")"
expect_rc 0 "$ag_prompt" '{"conversationId":"c2","lastUserInput":"hello"}'
jq -e '.injectSteps[0].ephemeralMessage | test("English-only")' "$HOME/.hook-out" >/dev/null || fail "antigravity did not inject the warning: $(cat "$HOME/.hook-out")"
pass "english-only warns on Vietnamese: Claude, Codex, Cursor, Antigravity (on the next PreInvocation)"

for c in "$ag_guard" "$ag_py" "$ag_prompt" "$ag_session"; do
  for input in 'not json' '' '[1,2]'; do
    expect_rc 0 "$c" "$input"
    jq -e 'type == "object"' "$HOME/.hook-out" >/dev/null || fail "antigravity hook printed no JSON object for '$input': $(cat "$HOME/.hook-out")"
  done
done
pass "antigravity hooks print a JSON object and exit 0 on garbage input"

# The session-start notice for each agent shape: CLAUDE, CODEX, CURSOR, ANTIGRAVITY inputs.
claude_start='{"hook_event_name":"SessionStart","session_id":"s1","source":"startup","cwd":"/tmp"}'
cursor_start='{"hook_event_name":"sessionStart","session_id":"s1","cursor_version":"2.0.0","workspace_roots":["/tmp"]}'
ag_start='{"conversationId":"c9","workspacePaths":["/tmp"]}'
notices() {   # notices: run every agent's SessionStart command; outputs in ~/.notice-<agent>
  expect_rc 0 "$notice_cmd" "$claude_start"; cp "$HOME/.hook-out" "$HOME/.notice-claude"
  expect_rc 0 "$codex_notice" "$claude_start"; cp "$HOME/.hook-out" "$HOME/.notice-codex"
  expect_rc 0 "$notice_cmd" "$cursor_start"; cp "$HOME/.hook-out" "$HOME/.notice-cursor"
  expect_rc 0 "$ag_session" "$ag_start"; cp "$HOME/.hook-out" "$HOME/.notice-antigravity"
}
notices
[ ! -s "$HOME/.notice-claude" ] && [ ! -s "$HOME/.notice-codex" ] && [ ! -s "$HOME/.notice-cursor" ] || fail "a session-start notice without pending updates: $(cat "$HOME"/.notice-*)"
jq -e '. == {}' "$HOME/.notice-antigravity" >/dev/null || fail "antigravity session notice without updates: $(cat "$HOME/.notice-antigravity")"
pass "session-start hooks are silent when nothing is pending (Claude, Codex, Cursor, Antigravity)"

# Missing hook scripts never block (Claude, Codex, Antigravity commands).
git -C "$proj" switch -q master
mv "$HOME/.claude/hooks" "$HOME/.claude/hooks.off"
mv "$A/core/hooks" "$A/core/hooks.off"
expect_rc 0 "$guard_cmd" "$claude_edit"
expect_rc 0 "$py_cmd" '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x.md","content":"x"}}'
expect_rc 0 "$notice_cmd" "$claude_start"
# On Windows the Codex guard is a plain 'bash "<script>"': exit 127, which does not block.
rc=0; printf '%s' "$codex_patch" | bash -c "$codex_guard" >/dev/null 2>&1 || rc=$?
[ "$rc" != 2 ] || fail "codex guard blocks without its script"
expect_rc 0 "$codex_py" '{}'
expect_rc 0 "$ag_guard" "$ag_write"
jq -e '.decision == "allow"' "$HOME/.hook-out" >/dev/null || fail "antigravity without scripts: $(cat "$HOME/.hook-out")"
expect_rc 0 "$ag_session" "$ag_start"
mv "$A/core/hooks.off" "$A/core/hooks"
mv "$HOME/.claude/hooks.off" "$HOME/.claude/hooks"
pass "hook commands exit 0 when their scripts are missing"

echo "== native plugins (stub claude, codex and agy CLIs)"
inst_json="$HOME/.claude/plugins/installed_plugins.json"
known="$HOME/.claude/plugins/known_marketplaces.json"
stublog="$HOME/.claude-stub.log"
for f in core/plugins.lock core/skills.lock tools/tools.lock; do
  grep -Eq '[0-9a-f]{40}|releases/download/v[0-9]|/v[0-9]+\.[0-9]' "$A/$f" && fail "$f holds a pinned version"
done
jq -e '.servers.playwright.args == ["-y", "@playwright/mcp@{version}"]' "$A/core/mcp.json" >/dev/null || fail "core/mcp.json pins playwright"
for id in superpowers@claude-plugins-official taste-skill@taste-skill gsap-skills@gsap-skills harness@harness-marketplace fakeplug@fakeplug; do
  jq -e --arg i "$id" '.plugins | has($i)' "$inst_json" >/dev/null || fail "claude: $id not installed"
done
for m in taste-skill:Leonxlnx/taste-skill gsap-skills:greensock/gsap-skills harness-marketplace:revfactory/harness claude-plugins-official:anthropics/claude-plugins-official; do
  jq -e --arg m "${m%%:*}" --arg r "${m#*:}" '.[$m].source == {source: "github", repo: $r}' "$known" >/dev/null || fail "claude: marketplace ${m%%:*} is not from GitHub ${m#*:}"
  jq -e --arg m "${m%%:*}" '.extraKnownMarketplaces[$m].autoUpdate == false' "$settings" >/dev/null || fail "claude: auto-update is not off for ${m%%:*}"
done
jq -e '[.extraKnownMarketplaces[] | .autoUpdate] | all(. == false)' "$settings" >/dev/null || fail "claude: a marketplace may auto-update"
[ "$(claude plugin marketplace list --json | jq length)" = 5 ] || fail "claude: not exactly 5 marketplaces"
grep -q 'plugin install harness' "$stublog" && fail "claude: harness was reinstalled instead of re-pointed"
[ "$(cat "$HOME/.claude/plugins/data/harness-harness-marketplace/keep")" = mine ] || fail "claude: harness plugin data lost"
[ ! -e "$A/build/claude-marketplaces" ] || fail "build/claude-marketplaces was not removed"
jq -e --arg a "@playwright/mcp@$pw" '.mcpServers.playwright.args == ["-y", $a]' "$HOME/.claude.json" >/dev/null || fail "claude: old playwright pin not moved to the approved version"
jq -e --arg a "@playwright/mcp@$pw" '.mcpServers.playwright.args == ["-y", $a]' "$HOME/.cursor/mcp.json" >/dev/null || fail "cursor: old playwright pin not moved to the approved version"
pass "claude: authors' marketplaces with auto-update off (official too), pinned catalog migrated in place (data kept), playwright at the approved version"
cstate="$HOME/.codex/stub-state.json"
jq -e '.plugins | keys == ["fakeplug@fakeplug", "gsap-skills@gsap-skills", "harness@harness-marketplace", "superpowers@superpowers", "taste-skill@taste-skill"]' "$cstate" >/dev/null || fail "codex: native plugins: $(cat "$cstate")"
jq -e '.marketplaces | to_entries | all(.value | test("build/codex-marketplaces/"))' "$cstate" >/dev/null || fail "codex: a marketplace is not a pinned local catalog: $(cat "$cstate")"
[ "$(jq -r '.plugins["taste-skill@taste-skill"]' "$cstate")" = "$(approved taste-skill)" ] || fail "codex: taste-skill not reinstalled at the approved commit"
[ "$(jq -r '.plugins["fakeplug@fakeplug"]' "$cstate")" = "$(approved plug)" ] || fail "codex: fakeplug not at the approved commit"
grep -q 'plugin marketplace remove taste-skill' "$HOME/.codex-stub.log" || fail "codex: the Git marketplace was not replaced"
jq -e --arg d "$A/vendor/obra__superpowers" '.superpowers.source | gsub("\\\\"; "/") | ascii_downcase | endswith("vendor/obra__superpowers")' "$HOME/.gemini/stub-plugins.json" >/dev/null || fail "antigravity: superpowers not installed from the vendor checkout: $(cat "$HOME/.gemini/stub-plugins.json")"
jq -e '.marketplaces | has("superpowers") and (has("superpowers-dev") | not)' "$cstate" >/dev/null || fail "codex: superpowers marketplace not renamed: $(cat "$cstate")"
[ "$(jq -r '.plugins["superpowers@superpowers"]' "$cstate")" = "$(approved superpowers)" ] || fail "codex: superpowers not at the approved commit"
pass "codex: every plugin from a pinned local catalog (Git marketplace and superpowers-dev migrated); antigravity: superpowers from the approved checkout"

echo "== Codex loses a native plugin"
codex plugin remove fakeplug@fakeplug >/dev/null
export STUB_FAIL_ADD=fakeplug@fakeplug
run --yes --skip-tools "$@"
unset STUB_FAIL_ADD
grep -q 'WARN: codex: could not install fakeplug@fakeplug' "$out" || fail "codex: the failed fakeplug install was not reported"
check_codex_skills fake-plug
[ -f "$HOME/.agents/skills/fake-plug/SKILL.md" ] || fail "fake-plug left ~/.agents/skills"
run --yes --skip-tools "$@"
check_codex_skills ""
run --yes --skip-tools "$@"
grep -q '^0 change(s) made' "$out" || fail "run after fakeplug came back made changes"
pass "codex: the skills.config entries follow the plugins Codex has natively"

echo "== upstream moves: nothing changes without approval"
new_one=$(commit_to one) new_two=$(commit_to two) new_plug=$(commit_to plug)
old_one=$(approved one) old_two=$(approved two) old_plug=$(approved plug)
run --yes --skip-tools "$@"
grep -q '^0 change(s) made' "$out" || fail "a plain run moved past the approved versions"
[ "$(vendor_head fake__one)" = "$old_one" ] && [ "$(approved one)" = "$old_one" ] || fail "one moved without approval"
pass "a plain run never moves past the approved versions"

echo "== --check"
inst --check
grep -q '^one:' "$out" && fail "--check ignored the 24-hour cache"
inst --check --force
grep -q "^one: ${old_one:0:12} -> ${new_one:0:12} https://github.com/fake/one/compare/${old_one:0:12}...${new_one:0:12}" "$out" || fail "--check --force does not report one"
grep -q '^two: ' "$out" && grep -q '^plug: ' "$out" || fail "--check --force does not report two and plug"
grep -q '^anatomy:' "$out" && fail "--check reports an item without a newer version"
inst --check --json
jq -e '[.updates[].name] | index("one") and index("two") and index("plug")' "$out" >/dev/null || fail "--check --json"
newer_one=$(commit_to one)
inst --check
grep -q "^one: .* -> ${new_one:0:12} " "$out" || fail "--check within 24 hours did not use the cache"
jq '.checked -= 90000' "$A/state/updates.json" >"$A/state/u.tmp" && mv "$A/state/u.tmp" "$A/state/updates.json"
inst --check
grep -q "^one: .* -> ${newer_one:0:12} " "$out" || fail "--check after 24 hours did not check upstream again"
new_one=$newer_one
w="$HOME/work-self"; gitc clone -q "$HOME/self.git" "$w" && date >"$w/x" && gitc -C "$w" add x && gitc -C "$w" commit -q -m x && gitc -C "$w" push -q origin HEAD:master
inst --check --force
grep -q '^agent-setup: 1 new commit(s) on origin' "$out" || fail "--check does not report the new commit on origin"
pass "--check: old -> new with compare links, 24-hour cache, --force, --json, new commits on origin"

echo "== session-start notices with pending updates"
notices
for a in claude codex; do
  jq -e '.hookSpecificOutput.hookEventName == "SessionStart" and (.hookSpecificOutput.additionalContext | test("one: .* -> .*compare") and test("--update <names> --yes") and test("--snooze") and test("--skip") and test("1 new commit"))' "$HOME/.notice-$a" >/dev/null ||
    fail "$a session notice: $(cat "$HOME/.notice-$a")"
done
jq -e '(.additional_context | test("one: ")) and (has("hookSpecificOutput") | not)' "$HOME/.notice-cursor" >/dev/null || fail "cursor session notice: $(cat "$HOME/.notice-cursor")"
jq -e '.injectSteps[0].ephemeralMessage | test("one: ")' "$HOME/.notice-antigravity" >/dev/null || fail "antigravity session notice: $(cat "$HOME/.notice-antigravity")"
pass "session-start notice: Claude and Codex additionalContext, Cursor additional_context, Antigravity injectSteps"

# Fail open without network: an expired cache, the upstreams and origin unreachable.
jq '.checked -= 90000' "$A/state/updates.json" >"$A/state/u.tmp" && mv "$A/state/u.tmp" "$A/state/updates.json"
mv "$up" "$up.off" && mv "$HOME/self.git" "$HOME/self.off"
start=$(date +%s)
HTTPS_PROXY=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 expect_rc 0 "$notice_cmd" "$claude_start"
jq -e '.hookSpecificOutput.additionalContext | test("one: ")' "$HOME/.hook-out" >/dev/null || fail "offline notice lost the cached updates: $(cat "$HOME/.hook-out")"
[ $(($(date +%s) - start)) -lt 30 ] || fail "the offline notice took $(($(date +%s) - start)) s"
HTTPS_PROXY=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 inst --check --force
grep -qi 'error\|fatal' "$out" && fail "--check printed errors offline"
mv "$up.off" "$up" && mv "$HOME/self.off" "$HOME/self.git"
pass "offline: hooks exit 0 quickly with the cached notice, --check prints no errors"

echo "== --snooze and --skip"
inst --snooze one,agent-setup
jq -e '.snoozed.one > now' "$A/state/updates.json" >/dev/null || fail "--snooze did not store the time"
skip_two=$(jq -r '.latest.two.version[0:12]' "$A/state/updates.json")
inst --skip "two@$skip_two"
jq -e --arg v "$skip_two" '.skipped.two == $v' "$A/state/updates.json" >/dev/null || fail "--skip did not store the version"
expect_rc 0 "$notice_cmd" "$claude_start"
jq -e '.hookSpecificOutput.additionalContext | (test("- one: ") or test("- two: ") or test("new commit")) | not' "$HOME/.hook-out" >/dev/null || fail "snoozed or skipped items still in the notice: $(cat "$HOME/.hook-out")"
jq -e '.hookSpecificOutput.additionalContext | test("- plug: ")' "$HOME/.hook-out" >/dev/null || fail "plug missing from the notice"
inst --check
grep -q '^two: .* (skipped)$' "$out" && grep -q '^one: .* (snoozed)$' "$out" || fail "--check does not mark skipped and snoozed items"
commit_to two >/dev/null
inst --check --force
grep -q '^two: .* (skipped)$' "$out" && fail "a newer version of a skipped item is still skipped"
pass "--snooze hides an item for 24 hours, --skip until a newer version appears"

echo "== --update"
before=$(snapshot)
inst --update one --yes --dry-run --skip-tools --agents "$agents"
[ "$before" = "$(snapshot)" ] || fail "--update --dry-run changed files"
[ "$(approved one)" = "$old_one" ] || fail "--update --dry-run approved"
head_before=$(git -C "$A" rev-parse HEAD)
run --update one --yes --skip-tools "$@"
[ "$(approved one)" = "$new_one" ] && [ "$(vendor_head fake__one)" = "$new_one" ] || fail "--update one did not move one"
[ "$(jq -r '.one.previous' "$A/state/approved.json")" = "$old_one" ] || fail "the previous version of one was not kept"
[ "$(approved two)" = "$old_two" ] && [ "$(vendor_head fake__two)" = "$old_two" ] && [ "$(approved plug)" = "$old_plug" ] || fail "--update one moved other items"
[ "$(git -C "$A" rev-parse HEAD)" = "$head_before" ] && [ -z "$(git -C "$A" status --porcelain)" ] || fail "--update changed the repo (commit or tracked files)"
grep -qi 'commit\|push' "$out" && fail "--update mentions a commit or push"
ls "$HOME"/.agent-setup-backups/*/.agent-setup/state/approved.json >/dev/null 2>&1 || fail "state/approved.json was not backed up"
run --update plug --yes --skip-tools "$@"
[ "$(approved plug)" = "$new_plug" ] || fail "--update plug did not approve the new commit"
[ "$(jq -r '.plugins["fakeplug@fakeplug"][0].gitCommitSha' "$inst_json")" = "$new_plug" ] || fail "claude: fakeplug not reinstalled at the new commit"
[ "$(jq -r '.plugins["fakeplug@fakeplug"]' "$cstate")" = "$new_plug" ] || fail "codex: fakeplug not reinstalled at the new commit"
grep -q 'plugin uninstall --keep-data fakeplug@fakeplug' "$stublog" || fail "claude: fakeplug was not reinstalled keeping its data"
run --yes --skip-tools "$@"
grep -q '^0 change(s) made' "$out" || fail "run after the updates made changes"
"$A/install.sh" --update nosuchitem --yes >/dev/null 2>&1 && fail "--update accepted an unknown item"
pass "--update NAME --yes moves only that item (state only, backed up, no commit); plugins reinstalled at the new commit"

echo "== a fetch fails"
vend="$A/vendor/fake__two"
url=$(git -C "$vend" remote get-url origin)
git -C "$vend" remote set-url origin "$HOME/no-such-repo"
run --update two --yes --skip-tools "$@"
grep -q 'WARN: failed: update vendor/fake__two' "$out" || fail "no warning for a failed fetch"
[ -f "$HOME/.agents/skills/fake-two/SKILL.md" ] || fail "fake-two link dangles after a failed fetch"
git -C "$vend" remote set-url origin "$url"
run --yes --skip-tools "$@"
[ "$(vendor_head fake__two)" = "$(approved two)" ] || fail "the approved commit was not fetched on the next run"
pass "a failed fetch keeps the last good copy; the next run gets the approved commit"

echo "== duplicates"
# A second copy of a plugin from another marketplace: warn, no second install.
jq '.["superpowers-dev"] = {source: {source: "github", repo: "obra/superpowers"}, installLocation: "/nonexistent"}' "$known" >"$known.tmp" && mv "$known.tmp" "$known"
jq '.plugins["superpowers@superpowers-dev"] = [{scope: "user", installPath: "/nonexistent", version: "7.0.2", gitCommitSha: "22f0b463e7a5e579904dd6211a520321035526f7"}]
  | del(.plugins["superpowers@claude-plugins-official"])' "$inst_json" >"$inst_json.tmp" && mv "$inst_json.tmp" "$inst_json"
jq '.plugins["gsap-skills@mine"] = "1.0.0" | del(.plugins["gsap-skills@gsap-skills"])
  | .marketplaces["superpowers-dev"] = "https://github.com/obra/superpowers.git"
  | .plugins["superpowers@superpowers-dev"] = "1.0.0" | .plugins["superpowers@openai-curated"] = "1.0.0"
  | del(.plugins["superpowers@superpowers"])' "$cstate" >"$cstate.tmp" && mv "$cstate.tmp" "$cstate"
: >"$stublog"
run --yes --skip-tools "$@"
grep -q "WARN: claude: superpowers is already installed as superpowers@superpowers-dev, so superpowers@claude-plugins-official was not installed as a second copy. Switch with: claude plugin uninstall superpowers@superpowers-dev && claude plugin install superpowers@claude-plugins-official" "$out" ||
  fail "duplicate plugin not reported with the switch commands"
grep -q 'plugin install superpowers@' "$stublog" && fail "a second copy of superpowers was installed"
grep -q "WARN: codex: gsap-skills is already installed as gsap-skills@mine" "$out" || fail "codex duplicate plugin not reported"
jq -e '.plugins | has("gsap-skills@gsap-skills") | not' "$cstate" >/dev/null || fail "codex: a second copy of gsap-skills was installed"
grep "WARN: codex: superpowers is already installed as" "$out" | grep 'superpowers@superpowers-dev' | grep -q 'superpowers@openai-curated' || fail "codex: superpowers from the Git marketplace and openai-curated not reported"
jq -e '.plugins | has("superpowers@superpowers") | not' "$cstate" >/dev/null || fail "codex: a second copy of superpowers was installed"
jq -e '.marketplaces["superpowers-dev"] | test("^https:")' "$cstate" >/dev/null || fail "codex: the author's Git marketplace was removed without --fix-duplicates"
[ -f "$HOME/.agents/skills/gsap-core/SKILL.md" ] || fail "gsap-core left ~/.agents/skills"
check_codex_skills ""
pass "plugin installed from another marketplace: warned with the switch commands, no second copy (claude, codex)"
run --yes --skip-tools --fix-duplicates "$@"
grep -q '^plugin uninstall superpowers@superpowers-dev' "$stublog" || fail "--fix-duplicates did not uninstall the other copy"
grep -q '^plugin marketplace remove superpowers-dev' "$stublog" || fail "--fix-duplicates did not remove the emptied marketplace"
jq -e '.plugins | has("superpowers@claude-plugins-official") and (has("superpowers@superpowers-dev") | not)' "$inst_json" >/dev/null || fail "superpowers was not switched"
jq -e '.plugins | has("gsap-skills@gsap-skills") and (has("gsap-skills@mine") | not)' "$cstate" >/dev/null || fail "codex: gsap-skills was not switched"
jq -e '.plugins | has("superpowers@superpowers") and (has("superpowers@superpowers-dev") or has("superpowers@openai-curated") | not)' "$cstate" >/dev/null || fail "codex: superpowers was not switched: $(cat "$cstate")"
ls "$HOME"/.agent-setup-backups/*/.claude/plugins/installed_plugins.json >/dev/null 2>&1 || fail "plugin records were not backed up"
pass "--fix-duplicates switches the plugins to the core/plugins.lock source (records backed up)"

# Duplicate skills: an unmanaged copy next to a managed one, for Codex (and
# Cursor, which reads ~/.codex/skills) and Claude (next to a plugin skill).
mkdir -p "$HOME/.codex/skills/anatomy" "$HOME/.claude/skills/harness" "$HOME/.cursor/skills/mine"
printf -- '---\nname: x\n---\n' | tee "$HOME/.codex/skills/anatomy/SKILL.md" "$HOME/.claude/skills/harness/SKILL.md" >"$HOME/.cursor/skills/mine/SKILL.md"
run --yes --skip-tools "$@"
grep -q "WARN: codex: skill 'anatomy' is in more than one place it reads: .*\.agents/skills/anatomy, .*\.codex/skills/anatomy (not managed)" "$out" || fail "codex skill duplicate not reported"
grep -q "WARN: cursor: skill 'anatomy'" "$out" || fail "cursor skill duplicate not reported"
grep -q "WARN: claude: skill 'harness' is in more than one place it reads: .*\.claude/skills/harness (not managed)" "$out" || fail "claude plugin skill duplicate not reported"
grep -q "skill 'mine'" "$out" && fail "a skill found once was reported"
[ -d "$HOME/.codex/skills/anatomy" ] && [ -d "$HOME/.claude/skills/harness" ] || fail "a duplicate skill was moved without --fix-duplicates"
pass "duplicate skills reported with paths, nothing moved"
run --yes --skip-tools --fix-duplicates "$@"
[ ! -e "$HOME/.codex/skills/anatomy" ] && [ ! -e "$HOME/.claude/skills/harness" ] || fail "--fix-duplicates did not move the unmanaged copies"
ls -d "$HOME"/.agent-setup-backups/*/.codex/skills/anatomy "$HOME"/.agent-setup-backups/*/.claude/skills/harness >/dev/null || fail "moved skills are not in the backups"
[ -d "$HOME/.cursor/skills/mine" ] || fail "a user skill was moved"
pass "--fix-duplicates moves unmanaged duplicates to the backups"

run --yes --skip-tools "$@"
grep -q '^0 change(s) made' "$out" || fail "run after the plugin and skill fixes made changes"
grep -q 'WARN: .*\(skill\|plugin\|fetch\|failed\)' "$out" && fail "warnings left after the fixes"
pass "after the fixes: 0 changes, no plugin, skill or fetch warnings"

echo "ALL CHECKS PASSED ($os)"
