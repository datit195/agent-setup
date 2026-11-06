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
| `core/mcp.json` | Shared MCP servers |
| `agents/<name>/adapter.sh` | Per-agent installer (`detect` and `install`) |
| `agents/claude/` | Claude Code extras: `CLAUDE.md` stub, rules, hooks, `settings.base.json`, `plugins.lock` |
| `tools/Brewfile`, `tools/tools.lock` | CLI tools |
| `git.conf` | Global git identity (set only when unset) |
| `issue-workflow/` | CI templates referenced by the issue-workflow rule |
| `lib/` | Installer helpers |
| `build/`, `vendor/` | Generated, gitignored |

`build/AGENTS.full.md` is `core/AGENTS.md` plus every `core/rules/*.md` (frontmatter stripped). Agents that read one instruction file link to it. The installer warns when it passes 32 KiB, the Codex limit.

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

Steps, in order: tools, git identity, build (`build/AGENTS.full.md` and `vendor/`), then each agent.

## Updating

```sh
git -C ~/.agent-setup pull && ~/.agent-setup/install.sh
```

## Editing

Edit files in the repo. Rules, skills, hooks and `CLAUDE.md` are symlinks, so changes apply at once. After editing `core/AGENTS.md` or `core/rules/`, re-run `install.sh` to regenerate `build/AGENTS.full.md` (and, for Cursor, paste it again). After editing `core/mcp.json`, `core/skills.lock`, `plugins.lock` or `settings.base.json`, re-run `install.sh`.

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
