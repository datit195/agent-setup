---
title: Agent setup
description: Dotfiles-style repo that configures many AI coding agents on macOS from one shared core.
updated: 2026-11-06
status: active
---

# Agent setup

## What it is

One repo, cloned to `~/.agent-setup`, holds the instructions, rules, skills and MCP servers shared by every AI coding agent on this Mac. `install.sh` links or merges them into each agent's own config. Files are symlinked, so editing the repo changes every agent at once. Re-running the installer is safe: it only changes what is missing or different.

## Layout

| Path | Contents |
|---|---|
| `core/AGENTS.md`, `core/rules/*.md` | Shared instructions and rules |
| `core/skills/<name>/` | Own skills |
| `core/skills.lock` | Third-party skills pinned to a commit (fetched into `vendor/`) |
| `core/skills.overrides` | Replacement descriptions for third-party skills |
| `core/mcp.json` | Shared MCP servers |
| `agents/<name>/adapter.sh` | Per-agent installer (`detect` and `install`) |
| `shell/env.sh` | Shared shell env (e.g. `IMPECCABLE_NO_TELEMETRY=1`), sourced from `~/.zshrc` |
| `agents/claude/` | Claude Code extras: `CLAUDE.md` stub, rules, hooks, `settings.base.json`, `plugins.lock` |
| `tools/Brewfile`, `tools/tools.lock` | CLI tools |
| `git.conf` | Global git identity (set only when unset) |
| `issue-workflow/` | CI templates referenced by the issue-workflow rule |
| `lib/` | Installer helpers |
| `build/`, `vendor/` | Generated, gitignored |

`build/AGENTS.full.md` is `core/AGENTS.md` plus every `core/rules/*.md` (frontmatter stripped). Agents that read one instruction file link to it. The installer warns when it passes 32 KiB, the Codex limit.

## Third-party skills

| Skill | Source | Pin |
|---|---|---|
| `anatomy` | `wheresryan22/anatomy` (whole repo) | `1482e84` |
| `threejs-*` (13 skills) | `cloudai-x/threejs-skills`, `skills/<name>` | `0e18186` |
| `impeccable` | `pbakaus/impeccable`, `.agents/skills/impeccable` | release `skill-v4.7.0` = `aeeb3d8` |

`impeccable` is a skill only (no plugin, no hooks), with telemetry off. Its description is overridden so agents use it only when the user says "impeccable" or runs `/impeccable <command>`; `taste-skill` stays the default for general frontend work.

Vendoring is sparse: each `owner/repo@sha` is fetched once as a shallow, blob-less partial clone into `vendor/<owner>__<repo>@<sha>/`, and only the paths `skills.lock` lists for it are checked out (path `.` checks out the whole tree). The impeccable repo is about 1 GB, but its vendor dir is a few MB. When `skills.lock` adds or drops a path for an already fetched commit, the next run updates the checked-out paths in place.

`core/skills.overrides` lines are `name<TAB>description`. For each one, the installer copies the vendored skill to `build/skills/<name>/`, replaces the `description:` in its `SKILL.md` frontmatter, and links that copy instead of the vendor dir. The pinned checkout is never edited, and the copy is rebuilt only when the source or the override changes.

## Shared vs per-agent

Shared skills means `~/.agents/skills`, linked once per run.

| Agent | Instructions | Skills | MCP servers |
|---|---|---|---|
| claude | `~/.claude/CLAUDE.md` stub + `~/.claude/rules/*` | `~/.claude/skills` | `claude mcp add --scope user` |
| codex | `~/.codex/AGENTS.md` | shared | `codex mcp add` |
| cursor | clipboard, paste into User Rules | shared | `~/.cursor/mcp.json` |
| gemini | `~/.gemini/GEMINI.md` | shared | `gemini mcp add -s user` |
| antigravity | `~/.gemini/GEMINI.md` | `~/.gemini/config/skills` | `~/.gemini/config/mcp_config.json` |
| copilot | `~/.copilot/copilot-instructions.md` | shared | `~/.copilot/mcp-config.json` |
| opencode | `~/.config/opencode/AGENTS.md` | shared | `~/.config/opencode/opencode.json` (V1 only) |
| devin | `~/.config/devin/AGENTS.md` | shared | `devin mcp add`, else `~/.config/devin/mcp_config.json` |
| amp | `~/.config/amp/AGENTS.md` | shared | `~/.config/amp/settings.json` |
| kiro | `~/.kiro/steering/AGENTS.md` | `~/.kiro/skills` | `~/.kiro/settings/mcp.json` |
| cline | `~/.agents/AGENTS.md` | shared | `cline mcp add` only |
| droid | `~/.factory/AGENTS.md` | shared | `droid mcp add` |
| zed | `~/.config/zed/AGENTS.md` | shared | `~/.config/zed/settings.json` |
| crush | `~/.config/crush/CRUSH.md` | shared | not handled |

