#!/usr/bin/env bash
# PreToolUse guard for file edits: block them while a GitHub/GitLab repo is on
# its default branch, master or main. Reads Claude Code, Codex (apply_patch)
# and Cursor hook input; Antigravity runs it through antigravity-shim.py.
# Fails open (exit 0) on any doubt.
# Opt out per repo: git config claude.issueWorkflow off
set -u

jq=/usr/bin/jq
[ -x "$jq" ] || jq=jq
# Windows (Git Bash): turn C:\x or C:/x paths into /c/x.
unix_path() { if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s' "$1"; fi; }

input=$(cat 2>/dev/null) || exit 0
# Edited paths: file_path/notebook_path/path, or the file lines of a Codex patch.
paths=$(printf '%s' "$input" | "$jq" -r '
  (.tool_input // {}) as $t
  | if ($t | type) != "object" then empty
    elif ($t.file_path // $t.notebook_path // $t.path // "") != "" then ($t.file_path // $t.notebook_path // $t.path)
    else (($t.command // $t.patch // $t.input // "") | tostring | split("\n")[]
          | capture("^\\*\\*\\* (Add|Update|Delete) File: (?<p>.+)$|^\\*\\*\\* Move to: (?<p>.+)$")? | .p)
    end' 2>/dev/null | tr -d '\r') || exit 0
[ -n "$paths" ] || exit 0
cwd=$(printf '%s' "$input" | "$jq" -r '.cwd // .workspace_roots[0]? // empty' 2>/dev/null | tr -d '\r')

# check PATH: print the block message and return 1 when PATH must not be edited.
check() {
  local path dir parent top branch default origin
  path=$(unix_path "$1")
  # Relative paths resolve against the hook's cwd.
  if [ "${path#/}" = "$path" ]; then
    [ -n "$cwd" ] || return 0
    path="$(unix_path "$cwd")/$path"
  fi
  # Never guard files inside a .git directory.
  case "/$path/" in */.git/*) return 0 ;; esac
  # Nearest existing ancestor of the file.
  dir=$(dirname -- "$path")
  while [ ! -d "$dir" ]; do
    parent=$(dirname -- "$dir")
    [ "$parent" = "$dir" ] && return 0
    dir=$parent
  done
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 0
  [ -n "$top" ] || return 0
  [ "$(git -C "$top" config --get claude.issueWorkflow 2>/dev/null)" = "off" ] && return 0
  branch=$(git -C "$top" symbolic-ref --short -q HEAD 2>/dev/null) || return 0
  # Default branch from origin/HEAD (local only; empty if not set).
  default=$(git -C "$top" symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null)
  default=${default#origin/}
  case "$branch" in master | main) ;; *) [ -n "$default" ] && [ "$branch" = "$default" ] || return 0 ;; esac
  origin=$(git -C "$top" remote get-url origin 2>/dev/null) || return 0
  case "$origin" in *github.com* | *gitlab*) ;; *) return 0 ;; esac
  echo "Blocked by issue workflow: $(basename -- "$top") is on $branch. First find or create the issue (gh/glab), then create the branch <type>/<N>-<slug> from origin/$branch (see ~/.agent-setup/core/rules/issue-workflow.md). To turn this off for this repo: git config claude.issueWorkflow off" >&2
  return 1
}

while IFS= read -r p; do
  [ -n "$p" ] || continue
  check "$p" || exit 2
done <<EOF2
$paths
EOF2
exit 0
