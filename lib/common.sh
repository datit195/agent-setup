# shellcheck shell=bash
# Logging, dry-run aware actions and small helpers. Bash 3.2 compatible.

DRY_RUN=${DRY_RUN:-0}
CHANGES=0
WARNINGS=()
RUN_TS=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$HOME/.agent-setup-backups/$RUN_TS"
BACKED_UP=$'\n'   # newline-separated list of paths already backed up this run
LINKED=$'\n'      # newline-separated list of link destinations handled this run

# Show paths under $HOME as ~/...
pretty() { local p=$1; case $p in "$HOME"/*) p="~/${p#"$HOME"/}" ;; esac; printf '%s' "$p"; }

log() { printf '%s\n' "$*"; }
section() { printf '\n== %s ==\n' "$*"; }
warn() { WARNINGS+=("$*"); printf 'WARN: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# act DESCRIPTION [COMMAND ARGS...]
# Prints the action (with "[dry-run] " prefix in dry-run), then runs the command
# unless in dry-run. Counts it as a change. A failing command is reported as a
# warning; act itself always returns 0 so one failure never aborts the run.
act() {
  local desc=$1; shift
  CHANGES=$((CHANGES + 1))
  if [ "$DRY_RUN" = 1 ]; then
    printf '[dry-run] %s\n' "$desc"
    return 0
  fi
  printf '%s\n' "$desc"
  if [ $# -gt 0 ] && ! "$@"; then
    warn "failed: $desc"
  fi
  return 0
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# Print the OS: macos, linux, wsl, windows (Git Bash / MSYS2 / Cygwin) or unknown.
detect_os() {
  case $(uname -s) in
    Darwin) printf macos ;;
    Linux) if grep -qi microsoft /proc/version 2>/dev/null; then printf wsl; else printf linux; fi ;;
    MINGW* | MSYS* | CYGWIN*) printf windows ;;
    *) printf unknown ;;
  esac
}
OS=$(detect_os)

# A path in the form Windows programs accept (C:/Users/x); unchanged elsewhere.
native_path() { if [ "$OS" = windows ]; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

# in_list LIST ITEM: is ITEM a line of the newline-separated LIST?
in_list() { case $1 in *$'\n'"$2"$'\n'*) return 0 ;; esac; return 1; }

# Escape a string for use inside an extended regex.
re_escape() { printf '%s' "$1" | sed 's/[][\.*^$+?(){}|/]/\\&/g'; }

# Print non-comment, non-blank lines of a lock/config file.
lock_lines() {
  [ -f "$1" ] || return 0
  grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$1" || true
}

summary() {
  section "Summary"
  if [ "$DRY_RUN" = 1 ]; then
    log "Dry run: $CHANGES change(s) would be made. Nothing was changed."
  else
    log "$CHANGES change(s) made."
  fi
  if [ -d "$BACKUP_DIR" ]; then log "Backups: $(pretty "$BACKUP_DIR")"; fi
  if [ ${#WARNINGS[@]} -gt 0 ]; then
    log "${#WARNINGS[@]} warning(s):"
    local w
    for w in "${WARNINGS[@]}"; do log "  - $w"; done
  else
    log "No warnings."
  fi
}

# Print the Python 3 command for hooks and helpers: /usr/bin/python3 when it
# works (a stable path), else python3, python or "py -3". On Windows the bare
# name is printed (hooks run with the user's PATH). Fails when none works.
python_cmd() {
  local c
  if [ "$OS" != windows ] && /usr/bin/python3 -c '' >/dev/null 2>&1; then
    printf '/usr/bin/python3'
    return 0
  fi
  for c in python3 python "py -3"; do
    # shellcheck disable=SC2086
    $c -c 'import sys; sys.exit(sys.version_info[0] != 3)' >/dev/null 2>&1 || continue
    if [ "$OS" = windows ] || [ "$c" = "py -3" ]; then printf '%s' "$c"; else command -v "$c"; fi
    return 0
  done
  return 1
}

# The shared agent env as a JSON object: every "export KEY=VALUE" line of
# shell/env.sh (surrounding quotes removed). shell/env.sh is the only source.
shared_env_json() {
  sed -n -e '/^export [A-Za-z_][A-Za-z0-9_]*=/!d' -e 's/^export //' -e 's/=\(["'"'"']\)\(.*\)\1$/=\2/' -e p "$ROOT/shell/env.sh" | tr -d '\r' |
    jq -Rn '[inputs | capture("^(?<k>[^=]+)=(?<v>.*)$") | {(.k): .v}] | add // {}'
}
