---
title: Agent setup reference
description: Maintainer reference for agent-setup covering layout, vendoring, plugins per agent, approved versions and updates, duplicates, per-agent paths, hooks, install steps, editing, backups and known gaps.
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
| `core/skills.lock` | Third-party skills and where they come from (no versions); options `skip=<agents>` and `track=<tag glob>` |
| `core/plugins.lock` | Plugins and, per agent, how that agent installs them natively (`claude=`, `codex=`, `antigravity=`; no versions) |
| `state/approved.json`, `state/updates.json` | Per machine, gitignored: the approved version of every item, and the update-check cache with your `--skip` and `--snooze` answers (see [Updates](#updates)) |
| `core/skills.overrides` | Replacement descriptions for third-party skills |
| `core/mcp.json` | Shared MCP servers; `"autoApprove": true` lets agents call a server's tools without asking; `"pin": {"npm": ...}` makes a server's `{version}` the approved one |
| `core/hooks.json`, `core/hooks/` | Hook definitions for every agent and the hook scripts |
| `agents/<name>/adapter.sh` | Per-agent installer (`detect` and `install`) |
| `shell/env.sh` | Shared agent env (e.g. `IMPECCABLE_NO_TELEMETRY=1`): sourced from `~/.zshrc` / `~/.bashrc`, and the source of Claude Code's `env` and Codex's `shell_environment_policy.set` |
| `agents/claude/` | Claude Code only: `CLAUDE.md` stub, `rules/claude-extras.md` (attribution), `settings.base.json` |
| `tools/Brewfile`, `tools/tools.lock` | CLI tools (`tools.lock` lines name the OSes they apply to; `release=<owner/repo>` makes a tool an approved item installed at `{tag}`) |
| `git.conf` | Global git identity (set only when unset) |
| `issue-workflow/` | CI templates referenced by the issue-workflow rule |
| `lib/` | Installer helpers (`toml_set.py` adds missing keys to Codex's `config.toml`; `plugins.sh` reads `core/plugins.lock` and tracks which agent has which plugin natively; `updates.sh` keeps the approved versions and implements `--check`, `--update`, `--snooze`, `--skip` and the session-start notice) |
| `tests/install-test.sh` | Sandbox-HOME install test, run by CI on macOS, Ubuntu and Windows, with stub `claude`, `codex` and `agy` CLIs (`tests/*-stub.sh`) |
| `docs/` | This reference |
| `build/`, `vendor/` | Generated, gitignored (`vendor/<owner>__<repo>/`: one checkout per skills repo; `build/codex-marketplaces/`: Codex's pinned plugin catalogs) |

`build/AGENTS.full.md` is `core/AGENTS.md` plus every `core/rules/*.md` (frontmatter stripped). Agents that read one instruction file link to it. The installer warns when it passes 32 KiB, the Codex limit; Antigravity reads at most 24 KB per file, so keep it below that (about 15 KB now).

Nothing is kept twice. Where an agent's format forces its own file (Codex `config.toml` and `hooks.json`, Antigravity `hooks.json` and CLI settings, Cursor `cli-config.json`, Claude `settings.json`), the installer generates or merges it from the shared files above.

## Third-party skills and vendoring

| Skill | Source | Item | Newer versions are |
|---|---|---|---|
| `anatomy` | `wheresryan22/anatomy` (whole repo) | `anatomy` | default branch commits |
| `threejs-*` (13 skills) | `cloudai-x/threejs-skills`, `skills/<name>` | `threejs-skills` | default branch commits |
| `impeccable` | `pbakaus/impeccable`, `.agents/skills/impeccable` | `impeccable` | `skill-v*` release tags (`track=skill-v*`) |
| `taste-skill` | `Leonxlnx/taste-skill`, `skills/taste-skill` | `taste-skill` | default branch commits |
| `gsap-*` (8 skills) | `greensock/gsap-skills`, `skills/gsap-*` | `gsap-skills` | default branch commits |
| superpowers (15 skills) | `obra/superpowers`, `skills/*` | `superpowers` | the commit Anthropic's official marketplace offers (Claude Code installs it from there) |
| `harness`, `evolve` | `revfactory/harness`, `skills/harness`, `skills/evolve` | `harness` | default branch commits |

An item is one repo: all skills from a repo, and the plugin from it in every agent, share its approved commit.

The last four repos are also plugins (`core/plugins.lock`): a skills.lock entry from a plugin's repo is a copy of that plugin, and an agent that has the plugin natively does not get the copy (see [Plugins per agent](#plugins-per-agent)).

Audit notes (nothing runs at install time; scripts run only when an agent invokes them): gsap and harness are Markdown only. superpowers has shell and Node helpers, including a local brainstorming web server. taste-skill is large (about 39 MB, 1,600 files) and its Node scripts download images (Wikimedia, picsum), icon sets and Google Fonts and start local servers.

`impeccable` is a skill only (no plugin, no hooks), with telemetry off. Its description is overridden so agents use it only when the user says "impeccable" or runs `/impeccable <command>`; `taste-skill` stays the default for general frontend work.

Vendoring is sparse: each repo is a shallow, blob-less partial clone in `vendor/<owner>__<repo>/`, and only the paths `skills.lock` lists for it are checked out (path `.` checks out the whole tree; a repo Antigravity installs as a plugin is checked out whole). The impeccable repo is about 1 GB, but its vendor dir is a few MB. The checkout is at the item's approved commit; a run fetches only when the approved commit changed (after `--update`), and moves the checkout in place, so links into it never dangle. When a fetch fails, the last good copy stays and the run warns and goes on. Vendor dirs no entry uses any more (such as the old pinned `<owner>__<repo>@<sha>` dirs) are removed at the end of the run, once no skill link points into them; links into an old dir are re-pointed at the new one.

### Overrides

`core/skills.overrides` lines are `name<TAB>description`, optionally followed by `<TAB>explicit`, which also writes `policy.allow_implicit_invocation: false` into the copy's `agents/openai.yaml` so Codex uses the skill only when asked. For each one, the installer copies the vendored skill to `build/skills/<name>/`, replaces the `description:` in its `SKILL.md` frontmatter, and links that copy instead of the vendor dir. The vendor checkout is never edited, and the copy is rebuilt only when the source or the override changes.

## Plugins per agent

`core/plugins.lock` lines are the plugin name, its GitHub repo, and `<agent>=<how>` entries. An agent with an entry installs the plugin natively (when its CLI is there), at the approved commit of the plugin's repo; any other agent gets the plugin's skills as vendored copies. No agent auto-updates them. Researched in November 2026 against the docs and source below; the Codex commands were also run against Codex CLI 0.167.0 in a scratch `CODEX_HOME`, the Claude Code ones against Claude Code 2.1.319.

### Matrix

Manifests each plugin repo ships (checked with `gh api`): superpowers has `.claude-plugin/` (plugin and marketplace), `.codex-plugin/`, `.cursor-plugin/`, `.antigravity-plugin/`, `.agents/plugins/marketplace.json` (`superpowers-dev`) and `gemini-extension.json`; taste-skill has `.claude-plugin/marketplace.json`, `.codex-plugin/` and `.agents/plugins/marketplace.json`; gsap-skills has `.claude-plugin/` and `.cursor-plugin/`; harness has `.claude-plugin/` only.

| Plugin | Claude Code | Codex | Cursor | Antigravity |
|---|---|---|---|---|
| superpowers (`obra/superpowers`) | `superpowers@claude-plugins-official` | `superpowers@superpowers-dev` (pinned local catalog) | vendored | `agy plugin install <vendor checkout>` |
| taste-skill (`Leonxlnx/taste-skill`) | `taste-skill@taste-skill` | `taste-skill@taste-skill` (pinned local catalog) | vendored | vendored (no Antigravity manifest) |
| gsap-skills (`greensock/gsap-skills`) | `gsap-skills@gsap-skills` | `gsap-skills@gsap-skills` (pinned local catalog) | vendored | vendored (no Antigravity manifest) |
| harness (`revfactory/harness`) | `harness@harness-marketplace` | `harness@harness-marketplace` (pinned local catalog) | vendored | vendored (no Antigravity manifest) |

Every other agent (Gemini CLI, Copilot, opencode, Kiro, ...) gets vendored skills.

### Claude Code

- Install: `claude plugin marketplace add <owner>/<repo>`, then `claude plugin install <plugin>@<marketplace>` ([create a marketplace](https://code.claude.com/docs/en/plugins/create-marketplace.md), [install plugins](https://code.claude.com/docs/en/plugins/install.md)). The official marketplace is added from `anthropics/claude-plugins-official`.
- Auto-update is off for every marketplace in `core/plugins.lock`, including `claude-plugins-official`: the installer sets `"autoUpdate": false` on the marketplace's `extraKnownMarketplaces` entry in `~/.claude/settings.json`. Per [when auto-update runs](https://code.claude.com/docs/en/plugins/loading.md#when-auto-update-runs), that setting comes first, before the `/plugin` toggle in `known_marketplaces.json` and before the default (on for Anthropic's official marketplaces, off for others). `claude plugin marketplace add` rewrites the entry without `autoUpdate` (seen in 2.1.319), so the installer sets the field after every add.
- An installed plugin is never updated by a plain run. When its approved commit moves (`install.sh --update <item>`), the installer runs `claude plugin marketplace update <marketplace>`, then `claude plugin uninstall --keep-data` and `claude plugin install` (a reinstall, because `claude plugin update` skips commits that keep the version string, see [versions and updates](https://code.claude.com/docs/en/plugins/loading.md#versions-and-updates)). The marketplace offers only its current commit, which is the commit the check reported; if upstream moved in between, the installed commit becomes the approved one, with a warning.
- A new install refreshes its marketplace first (`name@marketplace` installs always do), so it gets the marketplace's current commit; on a first install that is the commit just approved.
- Migration from the old pinned catalogs: a marketplace added from a folder in `build/claude-marketplaces/` is pointed at the author's GitHub repo in place (settings entry first, then `claude plugin marketplace add`), keeping its plugins and their data. `build/claude-marketplaces/` is removed once no marketplace uses it. Plugin records and settings are backed up first.

### Codex

- Install: `codex plugin marketplace add <dir>`, then `codex plugin add <plugin>@<marketplace>` ([build plugins](https://developers.openai.com/codex/plugins/build.md), `codex-rs/cli/src/plugin_cmd.rs` and `marketplace_cmd.rs` in [openai/codex](https://github.com/openai/codex)). The marketplace is a local catalog the installer writes in `build/codex-marketplaces/<marketplace>/.agents/plugins/marketplace.json`, with the author's marketplace name and one entry whose source is `{"source": "url", "url": "https://github.com/<repo>.git", "sha": "<approved commit>"}` (`RawMarketplaceManifestPluginSourceObject` in `codex-rs/core-plugins/src/marketplace.rs`).
- Why not the author's Git marketplace: at startup Codex upgrades every configured Git marketplace and reinstalls its plugins (`maybe_start_plugin_startup_tasks_for_config` in `codex-rs/core-plugins/src/manager.rs`, `upgrade_configured_git_marketplaces_with_mode` in `marketplace_upgrade.rs`); local marketplaces are not upgraded. A Git marketplace pinned with `--ref <full sha>` would also hold still (`git_remote_revision` returns a full sha as is), but taste-skill's `.agents/plugins/marketplace.json` points its plugin at the `main` branch, so only a catalog with a `sha` pins every plugin. `openai-curated` is synced by Codex itself and cannot be pinned, so superpowers comes from the pinned catalog as `superpowers@superpowers-dev` (the name of the author's own marketplace).
- When the approved commit moves, the catalog is rewritten and the plugin reinstalled (`codex plugin remove`, then `codex plugin add`). A marketplace added earlier from the author's Git repo is replaced with the local catalog (`codex plugin marketplace remove`, then add) and its plugin reinstalled.
- Codex reads plugin manifests from `.codex-plugin/plugin.json`, `.claude-plugin/plugin.json` or `.cursor-plugin/plugin.json` (`codex-rs/utils/plugins/src/plugin_namespace.rs`), so gsap-skills and harness install too.
- Verified against a real Codex CLI 0.167.0 (Homebrew) on macOS in November 2026: the install from the pinned catalogs; the replacement of a marketplace added from the author's Git repo; the reinstall when the approved commit moves (the plugin cache then holds the new commit); the `config.toml` keys against `codex-rs/core/config.schema.json`; the skills Codex loads (app server `skills/list`, `codex debug prompt-input`); and `~/.codex/hooks.json` as the app server's `hooks/list` reads it (no warnings; untrusted until `/hooks`). `codex plugin marketplace list --json` gives the source as `marketplaceSource: {sourceType, source}`. Hooks running in a live session need a login and were run only by hand with Codex-shaped input.
- Codex also reads `~/.agents/skills`, which keeps every vendored skill for the other agents that read it (Cursor, Gemini CLI, Copilot, opencode, Amp, Devin, Cline, Droid, Zed, Crush). For each vendored skill of a plugin Codex has natively, the installer adds a `[[skills.config]]` entry to `~/.codex/config.toml` that turns that copy off for Codex:

  ```toml
  [[skills.config]] # agent-setup
  path = "/Users/<name>/.agents/skills/brainstorming/SKILL.md"
  enabled = false
  ```

  Codex resolves symlinks in both an entry's `path` and each loaded skill's path before it compares them (`skill_config_rule_selector` in `codex-rs/config/src/skills_config.rs`, `load_skills_under_root` in `codex-rs/ext/skills/src/loader/host.rs`), so the path through the link turns off the vendored copy while the plugin's own copy, under `~/.codex/plugins/cache/`, stays on. Only entries whose header carries the `# agent-setup` comment are the installer's: it rewrites them at the end of the file on every run and removes the ones for a plugin Codex no longer has; other entries are never changed, and a path the user already has an entry for is left to the user. Codex keeps the comment when it rewrites `config.toml`. Checked with Codex CLI 0.167.0 (app server `skills/list`): each skill is enabled once.

### Cursor

- Plugins (Cursor Plugins and Agent Plugins) are installed from **Customize** in the app or `/plugin` in the CLI's interactive session; there is no documented non-interactive install. `~/.cursor/plugins/local` is for developing plugins, and symlinks out of it are skipped ([Cursor plugins](https://cursor.com/docs/plugins.md)). So Cursor gets vendored skills at the approved commits, and nothing of agent-setup's auto-updates there; installing superpowers or gsap-skills from the Cursor Marketplace yourself would duplicate them.

### Antigravity

- Install: `agy plugin install <dir>` from the vendor checkout of the repo, which is at the approved commit (whole tree); plugins need a `plugin.json` or `.antigravity-plugin/plugin.json` ([Antigravity plugins](https://antigravity.google/docs/plugins)). The docs list GitHub URLs (no ref or commit), local directories and the official marketplace as sources, so a local directory is the only pinnable one. Of the four plugins, only superpowers ships an Antigravity manifest.
- Updates: the docs describe auto-update only for plugins installed in the Antigravity app. The installer reinstalls the plugin (`agy plugin uninstall`, then install) only when the version in the approved checkout differs from the installed one, which happens only after an approval.
- A plugin installed from another source (such as the app) is not replaced: warning, or `--fix-duplicates` uninstalls it first. One installed earlier from `https://github.com/obra/superpowers` counts as the same source and is moved to the approved checkout when its version differs.

## Updates

There is no background or scheduled job, and nothing updates on its own. Each machine keeps the approved version of every item in `state/approved.json` (gitignored, backed up before each change, written by `install.sh` only). The lock files only say where items come from, so approving an update never needs a commit or push, and two machines may be on different approved versions.

| Item kind | Items | Approved version | Newer version |
|---|---|---|---|
| Skills/plugin repo | `anatomy`, `threejs-skills`, `taste-skill`, `gsap-skills`, `harness` | a commit | the default branch head (`git ls-remote`) |
| Tag-tracked repo | `impeccable` | a commit and its tag | the highest tag matching `track=` |
| Official-marketplace plugin repo | `superpowers` | a commit | the commit `anthropics/claude-plugins-official` pins for it |
| MCP server | `playwright` (`"pin": {"npm": "@playwright/mcp"}`) | an npm version, written into the configs as `@playwright/mcp@<version>` | the npm `latest` dist-tag |
| CLI tool | `codegraph`, `agent-reach` (`release=` in `tools.lock`) | a release tag | the GitHub latest release |

**First install.** An item without an approved version gets one: the installed version when there is one (Claude Code's record of the plugin, the vendor checkout, the tool's `--version`), else the newest upstream. Offline, an item that cannot be resolved is left out with a warning until a later run can approve it. A Codex or Cursor config of `playwright` that an older agent-setup wrote (`@latest` or `@0.0.83`) moves to the approved version.

**Plain run.** Installs exactly the approved versions and never moves past them: vendor checkouts, plugins, MCP server args and tools. At the end it prints the pending updates from the cache, without network.

**Check.** `install.sh --check` resolves the newest version of every item (in parallel, with short timeouts) at most once per 24 hours, caches it in `state/updates.json`, and prints `name: old -> new <compare URL>`; `--force` checks now, `--json` prints `{"checked", "behind", "updates": [{"name", "approved", "latest", "url", "state"}]}`. It also fetches origin of `~/.agent-setup` and reports commits this checkout lacks (repo changes such as new rules or skills, not approvals). Without network it prints nothing new and retries after an hour.

**Session-start notice.** The `update-notice.sh` hook (from `core/hooks.json`, event `SessionStart`) runs `install.sh --notice`, which uses the same cache. When something is pending and not skipped or snoozed, it returns text that tells the agent to list the updates (old -> new, compare links) to the user in their language and ask: update now, later, or skip this version; then to run `install.sh --update <names> --yes`, `--snooze <names>` or `--skip <name>@<version>`. Nothing pending: no output. It fails open (exit 0, no output on errors).

| Agent | How the notice arrives |
|---|---|
| Claude Code | `SessionStart` hook in `~/.claude/settings.json`, `hookSpecificOutput.additionalContext` |
| Codex | `SessionStart` hook in `~/.codex/hooks.json`, same output (`codex-rs/hooks/src/events/session_start.rs`); trust it once with `/hooks` |
| Cursor | the Claude Code hook, which Cursor runs as `sessionStart` ([third-party hooks](https://cursor.com/docs/reference/third-party-hooks.md)); the script sees `cursor_version` in the input and returns `additional_context` ([hooks](https://cursor.com/docs/hooks.md)). No `~/.cursor/hooks.json` entry, so it runs once |
| Antigravity | `SessionStart` in `~/.gemini/config/hooks.json` through `antigravity-shim.py session`, returned as `injectSteps` with an `ephemeralMessage` ([hooks](https://antigravity.google/docs/hooks)) |

**Answers.**

- `install.sh --update [names|all] [--yes]` checks upstream now, then asks y/N per item (old -> new and compare URL); with `--yes` it approves only the named items without asking (`--update --yes` without names is refused). It writes `state/approved.json` (keeping the previous version, so MCP configs at it are moved too) and runs the install, which moves only the approved items. `--dry-run` writes nothing.
- `install.sh --snooze <names|all>` hides the items from the notice for 24 hours (`agent-setup` snoozes the new-commits note).
- `install.sh --skip <name>@<version>` hides that version (as shown in the notice) until a newer one appears.

The CLI tools `gh`, `jq`, `uv` and `node` are installed when missing (Homebrew `--no-upgrade`, apt-get, dnf, pacman, winget) and never upgraded; they are not approved items.

## Duplicates

**Plugins.** Before installing `<plugin>@<marketplace>`, the installer lists the installed plugins (`claude plugin list --json`, `codex plugin list --json`, `agy plugin list --json`). When the same plugin name is installed from another marketplace or source (for example `superpowers@superpowers-dev`), it does not install a second copy and warns with the commands to switch, such as `claude plugin uninstall <plugin>@<other> && claude plugin install <plugin>@<marketplace>`. With `--fix-duplicates` it uninstalls the other copy and installs the one in `core/plugins.lock`; for Claude Code it first backs up `~/.claude/settings.json` and the plugin records, and removes the other marketplace when no installed plugin is left in it (never one in `core/plugins.lock`).

**Native plugin and vendored copy.** An agent that has a plugin natively never gets its vendored skills: Claude Code never links them into `~/.claude/skills`, Antigravity's `~/.gemini/config/skills` skips the plugins `agy` installed, and Codex turns its copies in the shared `~/.agents/skills` off in `config.toml` (see [Codex](#codex)), so the other agents that read that dir keep them. A link left from an earlier run is removed, including the links older versions made in `~/.cursor/skills` for the plugins Codex has.

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

- **Claude Code:** `settings.json`, running the scripts through the `~/.claude/hooks/` links. An older command for the same script is replaced, not duplicated. `SessionStart` hooks print context for the new session (the update notice, see [Updates](#updates)).
- **Codex:** merged into `~/.codex/hooks.json` (same schema as Claude Code; file edits are the `apply_patch` tool). Codex runs new or changed hooks only after you trust them once with `/hooks`.
- **Cursor:** nothing extra; Cursor loads the Claude Code hooks from `~/.claude/settings.json`. Writing `~/.cursor/hooks.json` too would run them twice.
- **Antigravity:** the `agent-setup` group in `~/.gemini/config/hooks.json`, run through `core/hooks/antigravity-shim.py`. The shim turns Antigravity's camelCase input into Claude Code's shape, turns a blocking exit 2 into `{"decision":"deny"}`, and always exits 0 with JSON. With no objection it returns `{"decision":"allow"}`, which the Antigravity docs define as "defer to the next hook or the default policy" (not auto-approve). PreToolUse cannot add context there, so English-only warnings are queued and injected as an `ephemeralMessage` on the next PreInvocation; the `codegraph prompt-hook` context is injected on PreInvocation once per new user message.

The hook scripts read every agent's input: Claude Code (`Edit`, `Write`, `Bash`, `mcp__*`), Codex (`apply_patch` with the paths and added lines of the patch), Cursor (`Write`, `Shell`, `MCP:*`, `workspace_roots`) and Antigravity (through the shim). A missing or broken script never blocks: the generated commands exit 0 when the script is missing, and the English-only hook always exits 0.

Hook commands use `/usr/bin/python3` when it works, else `python3`, `python` or `py -3`. Without Python 3 the English-only hook is not registered, Antigravity gets no hooks and Codex's `config.toml` is not edited (each with a warning). On Windows, Claude Code runs hook commands in Git Bash with `C:/Users/<name>` paths; Codex and Antigravity get plain commands there (their hook shell is unknown), with Python started through a small `runpy` guard so a missing script still exits 0.

## Install internals

Steps, in order: tools (base tools, then approving items without an approved version, then the `tools.lock` tools at their approved releases), git identity, shell env, build (`build/AGENTS.full.md`, the skills in `vendor/` at their approved commits, `build/skills/`, and `core/mcp.json` with the approved versions filled in), each agent (native plugins first, then links and config), then cleanup of unused `vendor/` dirs and the pending-updates summary.

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
- Antigravity hooks follow the documented format (`TargetFile` path, `injectSteps` with `ephemeralMessage`, `"decision"` output); exit-code handling is undocumented, hence the shim. None of this, and none of the Cursor settings, was tried against a real Cursor or Antigravity install, only in the install test.
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
- Plugins: the shape of `agy plugin list --json` is read loosely and unverified.
- The official Claude marketplace can lag the superpowers repo (7.0.0 against 7.0.2 in November 2026), and every agent follows the commit it offers.
- Cursor may also import Claude Code's installed plugins (its third-party import setting); if it does, those plugins' skills show up twice there, next to their vendored copies in `~/.agents/skills`. Unverified.
- Turning one of the disabled vendored skills back on in Codex removes its `[[skills.config]]` entry; the next install run adds it again.
- The Antigravity install from a local directory and the Antigravity `SessionStart` hook follow the docs and source but were only run against stub CLIs, not a real Antigravity install.
- Cursor installs plugins only through its UI; plugins you install there are not seen by the duplicate check.
- Links to removed skills or rules are not cleaned up; delete them by hand (links to plugin skills an agent now has natively are removed).
