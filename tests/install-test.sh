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

# A stub claude CLI on PATH, so the MCP and plugin steps run (tests/claude-stub.sh).
mkdir -p "$HOME/stub-bin"
cp "$repo/tests/claude-stub.sh" "$HOME/stub-bin/claude"
chmod +x "$HOME/stub-bin/claude"
export PATH="$HOME/stub-bin:$PATH"

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

# User values that the installer must keep, and an old-style Claude hook entry
# that it must replace (not duplicate).
# Keep XDG paths inside the sandbox (the Cursor CLI config honours it on Linux).
export XDG_CONFIG_HOME="$HOME/.xdg-config"
if [ "$os" = linux ]; then cursor_cfg="$XDG_CONFIG_HOME/cursor/cli-config.json"; else cursor_cfg="$HOME/.cursor/cli-config.json"; fi
mkdir -p "$HOME/.codex" "$(dirname "$cursor_cfg")" "$HOME/.gemini/antigravity-cli" "$HOME/.claude"
printf '# mine\nmodel = "o3"\nsandbox_mode = "read-only"\n\n[mcp_servers.codegraph]\ncommand = "my-codegraph"\n' >"$HOME/.codex/config.toml"
printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo user-hook"}]}]}}' >"$HOME/.codex/hooks.json"
printf '%s\n' '{"approvalMode":"allowlist","permissions":{"allow":["Shell(ls)"]}}' >"$cursor_cfg"
printf '%s\n' '{"agentMode":"manual","theme":"mine"}' >"$HOME/.gemini/antigravity-cli/settings.json"
chmod 600 "$HOME/.gemini/antigravity-cli/settings.json"
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/bin/python3 -I %s/.claude/hooks/english-only-warn.py"}]}]}}\n' "$HOME_NATIVE" >"$HOME/.claude/settings.json"

echo "== dry run on a fresh HOME"
before=$(snapshot)
run --dry-run --skip-tools "$@"
after=$(snapshot)
[ "$before" = "$after" ] || { diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true; fail "--dry-run changed files on a fresh HOME"; }
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
for f in .claude/CLAUDE.md .claude/rules/language.md .claude/rules/claude-extras.md .claude/rules/coordinator-mode.md \
  .claude/hooks/issue-branch-guard.sh .claude/hooks/english-only-warn.py .claude/skills/anatomy/SKILL.md \
  .agents/skills/anatomy/SKILL.md .agents/skills/impeccable/SKILL.md .agents/skills/taste-skill/SKILL.md \
  .agents/skills/gsap-core/SKILL.md .agents/skills/brainstorming/SKILL.md .agents/skills/harness/SKILL.md \
  .gemini/config/skills/evolve/SKILL.md .codex/AGENTS.md .gemini/GEMINI.md .config/opencode/AGENTS.md; do
  [ -f "$HOME/$f" ] || fail "missing ~/$f"
done
for f in .claude/skills/taste-skill .claude/skills/brainstorming .claude/skills/harness; do
  [ ! -e "$HOME/$f" ] || fail "~/$f exists; Claude gets plugin skills from its plugins"
done
grep -q 'allow_implicit_invocation: false' "$HOME/.agents/skills/impeccable/agents/openai.yaml" || fail "impeccable is not explicit-only for Codex"
grep -q '^@~/.agent-setup/core/AGENTS.md' "$HOME/.claude/CLAUDE.md" || fail "~/.claude/CLAUDE.md is not the import stub"
size=$(wc -c <"$HOME/.agent-setup/build/AGENTS.full.md" | tr -d ' ')
[ "$size" -lt 24000 ] || fail "build/AGENTS.full.md is $size bytes (Antigravity limit 24,000)"
if [ "$os" = windows ]; then zed="$APPDATA/Zed"; else zed="$HOME/.config/zed"; fi
[ -f "$zed/AGENTS.md" ] || fail "missing Zed AGENTS.md in $zed"
if [ "$os" = macos ]; then rc=.zshrc; else rc=.bashrc; fi
grep -Fq '.agent-setup/shell/env.sh' "$HOME/$rc" || fail "~/$rc does not source shell/env.sh"
pass "key files exist (shell rc: ~/$rc, AGENTS.full.md: $size bytes)"

