---
title: Agent setup reference
description: Maintainer reference for agent-setup covering layout, vendoring, plugins per agent, updates, duplicates, per-agent paths, hooks, install steps, editing, backups and known gaps.
updated: 2026-11-07
status: active
---

# Agent setup reference

## Contents

This page holds the details behind the [README](../README.md): how the repo is laid out, where each agent's files go, how skills are vendored, how hooks are generated, and how to change things.

- [Layout](#layout)
- [Third-party skills and vendoring](#third-party-skills-and-vendoring)
- [Plugins per agent](#plugins-per-agent)
- [Updates](#updates)
- [Duplicates](#duplicates)
- [Per-agent paths](#per-agent-paths)
- [Hooks](#hooks)
- [Install internals](#install-internals)
- [Editing](#editing)
- [Adding an agent](#adding-an-agent)
- [Backups](#backups)
- [Known gaps](#known-gaps)

## Layout

| Path | Contents |
|---|---|
| `core/AGENTS.md`, `core/rules/*.md` | Shared instructions and rules (including coordinator mode) |
| `core/skills/<name>/` | Own skills |
| `core/skills.lock` | Third-party skills and where they come from (the latest is fetched into `vendor/` on every run); options `skip=<agents>` and `track=<tag glob>` |
| `core/plugins.lock` | Plugins and, per agent, how that agent installs them natively (`claude=`, `codex=`, `antigravity=`) |
| `core/skills.overrides` | Replacement descriptions for third-party skills |
| `core/mcp.json` | Shared MCP servers; `"autoApprove": true` lets agents call a server's tools without asking |
| `core/hooks.json`, `core/hooks/` | Hook definitions for every agent and the hook scripts |
| `agents/<name>/adapter.sh` | Per-agent installer (`detect` and `install`) |
| `shell/env.sh` | Shared agent env (e.g. `IMPECCABLE_NO_TELEMETRY=1`): sourced from `~/.zshrc` / `~/.bashrc`, and the source of Claude Code's `env` and Codex's `shell_environment_policy.set` |
| `agents/claude/` | Claude Code only: `CLAUDE.md` stub, `rules/claude-extras.md` (attribution), `settings.base.json` |
| `tools/Brewfile`, `tools/tools.lock` | CLI tools (`tools.lock` lines may name the OSes they apply to) |
| `git.conf` | Global git identity (set only when unset) |
| `issue-workflow/` | CI templates referenced by the issue-workflow rule |
| `lib/` | Installer helpers (`toml_set.py` adds missing keys to Codex's `config.toml`; `plugins.sh` reads `core/plugins.lock` and tracks which agent has which plugin natively) |
| `tests/install-test.sh` | Sandbox-HOME install test, run by CI on macOS, Ubuntu and Windows, with stub `claude`, `codex` and `agy` CLIs (`tests/*-stub.sh`) |
| `docs/` | This reference |
| `build/`, `vendor/` | Generated, gitignored (`vendor/<owner>__<repo>/`: one checkout per skills repo) |

`build/AGENTS.full.md` is `core/AGENTS.md` plus every `core/rules/*.md` (frontmatter stripped). Agents that read one instruction file link to it. The installer warns when it passes 32 KiB, the Codex limit; Antigravity reads at most 24 KB per file, so keep it below that (about 15 KB now).

Nothing is kept twice. Where an agent's format forces its own file (Codex `config.toml` and `hooks.json`, Antigravity `hooks.json` and CLI settings, Cursor `cli-config.json`, Claude `settings.json`), the installer generates or merges it from the shared files above.

## Third-party skills and vendoring

| Skill | Source | Follows |
|---|---|---|
| `anatomy` | `wheresryan22/anatomy` (whole repo) | default branch |
| `threejs-*` (13 skills) | `cloudai-x/threejs-skills`, `skills/<name>` | default branch |
| `impeccable` | `pbakaus/impeccable`, `.agents/skills/impeccable` | latest `skill-v*` release tag (`track=skill-v*`) |
| `taste-skill` | `Leonxlnx/taste-skill`, `skills/taste-skill` | default branch |
| `gsap-*` (8 skills) | `greensock/gsap-skills`, `skills/gsap-*` | default branch |
| superpowers (15 skills) | `obra/superpowers`, `skills/*` | default branch |
| `harness`, `evolve` | `revfactory/harness`, `skills/harness`, `skills/evolve` | default branch |

The last four repos are also plugins (`core/plugins.lock`): a skills.lock entry from a plugin's repo is a copy of that plugin, and an agent that has the plugin natively does not get the copy (see [Plugins per agent](#plugins-per-agent)).

Audit notes (nothing runs at install time; scripts run only when an agent invokes them): gsap and harness are Markdown only. superpowers has shell and Node helpers, including a local brainstorming web server. taste-skill is large (about 39 MB, 1,600 files) and its Node scripts download images (Wikimedia, picsum), icon sets and Google Fonts and start local servers.

`impeccable` is a skill only (no plugin, no hooks), with telemetry off. Its description is overridden so agents use it only when the user says "impeccable" or runs `/impeccable <command>`; `taste-skill` stays the default for general frontend work.

Vendoring is sparse: each repo is a shallow, blob-less partial clone in `vendor/<owner>__<repo>/`, and only the paths `skills.lock` lists for it are checked out (path `.` checks out the whole tree). The impeccable repo is about 1 GB, but its vendor dir is a few MB. Every run (not `--dry-run`, which only says it would fetch) fetches the head of the default branch, or the highest tag matching `track=`, and moves the checkout in place when the commit changed, so links into it never dangle; that counts as a change, an unchanged repo does not. When a fetch fails, the last good copy stays and the run warns and goes on. Vendor dirs no entry uses any more (such as the old pinned `<owner>__<repo>@<sha>` dirs) are removed at the end of the run, once no skill link points into them; links into an old dir are re-pointed at the new one.

### Overrides

`core/skills.overrides` lines are `name<TAB>description`, optionally followed by `<TAB>explicit`, which also writes `policy.allow_implicit_invocation: false` into the copy's `agents/openai.yaml` so Codex uses the skill only when asked. For each one, the installer copies the vendored skill to `build/skills/<name>/`, replaces the `description:` in its `SKILL.md` frontmatter, and links that copy instead of the vendor dir. The vendor checkout is never edited, and the copy is rebuilt only when the source or the override changes.

## Plugins per agent

`core/plugins.lock` lines are the plugin name, its GitHub repo, and `<agent>=<how>` entries. An agent with an entry installs the plugin natively (when its CLI is there); any other agent gets the plugin's skills as vendored copies. Researched in November 2026 against the docs and source below; the Codex commands were also run against Codex CLI 0.167.0 in a scratch `CODEX_HOME`, the Claude Code ones against Claude Code 2.1.319.

### Matrix

Manifests each plugin repo ships (checked with `gh api`): superpowers has `.claude-plugin/` (plugin and marketplace), `.codex-plugin/`, `.cursor-plugin/`, `.antigravity-plugin/`, `.agents/plugins/marketplace.json` (`superpowers-dev`) and `gemini-extension.json`; taste-skill has `.claude-plugin/marketplace.json`, `.codex-plugin/` and `.agents/plugins/marketplace.json`; gsap-skills has `.claude-plugin/` and `.cursor-plugin/`; harness has `.claude-plugin/` only.

| Plugin | Claude Code | Codex | Cursor | Antigravity |
|---|---|---|---|---|
| superpowers (`obra/superpowers`) | native, auto-update (`superpowers@claude-plugins-official`, on by default) | native, auto-update (`superpowers@openai-curated`, the author's Codex recommendation; vendored until Codex has synced that marketplace) | vendored | native, refreshed by `install.sh` (`agy plugin install https://github.com/obra/superpowers`) |
| taste-skill (`Leonxlnx/taste-skill`) | native, auto-update (`taste-skill@taste-skill`, turned on by the installer) | native, auto-update (`taste-skill@taste-skill`, from its `.agents/plugins` marketplace) | vendored | vendored (no Antigravity manifest) |
| gsap-skills (`greensock/gsap-skills`) | native, auto-update (`gsap-skills@gsap-skills`, turned on by the installer) | native, auto-update (`gsap-skills@gsap-skills`; Codex reads its `.claude-plugin` marketplace) | vendored | vendored (no Antigravity manifest) |
| harness (`revfactory/harness`) | native, auto-update (`harness@harness-marketplace`, turned on by the installer) | native, auto-update (`harness@harness-marketplace`; Codex reads its `.claude-plugin` marketplace) | vendored | vendored (no Antigravity manifest) |

Every other agent (Gemini CLI, Copilot, opencode, Kiro, ...) gets vendored skills.

### Claude Code

- Install: `claude plugin marketplace add <owner>/<repo>`, then `claude plugin install <plugin>@<marketplace>` ([create a marketplace](https://code.claude.com/docs/en/plugins/create-marketplace.md), [install plugins](https://code.claude.com/docs/en/plugins/install.md)). The official marketplace is added from `anthropics/claude-plugins-official`.
- Auto-update: on by default for `claude-plugins-official`, off for third-party marketplaces. It is turned on with `"autoUpdate": true` on the marketplace's `extraKnownMarketplaces` entry in a settings file, which takes precedence over the `/plugin` toggle stored in `known_marketplaces.json` ([settings reference](https://code.claude.com/docs/en/settings-reference.md#extraknownmarketplaces), [when auto-update runs](https://code.claude.com/docs/en/plugins/loading.md#when-auto-update-runs)). The installer sets it in `~/.claude/settings.json` for each third-party marketplace. `claude plugin marketplace add` rewrites that entry without `autoUpdate` (seen in 2.1.319), so the installer only re-adds a marketplace when it must and sets the field afterwards. Auto-update runs a few minutes into an interactive session; `DISABLE_AUTOUPDATER=1` turns it off unless `FORCE_AUTOUPDATE_PLUGINS=1`.
- A new version arrives only when the plugin's version string changes ([release a new version](https://code.claude.com/docs/en/plugins/host-marketplace.md#release-a-new-version)).
- Each `install.sh` run also runs `claude plugin marketplace update <marketplace>` and `claude plugin update <id>` and reports a plugin as changed when its installed version or commit moved.
- Migration from the old pinned catalogs: a marketplace added from a folder in `build/claude-marketplaces/` is pointed at the author's GitHub repo in place: the installer rewrites the `extraKnownMarketplaces` source in user settings (Claude Code refuses a source that disagrees with it), then runs `claude plugin marketplace add <owner>/<repo>`, which re-points the marketplace and keeps its plugins and their data installed. `build/claude-marketplaces/` is removed once no marketplace uses it. Plugin records and settings are backed up first.

### Codex

- Install: `codex plugin marketplace add <owner>/<repo>`, then `codex plugin add <plugin>@<marketplace>`; installed plugins get `[plugins."<plugin>@<marketplace>"]` in `~/.codex/config.toml` ([build plugins](https://developers.openai.com/codex/plugins/build.md), `codex-rs/cli/src/plugin_cmd.rs` and `marketplace_cmd.rs` in [openai/codex](https://github.com/openai/codex)). `openai-curated` is built in and synced by Codex itself.
- Codex reads marketplaces from `.agents/plugins/marketplace.json` and `.claude-plugin/marketplace.json`, and plugin manifests from `.codex-plugin/plugin.json`, `.claude-plugin/plugin.json` or `.cursor-plugin/plugin.json` (`codex-rs/core-plugins/src/marketplace.rs`, `codex-rs/utils/plugins/src/plugin_namespace.rs`), so gsap-skills and harness install from their Claude marketplaces.
- Auto-update: at startup Codex upgrades every configured Git marketplace and reinstalls the configured plugins from it (`maybe_start_plugin_startup_tasks_for_config` in `codex-rs/core-plugins/src/manager.rs`), and syncs `openai-curated`. There is no per-plugin switch. Each `install.sh` run also runs `codex plugin marketplace upgrade` and reports a change when an installed version moved.
- Codex also reads `~/.agents/skills`, so a plugin Codex has natively (whichever marketplace it came from) is left out of that shared dir. The other agents that read it (Gemini CLI, Copilot, opencode, Amp, Devin, Cline, Droid, Zed, Crush, and Cursor) then miss that plugin's skills; Kiro and Antigravity have their own dirs.

### Cursor

- Plugins (Cursor Plugins and Agent Plugins) are installed from **Customize** in the app or `/plugin` in the CLI's interactive session; there is no documented non-interactive install. `~/.cursor/plugins/local` is for developing plugins, and symlinks out of it are skipped ([Cursor plugins](https://cursor.com/docs/plugins.md)). Team marketplaces (Teams and Enterprise) have Auto Refresh. So Cursor gets vendored skills; installing superpowers or gsap-skills from the Cursor Marketplace yourself would duplicate them.

### Antigravity

- Install: `agy plugin install https://github.com/<owner>/<repo>`; plugins need a `plugin.json` or `.antigravity-plugin/plugin.json` and live in `~/.gemini/config/plugins/<name>/` ([Antigravity plugins](https://antigravity.google/docs/plugins)). Of the four, only superpowers ships an Antigravity manifest.
- Updates: the docs describe no update command, and auto-update only for plugins installed in the Antigravity app. superpowers' README says to reinstall with the same command to update, so each `install.sh` run does that and reports a change when the version moved.
- A plugin installed from another source (such as the app) is not replaced: warning, or `--fix-duplicates` uninstalls it first.

## Updates

There is no background or scheduled job. Plugins update through the agents' own auto-update (Claude Code, Codex); everything else is refreshed whenever `install.sh` runs:

| What | How it follows upstream |
|---|---|
| Vendored skills | Fetched at the default branch head (or latest `track=` tag) on every run |
| Claude Code plugins | Claude Code auto-update; each run also runs its marketplace and plugin update commands |
| Codex plugins | Codex refreshes marketplaces at startup; each run also runs `codex plugin marketplace upgrade` |
| Antigravity plugin | Reinstalled from GitHub on every run |
| MCP `playwright` | `npx -y @playwright/mcp@latest` resolves the latest at each start. A config an older agent-setup wrote with exactly the old pinned args (`@playwright/mcp@0.0.83`) is migrated (Claude Code, Codex, and every agent whose MCP file the installer merges); a value you changed is left alone |
| `codegraph`, `agent-reach` | Installed at their latest release when missing; an installed copy is not upgraded |
| `gh`, `jq`, `uv`, `node` | Installed when missing (Homebrew `--no-upgrade`, apt-get, dnf, pacman, winget); never upgraded |

A re-run when nothing changed upstream reports `0 change(s) made.`; a run where a skill repo or plugin moved counts each move as a change. `--update` is kept as an alias for a plain run. `--dry-run` writes nothing: it prints `would fetch the latest <repo>` and `would update ...` lines without counting them.

Security: third-party code now updates without review. A new commit of a vendored skill reaches every agent on the next `install.sh` run, and a new plugin version reaches Claude Code and Codex on their next auto-update. Keep only sources you trust in the lock files.

## Duplicates

**Plugins.** Before installing `<plugin>@<marketplace>`, the installer lists the installed plugins (`claude plugin list --json`, `codex plugin list --json`, `agy plugin list --json`). When the same plugin name is installed from another marketplace or source (for example `superpowers@superpowers-dev`), it does not install a second copy and warns with the commands to switch, such as `claude plugin uninstall <plugin>@<other> && claude plugin install <plugin>@<marketplace>`. With `--fix-duplicates` it uninstalls the other copy and installs the one in `core/plugins.lock`; for Claude Code it first backs up `~/.claude/settings.json` and the plugin records, and removes the other marketplace when no installed plugin is left in it (never one in `core/plugins.lock`).

**Native plugin and vendored copy.** An agent that has a plugin natively never gets its vendored skills: Claude Code never links them into `~/.claude/skills`, Antigravity's `~/.gemini/config/skills` skips the plugins `agy` installed, and `~/.agents/skills` skips the plugins Codex has. A link left from an earlier run is removed.

**Skills.** Each focus agent's adapter lists the skill folders in every directory the agent reads and warns when a name appears more than once and at least one copy is not managed by agent-setup (a managed copy is a link this run made, or a link into this repo in a directory this run did not link into). It also catches an unmanaged folder with the same name as a managed skill. The directories checked:

| Agent | Skill directories checked |
|---|---|
| Claude Code | `~/.claude/skills`, plus the skills of installed user-scope plugins |
| Codex | `~/.agents/skills`, `~/.codex/skills` |
| Cursor | `~/.agents/skills`, `~/.claude/skills`, `~/.codex/skills`, `~/.cursor/skills` |
| Antigravity | `~/.gemini/config/skills`, `~/.gemini/antigravity/skills` (legacy, unverified) |

Two managed copies of the same skill (Cursor reads both `~/.agents/skills` and `~/.claude/skills`) are expected and not reported. With `--fix-duplicates`, an unmanaged copy is moved to the backup dir, and only when a managed copy of the name exists; plugin folders and a user's own skills found in two places are never moved.

## Per-agent paths

Shared skills means `~/.agents/skills`, linked once per run.

### Claude Code, Codex, Cursor and Antigravity

| Part | Claude Code | Codex | Cursor | Antigravity |
|---|---|---|---|---|
| Rules | `~/.claude/CLAUDE.md` stub + `~/.claude/rules/*` | `~/.codex/AGENTS.md` | clipboard, paste into User Rules | `~/.gemini/GEMINI.md` |
| Skills | `~/.claude/skills` + plugins | shared + plugins | shared (also reads `~/.claude/skills`) | `~/.gemini/config/skills` + plugins |
| MCP servers | `claude mcp add --scope user` | `config.toml` `[mcp_servers.*]` | `~/.cursor/mcp.json` | `~/.gemini/config/mcp_config.json` |
| MCP auto-approval | `permissions.allow` `mcp__codegraph__*` | `default_tools_approval_mode = "auto"` | CLI `Mcp(codegraph:*)` | CLI `mcp(codegraph/*)` |
| Hooks | `settings.json` | `~/.codex/hooks.json` (trust once with `/hooks`) | imported from `~/.claude/settings.json` | `~/.gemini/config/hooks.json`, group `agent-setup` |
| Permissions | `defaultMode: "auto"` | `approval_policy = "on-request"`, `sandbox_mode = "workspace-write"`, `approvals_reviewer = "auto_review"` | CLI `approvalMode: "auto-review"` | CLI `agentMode: "auto"` |
| Env | `env` | `[shell_environment_policy.set]` | shell env only | shell env only |
| Subagents | built in | built in | built in | built in |
| Coordinator mode | shared rule | shared rule | shared rule | shared rule |

Config files: Codex `~/.codex/config.toml`; Cursor CLI `~/.cursor/cli-config.json` (`$CURSOR_CONFIG_DIR/cli-config.json` when set; on Linux `$XDG_CONFIG_HOME/cursor/cli-config.json` when that is set); Antigravity CLI `~/.gemini/antigravity-cli/settings.json` (kept at mode 0600). The Cursor and Antigravity apps keep permissions in their UI.

Permissions, approval settings and env are only added when missing: a value the user already set is never changed, a missing file is created, and every edited file is backed up first. Codex does not get sandbox network access.

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

Claude Code also gets `settings.base.json` merged into `~/.claude/settings.json` (objects deep-merged, `permissions.allow` unioned) and the plugins in `core/plugins.lock`.

MCP servers are only ever added. An existing server with the same name is left as it is (Codex still gets `default_tools_approval_mode` added to it when the server is auto-approved), unless it is exactly what an older agent-setup wrote: a server's `oldArgs` in `core/mcp.json` lists those values, and a match is replaced with the current one (Claude Code, Codex and the agents whose MCP file the installer merges; not the agents configured through their own `mcp add` CLI: Gemini CLI, Devin, Cline and Droid).

## Hooks

`core/hooks.json` lists each hook once: its script in `core/hooks/` (or a command), its Claude Code event, and a tool-name regex per agent. The installer renders it into each agent's format:

- **Claude Code:** `settings.json`, running the scripts through the `~/.claude/hooks/` links. An older command for the same script is replaced, not duplicated.
- **Codex:** merged into `~/.codex/hooks.json` (same schema as Claude Code; file edits are the `apply_patch` tool). Codex runs new or changed hooks only after you trust them once with `/hooks`.
- **Cursor:** nothing extra; Cursor loads the Claude Code hooks from `~/.claude/settings.json`. Writing `~/.cursor/hooks.json` too would run them twice.
- **Antigravity:** the `agent-setup` group in `~/.gemini/config/hooks.json`, run through `core/hooks/antigravity-shim.py`. The shim turns Antigravity's camelCase input into Claude Code's shape, turns a blocking exit 2 into `{"decision":"deny"}`, and always exits 0 with JSON. With no objection it returns `{"decision":"allow"}`, which the Antigravity docs define as "defer to the next hook or the default policy" (not auto-approve). PreToolUse cannot add context there, so English-only warnings are queued and injected as an `ephemeralMessage` on the next PreInvocation; the `codegraph prompt-hook` context is injected on PreInvocation once per new user message.

The hook scripts read every agent's input: Claude Code (`Edit`, `Write`, `Bash`, `mcp__*`), Codex (`apply_patch` with the paths and added lines of the patch), Cursor (`Write`, `Shell`, `MCP:*`, `workspace_roots`) and Antigravity (through the shim). A missing or broken script never blocks: the generated commands exit 0 when the script is missing, and the English-only hook always exits 0.

Hook commands use `/usr/bin/python3` when it works, else `python3`, `python` or `py -3`. Without Python 3 the English-only hook is not registered, Antigravity gets no hooks and Codex's `config.toml` is not edited (each with a warning). On Windows, Claude Code runs hook commands in Git Bash with `C:/Users/<name>` paths; Codex and Antigravity get plain commands there (their hook shell is unknown), with Python started through a small `runpy` guard so a missing script still exits 0.

## Install internals

Steps, in order: tools, git identity, shell env, build (`build/AGENTS.full.md`, the latest skills in `vendor/`, and `build/skills/`), each agent (native plugins first, then links and config), then cleanup of unused `vendor/` dirs.

The repo must live at `~/.agent-setup`; the links and the Claude import stub depend on that path. `--allow-any-root` allows another checkout location (tests only).

The tools step installs `gh`, `jq`, `uv` and `node` with Homebrew on macOS (`tools/Brewfile`); on Linux with Homebrew when it is installed, else apt-get, dnf or pacman (`uv` through its official installer); on Windows with winget. Then it installs the `tools/tools.lock` entries for this OS. After winget installs, open a new Git Bash so the tools are on `PATH`, and re-run.

On Windows the installer uses native symlinks when it may create them (Developer Mode or an admin shell). Otherwise it copies the files and warns once: in copy mode, edits in the repo reach the agents only after re-running `install.sh`. Re-runs compare contents, so they still report 0 changes when nothing differs.

The shell env step makes the shell rc files source `shell/env.sh` with one line (added once, after a backup), so agents started from the shell inherit its variables. On macOS that is `~/.zshrc` (created if missing) and `~/.bashrc` if it exists; on Linux, WSL and Windows it is `~/.bashrc` (created if missing) and `~/.zshrc` if it exists. Claude Code also gets them through `env` in `~/.claude/settings.json`, merged from `shell/env.sh`.

## Editing

Edit files in the repo. Rules, skills, hooks and `CLAUDE.md` are symlinks, so changes apply at once. After editing `core/AGENTS.md` or `core/rules/`, re-run `install.sh` to regenerate `build/AGENTS.full.md` (and, for Cursor, paste it again). After editing `core/mcp.json`, `core/hooks.json`, `core/skills.lock`, `core/plugins.lock`, `core/skills.overrides`, `shell/env.sh` or `settings.base.json`, re-run `install.sh`. Edits to `shell/env.sh` apply in new shells.

## Adding an agent

Create `agents/<name>/adapter.sh` with `detect` and `install`, using the helpers in `lib/`, and add the name to `ALL_AGENTS` in `install.sh`.

## Backups

Anything the installer replaces or edits is first saved under `~/.agent-setup-backups/<run timestamp>/`, at its path relative to `$HOME`. The summary at the end of a run names the folder.

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
- Plugins: the Codex and Antigravity installs follow their docs and source; Codex was run in a scratch `CODEX_HOME`, Antigravity was not run (no `agy` here), and the shape of `agy plugin list --json` and whether `agy plugin install` over an installed plugin succeeds are unverified. `superpowers@openai-curated` was not installable in a scratch Codex home that had never started a session, hence the vendored fallback.
- `superpowers@openai-curated` is OpenAI's copy of superpowers and can lag the upstream repo (6.3.0 against 7.0.2 in November 2026).
- When Codex has a plugin natively, the other agents that read `~/.agents/skills` lose its vendored skills (see [Codex](#codex)).
- Cursor installs plugins only through its UI; plugins you install there are not seen by the duplicate check.
- A Claude Code or Codex plugin gets new commits only when its author bumps the version.
- Links to removed skills or rules are not cleaned up; delete them by hand (links to plugin skills an agent now has natively are removed).
