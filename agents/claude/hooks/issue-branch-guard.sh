#!/usr/bin/env bash
# PreToolUse guard (Edit|Write|NotebookEdit): block file edits while a
# GitHub/GitLab repo is on its default branch, master or main.
# Fails open (exit 0) on any doubt.
# Opt out per repo: git config claude.issueWorkflow off
set -u

jq=/usr/bin/jq
[ -x "$jq" ] || jq=jq
# Windows (Git Bash): turn C:\x or C:/x paths into /c/x.
unix_path() { if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s' "$1"; fi; }

input=$(cat 2>/dev/null) || exit 0
path=$(printf '%s' "$input" | "$jq" -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null) || exit 0
[ -n "$path" ] || exit 0
path=$(unix_path "$path")

# Relative paths resolve against the hook's cwd.
if [ "${path#/}" = "$path" ]; then
  cwd=$(printf '%s' "$input" | "$jq" -r '.cwd // empty' 2>/dev/null) || exit 0
  [ -n "$cwd" ] || exit 0
  path="$(unix_path "$cwd")/$path"
fi

# Never guard files inside a .git directory.
case "/$path/" in */.git/*) exit 0 ;; esac

# Nearest existing ancestor of the file.
dir=$(dirname -- "$path")
while [ ! -d "$dir" ]; do
  parent=$(dirname -- "$dir")
  [ "$parent" = "$dir" ] && exit 0
  dir=$parent
done

top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -n "$top" ] || exit 0

[ "$(git -C "$top" config --get claude.issueWorkflow 2>/dev/null)" = "off" ] && exit 0

branch=$(git -C "$top" symbolic-ref --short -q HEAD 2>/dev/null) || exit 0
# Default branch from origin/HEAD (local only; empty if not set).
default=$(git -C "$top" symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null)
default=${default#origin/}
case "$branch" in master|main) ;; *) [ -n "$default" ] && [ "$branch" = "$default" ] || exit 0 ;; esac

origin=$(git -C "$top" remote get-url origin 2>/dev/null) || exit 0
case "$origin" in *github.com*|*gitlab*) ;; *) exit 0 ;; esac

repo=$(basename -- "$top")
echo "Blocked by issue workflow: $repo is on $branch. First find or create the issue (gh/glab), then create the branch <type>/<N>-<slug> from origin/$branch (see ~/.agent-setup/core/rules/issue-workflow.md). To turn this off for this repo: git config claude.issueWorkflow off" >&2
exit 2
