# Issue workflow automation

## What it does

When a branch is merged into the repo's default branch, the automation finds the issues linked to that merge, adds the `done` label and closes them. Missing or already-closed issues only produce a warning; the job never fails the pipeline.

Files:

- `github/issue-done.yml`: GitHub Actions workflow.
- `gitlab/issue-done.gitlab-ci.yml`: GitLab CI job.

## How issues are linked

An issue is linked if either is true:

- The PR/MR description contains a closing keyword followed by a same-repo reference, for example `Closes #12`, `fixes: #3`, `Resolves #7`. Keywords (case-insensitive): close, closes, closed, fix, fixes, fixed, resolve, resolves, resolved. Cross-repo references like `other/repo#5` are ignored.
- The branch is named `<type>/<N>-<slug>`, for example `fix/42-login`.

Numbers found both ways are handled once.

## GitHub setup

1. Copy `github/issue-done.yml` to `.github/workflows/issue-done.yml` in the repo.
2. Commit it through the normal issue workflow (branch, PR, merge).

No secrets are needed; the workflow uses the built-in `github.token` with `issues: write`. The `done` label is created if missing.

It only fires for merged pull requests. A direct push to the default branch is handled by GitHub's native closing keywords in commit messages, which close the issue but do not add the `done` label. PRs from forks get a read-only token, so labeling and closing will only log warnings there.

## GitLab setup

1. In the project, create a project access token with the `api` scope and the Reporter role or higher.
2. Add it as a masked CI/CD variable named `ISSUE_BOT_TOKEN`.
3. Include the job: copy `gitlab/issue-done.gitlab-ci.yml` into the repo and add it under `include: - local: ...` in `.gitlab-ci.yml`, or paste the job in directly.

The job runs on pushes to the default branch, looks up the merged MRs for the pushed commit and closes their linked issues. If `ISSUE_BOT_TOKEN` is missing it prints a message and exits successfully.

## Default branch requirement

Issues are closed when work merges into the repo's default branch, whatever it is named: the GitHub workflow checks the PR's base against the repo default, and the GitLab job runs only on `$CI_DEFAULT_BRANCH`. Native closing keywords also only fire on the default branch. If the team merges features into a non-default branch, issues won't close until that work reaches the default branch.

## Related

- `~/.agent-setup/core/rules/issue-workflow.md`
