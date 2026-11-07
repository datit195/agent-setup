# shellcheck shell=bash
# Symlinks, backups and skill linking.

# Where a path is backed up: $BACKUP_DIR/<path relative to $HOME>.
backup_target() {
  local p=$1
  case $p in
    "$HOME"/*) printf '%s/%s' "$BACKUP_DIR" "${p#"$HOME"/}" ;;
    *) printf '%s/_abs%s' "$BACKUP_DIR" "$p" ;;
  esac
}

_move_to() { mkdir -p "$(dirname "$2")" && mv "$1" "$2"; }
_copy_to() { mkdir -p "$(dirname "$2")" && cp -p "$1" "$2"; }

# Move an existing path out of the way (used before replacing it with a link).
backup_move() {
  local p=$1 t
  t=$(backup_target "$p")
  act "back up $(pretty "$p") -> $(pretty "$t")" _move_to "$p" "$t"
}

# Copy a file to the backup dir, once per run (used before editing it in place).
backup_copy_once() {
  local p=$1 t
  [ -e "$p" ] || return 0
  in_list "$BACKED_UP" "$p" && return 0
  BACKED_UP="$BACKED_UP$p"$'\n'
  t=$(backup_target "$p")
  [ "$DRY_RUN" = 1 ] && return 0
  _copy_to "$p" "$t" || warn "could not back up $(pretty "$p")"
}

_make_link() { mkdir -p "$(dirname "$2")" && ln -s "$1" "$2"; }
_make_copy() { mkdir -p "$(dirname "$2")" && cp -R "$1" "$2" && rm -rf "$2/.git"; }

# link (default) or copy: set by setup_link_mode.
LINK_MODE=link

# On Windows, use native symlinks when the user may create them (Developer
# Mode or admin); otherwise copy files. AGENT_SETUP_LINK_MODE=copy forces copy
# mode (tests).
setup_link_mode() {
  if [ "${AGENT_SETUP_LINK_MODE:-}" = copy ]; then
    LINK_MODE=copy
  elif [ "$OS" = windows ]; then
    export MSYS=winsymlinks:nativestrict
    : >"$TMP_DIR/link-test-src"
    if ! ln -s "$TMP_DIR/link-test-src" "$TMP_DIR/link-test" 2>/dev/null || [ ! -L "$TMP_DIR/link-test" ]; then
      LINK_MODE=copy
    fi
  fi
  if [ "$LINK_MODE" = copy ]; then
    warn "symlinks are not available (on Windows: turn on Developer Mode); files are copied instead, so re-run install.sh after editing the repo"
  fi
}

# link SRC DEST: make DEST a symlink to SRC (in copy mode: a copy of SRC),
# backing up whatever was there.
link() {
  local src=$1 dest=$2
  in_list "$LINKED" "$dest" && return 0
  LINKED="$LINKED$dest"$'\n'
  if [ ! -e "$src" ] && [ "$DRY_RUN" != 1 ]; then
    warn "link source missing, skipped: $(pretty "$src")"
    return 0
  fi
  if [ "$LINK_MODE" = copy ]; then
    if [ -e "$dest" ] && [ ! -L "$dest" ] && diff -rq -x .git "$src" "$dest" >/dev/null 2>&1; then return 0; fi
    if [ -e "$dest" ] || [ -L "$dest" ]; then backup_move "$dest"; fi
    act "copy $(pretty "$src") -> $(pretty "$dest")" _make_copy "$src" "$dest"
    return 0
  fi
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then return 0; fi
  if _repo_link "$dest"; then
    # Our own link to an older place in the repo (e.g. an old vendor dir): re-point it in one step.
    act "re-link $(pretty "$dest") -> $(pretty "$src")" ln -sfn "$src" "$dest"
    return 0
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then backup_move "$dest"; fi
  act "link $(pretty "$dest") -> $(pretty "$src")" _make_link "$src" "$dest"
}

# _repo_link PATH: is PATH a symlink into this repo?
_repo_link() { [ -L "$1" ] && case $(readlink "$1") in "$ROOT"/*) true ;; *) false ;; esac; }

# unlink_managed SRC DEST [REASON]: remove DEST when it is this repo's link
# (in copy mode: an identical copy of SRC, moved to the backups); anything
# else is left.
unlink_managed() {
  local src=$1 dest=$2
  if _repo_link "$dest"; then
    act "remove $(pretty "$dest") (${3:-the agent has the native plugin})" rm -f "$dest"
  elif [ "$LINK_MODE" = copy ] && [ -d "$dest" ] && [ ! -L "$dest" ] && diff -rq -x .git "$src" "$dest" >/dev/null 2>&1; then
    backup_move "$dest"
  fi
}

# link_each DEST_DIR FILE...: link each existing FILE into DEST_DIR/<basename>.
link_each() {
  local dir=$1 f; shift
  for f in "$@"; do
    [ -e "$f" ] || continue
    link "$f" "$dir/$(basename "$f")"
  done
}

# Vendored skills, filled by vendor_skills (lib/build.sh): lines
# "name<TAB>dir<TAB>agents to skip (comma-separated)<TAB>plugin it copies".
VENDORED_SKILLS=""
SKILL_DIRS_DONE=$'\n'

# _native_for AGENT PLUGIN: does AGENT (or, for "shared", an agent that reads
# the shared skills dir: Codex) have PLUGIN natively?
_native_for() {
  [ -n "$2" ] || return 1
  if [ "$1" = shared ]; then codex_scan_native; native_has codex "$2"; else native_has "$1" "$2"; fi
}

# link_skills DEST_DIR [AGENT]: link every own skill and every vendored skill
# into DEST_DIR/<name>, except vendored skills whose lock entry skips AGENT and
# copies of a plugin AGENT has natively (a link left from an earlier run is
# removed).
link_skills() {
  local dest=$1 agent=${2:-} d name src skip plugin seen=$'\n'
  in_list "$SKILL_DIRS_DONE" "$dest" && return 0
  SKILL_DIRS_DONE="$SKILL_DIRS_DONE$dest"$'\n'
  for d in "$ROOT"/core/skills/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    seen="$seen$name"$'\n'
    link "${d%/}" "$dest/$name"
  done
  while IFS=$'\t' read -r name src skip plugin; do
    [ -n "$name" ] || continue
    case ",$skip," in *",$agent,"*) [ -n "$agent" ] && continue ;; esac
    if _native_for "$agent" "$plugin"; then
      unlink_managed "$src" "$dest/$name"
      continue
    fi
    if in_list "$seen" "$name"; then
      warn "skill name '$name' is both own and vendored; kept the own one"
      continue
    fi
    seen="$seen$name"$'\n'
    link "$src" "$dest/$name"
  done <<EOF
$VENDORED_SKILLS
EOF
}

# The shared skills dir read by most agents (Codex among them).
shared_skills() { link_skills "$HOME/.agents/skills" shared; }

# link_codex_native_skills DEST AGENT: the shared skills dir leaves out the
# vendored copies of plugins Codex has natively. Link those into DEST, a dir
# only AGENT (Cursor) reads, so it still gets them; remove such a link once
# Codex no longer has the plugin (the shared dir then has the copy).
link_codex_native_skills() {
  local dest=$1 agent=$2 name src skip plugin
  while IFS=$'\t' read -r name src skip plugin; do
    [ -n "$name" ] && [ -n "$plugin" ] || continue
    case ",$skip," in *",$agent,"*) continue ;; esac
    if _native_for shared "$plugin"; then
      link "$src" "$dest/$name"
    else
      unlink_managed "$src" "$dest/$name" "the shared skills dir has it"
    fi
  done <<EOF
$VENDORED_SKILLS
EOF
}

# The shared instruction file every agent links to.
link_instructions() { link "$ROOT/build/AGENTS.full.md" "$1"; }

# Is PATH (an entry of skill dir DIR) managed by this repo? Yes when this run
# linked it, or, in a dir this run did not link into, when it is a link into
# the repo. Anything else in a dir this run linked into is not ours.
_skill_managed() {
  local t
  if in_list "$LINKED" "$2"; then printf 1; return; fi
  if ! in_list "$SKILL_DIRS_DONE" "$1" && [ -L "$2" ]; then
    t=$(readlink "$2")
    case $t in "$ROOT"/*) printf 1; return ;; esac
  fi
  printf 0
}

# check_skill_dups AGENT DIR...: warn about every skill name found more than
# once across DIRs (the skill dirs AGENT reads) and the extra lines in
# $EXTRA_SKILLS ("name<TAB>path<TAB>1p|0p" for Claude plugin skills: 1p from
# plugins.lock, 0p from other plugins), when at least one copy is not managed
# by this repo. With --fix-duplicates, the unmanaged copies in DIRs are moved
# to the backup dir when a managed copy exists; plugin skills are never moved.
check_skill_dups() {
  local agent=$1 d e rows="" name group paths p flag
  shift
  for d in "$@"; do
    [ -d "$d" ] || continue
    for e in "$d"/*; do
      [ -d "$e" ] || continue
      rows="$rows$(basename "$e")"$'\t'"$e"$'\t'"$(_skill_managed "$d" "$e")"$'\n'
    done
  done
  rows="$rows${EXTRA_SKILLS:-}"
  while IFS= read -r name <&3; do
    [ -n "$name" ] || continue
    group=$(printf '%s' "$rows" | awk -F '\t' -v n="$name" '$1 == n')
    printf '%s\n' "$group" | cut -f3 | grep -q '^0' || continue
    paths=$(printf '%s\n' "$group" | while IFS=$'\t' read -r _ p flag; do
      case $flag in (1*) ;; (*p) p="$p (plugin)" ;; (*) p="$p (not managed)" ;; esac
      printf '%s, ' "$(pretty "$p")"
    done)
    paths=${paths%, }
    if [ "${FIX_DUPLICATES:-0}" = 1 ] && printf '%s\n' "$group" | cut -f3 | grep -q '^1'; then
      while IFS=$'\t' read -r _ p flag; do
        if [ "$flag" = 0 ]; then backup_move "$p"; fi
      done < <(printf '%s\n' "$group")
    else
      warn "$agent: skill '$name' is in more than one place it reads: $paths (move the unmanaged copy away, or re-run with --fix-duplicates to move it to the backups)"
    fi
  done 3< <(printf '%s' "$rows" | awk -F '\t' 'NF { c[$1]++ } END { for (n in c) if (c[n] > 1) print n }' | LC_ALL=C sort)
}