settings="$HOME/.claude/settings.json"
py_cmd=$(jq -r '.hooks.PreToolUse[].hooks[].command | select(test("english-only-warn"))' "$settings")
guard_cmd=$(jq -r '.hooks.PreToolUse[].hooks[].command | select(test("issue-branch-guard"))' "$settings")
echo "english-only hook: $py_cmd"
echo "guard hook:        $guard_cmd"
[ -n "$py_cmd" ] && [ -n "$guard_cmd" ] || fail "hooks missing in settings.json"
[ "$(printf '%s\n' "$py_cmd" | wc -l | tr -d ' ')" = 1 ] || fail "the old english-only hook entry was not replaced"
case "$py_cmd" in *"$HOME_NATIVE/.claude/hooks/english-only-warn.py"*) ;; *) fail "english-only hook path is not under HOME" ;; esac
jq -e '.permissions.allow | index("mcp__codegraph__*")' "$settings" >/dev/null || fail "mcp__codegraph__* not allowed"
jq -e '.env.IMPECCABLE_NO_TELEMETRY == "1" and .permissions.defaultMode == "auto"' "$settings" >/dev/null || fail "Claude env/defaultMode missing"
pass "Claude settings: hooks replaced, MCP auto-approval, env"

# Codex config.toml: parsed with tomllib when some Python has it.
toml_py=""
for c in python3 python "py -3"; do
  # shellcheck disable=SC2086
  if $c -c 'import tomllib' >/dev/null 2>&1; then toml_py=$c; break; fi
done
toml="$HOME/.codex/config.toml"
cat "$toml"
if [ -n "$toml_py" ]; then
  # shellcheck disable=SC2086
  $toml_py - "$(if [ "$os" = windows ]; then cygpath -m "$toml"; else printf '%s' "$toml"; fi)" <<'EOF' || fail "codex config.toml check failed"
import sys, tomllib
c = tomllib.load(open(sys.argv[1], "rb"))
assert c["model"] == "o3", "user model lost"
assert c["sandbox_mode"] == "read-only", "user sandbox_mode changed"
assert c["approval_policy"] == "on-request" and c["approvals_reviewer"] == "auto_review"
assert c["shell_environment_policy"]["set"]["IMPECCABLE_NO_TELEMETRY"] == "1"
cg = c["mcp_servers"]["codegraph"]
assert cg["command"] == "my-codegraph" and "args" not in cg, "user MCP server changed"
assert cg["default_tools_approval_mode"] == "auto"
assert c["mcp_servers"]["playwright"]["args"] == ["-y", "@playwright/mcp@0.0.83"]
assert "default_tools_approval_mode" not in c["mcp_servers"]["playwright"]
EOF
  pass "codex config.toml parses (tomllib via $toml_py), user values kept, keys added"
else
  grep -q '^approval_policy = "on-request"' "$toml" && grep -q '^model = "o3"' "$toml" || fail "codex config.toml keys"
  echo "note: no Python with tomllib; config.toml checked with grep only"
fi

jq -e '(.hooks.Stop | length) == 1 and (.hooks.PreToolUse | length) == 2 and (.hooks.UserPromptSubmit | length) == 1
  and (.hooks.PreToolUse[0].matcher == "^apply_patch$")' "$HOME/.codex/hooks.json" >/dev/null || fail "codex hooks.json"
jq -e '.approvalMode == "allowlist" and .permissions.allow == ["Shell(ls)", "Mcp(codegraph:*)"]' "$cursor_cfg" >/dev/null || fail "cursor cli-config.json"
ag="$HOME/.gemini/antigravity-cli/settings.json"
jq -e '.agentMode == "manual" and .theme == "mine" and .permissions.allow == ["mcp(codegraph/*)"]' "$ag" >/dev/null || fail "antigravity settings.json"
if [ "$os" != windows ]; then
  mode=$(stat -c %a "$ag" 2>/dev/null || stat -f %Lp "$ag")
  [ "$mode" = 600 ] || fail "antigravity settings.json mode is $mode, not 600"
fi
agh="$HOME/.gemini/config/hooks.json"
jq -e '(.["agent-setup"].PreToolUse | length) == 2 and (.["agent-setup"].PreInvocation | length) == 1' "$agh" >/dev/null || fail "antigravity hooks.json"
pass "codex hooks.json, cursor cli-config, antigravity settings and hooks.json (user values kept)"

echo "== hook commands (run with bash, as Claude Code does)"
proj="$HOME/proj"
mkdir -p "$proj"
git -C "$proj" init -q -b master
git -C "$proj" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$proj" remote add origin https://github.com/example/proj.git
P="$HOME_NATIVE/proj"
vi='Xin chào thế giới'   # JSON escapes keep this file ASCII
codex_guard=$(jq -r '.hooks.PreToolUse[].hooks[].command | select(test("issue-branch-guard"))' "$HOME/.codex/hooks.json")
codex_py=$(jq -r '.hooks.PreToolUse[].hooks[].command | select(test("english-only-warn"))' "$HOME/.codex/hooks.json")
ag_guard=$(jq -r '.["agent-setup"].PreToolUse[].hooks[].command | select(test("issue-branch-guard"))' "$agh")
ag_py=$(jq -r '.["agent-setup"].PreToolUse[].hooks[].command | select(test("english-only-warn"))' "$agh")
ag_prompt=$(jq -r '.["agent-setup"].PreInvocation[0].command' "$agh")

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

