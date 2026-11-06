---
name: create-release
description: Create semantic version releases with automated changelog generation and GitLab release creation. Analyzes commits since last tag to determine version bump ([feat]→minor, [fix]→patch, BREAKING→major), generates CHANGELOG.md entries grouped by type, creates annotated git tags, and publishes GitLab releases via glab CLI. Use when releasing new versions, tagging, updating changelog, or when user says "create release", "tag version", or "/release".
version: 1.0.0
---

# Create Release Skill

Automate semantic versioning releases with CHANGELOG generation and GitLab integration.

## Protocol: Create Release

### 1. Pre-Release Safety Checks

Before any release actions, verify all safety conditions:

**Working Tree Check:**
```bash
git status --porcelain
```
- If output is non-empty: **STOP** and warn user
- Message: "Please commit or stash changes before releasing"

**Branch Check:**
```bash
git branch --show-current
```
- Allowed branches: `main`, `master`
- If on different branch: Use `AskUserQuestion` to confirm proceeding

**Remote Sync Check:**
```bash
git fetch origin
git status -sb
```
- If local is behind remote: **STOP** and warn user to pull first
- If local is ahead: Continue (these are commits to be released)

**Get Last Tag:**
```bash
git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0"
```
- Extract last version tag for base
- Default to `v0.0.0` if no tags exist (first release will be `v0.1.0`)

**glab CLI Check:**
```bash
which glab
```
- If not found: **STOP** with message "glab CLI not installed. Install: https://gitlab.com/gitlab-org/cli"

---

### 2. Analyze Commits Since Last Tag

**Get Commits:**
```bash
git log <last-tag>..HEAD --pretty=format:"%H|%s" --no-merges
```

**Categorization Rules:**

| Prefix Pattern | Category | Version Impact |
|----------------|----------|----------------|
| `[feat]` | Features | MINOR |
| `[fix]` | Bug Fixes | PATCH |
| `[chore]` | Maintenance | PATCH |
| `[refactor]` | Maintenance | PATCH |
| `[docs]` | Maintenance | PATCH |
| `BREAKING` in subject | Breaking Changes | MAJOR |

**Categorize Each Commit:**
1. Check if subject contains `BREAKING` → Breaking Changes (MAJOR)
2. Check prefix `[feat]` → Features (MINOR)
3. Check prefix `[fix]` → Bug Fixes (PATCH)
4. Check prefixes `[chore]`, `[refactor]`, `[docs]` → Maintenance (PATCH)
5. Other commits → Uncategorized (PATCH)

**Handle Edge Cases:**
- **No commits since last tag:** Ask user: "No new commits found. Create PATCH release anyway or cancel?"
- **Only merge commits:** Warn user, offer PATCH release
- **No recognized prefixes:** Default to PATCH, show warning

---

### 3. Calculate New Version

**Parse Current Version:**
Extract from last tag (e.g., `v1.2.3`):
- major = 1
- minor = 2
- patch = 3

**Determine Bump Type:**
Apply highest priority from commit analysis:
- Any BREAKING → MAJOR bump
- Any `[feat]` → MINOR bump (if no BREAKING)
- Otherwise → PATCH bump

**Apply Bump:**
```
MAJOR: major+1, minor=0, patch=0  (v1.2.3 → v2.0.0)
MINOR: minor+1, patch=0          (v1.2.3 → v1.3.0)
PATCH: patch+1                   (v1.2.3 → v1.2.4)
```

**Pre-release Handling:**
If user specified suffix (via `$ARGUMENTS`):
- `alpha` → `v1.3.0-alpha`
- `beta` → `v1.3.0-beta`
- `rc.1` → `v1.3.0-rc.1`
- Check existing tags to auto-increment: `v1.3.0-alpha` exists → `v1.3.0-alpha.1`

**Explicit Version Override:**
If user specified full version (e.g., `v2.0.0`):
- Use that version directly
- Validate format matches `vX.Y.Z` pattern

---

### 4. Confirm Release with User

Present summary using `AskUserQuestion`:

```json
{
  "question": "Ready to create release:\n\n**Version:** v1.2.3 → v1.3.0 (MINOR)\n\n**Changes:**\n- 3 Features\n- 2 Bug Fixes\n- 1 Maintenance\n\nProceed?",
  "header": "Release",
  "multiSelect": false,
  "options": [
    {"label": "Create Release", "description": "Create tag, update CHANGELOG, publish to GitLab"},
    {"label": "Change Version", "description": "Specify different version or add pre-release suffix"},
    {"label": "Preview Only", "description": "Show what would be released without creating anything"},
    {"label": "Cancel", "description": "Abort release process"}
  ]
}
```

