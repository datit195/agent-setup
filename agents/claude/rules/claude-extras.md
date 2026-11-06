---
title: Claude extras
description: Claude Code only additions to the shared core rules, covering commit attribution
updated: 2026-11-07
status: active
---

# Claude extras

These items extend the shared rules in `~/.agent-setup/core/rules/` and apply to Claude Code only.

## Git attribution

In place of the placeholder co-author line in `core/rules/git-style.md`, Claude Code uses:

- Commit messages end with `Co-Authored-By: Claude <noreply@anthropic.com>`, or the model-specific line the session gives.
- MR/PR descriptions end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

The commit example in the original rule also carried the `🤖 Generated with [Claude Code](https://claude.com/claude-code)` line above the co-author line.