for c in "$ag_guard" "$ag_py" "$ag_prompt"; do
  for input in 'not json' '' '[1,2]'; do
    expect_rc 0 "$c" "$input"
    jq -e 'type == "object"' "$HOME/.hook-out" >/dev/null || fail "antigravity hook printed no JSON object for '$input': $(cat "$HOME/.hook-out")"
  done
done
pass "antigravity hooks print a JSON object and exit 0 on garbage input"

# Missing hook scripts never block (Claude, Codex, Antigravity commands).
git -C "$proj" switch -q master
mv "$HOME/.claude/hooks" "$HOME/.claude/hooks.off"
mv "$HOME/.agent-setup/core/hooks" "$HOME/.agent-setup/core/hooks.off"
expect_rc 0 "$guard_cmd" "$claude_edit"
expect_rc 0 "$py_cmd" '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x.md","content":"x"}}'
# On Windows the Codex guard is a plain 'bash "<script>"': exit 127, which does not block.
rc=0; printf '%s' "$codex_patch" | bash -c "$codex_guard" >/dev/null 2>&1 || rc=$?
[ "$rc" != 2 ] || fail "codex guard blocks without its script"
expect_rc 0 "$codex_py" '{}'
expect_rc 0 "$ag_guard" "$ag_write"
jq -e '.decision == "allow"' "$HOME/.hook-out" >/dev/null || fail "antigravity without scripts: $(cat "$HOME/.hook-out")"
mv "$HOME/.agent-setup/core/hooks.off" "$HOME/.agent-setup/core/hooks"
mv "$HOME/.claude/hooks.off" "$HOME/.claude/hooks"
pass "hook commands exit 0 when their scripts are missing"

