# Git and MR Style

---

## Commit Prefixes

| Prefix | Use For |
|--------|---------|
| `[feat]` | New feature |
| `[fix]` | Bug fix |
| `[chore]` | Minor update/rename |
| `[refactor]` | Impactful update |
| `[docs]` | Documentation only changes |

---

## Commit Message Format

Use HEREDOC for proper formatting:

```bash
git commit -m "$(cat <<'EOF'
[feat] Add user authentication endpoint

- Implement JWT token validation
- Add login/logout endpoints

Co-Authored-By: <your agent name and model> <its noreply address, if any>
EOF
)"
```

End commits with your own agent's co-author line.

---

## Critical Rules

1. **NEVER commit without user request** - Only commit when explicitly asked
2. **NEVER use `--no-verify`** without asking user first
3. **NEVER amend pushed commits** without explicit user permission
4. **NEVER force push to main/master** - warn user if requested
5. **Check staged changes** - Run `git status` and `git diff` before committing
6. **Follow repo conventions** - Check recent commits for style

---

## Pre-commit Hook Failures

| Scenario | Action |
|----------|--------|
| Hook **REJECTED** | Fix issue, create NEW commit (never amend) |
| Hook **auto-modified files** | May amend ONLY if commit succeeded and not pushed |

---

## Merge Request Rules (GitLab)

### MR Creation Format

```bash
glab mr create --title "[feat] Add feature name" --description "$(cat <<'EOF'
## Summary
- Brief description of changes
- Key implementation details

## Test plan
- [ ] Unit tests added
- [ ] E2E tests passing
- [ ] Manual testing completed

Co-Authored-By: <your agent name and model> <its noreply address, if any>
EOF
)"
```

### Before Creating MR

1. Run `git status` to check untracked files
2. Run `git diff` to review staged/unstaged changes
3. Run `git log` to check recent commit style
4. Verify branch is up-to-date with remote
5. Ensure all tests pass

### MR Description Requirements

- **Summary section:** 1-3 bullet points
- **Test plan:** Checklist of testing steps
- **Link related issues** if applicable
