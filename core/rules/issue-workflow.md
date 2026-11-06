---
title: Issue workflow
description: Every change starts as an issue, is built on its own branch, and the issue is closed with a done label when merged into the default branch
updated: 2026-11-06
status: active
---

# Issue workflow

Every change starts as an issue, is built on its own branch, and lands in the repo's default branch through a PR/MR that closes the issue.

## When it applies

Apply this workflow to any task that changes files in a git repo whose `origin` remote is on GitHub or GitLab.

Skip it when:

- The task is a question or read-only work.
- The folder is not a git repo, or the repo has no GitHub/GitLab `origin`.
- The user explicitly says to skip it for this task.
- The repo has opted out permanently: `git config claude.issueWorkflow` returns `off` (set with `git config claude.issueWorkflow off`).

## Pick the platform

Run `git remote get-url origin`:

- Contains `github.com` → use `gh`.
- Contains `gitlab` → use `glab`. If `glab` is missing or not logged in, tell the user to run `brew install glab` and `glab auth login`, and stop.

Find the default branch: `git symbolic-ref --short refs/remotes/origin/HEAD` and strip `origin/`. If that fails, use `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` (GitHub) or `glab repo view -F json | jq -r .default_branch` (GitLab). This rule calls it `<default>` from here on.

In repos with more than one long-lived branch (e.g. git-flow: `develop` is default, releases go to `master`), issues are closed when work merges into the default branch.

## Step 1 — Issue first

Before editing anything:

1. If the user gave an issue number or link, use that issue.
2. Otherwise search open issues for one that already covers the task: `gh issue list --search "<keywords>"` / `glab issue list --search "<keywords>"`.
3. If none fits, create one with a clear title and a body that states the problem or goal plus a short `Done when` checklist.
4. Tell the user the issue number and link.

## Step 2 — Branch

1. `git fetch origin`.
2. Create the branch from the latest default branch: `git switch -c <branch> origin/<default>`.
3. Name it `<type>/<N>-<short-kebab-slug>`:
   - `<type>` is one of `feat`, `fix`, `chore`, `refactor`, `docs` (same meaning as the prefixes in `git-style.md`).
   - `<N>` is the issue number.
   - Example: `fix/42-login-redirect`.
4. If already on the right issue branch, continue there.
5. One issue per branch.

Create the branch before the first edit.

## Step 3 — Commits

- Follow `git-style.md` for prefix and format.
- Add a `Refs #N` line in the commit body.
- Only commit when the user asks (git-style rule 1).

## Step 4 — PR/MR into `<default>`

Only when the user asks to open it:

- GitHub: `gh pr create --base <default>`.
- GitLab: `glab mr create --target-branch <default>`.
- Title uses the git-style prefix, e.g. `[fix] Fix login redirect`.
- Description contains `Closes #N` on its own line, plus the Summary and Test plan sections from `git-style.md`. Both platforms close the issue when this merges into the default branch.
- Never merge unless the user asks.

## Step 5 — On merge (automatic)

- The `Closes #N` keyword closes the issue.
- A per-repo automation also adds a `done` label and closes any issue the keyword missed (it also reads the issue number from the branch name).
- Templates live in `~/.agent-setup/issue-workflow/`:
  - GitHub: copy `github/issue-done.yml` to `.github/workflows/issue-done.yml`.
  - GitLab: include `gitlab/issue-done.gitlab-ci.yml` in `.gitlab-ci.yml`; needs an `ISSUE_BOT_TOKEN` CI variable.
  - Setup steps: `~/.agent-setup/issue-workflow/README.md`.
- The first time this workflow is used in a repo that lacks the automation, offer to add it as its own small issue and branch, following this same workflow. Do not add it without the user's yes.
