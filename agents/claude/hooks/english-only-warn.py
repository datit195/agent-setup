#!/usr/bin/python3 -I
# PreToolUse hook: warn (never block) when a tool call writes Vietnamese text.
# Emits hookSpecificOutput.additionalContext with no permissionDecision, so the
# call goes through the normal permission flow and Claude sees the warning next
# to the tool result. Any error -> exit 0 silently (fail open).
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


def texts_for(tool, ti):
    if tool == "Write":
        return [ti.get("content")]
    if tool == "Edit":
        return [ti.get("new_string")]
    if tool == "MultiEdit":
        return [e.get("new_string") for e in ti.get("edits") or [] if isinstance(e, dict)]
    if tool == "NotebookEdit":
        return [ti.get("new_source")]
    if tool == "Bash":
        return [ti.get("command")]
    if tool.startswith("mcp__"):
        out = []
        collect_strings(ti, out)
        return out
    return []


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
    data = json.loads(sys.stdin.read())
    tool = data.get("tool_name") or ""
    ti = data.get("tool_input") or {}
    if not isinstance(ti, dict):
        return
    path = ti.get("file_path") or ti.get("notebook_path")
    if isinstance(path, str) and path and is_translation_path(path):
        return

    found = None
    for t in texts_for(tool, ti):
        if isinstance(t, str) and t:
            found = snippet(unicodedata.normalize("NFC", t))
            if found:
                break
    if not found:
        return

    if english_only_off(repo_dir(path if isinstance(path, str) else None, data.get("cwd"))):
        return

    msg = ('English-only writing: this %s contains Vietnamese text (e.g. "%s"). '
           "Rewrite it in English unless an exception applies (translation file, "
           "content for Vietnamese users, verbatim quote, proper name, or the user "
           "asked for Vietnamese) - see ~/.agent-setup/core/rules/language.md and "
           "~/.agent-setup/agents/claude/rules/claude-extras.md. "
           "Turn off for a repo: git config claude.englishOnly off") % (tool, found)
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "additionalContext": msg}}))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