echo "== locks and Claude plugins (stub claude CLI)"
lockdir="$HOME/.agent-setup"
plock="$lockdir/agents/claude/plugins.lock"
slock="$lockdir/core/skills.lock"
inst="$HOME/.claude/plugins/installed_plugins.json"
known="$HOME/.claude/plugins/known_marketplaces.json"
stublog="$HOME/.claude-stub.log"
locked() { awk -F '\t' -v i="$1" '$1 == i { print $3 }' "$plock"; }
isha() { jq -r --arg i "$1" '.plugins[$i][0].gitCommitSha // empty' "$inst"; }
setsha() { jq --arg i "$1" --arg s "$2" '.plugins[$i][0].gitCommitSha = $s' "$inst" >"$inst.tmp" && mv "$inst.tmp" "$inst"; }
grep -q 'skills.lock: .* pinned to' "$out" && fail "the locks in the repo disagree"
grep -v '^#' "$plock" | while IFS=$'\t' read -r id _ sha _ how; do
  [ "$(isha "$id")" = "$sha" ] || fail "$id is not installed at its locked commit $sha"
  if [ "$how" = pinned ]; then
    m=${id#*@}
    jq -e --arg m "$m" '.[$m].source.source == "directory"' "$known" >/dev/null || fail "marketplace $m is not the pinned catalog"
    jq -e --arg s "$sha" '.plugins[0].source.sha == $s' "$lockdir/build/claude-marketplaces/$m/.claude-plugin/marketplace.json" >/dev/null ||
      fail "catalog $m is not pinned to $sha"
  fi
done
jq -e '.plugins[0] | .version == "2.5.0" and .skills == ["./skills/taste-skill"] and .source.source == "github"' \
  "$lockdir/build/claude-marketplaces/taste-skill/.claude-plugin/marketplace.json" >/dev/null || fail "taste-skill catalog does not keep the author's entry"
pass "every plugin installed at its locked commit; pinned catalogs keep the author's entry"

# A skip=claude copy on another commit than its plugin is reported.
cp "$slock" "$HOME/skills.lock.orig"
awk -F '\t' -v OFS='\t' '$1 == "brainstorming" { $3 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } { print }' "$HOME/skills.lock.orig" >"$slock"
run --dry-run --skip-tools "$@"
grep -q "skills.lock: brainstorming is at aaaaaaaaaaaa but plugin superpowers@claude-plugins-official is pinned to" "$out" || fail "lock mismatch not reported"
cp "$HOME/skills.lock.orig" "$slock"
pass "a skip=claude copy on another commit than its plugin is reported"

# Pinned plugin on another commit: reinstalled at the lock. Official plugin on
# another commit while its marketplace offers the lock: reinstalled too.
setsha gsap-skills@gsap-skills 0000000000000000000000000000000000000000
setsha superpowers@claude-plugins-official bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
: >"$stublog"
run --yes --skip-tools "$@"
grep -q '^plugin uninstall --keep-data gsap-skills@gsap-skills' "$stublog" || fail "gsap-skills was not reinstalled"
[ "$(isha gsap-skills@gsap-skills)" = "$(locked gsap-skills@gsap-skills)" ] || fail "gsap-skills is not back at the lock"
[ "$(isha superpowers@claude-plugins-official)" = "$(locked superpowers@claude-plugins-official)" ] ||
  { claude plugin marketplace list --json; ls -laR "$HOME/.claude/plugins/marketplaces"; fail "superpowers is not back at the lock"; }
pass "plugins on another commit are reinstalled at the locked commit"

# The official marketplace offers another commit than the lock: warn only.
off="$HOME/.claude/plugins/marketplaces/claude-plugins-official/.claude-plugin/marketplace.json"
cp "$off" "$HOME/official.orig"
jq '.plugins[0].source.sha = "cccccccccccccccccccccccccccccccccccccccc"' "$HOME/official.orig" >"$off"
setsha superpowers@claude-plugins-official cccccccccccccccccccccccccccccccccccccccc
run --yes --skip-tools "$@"
grep -q "superpowers@claude-plugins-official is installed at cccccccccccc, plugins.lock pins" "$out" || fail "official drift not reported"
cp "$HOME/official.orig" "$off"
run --yes --skip-tools "$@"
pass "official plugin on another commit than the lock: warned, then reinstalled once the marketplace offers the lock"

# A second copy of a plugin from another marketplace: warn, no second install.
jq '.["superpowers-dev"] = {source: {source: "github", repo: "obra/superpowers"}, installLocation: "/nonexistent"}' "$known" >"$known.tmp" && mv "$known.tmp" "$known"
jq '.plugins["superpowers@superpowers-dev"] = [{scope: "user", installPath: "/nonexistent", version: "7.0.2", gitCommitSha: "22f0b463e7a5e579904dd6211a520321035526f7"}]
  | del(.plugins["superpowers@claude-plugins-official"])' "$inst" >"$inst.tmp" && mv "$inst.tmp" "$inst"
: >"$stublog"
run --yes --skip-tools "$@"
grep -q "WARN: claude: superpowers is already installed as superpowers@superpowers-dev, so superpowers@claude-plugins-official was not installed as a second copy. Switch with: claude plugin uninstall superpowers@superpowers-dev && claude plugin install superpowers@claude-plugins-official" "$out" ||
  fail "duplicate plugin not reported with the switch commands"
grep -q 'plugin install superpowers@' "$stublog" && fail "a second copy of superpowers was installed"
pass "plugin installed from another marketplace: warned with the switch commands, no second copy"
run --yes --skip-tools --fix-duplicates "$@"
grep -q '^plugin uninstall superpowers@superpowers-dev' "$stublog" || fail "--fix-duplicates did not uninstall the other copy"
grep -q '^plugin marketplace remove superpowers-dev' "$stublog" || fail "--fix-duplicates did not remove the emptied marketplace"
jq -e '.plugins | has("superpowers@claude-plugins-official") and (has("superpowers@superpowers-dev") | not)' "$inst" >/dev/null || fail "superpowers was not switched"
ls "$HOME"/.agent-setup-backups/*/.claude/plugins/installed_plugins.json >/dev/null 2>&1 || fail "plugin records were not backed up"
pass "--fix-duplicates switches the plugin to the locked marketplace (records backed up)"

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
grep -q 'WARN: .*\(skill\|plugin\|skills.lock\)' "$out" && fail "warnings left after the fixes"
pass "after the fixes: 0 changes, no plugin or skill warnings"

echo "== --update --dry-run"
before=$(snapshot)
run --update --dry-run --skip-tools "$@"
grep -q '^== Update ==' "$out" && grep -q 'plugin superpowers@claude-plugins-official: ' "$out" && grep -q 'skills cloudai-x/threejs-skills' "$out" ||
  fail "--update --dry-run printed no per-entry summary"
grep -q 'Dry run: the lock files were not written' "$out" || fail "--update --dry-run printed no next steps"
[ "$before" = "$(snapshot)" ] || fail "--update --dry-run changed files"
pass "--update --dry-run shows the changes and writes nothing"

echo "ALL CHECKS PASSED ($os)"
