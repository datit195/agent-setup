---
title: Language
description: Chat in any language, but everything the agent writes is in English
updated: 2026-11-06
status: active
---

# Language

Chat with the user in any language. Everything the agent writes is in English.

## Chat

- Reply to the user in the session in English or Vietnamese; there is no fixed reply language.

## Writes are English

Write in English any content the agent creates or changes:

- **Repo files:** code, comments, docs, config, test names, log and error messages.
- **Git:** commit messages, branch names, tags, changelog entries.
- **GitHub/GitLab:** issue and PR/MR titles, descriptions, comments, labels.
- **External docs and platforms:** Notion, Google Docs, Claude Docs, artifacts.
- **Messages to other people:** Slack, Telegram, email.
- **The agent's own files:** memory, rules, skills, agent briefs and subagent prompts.

## Translate the user's words

When the user's Vietnamese request ends up in an artifact (an issue title, a commit message, a doc), write the English translation, not the original text.

## Exceptions

Keep Vietnamese for:

- Translation and locale files, e.g. `vi.json`, `locales/`, `i18n/`.
- Product content meant for Vietnamese users (UI copy, marketing text) when the project is built for them.
- Text quoted verbatim, e.g. a Telegram message, a user's quote, or test data that must be Vietnamese (same as `markdown-style.md`).
- Proper names of people, places and brands; keep their spelling and diacritics.
- Writing the user explicitly asks to have in Vietnamese, for that piece only.

## Enforcement

Before writing, check that the content is English unless an exception applies.