Claude Code also gets hooks in `~/.claude/hooks/`, `settings.base.json` merged into `~/.claude/settings.json` (objects deep-merged, `permissions.allow` unioned, hook entries added only when their command is not already there), and the plugins in `agents/claude/plugins.lock`.

MCP servers are only ever added. An existing server with the same name is left as it is.

## New machine

```sh
gh auth login
gh repo clone datit195/agent-setup ~/.agent-setup
~/.agent-setup/install.sh --dry-run   # see what it would do
~/.agent-setup/install.sh
```

The repo must live at `~/.agent-setup`; the links and the Claude import stub depend on that path.

Options:

- `--dry-run` prints every action and changes nothing.
- `--agents claude,codex` limits the run to these agents. By default every detected agent is configured. A selected agent is configured even when it is not detected.
- `--skip-tools` skips Homebrew and `tools/tools.lock`.
- `--yes` installs missing tools without asking.
- `--allow-any-root` allows another checkout location (tests only).

Steps, in order: tools, git identity, shell env, build (`build/AGENTS.full.md`, `vendor/` and `build/skills/`), then each agent.

The shell env step makes `~/.zshrc` source `shell/env.sh` with one line (added once, after a backup; the file is created if missing), so agents started from the shell inherit its variables. Claude Code also gets them through `env` in `settings.base.json`.

## Updating

```sh
git -C ~/.agent-setup pull && ~/.agent-setup/install.sh
```

## Editing

Edit files in the repo. Rules, skills, hooks and `CLAUDE.md` are symlinks, so changes apply at once. After editing `core/AGENTS.md` or `core/rules/`, re-run `install.sh` to regenerate `build/AGENTS.full.md` (and, for Cursor, paste it again). After editing `core/mcp.json`, `core/skills.lock`, `core/skills.overrides`, `plugins.lock` or `settings.base.json`, re-run `install.sh`. Edits to `shell/env.sh` apply in new shells.

To add an agent, create `agents/<name>/adapter.sh` with `detect` and `install`, using the helpers in `lib/`, and add the name to `ALL_AGENTS` in `install.sh`.

## Backups

Anything the installer replaces or edits is first saved under `~/.agent-setup-backups/<run timestamp>/`, at its path relative to `$HOME`. The summary at the end of a run names the folder.

## Not included

- Chat history, sessions, memory and project state.
- `~/.claude.json` and other files holding logins or tokens.
- Logins: run `gh auth login`, start `claude` and sign in, and sign in to each other agent yourself.
- Secrets: keep them out of `core/mcp.json`; the installer never prints env values.

## Known gaps

- Cursor user rules have no file; the installer copies `build/AGENTS.full.md` to the clipboard to paste into Cursor → Settings → Rules → User Rules.
- OpenCode V2 MCP config is not handled; add servers by hand.
- Crush MCP servers are not handled; add them to `~/.config/crush/crush.json` by hand.
- Droid's global instructions path (`~/.factory/AGENTS.md`) is unconfirmed.
- Devin, Cline and Droid CLIs are not passed MCP env vars; the installer warns when a server needs them.
- Zed's `settings.json` is usually JSONC; when it has comments the installer skips it with a warning.
- Hooks are Claude-only.
- Plugins install their current versions, not the reviewed ones.
- Links to removed skills or rules are not cleaned up; delete them by hand.
