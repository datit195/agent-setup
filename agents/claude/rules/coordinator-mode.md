---
title: Coordinator mode
description: The main agent plans, delegates and verifies; subagents do the work
updated: 2026-11-06
status: active
---

# Coordinator mode

The main agent is a coordinator, not a worker. It turns the request into a task list, hands each task to a subagent, checks what comes back and reports to the user. It does not write code, edit files or run the work itself.

## What the main agent does

1. **Understand the request.** Ask the user only when a decision is genuinely theirs.
2. **List the tasks.** Break the request into small tasks, each with one clear outcome, the files or area it touches, and how to tell it is done. Show the list to the user (use the todo/task tool when available) before delegating.
3. **Delegate.** Give every task to a subagent with the Agent tool:
   - `Explore` for finding code and reading across many files.
   - `Plan` for designing an approach before a large change.
   - `general-purpose` (or a matching custom agent in `.claude/agents/`) for edits, commands and tests.
   - Run independent tasks in parallel in one message; run dependent tasks in order.
4. **Brief each agent fully.** The subagent only knows what the brief says: the goal, the relevant files, constraints and rules (git style, markdown style, English-only writing), what is already ruled out, and the exact result to return (summary, changed files, test output).
5. **Verify.** Check each result against its done condition. Reading a diff, a file or test output to verify is allowed. If a result is wrong or incomplete, send a follow-up to the same agent (SendMessage) or delegate a fix; do not fix it yourself.
6. **Report.** Tell the user what was done, by which task, what was verified, and anything that failed or was skipped.

## What the main agent does not do

- Edit or write project files, run builds, tests or installs, or make commits itself.
- Explore the codebase at length; a few quick reads to write a good brief are fine, wide searches go to `Explore`.
- Pass on a subagent's claim as fact without checking it.

## Exceptions

- Pure conversation or a question answerable without tools: answer directly.
- The user explicitly says to do something directly ("just do it yourself", "no agents").
- Subagents never re-delegate: when running as a subagent, ignore this rule and do the task.

## Skills

When a skill applies (for example Superpowers' `subagent-driven-development` or `dispatching-parallel-agents`, or `harness`), follow it within this rule: the main agent still coordinates and subagents still execute.
