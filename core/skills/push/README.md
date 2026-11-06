# Push Skill

Commit and push changes following git-style rules with proper commit message prefixes.

## Quick Usage

Use when:
- Saving and pushing changes to remote
- Creating commits with proper formatting
- Following team git conventions

**Triggers:**
- "push"
- "commit and push"
- `/push`

**Workflow:**
1. Analyzes changes (git status, diff)
2. Determines commit prefix (`[feat]`, `[fix]`, `[chore]`, `[refactor]`, `[docs]`)
3. Stages changes
4. Generates commit message with Co-Authored-By
5. Handles pre-commit hooks
6. Pushes to remote
7. Auto-creates Notion ticket (if configured)

**Commit Prefixes:**
- `[feat]` - New features
- `[fix]` - Bug fixes
- `[chore]` - Minor updates
- `[refactor]` - Significant restructuring
- `[docs]` - Documentation only

---

📖 **Full Documentation:** See [SKILL.md](./SKILL.md) for complete details and protocol.
