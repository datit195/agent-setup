---
title: Agent setup
description: Dotfiles-style repo that configures many AI coding agents on macOS, Linux, WSL and Windows from one shared core.
updated: 2026-11-07
status: active
---

# Agent setup

## What it is

One repo, cloned to `~/.agent-setup`, holds the instructions, rules, skills and MCP servers shared by every AI coding agent on the machine. `install.sh` links or merges them into each agent's own config. It is one bash script for macOS, Linux (including WSL) and Windows (run from Git Bash). Files are symlinked, so editing the repo changes every agent at once (on Windows without symlink rights they are copied; see below). Re-running the installer is safe: it only changes what is missing or different.

## Layout

| Path | Contents |
|---|---|
| `core/AGENTS.md`, `core/rules/*.md` | Shared instructions and rules (including coordinator mode) |
| `core/skills/<name>/` | Own skills |
| `core/skills.lock` | Third-party skills pinned to a commit (fetched into `vendor/`) |
| `core/skills.overrides` | Replacement descriptions for third-party skills |
| `core/mcp.json` | Shared MCP servers; `"autoApprove": true` lets agents call a server's tools without asking |
| `core/hooks.json`, `core/hooks/` | Hook definitions for every agent and the hook scripts |
| `agents/<name>/adapter.sh` | Per-agent installer (`detect` and `install`) |
| `shell/env.sh` | Shared agent env (e.g. `IMPECCABLE_NO_TELEMETRY=1`): sourced from `~/.zshrc` / `~/.bashrc`, and the source of Claude Code's `env` and Codex's `shell_environment_policy.set` |
| `agents/claude/` | Claude Code only: `CLAUDE.md` stub, `rules/claude-extras.md` (attribution), `settings.base.json`, `plugins.lock` |
| `tools/Brewfile`, `tools/tools.lock` | CLI tools (`tools.lock` lines may name the OSes they apply to) |
| `git.conf` | Global git identity (set only when unset) |
| `issue-workflow/` | CI templates referenced by the issue-workflow rule |
| `lib/` | Installer helpers (`toml_set.py` adds missing keys to Codex's `config.toml`) |
| `tests/install-test.sh` | Sandbox-HOME install test, run by CI on macOS, Ubuntu and Windows |
| `build/`, `vendor/` | Generated, gitignored |

`build/AGENTS.full.md` is `core/AGENTS.md` plus every `core/rules/*.md` (frontmatter stripped). Agents that read one instruction file link to it. The installer warns when it passes 32 KiB, the Codex limit; Antigravity reads at most 24 KB per file, so keep it below that (about 15 KB now).

Nothing is kept twice. Where an agent's format forces its own file (Codex `config.toml` and `hooks.json`, Antigravity `hooks.json` and CLI settings, Cursor `cli-config.json`, Claude `settings.json`), the installer generates or merges it from the shared files above.

## Third-party skills

| Skill | Source | Pin |
|---|---|---|
| `anatomy` | `wheresryan22/anatomy` (whole repo) | `1482e84` |
| `threejs-*` (13 skills) | `cloudai-x/threejs-skills`, `skills/<name>` | `0e18186` |
| `impeccable` | `pbakaus/impeccable`, `.agents/skills/impeccable` | release `skill-v4.7.0` = `aeeb3d8` |
| `taste-skill` | `Leonxlnx/taste-skill`, `skills/taste-skill` | `9b4bf93` (plugin 2.5.0) |
| `gsap-*` (8 skills) | `greensock/gsap-skills`, `skills/gsap-*` | `aed9cfd` (plugin 1.0.0) |
| superpowers (15 skills) | `obra/superpowers`, `skills/*` | `22f0b46` (plugin 7.0.2) |
| `harness`, `evolve` | `revfactory/harness`, `skills/harness`, `skills/evolve` | `92d9f1b` (plugin 2.1.0) |

The last four are the skills Claude Code gets from its plugins (`agents/claude/plugins.lock`). Their lock lines end with `skip=claude`: Claude keeps the plugins, every other agent gets these pinned copies. Claude's plugins install their current versions; the copies stay at the commits above until `skills.lock` is bumped.

Audit notes (nothing runs at install time; scripts run only when an agent invokes them): gsap and harness are Markdown only. superpowers has shell and Node helpers, including a local brainstorming web server. taste-skill is large (about 39 MB, 1,600 files) and its Node scripts download images (Wikimedia, picsum), icon sets and Google Fonts and start local servers.

`impeccable` is a skill only (no plugin, no hooks), with telemetry off. Its description is overridden so agents use it only when the user says "impeccable" or runs `/impeccable <command>`; `taste-skill` stays the default for general frontend work.

Vendoring is sparse: each `owner/repo@sha` is fetched once as a shallow, blob-less partial clone into `vendor/<owner>__<repo>@<sha>/`, and only the paths `skills.lock` lists for it are checked out (path `.` checks out the whole tree). The impeccable repo is about 1 GB, but its vendor dir is a few MB. When `skills.lock` adds or drops a path for an already fetched commit, the next run updates the checked-out paths in place.

`core/skills.overrides` lines are `name<TAB>description`, optionally followed by `<TAB>explicit`, which also writes `policy.allow_implicit_invocation: false` into the copy's `agents/openai.yaml` so Codex uses the skill only when asked. For each one, the installer copies the vendored skill to `build/skills/<name>/`, replaces the `description:` in its `SKILL.md` frontmatter, and links that copy instead of the vendor dir. The pinned checkout is never edited, and the copy is rebuilt only when the source or the override changes.

## Shared vs per-agent

Shared skills means `~/.agents/skills`, linked once per run.

### Claude Code, Codex, Cursor and Antigravity

| Part | Claude Code | Codex | Cursor | Antigravity |
|---|---|---|---|---|
| Rules | `~/.claude/CLAUDE.md` stub + `~/.claude/rules/*` | `~/.codex/AGENTS.md` | clipboard, paste into User Rules | `~/.gemini/GEMINI.md` |
| Skills | `~/.claude/skills` + plugins | shared | shared (also reads `~/.claude/skills`) | `~/.gemini/config/skills` |
| MCP servers | `claude mcp add --scope user` | `config.toml` `[mcp_servers.*]` | `~/.cursor/mcp.json` | `~/.gemini/config/mcp_config.json` |
| MCP auto-approval | `permissions.allow` `mcp__codegraph__*` | `default_tools_approval_mode = "auto"` | CLI `Mcp(codegraph:*)` | CLI `mcp(codegraph/*)` |
| Hooks | `settings.json` | `~/.codex/hooks.json` (trust once with `/hooks`) | imported from `~/.claude/settings.json` | `~/.gemini/config/hooks.json`, group `agent-setup` |
| Permissions | `defaultMode: "auto"` | `approval_policy = "on-request"`, `sandbox_mode = "workspace-write"`, `approvals_reviewer = "auto_review"` | CLI `approvalMode: "auto-review"` | CLI `agentMode: "auto"` |
| Env | `env` | `[shell_environment_policy.set]` | shell env only | shell env only |
| Subagents | built in | built in | built in | built in |
| Coordinator mode | shared rule | shared rule | shared rule | shared rule |

Config files: Codex `~/.codex/config.toml`; Cursor CLI `~/.cursor/cli-config.json` (`$CURSOR_CONFIG_DIR/cli-config.json` when set; on Linux `$XDG_CONFIG_HOME/cursor/cli-config.json` when that is set); Antigravity CLI `~/.gemini/antigravity-cli/settings.json` (kept at mode 0600). The Cursor and Antigravity apps keep permissions in their UI.

Permissions, approval settings and env are only added when missing: a value the user already set is never changed, a missing file is created, and every edited file is backed up first. Codex does not get sandbox network access.

### Hooks

`core/hooks.json` lists each hook once: its script in `core/hooks/` (or a command), its Claude Code event, and a tool-name regex per agent. The installer renders it into each agent's format:

- **Claude Code:** `settings.json`, running the scripts through the `~/.claude/hooks/` links. An older command for the same script is replaced, not duplicated.
- **Codex:** merged into `~/.codex/hooks.json` (same schema as Claude Code; file edits are the `apply_patch` tool). Codex runs new or changed hooks only after you trust them once with `/hooks`.
- **Cursor:** nothing extra; Cursor loads the Claude Code hooks from `~/.claude/settings.json`. Writing `~/.cursor/hooks.json` too would run them twice.
- **Antigravity:** the `agent-setup` group in `~/.gemini/config/hooks.json`, run through `core/hooks/antigravity-shim.py`. The shim turns Antigravity's camelCase input into Claude Code's shape, turns a blocking exit 2 into `{"decision":"deny"}`, and always exits 0 with JSON. With no objection it returns `{"decision":"allow"}`, which the Antigravity docs define as "defer to the next hook or the default policy" (not auto-approve). PreToolUse cannot add context there, so English-only warnings are queued and injected as an `ephemeralMessage` on the next PreInvocation; the `codegraph prompt-hook` context is injected on PreInvocation once per new user message.

The hook scripts read every agent's input: Claude Code (`Edit`, `Write`, `Bash`, `mcp__*`), Codex (`apply_patch` with the paths and added lines of the patch), Cursor (`Write`, `Shell`, `MCP:*`, `workspace_roots`) and Antigravity (through the shim). A missing or broken script never blocks: the generated commands exit 0 when the script is missing, and the English-only hook always exits 0.

### Other agents

| Agent | Instructions | Skills | MCP servers |
|---|---|---|---|
| gemini | `~/.gemini/GEMINI.md` | shared | `gemini mcp add -s user` |
| copilot | `~/.copilot/copilot-instructions.md` | shared | `~/.copilot/mcp-config.json` |
| opencode | `~/.config/opencode/AGENTS.md` | shared | `~/.config/opencode/opencode.json` (V1 only) |
| devin | `~/.config/devin/AGENTS.md` | shared | `devin mcp add`, else `~/.config/devin/mcp_config.json` |
| amp | `~/.config/amp/AGENTS.md` | shared | `~/.config/amp/settings.json` |
| kiro | `~/.kiro/steering/AGENTS.md` | `~/.kiro/skills` | `~/.kiro/settings/mcp.json` |
| cline | `~/.agents/AGENTS.md` | shared | `cline mcp add` only |
| droid | `~/.factory/AGENTS.md` | shared | `droid mcp add` |
| zed | `~/.config/zed/AGENTS.md` (Windows: `%APPDATA%\Zed\AGENTS.md`) | shared | `settings.json` in the same dir |
| crush | `~/.config/crush/CRUSH.md` | shared | not handled |

Claude Code also gets `settings.base.json` merged into `~/.claude/settings.json` (objects deep-merged, `permissions.allow` unioned) and the plugins in `agents/claude/plugins.lock`.

MCP servers are only ever added. An existing server with the same name is left as it is (Codex still gets `default_tools_approval_mode` added to it when the server is auto-approved).

## New machine

Prerequisites per OS:

- **macOS:** Xcode Command Line Tools (`xcode-select --install`), [Homebrew](https://brew.sh), then `brew install gh`.
- **Linux and WSL:** `git` and `gh` from the package manager (Debian/Ubuntu: `gh` needs GitHub's apt repo, see [cli/cli install_linux.md](https://github.com/cli/cli/blob/trunk/docs/install_linux.md); Fedora: `sudo dnf install gh`; Arch: `sudo pacman -S github-cli`). In WSL, run everything inside WSL; agents running there are configured there.
- **Windows:** [Git for Windows](https://gitforwindows.org) (provides Git Bash, which Claude Code also needs) and winget (`winget install -e --id GitHub.cli`). Optionally turn on Developer Mode (Settings → System → For developers) so the installer can create symlinks. Run every command below from Git Bash.

Then:

```sh
gh auth login
gh repo clone datit195/agent-setup ~/.agent-setup
~/.agent-setup/install.sh --dry-run   # see what it would do
~/.agent-setup/install.sh             # asks before installing missing tools; --yes to skip asking
```

The repo must live at `~/.agent-setup`; the links and the Claude import stub depend on that path.

The tools step installs `gh`, `jq`, `uv` and `node` with Homebrew on macOS (`tools/Brewfile`); on Linux with Homebrew when it is installed, else apt-get, dnf or pacman (`uv` through its official installer); on Windows with winget. Then it installs the `tools/tools.lock` entries for this OS. After winget installs, open a new Git Bash so the tools are on `PATH`, and re-run.

On Windows the installer uses native symlinks when it may create them (Developer Mode or an admin shell). Otherwise it copies the files and warns once: in copy mode, edits in the repo reach the agents only after re-running `install.sh`. Re-runs compare contents, so they still report 0 changes when nothing differs.

Options:

- `--dry-run` prints every action and changes nothing.
- `--agents claude,codex` limits the run to these agents. By default every detected agent is configured. A selected agent is configured even when it is not detected.
- `--skip-tools` skips the package manager step (Homebrew, apt-get/dnf/pacman or winget) and `tools/tools.lock`.
- `--yes` installs missing tools without asking.
- `--allow-any-root` allows another checkout location (tests only).

Steps, in order: tools, git identity, shell env, build (`build/AGENTS.full.md`, `vendor/` and `build/skills/`), then each agent.

The shell env step makes the shell rc files source `shell/env.sh` with one line (added once, after a backup), so agents started from the shell inherit its variables. On macOS that is `~/.zshrc` (created if missing) and `~/.bashrc` if it exists; on Linux, WSL and Windows it is `~/.bashrc` (created if missing) and `~/.zshrc` if it exists. Claude Code also gets them through `env` in `settings.base.json`.

Hook commands use `/usr/bin/python3` when it works, else `python3`, `python` or `py -3`. Without Python 3 the English-only hook is not registered, Antigravity gets no hooks and Codex's `config.toml` is not edited (each with a warning). On Windows, Claude Code runs hook commands in Git Bash with `C:/Users/<name>` paths; Codex and Antigravity get plain commands there (their hook shell is unknown), with Python started through a small `runpy` guard so a missing script still exits 0.

## Updating

```sh
git -C ~/.agent-setup pull && ~/.agent-setup/install.sh
```

## Editing

Edit files in the repo. Rules, skills, hooks and `CLAUDE.md` are symlinks, so changes apply at once. After editing `core/AGENTS.md` or `core/rules/`, re-run `install.sh` to regenerate `build/AGENTS.full.md` (and, for Cursor, paste it again). After editing `core/mcp.json`, `core/hooks.json`, `core/skills.lock`, `core/skills.overrides`, `shell/env.sh`, `plugins.lock` or `settings.base.json`, re-run `install.sh`. Edits to `shell/env.sh` apply in new shells.

To add an agent, create `agents/<name>/adapter.sh` with `detect` and `install`, using the helpers in `lib/`, and add the name to `ALL_AGENTS` in `install.sh`.

## Backups

Anything the installer replaces or edits is first saved under `~/.agent-setup-backups/<run timestamp>/`, at its path relative to `$HOME`. The summary at the end of a run names the folder.

## Not included

- Chat history, sessions, memory and project state.
- `~/.claude.json` and other files holding logins or tokens.
- Logins: run `gh auth login`, start `claude` and sign in, and sign in to each other agent yourself.
- Secrets: keep them out of `core/mcp.json`; the installer never prints env values.

## Known gaps

- Cursor user rules have no file; the installer copies `build/AGENTS.full.md` to the clipboard (pbcopy, wl-copy, xclip, xsel or clip.exe, whichever works) to paste into Cursor → Settings → Rules → User Rules. Cursor also reads `~/.claude/CLAUDE.md`, but whether it follows its `@~/.agent-setup/core/AGENTS.md` import line is unverified, so keep pasting.
- Cursor reads `~/.agents/skills`, `~/.claude/skills`, `~/.codex/skills` and `~/.cursor/skills`, so skills linked in both `~/.agents/skills` and `~/.claude/skills` (own and most vendored skills), and Claude's plugin skills next to their `~/.agents/skills` copies, may show up twice. Only a Cursor setting can turn the third-party skill dirs off.
- Cursor: imported Claude hooks cannot add context on `preToolUse`, so the English-only warning is sent as `agent_message` (it may be ignored), and `codegraph prompt-hook` cannot inject context on `beforeSubmitPrompt`.
- Cursor and Antigravity apps get no env (`shell/env.sh` reaches them only when started from a shell) and keep their permissions in the UI; only their CLIs are configured.
- Antigravity hooks follow the documented format (`TargetFile` path, `injectSteps` with `ephemeralMessage`, `"decision"` output); exit-code handling is undocumented, hence the shim. None of this, and none of the Codex or Cursor settings, was tried against a real Codex, Cursor or Antigravity install, only in the install test.
- Codex and Antigravity on Windows: hook commands assume `bash` and the Python command are on `PATH`; not verified.
- OpenCode V2 MCP config is not handled; add servers by hand.
- Crush MCP servers are not handled; add them to `~/.config/crush/crush.json` by hand.
- Droid's global instructions path (`~/.factory/AGENTS.md`) is unconfirmed.
- Devin, Cline and Droid CLIs are not passed MCP env vars; the installer warns when a server needs them.
- Zed's `settings.json` is usually JSONC; when it has comments the installer skips it with a warning.
- Fish shell is not handled; source `~/.agent-setup/shell/env.sh` from your fish config by hand (it is POSIX sh).
- Windows: the `codegraph` CLI is a `.cmd` launcher, which Git Bash runs only as `codegraph.cmd`; the `codegraph prompt-hook` Claude hook and the `codegraph` and `npx` MCP servers may need a `cmd /c` wrapper there. Not verified.
- Windows: config paths are verified only for Zed (`%APPDATA%\Zed`), Amp, OpenCode and Crush (all under `~/.config`); Devin, Kiro, Cline, Droid, Copilot, Antigravity and Gemini keep their macOS paths under `~`, which is unconfirmed on Windows.
- Linux and Windows: app-only installs (no CLI, no config dir yet) of Cursor, Zed, Kiro, Devin and Antigravity are not detected, because detection looks in `/Applications` on macOS; select them with `--agents`.
- `agent-reach setup` is only tested on macOS.
- The Linux and Windows package-manager installs are exercised in CI only as a dry run.
- Plugins install their current versions, not the reviewed ones.
- Links to removed skills or rules are not cleaned up; delete them by hand.
