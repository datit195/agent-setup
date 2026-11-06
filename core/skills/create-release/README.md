# Create Release Skill

Create semantic version releases with automated changelog generation and GitLab release creation.

## Quick Usage

Use when releasing new versions:
- Analyzes commits since last tag
- Determines version bump (`[feat]`→minor, `[fix]`→patch, `BREAKING`→major)
- Generates CHANGELOG.md entries grouped by type
- Creates annotated git tags
- Publishes GitLab releases via `glab` CLI

**Triggers:**
- "create release"
- "tag version"
- "update changelog"
- `/release`

**Requirements:**
- `glab` CLI installed and configured
- Conventional commit messages with prefixes

---

📖 **Full Documentation:** See [SKILL.md](./SKILL.md) for complete details and protocol.
