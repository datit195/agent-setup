---
title: Claude extras
description: Claude Code only additions to the shared core rules, covering hooks, skills and commit attribution
updated: 2026-11-06
status: active
---

# Claude extras

These items extend the shared rules in `~/.agent-setup/core/rules/` and apply to Claude Code only, because they rely on Claude hooks, Claude skills or Claude attribution.

## Issue workflow

Additions to `core/rules/issue-workflow.md`:

- A guard hook (`~/.claude/hooks/issue-branch-guard.sh`) blocks file edits on the default branch and on `master`/`main` in GitHub/GitLab repos, so the branch must exist before the first edit.
- The guard hook honours the per-repo opt-out `git config claude.issueWorkflow off`.

### Fit with other rules and skills

- **Coordinator mode:** the coordinator creates or identifies the issue and branch (or delegates that) before delegating any edit task, and puts the issue number and branch name in every subagent brief. Subagents work on that branch.
- **Superpowers `using-git-worktrees`:** worktree branches use the same `<type>/<N>-<slug>` naming.
- **Superpowers `finishing-a-development-branch`:** finishing means a PR/MR into `<default>` with `Closes #N`.
- **`push` skill:** still applies; commits it makes carry `Refs #N`.

## Language

Enforcement of `core/rules/language.md`:

- A hook (`~/.claude/hooks/english-only-warn.py`) warns when a write contains Vietnamese.
- When warned, rewrite in English, unless an exception applies; then say briefly which one.
- A repo can turn the warning off with `git config claude.englishOnly off`.

## Git attribution

In place of the placeholder co-author line in `core/rules/git-style.md`, Claude Code uses:

- Commit messages end with `Co-Authored-By: Claude <noreply@anthropic.com>`, or the model-specific line the session gives.
- MR/PR descriptions end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

The commit example in the original rule also carried the `🤖 Generated with [Claude Code](https://claude.com/claude-code)` line above the co-author line.
