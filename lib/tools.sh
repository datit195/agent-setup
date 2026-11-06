# shellcheck shell=bash
# Tools step (Homebrew bundle or the OS package manager + tools.lock), git
# identity and shell env.

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

brew_bundle() {
  local brewfile="$ROOT/tools/Brewfile"
  [ -f "$brewfile" ] || return 0
  if ! has_cmd brew; then
    warn "Homebrew not found; tools/Brewfile skipped (install it from https://brew.sh)"
  elif brew bundle check --no-upgrade --file "$brewfile" >/dev/null 2>&1; then
    log "Brewfile: everything installed"
  else
    act "brew bundle --file tools/Brewfile" brew bundle --no-upgrade --file "$brewfile"
  fi
}

# The base tools (the Brewfile set) as "command<TAB>install command" for this
# OS's package manager; empty when there is none.
GH_APT='(type -p wget >/dev/null || (sudo apt-get update && sudo apt-get install -y wget)) && sudo mkdir -p -m 755 /etc/apt/keyrings && out=$(mktemp) && wget -nv -O"$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg && cat "$out" | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && sudo mkdir -p -m 755 /etc/apt/sources.list.d && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null && sudo apt-get update && sudo apt-get install -y gh'
UV_SH='curl -LsSf https://astral.sh/uv/install.sh | sh'
base_tool_cmds() {
  local w='winget install -e --accept-source-agreements --accept-package-agreements --id'
  if [ "$OS" = windows ]; then
    has_cmd winget || return 0
    printf '%s\t%s\n' gh "$w GitHub.cli" jq "$w jqlang.jq" uv "$w astral-sh.uv" node "$w OpenJS.NodeJS.LTS"
  elif has_cmd apt-get; then
    printf '%s\t%s\n' gh "$GH_APT" jq 'sudo apt-get update && sudo apt-get install -y jq' \
      uv "$UV_SH" node 'sudo apt-get update && sudo apt-get install -y nodejs npm'
  elif has_cmd dnf; then
    printf '%s\t%s\n' gh 'sudo dnf install -y gh' jq 'sudo dnf install -y jq' uv "$UV_SH" node 'sudo dnf install -y nodejs npm'
  elif has_cmd pacman; then
    printf '%s\t%s\n' gh 'sudo pacman -S --needed --noconfirm github-cli' jq 'sudo pacman -S --needed --noconfirm jq' \
      uv "$UV_SH" node 'sudo pacman -S --needed --noconfirm nodejs npm'
  fi
}

# install_one NAME CMD: run CMD after asking (dry-run: only print it).
# Returns 1 when declined.
install_one() {
  if [ "$DRY_RUN" = 1 ]; then
    act "install $1: $2"
    return 0
  fi
  ask "Install $1 ($2)?" || return 1
  act "install $1" bash -c "$2"
}

# Base tools: Homebrew on macOS (and on Linux when brew is there), else the
# Linux package manager or winget.
base_tools() {
  local name cmd missing="" pm
  if [ "$OS" = macos ] || { [ "$OS" != windows ] && has_cmd brew; }; then
    brew_bundle
    return 0
  fi
  while IFS=$'\t' read -r name cmd <&3; do
    [ -n "$name" ] || continue
    has_cmd "$name" || missing="$missing$name"$'\t'"$cmd"$'\n'
  done 3< <(base_tool_cmds)
  if [ -z "$(base_tool_cmds)" ]; then
    if [ "$OS" = windows ]; then pm="winget"; else pm="apt-get, dnf, pacman or brew"; fi
    for name in gh jq uv node; do has_cmd "$name" || warn "$name is missing and no package manager was found ($pm); install it by hand"; done
    return 0
  fi
  if [ -z "$missing" ]; then
    log "base tools (gh, jq, uv, node): everything installed"
    return 0
  fi
  while IFS=$'\t' read -r name cmd <&3; do
    [ -n "$name" ] || continue
    install_one "$name" "$cmd" || log "skipped $name (declined)"
  done 3<<EOF
$missing
EOF
  # Installers such as uv's put tools in ~/.local/bin, which may not be on PATH yet.
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac
  [ "$OS" != windows ] || [ "$DRY_RUN" = 1 ] || log "NOTE: winget installs show up on PATH in a new terminal; open a new Git Bash if a tool is still not found"
}

install_tools() {
  local name cmd check oses
  local ok="" added="" manual="" declined="" failed=""
  base_tools
  while IFS=$'\t' read -r name cmd check oses <&3; do
    [ -n "$name" ] || continue
    # Optional 4th column: comma-separated OSes the line applies to.
    case ",${oses:-$OS}," in *",$OS,"*) ;; *) continue ;; esac
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

SHELL_ENV_LINE='[ -f "$HOME/.agent-setup/shell/env.sh" ] && . "$HOME/.agent-setup/shell/env.sh"'

_append_lines() {
  local file=$1; shift
  if [ -s "$file" ] && [ -n "$(tail -c 1 "$file")" ]; then printf '\n' >>"$file" || return 1; fi
  printf '%s\n' "$@" >>"$file"
}

# _source_env_from RC: make RC source shell/env.sh (once; creates RC if missing).
_source_env_from() {
  local rc=$1
  if [ -f "$rc" ] && grep -Fxq "$SHELL_ENV_LINE" "$rc"; then
    log "$(pretty "$rc") already sources shell/env.sh"
    return 0
  fi
  backup_copy_once "$rc"
  act "add shell/env.sh source line to $(pretty "$rc")" _append_lines "$rc" "# agent-setup: shared agent env (shell/env.sh)" "$SHELL_ENV_LINE"
}

# Make the shell rc files source shell/env.sh, so agents started from the shell
# get its env. macOS: ~/.zshrc (created if missing) and ~/.bashrc if it exists.
# Elsewhere: ~/.bashrc (created if missing) and ~/.zshrc if it exists.
shell_env() {
  if [ "$OS" = macos ]; then
    _source_env_from "$HOME/.zshrc"
    [ ! -f "$HOME/.bashrc" ] || _source_env_from "$HOME/.bashrc"
  else
    _source_env_from "$HOME/.bashrc"
    [ ! -f "$HOME/.zshrc" ] || _source_env_from "$HOME/.zshrc"
  fi
}
