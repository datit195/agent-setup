# Agent setup

<div align="center">

### One config for every AI coding agent on your machine

**Rules · skills · MCP servers · hooks · settings, written once and installed into Claude Code, Codex, Cursor, Antigravity and 10 more agents**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

[![macOS](https://img.shields.io/badge/macOS-supported-blue.svg)](#supported-platforms)
[![Linux / WSL](https://img.shields.io/badge/Linux_%2F_WSL-supported-blue.svg)](#supported-platforms)
[![Windows](https://img.shields.io/badge/Windows_(Git_Bash)-supported-blue.svg)](#supported-platforms)

[![Claude Code](https://img.shields.io/badge/Claude_Code-supported-blueviolet.svg)](#supported-agents)
[![Codex](https://img.shields.io/badge/Codex-supported-blueviolet.svg)](#supported-agents)
[![Cursor](https://img.shields.io/badge/Cursor-supported-blueviolet.svg)](#supported-agents)
[![Antigravity](https://img.shields.io/badge/Antigravity-supported-blueviolet.svg)](#supported-agents)

</div>

## Contents

- [Why agent setup?](#why-agent-setup)
- [Quick start](#quick-start)
- [What you get](#what-you-get)
- [Supported agents](#supported-agents)
- [Supported platforms](#supported-platforms)
- [How it works](#how-it-works)
- [Not included](#not-included)
- [Known gaps](#known-gaps)
- [Troubleshooting](#troubleshooting)
- [Reference](#reference)
- [License](#license)

## Why agent setup?

Every AI coding agent wants its own instruction file, its own skills folder, its own MCP config and its own hook format. Keep several agents in sync by hand and they drift: one follows the git style and another does not, one has the MCP server and another lost it.

**This repo is the single source.** Rules, skills, MCP servers, hooks and settings live once in `~/.agent-setup`. One bash script, `install.sh`, links or merges them into each agent's own config on macOS, Linux (including WSL) and Windows (from Git Bash).

| | |
|---|---|
| **Nothing kept twice** | Each rule, skill, server and hook is written once; files an agent's format forces on it are generated or merged from the shared ones |
| **Symlinked** | Edit a rule in the repo and every agent sees it at once (Windows without symlink rights falls back to copies) |
| **Safe to re-run** | The installer only changes what is missing or different; a clean re-run reports `0 change(s) made.` |
| **Keeps your choices** | Permissions, approval settings, env and MCP servers are only added when missing, never changed |
| **Backed up** | Every file it replaces or edits is saved first under `~/.agent-setup-backups/<run timestamp>/` |
| **Dry run first** | `--dry-run` prints every action and changes nothing |

## Quick start

### 1. Install and sign in to your agents

Install the agents you use (Claude Code, Codex, Cursor, Antigravity, ...) and sign in to each one first. The installer configures every agent it detects; it never signs in for you.

### 2. Install the prerequisites

<details open>
<summary><b>macOS</b></summary>

```sh
xcode-select --install   # Xcode Command Line Tools (git)
# Install Homebrew from https://brew.sh, then:
brew install gh
```

</details>

<details>
<summary><b>Linux and WSL</b></summary>

Install `git` and `gh` from the package manager:

- Debian/Ubuntu: `gh` needs GitHub's apt repo, see [cli/cli install_linux.md](https://github.com/cli/cli/blob/trunk/docs/install_linux.md).
- Fedora: `sudo dnf install gh`
- Arch: `sudo pacman -S github-cli`

In WSL, run everything inside WSL; agents running there are configured there.

</details>

<details>
<summary><b>Windows</b></summary>

- Install [Git for Windows](https://gitforwindows.org). It provides Git Bash, which Claude Code also needs.
- Install the GitHub CLI with winget: `winget install -e --id GitHub.cli`
- Optional: turn on Developer Mode (Settings → System → For developers) so the installer can create symlinks.

Run every command below from **Git Bash**.

</details>

### 3. Clone and install

```sh
gh auth login
gh repo clone datit195/agent-setup ~/.agent-setup
~/.agent-setup/install.sh --dry-run   # see what it would do
~/.agent-setup/install.sh             # asks before installing missing tools; --yes to skip asking
```

<sub>The repo must live at `~/.agent-setup`; the links and the Claude import stub depend on that path.</sub>

| Option | What it does |
|---|---|
| `--dry-run` | Print every action, change nothing |
| `--agents claude,codex` | Only these agents. By default every detected agent is configured; a selected agent is configured even when it is not detected |
| `--check` | List newer upstream versions of what is installed (`--json` for JSON, `--force` to check upstream now); see [Updates](#updates-you-approve-every-update) |
| `--update [names\|all]` | Approve newer versions (asks per item; `--yes` approves the named ones) and install them |
| `--snooze <names\|all>`, `--skip <name>@<version>` | Ask about an update again in 24 hours, or not for this version |
| `--fix-duplicates` | Switch plugins installed from another marketplace or source to the one in `core/plugins.lock`; move unmanaged duplicate skills to the backups |
| `--skip-tools` | Skip the package manager step (Homebrew, apt-get/dnf/pacman or winget) and `tools/tools.lock` |
| `--yes` | Install missing tools without asking; with `--update <names>`, approve them without asking |
| `-h`, `--help` | Show help |

### 4. After the install

- **Open a new terminal** so the shared env and new tools are picked up. On Windows, after winget installs, open a new Git Bash and re-run `install.sh`.
- **Cursor:** the installer copies the full rules to the clipboard; paste them into Cursor → Settings → Rules → User Rules.
- **Codex:** run `/hooks` once in Codex to trust the hooks; Codex runs new or changed hooks only after that.

### 5. Verify

```sh
~/.agent-setup/install.sh   # a second run should end with "0 change(s) made."
claude mcp list             # codegraph and playwright should be listed
```

### Updates: you approve every update

Nothing agent-setup installed changes without your yes. Every third-party skill repo, plugin, MCP server and CLI tool has an **approved version on each machine**, kept in `~/.agent-setup/state/approved.json` (local, never committed). The first install approves what is already installed, or else the newest upstream version. After that, `install.sh` installs exactly the approved versions and never moves past them, and the agents' own auto-update is off (Claude Code marketplaces have `autoUpdate: false`, Codex plugins come from pinned local catalogs, Antigravity's plugin is reinstalled only after an approval).

When an author publishes something newer, every agent tells you at the start of a session (a session-start hook, checked against upstream at most once a day, silent when nothing is pending):

```text
Newer upstream versions exist for items agent-setup installed on this machine:
- superpowers: bb92a7774141 -> 22f0b463e7a5 https://github.com/obra/superpowers/compare/bb92a7774141...22f0b463e7a5
```

The agent then asks you, in your language, what to do with each item, and runs the matching command after you answer:

| Your answer | Command the agent runs |
|---|---|
| Update now | `~/.agent-setup/install.sh --update <names> --yes` |
| Later | `~/.agent-setup/install.sh --snooze <names>` (asks again in 24 hours) |
| Skip this version | `~/.agent-setup/install.sh --skip <name>@<version>` (asks again only when a newer version appears) |

The same from a terminal:

```sh
~/.agent-setup/install.sh --check          # list pending updates: name: old -> new <compare link>
~/.agent-setup/install.sh --update         # asks y/N per item, then installs the approved ones
~/.agent-setup/install.sh --update superpowers,codegraph --yes
```

Each machine asks and approves separately, so two machines may run different approved versions. Approving never commits or pushes anything. When the repo itself has new commits on GitHub (new rules or skills you added elsewhere), the notice also says so; run `git -C ~/.agent-setup pull && ~/.agent-setup/install.sh`.

Details: [updates](docs/reference.md#updates), [plugins per agent](docs/reference.md#plugins-per-agent).

**Duplicates.** The installer never gives an agent the same skill twice: an agent that has a plugin natively does not get its vendored copy. It warns when a plugin is already installed from another marketplace (it does not install a second copy), or when a skill is in more than one folder an agent reads. `install.sh --fix-duplicates` switches such plugins to the source in `core/plugins.lock` and moves unmanaged duplicate skill folders to the backups.

## What you get

### Shared instructions and rules

Every agent gets `core/AGENTS.md` plus every rule in `core/rules/` (combined into one file for agents that read a single instruction file).

| Rule | What it says |
|---|---|
| `AGENTS.md` | Behavioral guidelines: think before coding, simplicity first, surgical changes, goal-driven execution; use CodeGraph first in indexed repos |
| `coordinator-mode.md` | The main agent plans, delegates to subagents and verifies; it does not do the work itself |
| `git-style.md` | Commit prefixes (`[feat]`, `[fix]`, `[chore]`, `[refactor]`, `[docs]`), HEREDOC commit messages, MR format; never commit unless asked |
| `issue-workflow.md` | Every change starts as an issue, gets a `<type>/<N>-<slug>` branch and lands through a PR/MR with `Closes #N` |
| `language.md` | Chat in any language, but everything the agent writes is in English |
| `markdown-style.md` | Every `.md` file starts with a `title`/`description`/`updated`/`status` frontmatter |
| `claude-extras.md` | Claude Code only: hook notes for the issue workflow and English-only rule, and Claude's commit/PR attribution lines |

### Own skills

| Skill | What it is for |
|---|---|
| `push` | Commit and push following the git-style rules |
| `create-release` | Semantic version releases: version bump from commits, `CHANGELOG.md`, annotated tag, GitLab release via `glab` |

### Third-party skills

Listed in `core/skills.lock`; each repo is checked out into `vendor/` at the commit approved on this machine. Nothing runs at install time.

| Skill | Source | What it is for |
|---|---|---|
| `anatomy` | `wheresryan22/anatomy` | Detailed, interactive isometric SVG figures that explain technical ideas |
| `threejs-*` (13 skills) | `cloudai-x/threejs-skills` | three.js: scenes, geometry, materials, lighting, shaders, loaders, animation, performance, React Three Fiber and more |
| `impeccable` | `pbakaus/impeccable` | Design toolkit (polish, audit, critique, animate, ...); used only when you say "impeccable" or run `/impeccable <command>` |
| `taste-skill` | `Leonxlnx/taste-skill` | The default skill for frontend and website design work |
| `gsap-*` (8 skills) | `greensock/gsap-skills` | Official GSAP skills: core, timelines, ScrollTrigger, plugins, React, other frameworks, utils, performance |
| superpowers (15 skills) | `obra/superpowers` | Brainstorming, plans, TDD, debugging, code review, subagent-driven development, worktrees |
| `harness`, `evolve` | `revfactory/harness` | Design an agent team (harness) for a project and evolve it from feedback |

### Plugins

The last four sources above are also plugins (`core/plugins.lock`). Each agent that can install a plugin natively gets it that way, under the id its author recommends; the other agents get the vendored skills.

| Plugin | Claude Code | Codex | Antigravity | Cursor and the rest |
|---|---|---|---|---|
| `superpowers` | `superpowers@claude-plugins-official` | `superpowers@superpowers-dev` | `agy plugin install` from the approved checkout | vendored skills |
| `taste-skill` | `taste-skill@taste-skill` | `taste-skill@taste-skill` | vendored skills | vendored skills |
| `gsap-skills` | `gsap-skills@gsap-skills` | `gsap-skills@gsap-skills` | vendored skills | vendored skills |
| `harness` | `harness@harness-marketplace` | `harness@harness-marketplace` | vendored skills | vendored skills |

Every plugin stays at its approved version: auto-update is off, and Codex installs from local catalogs pinned to the approved commit. The shared `~/.agents/skills` keeps every vendored skill for the agents that read it; Codex reads it too, so the installer turns its copies of the plugins Codex has natively off in `~/.codex/config.toml` (`[[skills.config]]` entries marked `# agent-setup`).

### MCP servers

| Server | What it is | Approval |
|---|---|---|
| `codegraph` | [CodeGraph](https://github.com/colbymchenry/codegraph) code intelligence (`codegraph serve --mcp`); index a project with `codegraph init` | Auto-approved |
| `playwright` | [microsoft/playwright-mcp](https://github.com/microsoft/playwright-mcp), `@playwright/mcp@<approved version>` | Asks as usual |

### Hooks

| Hook | When | What it does |
|---|---|---|
| Issue-branch guard | Before a file edit | Blocks edits on the default branch (and `master`/`main`) of GitHub/GitLab repos, so work happens on an issue branch. Opt out per repo: `git config claude.issueWorkflow off` |
| English-only warning | Before a file write, shell command or MCP write | Warns when the content contains Vietnamese; never blocks. Opt out per repo: `git config claude.englishOnly off` |
| CodeGraph prompt context | On each user prompt | Runs `codegraph prompt-hook` to add CodeGraph context |
| Update notice | At session start | Tells the agent which installed items have newer versions, so it asks you (see [Updates](#updates-you-approve-every-update)); silent otherwise |

Hooks fail open: a missing or broken script never blocks.

### Settings

- **Permissions:** Claude Code runs in auto mode (`defaultMode: "auto"`); Codex uses `on-request` approvals with a `workspace-write` sandbox and auto review; the Cursor and Antigravity CLIs use their auto modes. Only added when you have not set a value.
- **Env:** `IMPECCABLE_NO_TELEMETRY=1` (impeccable telemetry off) from `shell/env.sh`, sourced by your shell and also written into Claude Code's and Codex's config.
- **Git identity:** `user.name` and `user.email` from `git.conf`, set only when unset.

### CLI tools

| Tool | Installed with |
|---|---|
| `gh`, `jq`, `uv`, `node` | Homebrew on macOS; Homebrew, apt-get, dnf or pacman on Linux; winget on Windows (installed when missing, never upgraded) |
| `codegraph` | Its official installer, at the approved release |
| `agent-reach` | `uv tool install` of the approved release, then `agent-reach setup` |

## Supported agents

### Focus agents

| | Claude Code | Codex | Cursor | Antigravity |
|---|:---:|:---:|:---:|:---:|
| Rules | ✔ | ✔ | partial: paste into User Rules | ✔ |
| Skills | ✔ (+ plugins) | ✔ (+ plugins) | ✔ | ✔ (+ plugins) |
| MCP servers + auto-approval | ✔ | ✔ | ✔ | ✔ |
| Hooks | ✔ | ✔ (trust once with `/hooks`) | partial: imported from Claude Code, cannot add context | ✔ (through a shim) |
| Permissions / auto mode | ✔ | ✔ | partial: CLI only | partial: CLI only |
| Env | ✔ | ✔ | partial: shell only | partial: shell only |
| Subagents + coordinator mode | ✔ | ✔ | ✔ | ✔ |

### Other agents

Gemini CLI, GitHub Copilot, opencode, Devin, Amp, Kiro, Cline, Factory Droid, Zed and Crush get the shared instructions and skills, and the MCP servers where the installer can write their config (not Crush or OpenCode V2). Where each file goes: [per-agent paths](docs/reference.md#per-agent-paths).

## Supported platforms

| Platform | Run from | Package manager | Links |
|---|---|---|---|
| macOS | Terminal | Homebrew | Symlinks |
| Linux and WSL | Terminal (inside WSL for WSL) | Homebrew, else apt-get, dnf or pacman | Symlinks |
| Windows | Git Bash | winget | Symlinks with Developer Mode or an admin shell, else copies (re-run `install.sh` after edits) |

## How it works

```
~/.agent-setup
  core/AGENTS.md + core/rules/     shared instructions
  core/skills/ + skills.lock       own and third-party skills
  core/plugins.lock                plugins installed natively per agent
  state/approved.json              approved versions on this machine (local)
  core/mcp.json                    MCP servers
  core/hooks.json + core/hooks/    hooks
  shell/env.sh, tools/, git.conf   env, CLI tools, git identity
        │
        │  install.sh:  tools → git identity → shell env → build → agents
        ▼
  Claude Code · Codex · Cursor · Antigravity · 10 more agents
  (symlinks, merged settings, generated hook and MCP config per agent)
```

1. **Tools:** installs missing CLI tools (asks first unless `--yes`).
2. **Git identity and shell env:** sets the git identity if unset and makes your shell source `shell/env.sh`.
3. **Build:** combines the rules into `build/AGENTS.full.md` and checks out the third-party skills into `vendor/` at their approved commits.
4. **Agents:** each agent's adapter installs its native plugins at the approved versions, links the rules and skills, adds the MCP servers, renders the hooks into the agent's format and merges its settings.

## Not included

- Logins and tokens: run `gh auth login`, start `claude` and sign in, and sign in to each other agent yourself.
- Chat history, sessions, memory and project state.
- `~/.claude.json` and other files holding logins or tokens.
- Secrets: keep them out of `core/mcp.json`; the installer never prints env values.

## Known gaps

- Cursor has no file for user rules, so you paste them; its imported hooks cannot add context.
- The Cursor and Antigravity apps get no env and keep permissions in their UI; only their CLIs are configured.
- The Cursor and Antigravity setups are checked by the install test, not yet against real installs. The Codex setup was also checked against a real Codex CLI 0.167.0 on macOS, except the hooks running in a live session, which needs a login (see [Reference](docs/reference.md#codex)).
- Some Windows config paths and the `codegraph` launcher on Windows are not verified.
- Cursor installs plugins only from its UI, so it gets vendored skills; Antigravity installs plugins from GitHub only when the repo has an Antigravity manifest (only `superpowers` has one).

Full list: [docs/reference.md#known-gaps](docs/reference.md#known-gaps).

## Troubleshooting

**A hook blocks every edit.** The issue-branch guard blocks edits on the default branch: create an issue branch, or turn the guard off for that repo with `git config claude.issueWorkflow off`. If a hook fails on everything, re-run `~/.agent-setup/install.sh` to rewrite the hook config.

**Something broke after an install.** Every replaced or edited file is in `~/.agent-setup-backups/<run timestamp>/`, at its path relative to `$HOME`; the run summary names the folder. Copy the file back.

**A tool is not found right after the install.** Open a new terminal (on Windows, a new Git Bash) and re-run `install.sh`.

**Codex ignores the hooks.** Run `/hooks` in Codex and trust them.

**Cursor does not follow the rules.** Re-run `install.sh` and paste the clipboard into Cursor → Settings → Rules → User Rules.

**An agent was not configured.** App-only installs on Linux and Windows are not detected; select the agent with `--agents <name>`.

## Reference

Layout, per-agent paths, vendoring and overrides, hook generation, install internals, editing, adding an agent, backups and the full list of known gaps: [docs/reference.md](docs/reference.md).

## License

MIT — see [LICENSE](LICENSE). The vendored third-party skills and the plugins keep their own licenses.
