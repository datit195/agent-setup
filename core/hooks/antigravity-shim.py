#!/usr/bin/env python3
# Antigravity hook shim: run a shared hook (written for Claude Code input) from
# an Antigravity hook and translate its input and output.
#
#   antigravity-shim.py pretool CMD...   PreToolUse: CMD gets Claude-shaped
#       input. Exit 2 -> {"decision":"deny","reason":<stderr>}. Context the
#       hook adds (additionalContext) is kept and injected on the next
#       PreInvocation, because PreToolUse cannot add context.
#   antigravity-shim.py prompt [CMD...]  PreInvocation: injects kept context,
#       and runs CMD as a UserPromptSubmit hook once per new user input.
#
# CMD is a hook script path (.py runs with this Python, .sh with bash; a
# missing script is skipped) or a command line.
#
# Always exits 0 and prints JSON: Antigravity does not document exit codes,
# and a failing hook may block every tool. "allow" is the documented
# no-opinion decision (it defers to the next hook or the default policy).
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

PATH_KEYS = ("TargetFile", "targetFile", "AbsolutePath", "FilePath", "file_path", "path")
# Old text being replaced is not something the agent writes.
DROP_KEYS = {"TargetContent"}


def clean(value):
    if isinstance(value, dict):
        return {k: clean(v) for k, v in value.items() if k not in DROP_KEYS}
    if isinstance(value, list):
        return [clean(v) for v in value]
    return value


def state_path(conv):
    d = os.path.join(tempfile.gettempdir(), "agent-setup-antigravity")
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, hashlib.sha1(conv.encode("utf-8")).hexdigest() + ".json")


def load_state(conv):
    try:
        with open(state_path(conv), encoding="utf-8") as f:
            s = json.load(f)
        return s if isinstance(s, dict) else {}
    except Exception:
        return {}


def save_state(conv, state):
    try:
        with open(state_path(conv), "w", encoding="utf-8") as f:
            json.dump(state, f)
    except Exception:
        pass


def run(cmd, payload, cwd):
    r = subprocess.run(cmd, input=json.dumps(payload).encode("utf-8"), capture_output=True,
                       timeout=25, cwd=cwd if cwd and os.path.isdir(cwd) else None)
    return r.returncode, r.stdout.decode("utf-8", "replace"), r.stderr.decode("utf-8", "replace")


def context_of(out):
    out = out.strip()
    if not out:
        return None
    try:
        data = json.loads(out)
    except ValueError:
        return out
    if isinstance(data, dict):
        hso = data.get("hookSpecificOutput")
        if isinstance(hso, dict) and isinstance(hso.get("additionalContext"), str):
            return hso["additionalContext"] or None
        return None
    return out


def pretool(data, cmd, conv, cwd):
    call = data.get("toolCall") or {}
    args = call.get("args") or {}
    if isinstance(args, str):
        args = json.loads(args)
    ti = clean(args) if isinstance(args, dict) else {}
    for k in PATH_KEYS:
        if isinstance(args.get(k), str) and args[k]:
            ti["file_path"] = args[k]
            break
    payload = {"hook_event_name": "PreToolUse", "session_id": conv, "cwd": cwd,
               "tool_name": call.get("name") or "", "tool_input": ti}
    rc, out, err = run(cmd, payload, cwd)
    if rc == 2:
        return {"decision": "deny", "reason": err.strip() or "Blocked by a hook"}
    ctx = context_of(out) if rc == 0 else None
    if ctx and conv:
        state = load_state(conv)
        state.setdefault("pending", []).append(ctx)
        save_state(conv, state)
    return {"decision": "allow"}


def prompt(data, cmd, conv, cwd):
    state = load_state(conv) if conv else {}
    steps = [{"ephemeralMessage": m} for m in state.pop("pending", []) if isinstance(m, str)]
    text = data.get("lastUserInput") or ""
    if cmd and isinstance(text, str) and text:
        key = hashlib.sha1(text.encode("utf-8")).hexdigest()
        if state.get("lastInput") != key:
            state["lastInput"] = key
            payload = {"hook_event_name": "UserPromptSubmit", "session_id": conv, "cwd": cwd,
                       "prompt": text}
            try:
                rc, out, _ = run(cmd, payload, cwd)
                ctx = context_of(out) if rc == 0 else None
            except Exception:
                ctx = None
            if ctx:
                steps.append({"ephemeralMessage": ctx})
    if conv:
        save_state(conv, state)
    return {"injectSteps": steps} if steps else {}


def resolve(cmd):
    if len(cmd) == 1 and cmd[0].endswith((".py", ".sh")):
        if not os.path.isfile(cmd[0]):
            return None
        # shutil.which follows PATH; on Windows a bare "bash" would start
        # System32's WSL launcher instead of Git Bash.
        return [sys.executable, "-I", cmd[0]] if cmd[0].endswith(".py") else [shutil.which("bash") or "bash", cmd[0]]
    return cmd or None


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    cmd = resolve(sys.argv[2:])
    result = {"decision": "allow"} if mode == "pretool" else {}
    try:
        data = json.loads(sys.stdin.buffer.read() or b"{}")
        if not isinstance(data, dict):
            data = {}
        conv = str(data.get("conversationId") or "")
        ws = data.get("workspacePaths")
        cwd = ws[0] if isinstance(ws, list) and ws and isinstance(ws[0], str) else None
        if mode == "pretool" and cmd:
            result = pretool(data, cmd, conv, cwd)
        elif mode == "prompt":
            result = prompt(data, cmd, conv, cwd)
    except Exception:
        pass
    sys.stdout.write(json.dumps(result) + "\n")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.stdout.write("{}\n")
    sys.exit(0)
