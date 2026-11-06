---
title: Markdown conventions
description: Every .md file starts with a frontmatter of title, description, updated and status
updated: 2026-11-06
status: active
---

# Markdown conventions

Every `.md` file in the repo (rules, memory, skills, agents, docs) starts with:

```markdown
---
title: Document name
description: One sentence about its purpose
updated: 2026-10-10
status: active
---
```

- `updated` uses `YYYY-MM-DD` and is bumped on every content change.
- `status`: `draft` (being written), `active` (in force), `deprecated` (no longer used; the agent must not rely on it).
- `core/AGENTS.md` in the agent-setup repo is kept verbatim without frontmatter.
- Skills and agents keep the `name` and `description` keys Claude Code requires in the same frontmatter.
- After the frontmatter comes a `# Title` heading, then `## Sections`.
- Written in English. Only text that is quoted as a Telegram message may be Vietnamese.
- Checked by `npm run lint:md`.
