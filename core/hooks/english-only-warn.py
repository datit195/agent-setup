#!/usr/bin/python3 -I
# PreToolUse hook: warn (never block) when a tool call writes Vietnamese text.
# Reads Claude Code, Codex (apply_patch) and Cursor hook input; Antigravity runs
# it through antigravity-shim.py. Emits hookSpecificOutput.additionalContext
# with no permissionDecision, so the call goes through the normal permission
# flow and the agent sees the warning next to the tool result (Cursor gets
# agent_message instead). Any error -> exit 0 silently (fail open).
# Opt out per repo: git config claude.englishOnly off
import json
import os
import re
import subprocess
import sys
import unicodedata

_VI_BASE = "ăđơư" "ạảấầẩẫậắằẳẵặẹẻẽếềểễệĩỉịọỏốồổỗộớờởỡợũụủứừửữựỳỵỷỹ"
VI_CHARS = frozenset(_VI_BASE + _VI_BASE.upper())

TRANSLATION_DIRS = {"locale", "locales", "i18n", "l10n", "translations", "lang",
                    "vi", "vi-vn", "vi_vn"}
TRANSLATION_FILE = re.compile(r"^(vi|vi[-_]vn)\.|\.vi\.|_vi\.", re.IGNORECASE)


def collect_strings(value, out):
    if isinstance(value, str):
        out.append(value)
    elif isinstance(value, dict):
        for v in value.values():
            collect_strings(v, out)
    elif isinstance(value, list):
        for v in value:
            collect_strings(v, out)


PATCH_FILE = re.compile(r"^\*\*\* (?:(?:Add|Update|Delete) File|Move to): (.+?)\s*$")


def patch_text(ti):
    p = ti.get("command") or ti.get("patch") or ti.get("input")
    return p if isinstance(p, str) else ""


def texts_for(tool, ti):
    if tool == "apply_patch":
        # Codex: only the added lines of the patch.
        return ["\n".join(l[1:] for l in patch_text(ti).splitlines()
                          if l.startswith("+") and not l.startswith("+++"))]
    if tool == "Write" and isinstance(ti.get("content"), str):
        return [ti.get("content")]
    if tool == "Edit" and isinstance(ti.get("new_string"), str):
        return [ti.get("new_string")]
    if tool == "MultiEdit":
        return [e.get("new_string") for e in ti.get("edits") or [] if isinstance(e, dict)]
    if tool == "NotebookEdit":
        return [ti.get("new_source")]
    if tool in ("Bash", "Shell"):
        return [ti.get("command")]
    # MCP tools (mcp__x__y, Cursor MCP:y), other agents' edit tools and
    # unknown input shapes: every string in the input. Only tools that the
    # hook's matcher selects get here.
    out = []
    collect_strings(ti, out)
    return out


def paths_for(tool, ti):
    if tool == "apply_patch":
        return [m.group(1) for m in map(PATCH_FILE.match, patch_text(ti).splitlines()) if m]
    p = ti.get("file_path") or ti.get("notebook_path") or ti.get("path")
    return [p] if isinstance(p, str) and p else []


def is_translation_path(path):
    parts = path.replace("\\", "/").split("/")
    if any(p.lower() in TRANSLATION_DIRS for p in parts[:-1]):
        return True
    return bool(TRANSLATION_FILE.search(parts[-1]))


def repo_dir(path, cwd):
    if path:
        if not os.path.isabs(path) and cwd:
            path = os.path.join(cwd, path)
        d = os.path.dirname(path)
        while d and not os.path.isdir(d):
            parent = os.path.dirname(d)
            if parent == d:
                return None
            d = parent
        return d or None
    return cwd or None


def english_only_off(d):
    if not d:
        return False
    try:
        r = subprocess.run(["git", "-C", d, "config", "--get", "claude.englishOnly"],
                           capture_output=True, text=True, timeout=2)
        return r.returncode == 0 and r.stdout.strip().lower() == "off"
    except Exception:
        return False


def snippet(text):
    for i, ch in enumerate(text):
        if ch in VI_CHARS:
            start = i
            while start > 0 and i - start < 20 and not text[start - 1].isspace():
                start -= 1
            s = " ".join(text[start:start + 40].split())
            return s
    return None


def main():
    # Bytes, not text: on Windows stdin text uses the ANSI code page, not UTF-8.
    data = json.loads(sys.stdin.buffer.read())
    tool = data.get("tool_name") or ""
    ti = data.get("tool_input") or {}
    if not isinstance(ti, dict):
        return
    paths = paths_for(tool, ti)
    if paths and all(is_translation_path(p) for p in paths):
        return
    path = paths[0] if paths else None
    roots = data.get("workspace_roots")
    cwd = data.get("cwd") or (roots[0] if isinstance(roots, list) and roots else None)

    found = None
    for t in texts_for(tool, ti):
        if isinstance(t, str) and t:
            found = snippet(unicodedata.normalize("NFC", t))
            if found:
                break
    if not found:
        return

    if english_only_off(repo_dir(path, cwd)):
        return

    msg = ('English-only writing: this %s contains Vietnamese text (e.g. "%s"). '
           "Rewrite it in English unless an exception applies (translation file, "
           "content for Vietnamese users, verbatim quote, proper name, or the user "
           "asked for Vietnamese) - see ~/.agent-setup/core/rules/language.md. "
           "Turn off for a repo: git config claude.englishOnly off") % (tool, found)
    if "cursor_version" in data or "workspace_roots" in data:
        # Cursor: no additionalContext on preToolUse; never set "permission".
        print(json.dumps({"agent_message": msg}))
    else:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                                 "additionalContext": msg}}))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
