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
