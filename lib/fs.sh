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
  if [ -e "$dest" ] || [ -L "$dest" ]; then backup_move "$dest"; fi
  act "link $(pretty "$dest") -> $(pretty "$src")" _make_link "$src" "$dest"
}

# link_each DEST_DIR FILE...: link each existing FILE into DEST_DIR/<basename>.
link_each() {
  local dir=$1 f; shift
  for f in "$@"; do
    [ -e "$f" ] || continue
    link "$f" "$dir/$(basename "$f")"
  done
}

# Vendored skills, filled by vendor_skills (lib/build.sh): lines "name<TAB>dir".
VENDORED_SKILLS=""
SKILL_DIRS_DONE=$'\n'

# link_skills DEST_DIR: link every own skill and every vendored skill into DEST_DIR/<name>.
link_skills() {
  local dest=$1 d name src seen=$'\n'
  in_list "$SKILL_DIRS_DONE" "$dest" && return 0
  SKILL_DIRS_DONE="$SKILL_DIRS_DONE$dest"$'\n'
  for d in "$ROOT"/core/skills/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    seen="$seen$name"$'\n'
    link "${d%/}" "$dest/$name"
  done
  while IFS=$'\t' read -r name src; do
    [ -n "$name" ] || continue
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

# The shared skills dir read by most agents.
shared_skills() { link_skills "$HOME/.agents/skills"; }

# The shared instruction file every agent links to.
link_instructions() { link "$ROOT/build/AGENTS.full.md" "$1"; }
