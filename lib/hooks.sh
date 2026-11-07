# shellcheck shell=bash
# Hooks from core/hooks.json, rendered for each agent's hook format.

# jq: pyrun(FILE[; ARGS; DEFAULT]): a Python command that runs FILE (with
# ARGS) only when it exists, else prints DEFAULT; never exit 2 for a missing
# file. Used where no sh is assumed (WRAP=0); needs $py.
# shellcheck disable=SC2016
PYRUN_JQ='
  def pyrun($f; $args; $default):
    "\($py) -I -c \"import os,runpy,sys; f=r\u0027\($f)\u0027; sys.argv=[f]+\($args | map("r\u0027\(.)\u0027") | "[" + join(", ") + "]"); "
    + "os.path.isfile(f) and runpy.run_path(f, run_name=\u0027__main__\u0027)"
    + (if $default == "" then "" else " or print(\u0027\($default | gsub("\""; "\\\""))\u0027)" end) + "\"";
  def pyrun($f): pyrun($f; []; "");'

# hooks_json AGENT DIR PY WRAP: the hooks for AGENT (claude or codex) as
# {"<event>": [matcher groups]}; each group carries an "id" (its script or
# command) for hooks_merge. DIR holds the scripts (a path the agent's shell
# understands). PY is the Python command; "" drops Python hooks. WRAP=1 makes
# script commands sh snippets that exit 0 when the script is missing; hooks
# without "blocks" also exit 0 when they fail.
hooks_json() {
  jq -n --slurpfile h "$ROOT/core/hooks.json" --arg agent "$1" --arg dir "$2" --arg py "$3" --arg wrap "$4" '
    '"$PYRUN_JQ"'
    [$h[0].hooks[]
      | select(.event != "PreToolUse" or (.matcher[$agent] // "") != "")
      | select(((.script // "") | endswith(".py") | not) or $py != "")]
    | reduce .[] as $x ({};
        (if $x.command then $x.command
         else "\($dir)/\($x.script)" as $f
           | (if ($x.script | endswith(".py")) then "\($py) -I" else "bash" end) as $run
           | if $wrap == "1" then
               "f=\"\($f)\"; [ -f \"$f\" ] || exit 0; \($run) \"$f\"" + (if $x.blocks then "" else " || true" end)
             elif ($x.script | endswith(".py")) then pyrun($f)
             else "\($run) \"\($f)\"" end
         end) as $cmd
        | .[$x.event] += [{id: ($x.script // $x.command)}
            + (if $x.event == "PreToolUse" then {matcher: $x.matcher[$agent]} else {} end)
            + {hooks: [{type: "command", command: $cmd} + (if $x.timeout then {timeout: $x.timeout} else {} end)]}])'
}

# jq definition add_hooks($new): merge hooks_json output into .hooks. A group
# whose command is already registered is left as it is. Otherwise hooks whose
# command contains the group's id (an older command for the same script) are
# removed first, so a changed command replaces the old entry.
# shellcheck disable=SC2016
HOOKS_MERGE_JQ='
  def add_hooks($new):
    reduce ($new | to_entries[]) as $ev (.;
      .hooks[$ev.key] = reduce $ev.value[] as $g ((.hooks[$ev.key] // []);
        ($g.hooks[0].command) as $c
        | if any(.[]?.hooks[]?; .command == $c) then .
          else map(if (.hooks | type) == "array"
                   then .hooks |= map(select((.command // "" | tostring | contains($g.id)) | not))
                   else . end)
               | map(select((.hooks | type) != "array" or (.hooks | length) > 0))
               + [$g | del(.id)]
          end));'

# antigravity_hooks_json SHIM DIR PY WRAP: the "agent-setup" group for
# ~/.gemini/config/hooks.json. Every hook runs through SHIM (Claude-shaped
# input and output); UserPromptSubmit hooks run on PreInvocation, SessionStart
# hooks on SessionStart.
antigravity_hooks_json() {
  jq -n --slurpfile h "$ROOT/core/hooks.json" --arg shim "$1" --arg dir "$2" --arg py "$3" --arg wrap "$4" '
    '"$PYRUN_JQ"'
    def run($mode; $target; $argv; $default):
      if $wrap == "1" then
        "f=\"\($shim)\"; [ -f \"$f\" ] || { echo '"'"'\($default)'"'"'; exit 0; }; \($py) -I \"$f\" \($mode) \($target) || echo '"'"'\($default)'"'"'"
      else pyrun($shim; [$mode] + $argv; $default) end;
    [$h[0].hooks[]
      | select(.event == "UserPromptSubmit" or .event == "SessionStart" or (.event == "PreToolUse" and (.matcher.antigravity // "") != ""))]
    | reduce .[] as $x ({};
        (if $x.command then ($x.command | split(" ")) else ["\($dir)/\($x.script)"] end) as $argv
        | ($argv | map(if test("^[A-Za-z0-9_./:-]+$") then . else "\"\(.)\"" end) | join(" ")) as $t
        | (if $x.timeout then {timeout: $x.timeout} else {} end) as $to
        | if $x.event == "PreToolUse" then
            .PreToolUse += [{matcher: $x.matcher.antigravity,
                             hooks: [{type: "command", command: run("pretool"; $t; $argv; "{\"decision\":\"allow\"}")} + $to]}]
          elif $x.event == "SessionStart" then .SessionStart += [{type: "command", command: run("session"; $t; $argv; "{}")} + $to]
          else .PreInvocation += [{type: "command", command: run("prompt"; $t; $argv; "{}")} + $to]
          end)'
}

# Scripts named in core/hooks.json, one per line.
hook_scripts() { jq -r '.hooks[].script // empty' "$ROOT/core/hooks.json" | tr -d '\r'; }

# Wrap hook commands in sh snippets everywhere except for non-Claude agents on
# Windows, whose hook shell is unknown there.
hook_wrap() { if [ "$OS" = windows ]; then printf 0; else printf 1; fi; }