**If "Change Version" selected:**
Ask for explicit version input or pre-release suffix.

**If "Preview Only" selected:**
Show CHANGELOG preview and tag details, then ask again.

---

### 5. Generate CHANGELOG Entry

**Entry Format:**
```markdown
## [v1.3.0] - YYYY-MM-DD

### Features
- Add dark mode toggle
- Implement user preferences API

### Bug Fixes
- Fix null pointer in handler
- Resolve race condition in sync

### Maintenance
- Update dependencies
- Refactor authentication module
- Add API documentation
```

**Section Order:**
1. Breaking Changes (if any)
2. Features (from `[feat]`)
3. Bug Fixes (from `[fix]`)
4. Maintenance (from `[chore]`, `[refactor]`, `[docs]`)

**Commit Message Formatting:**
- Strip prefix: `[feat] Add feature` → `Add feature`
- Capitalize first letter if needed
- Remove trailing periods for consistency

**File Update Process:**
1. Check if `CHANGELOG.md` exists
2. If exists: Read current content
3. If missing: Create with header (see below)
4. Insert new entry after header/title
5. Preserve all existing content

**CHANGELOG Header (for new files):**
```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

```

---

### 6. Create Git Tag

**Commit CHANGELOG Changes:**
```bash
git add CHANGELOG.md
git commit -m "$(cat <<'EOF'
[chore] Release v1.3.0

- Update CHANGELOG.md with release notes

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

**Create Annotated Tag:**
```bash
git tag -a v1.3.0 -m "$(cat <<'EOF'
Release v1.3.0

Features:
- Add dark mode toggle
- Implement user preferences API

Bug Fixes:
- Fix null pointer in handler

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Push to Remote:**
```bash
git push origin main
git push origin v1.3.0
```

**Verify Tag:**
```bash
git tag -l "v1.3.0"
```

---

### 7. Create GitLab Release

**Create Release via glab:**
```bash
glab release create v1.3.0 --name "v1.3.0" --notes "$(cat <<'EOF'
## Features
- Add dark mode toggle
- Implement user preferences API

## Bug Fixes
- Fix null pointer in handler
- Resolve race condition in sync

## Maintenance
- Update dependencies
- Refactor authentication module
EOF
)"
```

**Verify Release:**
```bash
glab release view v1.3.0
```

**Report Success:**
Display to user:
- Release URL (from glab output)
- Version summary
- Confirmation of all artifacts created

---

## Edge Cases

| Scenario | Handling |
|----------|----------|
| No commits since last tag | Ask: PATCH anyway or cancel |
| Working tree dirty | STOP with clear message |
| Not on main/master branch | Ask for confirmation |
| Tag already exists | STOP with error message |
| glab not installed | STOP with installation instructions |
| No GitLab remote configured | Skip GitLab release, warn user |
| CHANGELOG.md missing | Create new file with standard header |
| No previous tags | Start from v0.0.0 → v0.1.0 |
| Only merge commits | Warn and offer PATCH |
| Commit without recognized prefix | Include in "Maintenance" section |

---

## Arguments

The skill accepts optional arguments via `$ARGUMENTS`:

| Argument | Effect | Example |
|----------|--------|---------|
| (none) | Auto-determine version | v1.2.3 → v1.3.0 |
| `alpha` | Pre-release suffix | v1.3.0-alpha |
| `beta` | Pre-release suffix | v1.3.0-beta |
| `rc.N` | Release candidate | v1.3.0-rc.1 |
| `vX.Y.Z` | Explicit version | v2.0.0 |

---

## Example Workflow

```
User: /release

Claude: Analyzing commits since v1.2.3...

Found 6 commits:
- 3 Features ([feat])
- 2 Bug Fixes ([fix])
- 1 Maintenance ([chore])

Proposed version: v1.2.3 → v1.3.0 (MINOR bump due to new features)

[AskUserQuestion: Create Release / Change Version / Preview / Cancel]

User: Create Release

Claude:
✓ Updated CHANGELOG.md
✓ Created commit: [chore] Release v1.3.0
✓ Created tag: v1.3.0
✓ Pushed to origin/main
✓ Pushed tag v1.3.0
✓ Created GitLab release

Release v1.3.0 published successfully!
https://gitlab.com/org/repo/-/releases/v1.3.0
```
