#!/usr/bin/env bash
# Configure AI coding agents from the shared core in this repo.
# Runs on macOS, Linux (including WSL) and Windows (Git Bash).
# Safe to re-run: every step is idempotent. Try --dry-run first.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
ALL_AGENTS="claude codex cursor gemini antigravity copilot opencode devin amp kiro cline droid zed crush"

usage() {
  cat <<EOF
Usage: install.sh [options]

  --dry-run          print every action, change nothing
  --agents a,b       only these agents (default: every detected agent)
                     known: $ALL_AGENTS
  --skip-tools       skip package manager and tools.lock installs
  --yes              install missing tools without asking; with --update NAMES: approve them
                     without asking
  --check            list newer upstream versions of the installed items (cached for 24 h)
    --json           ... as JSON
    --force          ... checking upstream now
  --update [NAMES]   approve newer versions (asks per item; NAMES: comma-separated or all),
                     then install them. Approvals are kept per machine in state/approved.json
  --snooze NAMES     ask about these updates again in 24 h (all: every pending one)
  --skip NAME@VER    do not ask about this version again
  --fix-duplicates   uninstall plugins installed from another marketplace or source than
                     core/plugins.lock's, move unmanaged duplicate skill dirs to the backups,
                     and delete Claude Code plugin cache dirs no installed plugin uses
  --allow-any-root   allow running from a checkout other than ~/.agent-setup (tests)
  -h, --help         show this help
EOF
}

DRY_RUN=0 YES=0 SKIP_TOOLS=0 ANY_ROOT=0 FIX_DUPLICATES=0 SELECTED="" MODE=install JSON=0 FORCE=0 MODE_ARGS=()
# set_mode MODE: --check, --notice, --update, --snooze and --skip exclude each other.
set_mode() { [ "$MODE" = install ] || [ "$MODE" = "$1" ] || { printf 'Options --%s and --%s exclude each other\n' "$MODE" "$1" >&2; exit 2; }; MODE=$1; }
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run) DRY_RUN=1 ;;
    --agents) [ $# -ge 2 ] || { usage >&2; exit 2; }; SELECTED=$(printf '%s' "$2" | tr ',' ' '); shift ;;
    --agents=*) SELECTED=$(printf '%s' "${1#*=}" | tr ',' ' ') ;;
    --skip-tools) SKIP_TOOLS=1 ;;
    --yes | -y) YES=1 ;;
    --check | --notice) set_mode "${1#--}" ;;
    --json) JSON=1 ;;
    --force) FORCE=1 ;;
    --update | --snooze | --skip)
      set_mode "${1#--}"
      while [ $# -ge 2 ] && case $2 in -*) false ;; *) true ;; esac; do MODE_ARGS+=("$2"); shift; done ;;
    --fix-duplicates) FIX_DUPLICATES=1 ;;
    --allow-any-root) ANY_ROOT=1 ;;
    -h | --help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

for lib in common fs json build tools hooks plugins updates; do
  # shellcheck source=/dev/null
  . "$ROOT/lib/$lib.sh"
done

case $OS in
  unknown) warn "untested OS $(uname -s); continuing" ;;
  # Git Bash may hand HOME over as C:\Users\x or C:/Users/x; use /c/Users/x.
  windows) HOME=$(cygpath -u "$HOME"); export HOME; BACKUP_DIR="$HOME/.agent-setup-backups/$RUN_TS" ;;
esac
if [ "$ANY_ROOT" != 1 ]; then
  expected=$(cd "$HOME/.agent-setup" 2>/dev/null && pwd -P || true)
  [ "$ROOT" = "$expected" ] ||
    die "this repo must live at ~/.agent-setup (found $ROOT); links depend on that path. Use --allow-any-root only for tests."
fi
for a in $SELECTED; do
  case " $ALL_AGENTS " in *" $a "*) ;; *) die "unknown agent '$a' (known: $ALL_AGENTS)" ;; esac
done
case $OS in
  macos) git_hint="xcode-select --install" ;;
  windows) git_hint="install Git for Windows and run from Git Bash" ;;
  *) git_hint="install git with your package manager" ;;
esac
has_cmd git || die "git is required ($git_hint)"
cd "$ROOT"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/agent-setup.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT
load_state

# Update commands: they read and write only state/ (and, for --update, then
# run the install below).
case $MODE in
  check | notice | snooze | skip)
    has_cmd jq || { [ "$MODE" = notice ] && exit 0; die "jq is required for --$MODE"; }
    case $MODE in
      check) run_check ;;
      notice) run_notice 2>/dev/null || true ;;
      snooze) run_snooze ${MODE_ARGS[@]+"${MODE_ARGS[@]}"} ;;
      skip) run_skip ${MODE_ARGS[@]+"${MODE_ARGS[@]}"} ;;
    esac
    exit 0 ;;
  update)
    has_cmd jq || die "jq is required for --update"
    run_update ${MODE_ARGS[@]+"${MODE_ARGS[@]}"} || exit 0 ;;
esac

setup_link_mode

[ "$DRY_RUN" = 1 ] && log "Dry run: nothing will be changed."
log "Repo: $(pretty "$ROOT")"

# 1. Tools
section "Tools"
if [ "$SKIP_TOOLS" = 1 ]; then
  log "skipped (--skip-tools)"
else
  base_tools
fi
if ! has_cmd jq; then
  if [ "$SKIP_TOOLS" != 1 ] && has_cmd brew; then
    act "brew install jq" brew install jq
  fi
  if ! has_cmd jq; then
    if [ "$DRY_RUN" = 1 ]; then
      warn "jq is missing; the build and agent steps need it (run without --skip-tools)"
      summary
      exit 0
    fi
    die "jq is required: run install.sh without --skip-tools, or install jq with your package manager"
  fi
fi
# jq may be new; --update keeps the approvals it just made in memory.
[ "$MODE" = update ] || load_state
# Approve what has no approved version yet, then the tools.lock tools at it.
approve_missing
if [ "$SKIP_TOOLS" = 1 ]; then install_updated_tools; else install_tools; fi

# 2. Git identity
section "Git identity"
git_identity

# 3. Shell env
section "Shell env"
shell_env

# 4. Build (approved versions, third-party skills at them, resolved MCP servers)
section "Build"
build_agents_md
vendor_skills
override_skills
resolve_mcp

# 5. Agents
section "Agents"
installed_any=0
for name in $ALL_AGENTS; do
  if [ -n "$SELECTED" ]; then
    case " $SELECTED " in *" $name "*) ;; *) continue ;; esac
  fi
  adapter="$ROOT/agents/$name/adapter.sh"
  if [ ! -f "$adapter" ]; then
    warn "$name: no adapter at agents/$name/adapter.sh"
    continue
  fi
  unset -f detect install 2>/dev/null || true
  # shellcheck source=/dev/null
  . "$adapter"
  if detect; then
    :
  elif [ -n "$SELECTED" ]; then
    log "-- $name (not detected; installing because it was selected)"
  else
    log "-- $name: not installed, skipped"
    continue
  fi
  section "$name"
  install || warn "$name: adapter returned an error"
  installed_any=1
done
[ "$installed_any" = 1 ] || log "No agents detected."

# 6. Vendor dirs no skill uses any more
section "Cleanup"
cleanup_vendor
save_approved

summary
pending_summary
