---
name: push
description: |
  Commit and push changes following git-style rules. Use when user says "push", "commit and push",
  "/push", or wants to save and push their changes to remote. Handles staging, commit message
  generation with proper prefixes ([feat], [fix], [chore], [refactor], [docs]), and push to remote.
---

# Push Skill

Stage, commit, and push changes following team git conventions.

## Workflow

### 1. Analyze Changes

Run in parallel:
```bash
git status
git diff --staged
git diff
git log --oneline -5
```

### 2. Determine Commit Prefix

| Changes Include | Prefix |
|-----------------|--------|
| New functionality, features | `[feat]` |
| Bug fixes, error corrections | `[fix]` |
| Minor updates, renames, cleanup | `[chore]` |
| Significant restructuring | `[refactor]` |
| Only .md files, comments, docstrings | `[docs]` |

### 3. Stage Changes

```bash
git add -A  # or specific files if user specified
```

### 4. Generate Commit Message

Use HEREDOC format:
```bash
git commit -m "$(cat <<'EOF'
[prefix] Short summary (imperative mood)

- Bullet point describing change
- Another change if applicable

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

**Message rules:**
- First line: prefix + summary under 72 chars
- Blank line after summary
- Bullet points for details (optional if changes are obvious)
- Always include Co-Authored-By

### 5. Handle Pre-commit Hooks

| Result | Action |
|--------|--------|
| Success | Proceed to push |
| Hook auto-modified files | Run `git add -A && git commit --amend --no-edit` |
| Hook rejected | Fix issues, create NEW commit (never amend rejected) |

### 6. Push to Remote

```bash
git push -u origin HEAD
```

If push fails (no upstream), use:
```bash
git push --set-upstream origin $(git branch --show-current)
```

### 7. Create Notion Ticket (Auto)

After successful push, **automatically create a Notion ticket** for the commit:

1. Check if context file exists (`.claude/tmp/notion_context.json` or `~/.claude/tmp/notion_context.json`)
2. Get the pushed commit hash (short form, 7 chars)
3. Parse commit message for task name and type
4. Run the Python script with commit ID:
   ```bash
   python3 ~/.claude/scripts/notion_ticket.py "Task Name" "Description" --cid abc1234
   ```
5. Report created ticket ID and URL

**Skip ticket creation only if:**
- Context file doesn't exist (skill not initialized)
- Commit is a merge commit (`Merge branch` or `Merge pull request`)
- Commit is a revert (`Revert "..."`)
- User explicitly says "no ticket" or "skip ticket" in the push request

**Ticket naming from commit:**
| Commit Prefix | Task Type | Name Extraction |
|---------------|-----------|-----------------|
| `[feat]` | Feature | Remove prefix, capitalize |
| `[fix]` | 🐞 Bug | Remove prefix, capitalize |
| `[chore]` | Feature | Remove prefix, capitalize |
| `[refactor]` | Feature | Remove prefix, capitalize |
| `[docs]` | Feature | Remove prefix, capitalize |

## Critical Rules

1. **NEVER use `--no-verify`** without explicit user permission
2. **NEVER force push** without explicit user permission
3. **NEVER amend** already-pushed commits
4. If on main/master, warn user before pushing directly

## Example Output

```
Analyzing changes...

Staged: 3 files (2 modified, 1 new)
- src/auth/handler.py (modified)
- src/auth/token.py (modified)
- tests/test_auth.py (new)

Committing with prefix [feat]:

[feat] Add JWT token validation

- Implement token verification in handler
- Add token refresh logic
- Add unit tests for auth flow

Co-Authored-By: Claude <noreply@anthropic.com>

Pushing to origin/feature/auth...
Done.
```
