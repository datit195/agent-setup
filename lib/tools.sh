# shellcheck shell=bash
# Tools step (Homebrew bundle + tools.lock) and git identity.

# ask QUESTION: 0 if the answer is yes. --yes answers yes; no terminal answers no.
ask() {
  [ "$YES" = 1 ] && return 0
  local ans=""
  if [ -r /dev/tty ]; then
    printf '%s [y/N] ' "$1" >/dev/tty
    read -r ans </dev/tty || ans=""
  fi
  case $ans in y | Y | yes | YES) return 0 ;; esac
  return 1
}

install_tools() {
  local brewfile="$ROOT/tools/Brewfile" name cmd check
  local ok="" added="" manual="" declined="" failed=""
  if [ -f "$brewfile" ]; then
    if ! has_cmd brew; then
      warn "Homebrew not found; tools/Brewfile skipped (install it from https://brew.sh)"
    elif brew bundle check --no-upgrade --file "$brewfile" >/dev/null 2>&1; then
      log "Brewfile: everything installed"
    else
      act "brew bundle --file tools/Brewfile" brew bundle --no-upgrade --file "$brewfile"
    fi
  fi
  while IFS=$'\t' read -r name cmd check <&3; do
    [ -n "$name" ] || continue
    if [ -n "$check" ] && bash -c "$check" >/dev/null 2>&1; then
      ok="$ok $name"
      continue
    fi
    if [ "$cmd" = "MANUAL" ]; then
      log "NOTE: $name must be installed by hand (see tools/tools.lock)"
      manual="$manual $name"
      continue
    fi
    if [ "$DRY_RUN" = 1 ]; then
      act "install $name: $cmd"
      continue
    fi
    if ! ask "Install $name ($cmd)?"; then
      declined="$declined $name"
      continue
    fi
    act "install $name" bash -c "$cmd"
    if [ -n "$check" ] && ! bash -c "$check" >/dev/null 2>&1; then
      failed="$failed $name"
    else
      added="$added $name"
    fi
  done 3< <(lock_lines "$ROOT/tools/tools.lock")
  log "tools: present:${ok:- none} | installed:${added:- none} | manual:${manual:- none} | declined:${declined:- none} | failed:${failed:- none}"
  [ -z "$failed" ] || warn "tools failed to install:$failed"
}

# Set each git.conf key globally, only when it is not set yet.
git_identity() {
  local line key val
  while IFS= read -r line; do
    case $line in *=*) ;; *) warn "git.conf: line without '=' skipped"; continue ;; esac
    key=$(printf '%s' "${line%%=*}" | tr -d '[:space:]')
    val=${line#*=}
    if git config --global --get "$key" >/dev/null 2>&1; then
      log "git $key already set"
      continue
    fi
    act "git config --global $key '$val'" git config --global "$key" "$val"
  done < <(lock_lines "$ROOT/git.conf")
}
