# shellcheck shell=bash
# Approved versions and update checks.
#
# Every third-party item (each skills/plugin repo, each pinned MCP server and
# each tools.lock tool with a release=) has one approved version per machine,
# kept in state/approved.json (gitignored, never committed). A plain run
# installs exactly that version. The first run approves what is already
# installed, else the newest upstream. Newer upstream versions are only
# installed after the user approves them with --update.
#
# state/updates.json caches the newest upstream versions (checked at most once
# per CHECK_TTL), whether origin has new commits for this repo, and the
# user's --skip and --snooze answers.

STATE_DIR="$ROOT/state"
APPROVED_FILE="$STATE_DIR/approved.json"
UPDATES_FILE="$STATE_DIR/updates.json"
OFFICIAL_CATALOG_REPO=anthropics/claude-plugins-official
CHECK_TTL=${AGENT_SETUP_CHECK_TTL:-86400}
SNOOZE_SECS=86400

APPROVED='{}' APPROVED_ORIG='{}' UPSTATE='{}'
UPDATING=$'\n'   # items approved by this run's --update, one per line

_json_file() { jq -c 'if type == "object" then . else {} end' "$1" 2>/dev/null | tr -d '\r' || true; }
load_state() {
  has_cmd jq || return 0
  APPROVED=$(_json_file "$APPROVED_FILE"); APPROVED=${APPROVED:-'{}'}
  APPROVED_ORIG=$APPROVED
  UPSTATE=$(_json_file "$UPDATES_FILE"); UPSTATE=${UPSTATE:-'{}'}
}
now() { date +%s; }

# approved ITEM [FIELD]: the approved version (or FIELD: tag, previous) of ITEM, or "".
approved() { printf '%s' "$APPROVED" | jq -r --arg n "$1" --arg f "${2:-version}" '.[$n][$f] // empty'; }

# set_approved ITEM VERSION TAG: approve VERSION (keeping the old one as "previous").
set_approved() {
  APPROVED=$(printf '%s' "$APPROVED" | jq -c --arg n "$1" --arg v "$2" --arg t "${3:-}" '
    (.[$n].version // "") as $old
    | .[$n] = ({version: $v} + (if $t != "" then {tag: $t} else {} end)
               + (if $old != "" and $old != $v then {previous: $old} else {} end))')
}

# Write state/approved.json when this run changed it (backed up first).
save_approved() {
  [ "$(printf '%s' "$APPROVED" | jq -cS .)" != "$(printf '%s' "$APPROVED_ORIG" | jq -cS .)" ] || return 0
  backup_copy_once "$APPROVED_FILE"
  act "write state/approved.json (approved versions on this machine)" _write_file "$APPROVED_FILE" "$(printf '%s' "$APPROVED" | jq -S .)"
  APPROVED_ORIG=$APPROVED
}

# Write state/updates.json (never in a dry run).
save_upstate() { [ "$DRY_RUN" = 1 ] || _write_file "$UPDATES_FILE" "$(printf '%s' "$UPSTATE" | jq -S .)" || true; }

updating() { in_list "$UPDATING" "$1"; }

# repo_item OWNER/REPO: the item name of a repo (its name, lower case).
repo_item() { printf '%s' "${1#*/}" | tr 'A-Z' 'a-z'; }

# Every item, as "name<TAB>kind<TAB>source<TAB>extra":
#   git       a skills/plugin repo at its default branch head (source owner/repo)
#   tag       a skills repo following its newest tag matching extra (track=)
#   official  a plugin repo Claude Code installs from Anthropic's official
#             marketplace: the newest is the commit that catalog offers (extra: plugin name)
#   npm       a core/mcp.json server with "pin": {"npm": package} (extra: compare URL template)
#   release   a tools.lock tool with release=owner/repo (its newest GitHub release tag)
update_items() {
  local repo name off track opts
  { lock_lines "$ROOT/core/skills.lock" | cut -f2; lock_lines "$PLUGINS_LOCK" | cut -f2; } | tr -d '\r' | awk 'NF && !seen[$0]++' |
    while IFS= read -r repo; do
      name=$(repo_item "$repo")
      off=$(lock_lines "$PLUGINS_LOCK" | awk -F '\t' -v r="$repo" '$2 == r && $3 ~ /claude=[^ ]*@claude-plugins-official/ { print $1; exit }')
      track=$(lock_lines "$ROOT/core/skills.lock" | awk -F '\t' -v r="$repo" '$2 == r { print $4 }' |
        while IFS= read -r opts; do opt_value "$opts" track; done | head -n 1)
      if [ -n "$off" ]; then printf '%s\tofficial\t%s\t%s\n' "$name" "$repo" "$off"
      elif [ -n "$track" ]; then printf '%s\ttag\t%s\t%s\n' "$name" "$repo" "$track"
      else printf '%s\tgit\t%s\t\n' "$name" "$repo"; fi
    done
  jq -r '.servers // {} | to_entries[] | select(.value.pin.npm) | "\(.key)\tnpm\t\(.value.pin.npm)\t\(.value.pin.compare // "")"' "$ROOT/core/mcp.json" | tr -d '\r'
  lock_lines "$ROOT/tools/tools.lock" | while IFS=$'\t' read -r name _ _ _ opts; do
    repo=$(opt_value "$opts" release)
    [ -z "$repo" ] || printf '%s\trelease\t%s\t\n' "$name" "$repo"
  done | awk -F '\t' '!seen[$1]++'
}

item_line() { update_items | awk -F '\t' -v n="$1" '$1 == n && !f { print; f = 1 }'; }

# Network helpers with short timeouts and no prompts.
_git_net() { GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=10 "$@"; }

# with_timeout SECS CMD...: run CMD, killing it after SECS (macOS has no timeout(1)).
with_timeout() {
  local secs=$1 pid w rc=0; shift
  "$@" &
  pid=$!
  { sleep "$secs"; kill "$pid" 2>/dev/null; } >/dev/null 2>&1 &
  w=$!
  wait "$pid" || rc=$?
  kill "$w" 2>/dev/null || true
  return $rc
}
_curl() { curl -fsSL --connect-timeout 5 --max-time 15 "$@"; }
gh_url() { printf 'https://github.com/%s.git' "$1"; }
_is_sha() { printf '%s' "$1" | grep -Eq '^[0-9a-f]{40}$'; }

# resolve_latest KIND SOURCE EXTRA: the newest upstream version as
# "version<TAB>tag" (tag may be empty). Fails when it cannot be resolved.
resolve_latest() {
  local kind=$1 src=$2 extra=$3 v="" t="" entry url ref
  case $kind in
    git) v=$(_git_net ls-remote "$(gh_url "$src")" HEAD 2>/dev/null | awk 'NR == 1 { print $1 }') ;;
    tag)
      read -r v t < <(_git_net ls-remote --tags --sort=-v:refname "$(gh_url "$src")" "refs/tags/$extra" 2>/dev/null | awk '
        { r = $2; sub("^refs/tags/", "", r); peeled = sub(/\^\{\}$/, "", r)
          if (top == "") top = r
          if (r == top) { if (peeled) p = $1; else d = $1 } }
        END { if (top != "") print (p != "" ? p : d), top }') || true ;;
    official)
      entry=$(_curl "https://raw.githubusercontent.com/$OFFICIAL_CATALOG_REPO/HEAD/.claude-plugin/marketplace.json" 2>/dev/null |
        jq -c --arg n "$extra" '[.plugins[]? | select(.name == $n) | .source][0] // empty' 2>/dev/null) || true
      [ -n "$entry" ] || return 1
      v=$(printf '%s' "$entry" | jq -r 'if type == "object" then .sha // "" else "" end')
      if [ -z "$v" ]; then
        url=$(printf '%s' "$entry" | jq -r 'if type == "object" then .url // (if .repo then "https://github.com/\(.repo).git" else "" end) else "" end')
        ref=$(printf '%s' "$entry" | jq -r 'if type == "object" then .ref // "HEAD" else "HEAD" end')
        [ -n "$url" ] || url=$(gh_url "$src")
        v=$(_git_net ls-remote "$url" "$ref" 2>/dev/null | awk 'NR == 1 { print $1 }')
      fi ;;
    npm) v=$(_curl "https://registry.npmjs.org/$(printf '%s' "$src" | sed 's|/|%2f|')/latest" 2>/dev/null | jq -r '.version // empty' 2>/dev/null) || true ;;
    release)
      v=$(_curl -I -o /dev/null -w '%{url_effective}' "https://github.com/$src/releases/latest" 2>/dev/null) || true
      v=${v##*/}
      case $v in latest | releases | "") v="" ;; esac ;;
  esac
  case $kind in git | tag | official) _is_sha "$v" || return 1 ;; *) [ -n "$v" ] || return 1 ;; esac
  printf '%s\t%s\n' "$v" "$t"
}

# show_version KIND VERSION TAG: how a version is shown (a tag, a short commit or the version).
show_version() {
  if [ -n "$3" ]; then printf '%s' "$3"
  else case $1 in git | tag | official) printf '%s' "${2:0:12}" ;; *) printf '%s' "$2" ;; esac; fi
}

# compare_url KIND SOURCE EXTRA OLD NEW (as shown).
compare_url() {
  case $1 in
    git | tag | official | release) printf 'https://github.com/%s/compare/%s...%s' "$2" "$4" "$5" ;;
    npm)
      if [ -n "$3" ]; then printf '%s' "$3" | sed -e "s|{old}|$4|g" -e "s|{new}|$5|g"
      else printf 'https://www.npmjs.com/package/%s?activeTab=versions' "$2"; fi ;;
  esac
}

# Commits on origin's default branch that this checkout does not have, or fail.
self_behind() {
  local def
  [ -d "$ROOT/.git" ] || return 1
  with_timeout 20 env GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=10 \
    -C "$ROOT" fetch -q origin </dev/null >/dev/null 2>&1 || return 1
  def=$(git -C "$ROOT" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) || def=origin/master
  git -C "$ROOT" rev-list --count "HEAD..$def" 2>/dev/null
}

# Resolve the newest version of every item at once (in parallel) and cache
# the results in state/updates.json. Items that fail keep their last result.
refresh_updates() {
  local d="$TMP_DIR/resolve" i=0 name kind src extra r latest behind=""
  rm -rf "$d" && mkdir -p "$d"
  while IFS=$'\t' read -r name kind src extra <&3; do
    [ -n "$name" ] || continue
    i=$((i + 1))
    { r=$(resolve_latest "$kind" "$src" "$extra") && printf '%s\t%s\n' "$name" "$r" >"$d/item.$i"; } </dev/null >/dev/null 2>&1 &
  done 3< <(update_items)
  { r=$(self_behind) && printf '%s' "$r" >"$d/behind"; } </dev/null >/dev/null 2>&1 &
  wait
  [ ! -f "$d/behind" ] || behind=$(cat "$d/behind")
  latest=$({ cat "$d"/item.* 2>/dev/null || true; } | jq -Rn '[inputs | split("\t") | {(.[0]): {version: .[1], tag: (.[2] // "")}}] | add // {}')
  if [ "$latest" = "{}" ] && [ -z "$behind" ]; then
    UPSTATE=$(printf '%s' "$UPSTATE" | jq -c --argjson t "$(now)" '.failed = $t')
  else
    UPSTATE=$(printf '%s' "$UPSTATE" | jq -c --argjson l "$latest" --arg b "$behind" --argjson t "$(now)" '
      .latest = ((.latest // {}) + $l) | .checked = $t | del(.failed)
      | if $b != "" then .behind = ($b | tonumber) else . end')
  fi
  save_upstate
}

# Refresh when the cache is older than CHECK_TTL (or FORCE=1); after a failed
# check (offline) wait an hour before trying again.
maybe_refresh() {
  local t checked failed
  t=$(now)
  checked=$(printf '%s' "$UPSTATE" | jq -r '.checked // 0')
  failed=$(printf '%s' "$UPSTATE" | jq -r '.failed // 0')
  if [ "${FORCE:-0}" = 1 ] || { [ $((t - checked)) -ge "$CHECK_TTL" ] && [ $((t - failed)) -ge 3600 ]; }; then
    refresh_updates
  fi
}

# Items with a newer upstream than their approved version, from the cache:
# "name<TAB>old<TAB>new<TAB>url<TAB>state<TAB>new version<TAB>new tag", where
# state is "", "skipped" (the user skipped that version) or "snoozed".
pending_updates() {
  local name kind src extra a at l lt old new state t
  t=$(now)
  while IFS=$'\t' read -r name kind src extra <&3; do
    [ -n "$name" ] || continue
    a=$(approved "$name"); [ -n "$a" ] || continue
    l=$(printf '%s' "$UPSTATE" | jq -r --arg n "$name" '.latest[$n].version // empty')
    [ -n "$l" ] && [ "$l" != "$a" ] || continue
    at=$(approved "$name" tag)
    lt=$(printf '%s' "$UPSTATE" | jq -r --arg n "$name" '.latest[$n].tag // empty')
    old=$(show_version "$kind" "$a" "$at") new=$(show_version "$kind" "$l" "$lt")
    if [ -n "$at" ] || [ -n "$lt" ]; then [ -n "$at" ] && [ -n "$lt" ] || { old=${a:0:12} new=${l:0:12}; }; fi
    state=$(printf '%s' "$UPSTATE" | jq -r --arg n "$name" --arg v "$new" --argjson t "$t" '
      if (.skipped[$n] // "") == $v then "skipped" elif (.snoozed[$n] // 0) > $t then "snoozed" else "-" end')
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$old" "$new" "$(compare_url "$kind" "$src" "$extra" "$old" "$new")" "$state" "$l" "${lt:--}"
  done 3< <(update_items)
}

# Commits origin has that this checkout lacks, when not snoozed ("" otherwise).
behind_notice() {
  printf '%s' "$UPSTATE" | jq -r --argjson t "$(now)" '
    if (.behind // 0) > 0 and (.snoozed["agent-setup"] // 0) <= $t then .behind else empty end'
}

# --check [--json] [--force]: list the newer versions.
run_check() {
  local p b
  maybe_refresh
  [ "$(printf '%s' "$UPSTATE" | jq -r '.checked // empty')" != "" ] || return 0
  p=$(pending_updates)
  b=$(printf '%s' "$UPSTATE" | jq -r '.behind // 0')
  if [ "${JSON:-0}" = 1 ]; then
    printf '%s' "$p" | jq -Rn --argjson b "$b" --argjson c "$(printf '%s' "$UPSTATE" | jq '.checked')" '
      {checked: $c, behind: $b,
       updates: [inputs | split("\t") | select(length >= 5)
                 | {name: .[0], approved: .[1], latest: .[2], url: .[3], state: (if .[4] == "-" then "pending" else .[4] end)}]}'
    return 0
  fi
  if [ -z "$p" ] && [ "$b" = 0 ]; then log "No updates: every item is at the newest upstream version."; return 0; fi
  printf '%s\n' "$p" | while IFS=$'\t' read -r name old new url state _; do
    [ -n "$name" ] || continue
    case $state in -) state="" ;; *) state=" ($state)" ;; esac
    printf '%s: %s -> %s %s%s\n' "$name" "$old" "$new" "$url" "$state"
  done
  [ "$b" = 0 ] || printf 'agent-setup: %s new commit(s) on origin (git -C ~/.agent-setup pull && ~/.agent-setup/install.sh)\n' "$b"
}

# --notice: the session-start text for agents (nothing when nothing is pending).
run_notice() {
  local p b list names
  maybe_refresh
  p=$(pending_updates | awk -F '\t' '$5 == "-"')
  b=$(behind_notice)
  [ -n "$p" ] || [ -n "$b" ] || return 0
  printf 'agent-setup update notice (from the SessionStart hook of ~/.agent-setup).\n'
  if [ -n "$p" ]; then
    list=$(printf '%s\n' "$p" | awk -F '\t' 'NF { printf "- %s: %s -> %s %s\n", $1, $2, $3, $4 }')
    names=$(printf '%s\n' "$p" | cut -f1 | paste -sd, -)
    cat <<EOF
Newer upstream versions exist for items agent-setup installed on this machine. Nothing changes until the user approves (approved version -> newest):
$list
In your first reply, before other work, tell the user in the language they are using which items have updates, with the versions and compare links, and ask for each one: update now, later, or skip this version. Run nothing before they answer. Then, for the items they chose:
- update now: ~/.agent-setup/install.sh --update <names> --yes   (comma-separated names, e.g. $names; "all" for every item)
- later: ~/.agent-setup/install.sh --snooze <names>   (asks again in 24 hours)
- skip this version: ~/.agent-setup/install.sh --skip <name>@<version>   (asks again only when a newer version appears)
After an update, tell them to restart the agent (in Claude Code, /reload-plugins also works) to load new plugin versions.
EOF
  fi
  if [ -n "$b" ]; then
    printf 'The agent-setup repo has %s new commit(s) on origin (changes to rules, skills or settings). Mention it and suggest: git -C ~/.agent-setup pull && ~/.agent-setup/install.sh (to stop this reminder for 24 hours: ~/.agent-setup/install.sh --snooze agent-setup).\n' "$b"
  fi
}

# _names ARGS: the item names in ARGS (comma or space separated), one per line;
# "all" stays "all".
_names() { printf '%s\n' "$@" | tr ', ' '\n\n' | awk 'NF && !seen[$0]++'; }

_known_item() { [ "$1" = agent-setup ] || [ -n "$(item_line "$1")" ]; }

# --snooze NAMES|all
run_snooze() {
  local n until list
  [ $# -gt 0 ] || die "--snooze needs item names (or all)"
  until=$(( $(now) + SNOOZE_SECS ))
  list=$(_names "$@")
  if [ "$list" = all ]; then list=$(printf '%s\n' "$(pending_updates | cut -f1)" agent-setup | awk 'NF'); fi
  for n in $list; do
    _known_item "$n" || die "unknown item '$n' (known: $(update_items | cut -f1 | tr '\n' ' ')agent-setup)"
    UPSTATE=$(printf '%s' "$UPSTATE" | jq -c --arg n "$n" --argjson u "$until" '.snoozed[$n] = $u')
    log "Snoozed $n: you are asked again after 24 hours."
  done
  save_upstate
}

# --skip NAME@VERSION...
run_skip() {
  local a n v
  [ $# -gt 0 ] || die "--skip needs NAME@VERSION"
  for a in $(_names "$@"); do
    n=${a%%@*} v=${a#*@}
    [ "$n" != "$a" ] && [ -n "$v" ] || die "--skip needs NAME@VERSION (got '$a')"
    _known_item "$n" || die "unknown item '$n' (known: $(update_items | cut -f1 | tr '\n' ' '))"
    UPSTATE=$(printf '%s' "$UPSTATE" | jq -c --arg n "$n" --arg v "$v" '.skipped[$n] = $v | del(.snoozed[$n])')
    log "Skipped $n $v: you are asked again only when a newer version appears."
  done
  save_upstate
}

# --update [NAMES|all]: approve newer versions (asking per item unless --yes
# with names), then the run installs them. Only state/ changes in the repo.
run_update() {
  local list p name old new url state v t n=0
  list=$(_names "$@")
  [ -n "$list" ] || [ "$YES" != 1 ] || die "--update --yes needs item names (or all)"
  for name in $list; do [ "$name" = all ] || _known_item "$name" || die "unknown item '$name' (known: $(update_items | cut -f1 | tr '\n' ' '))"; done
  log "Checking upstream versions..."
  FORCE=1 refresh_updates
  p=$(pending_updates)
  for name in $list; do
    [ "$name" = all ] || [ "$name" = agent-setup ] || printf '%s\n' "$p" | cut -f1 | grep -qx "$name" ||
      log "$name: no newer version (approved: $(show_version "$(item_line "$name" | cut -f2)" "$(approved "$name")" "$(approved "$name" tag)"))"
  done
  while IFS=$'\t' read -r name old new url state v t <&3; do
    [ -n "$name" ] || continue
    if [ -n "$list" ]; then
      [ "$list" = all ] || in_list $'\n'"$list"$'\n' "$name" || continue
    else
      [ "$state" = - ] || continue
    fi
    if [ -n "$list" ] && [ "$YES" = 1 ]; then
      log "update $name: $old -> $new $url"
    elif ! ask "Update $name: $old -> $new ($url)?"; then
      log "kept $name at $old"
      continue
    fi
    [ "$t" != - ] || t=""
    set_approved "$name" "$v" "$t"
    UPDATING="$UPDATING$name"$'\n'
    UPSTATE=$(printf '%s' "$UPSTATE" | jq -c --arg n "$name" 'del(.skipped[$n]) | del(.snoozed[$n])')
    n=$((n + 1))
  done 3<<EOF
$p
EOF
  save_upstate
  [ "$n" -gt 0 ] || { log "Nothing to update."; return 1; }
  log "Approved $n update(s) on this machine; installing them."
}

# Installed commit of a repo: Claude Code's record of its plugin, else the vendor checkout.
_installed_commit() {
  local repo=$1 id sha
  id=$(plugin_ids claude | awk -F '\t' -v r="$repo" '$2 == r && !f { print $3; f = 1 }')
  if [ -n "$id" ]; then
    sha=$(claude_installed_ref "$id" | awk '{ print $2 }')
    _is_sha "$sha" && { printf '%s' "$sha"; return 0; }
  fi
  sha=$(git -C "$ROOT/vendor/${repo%%/*}__${repo#*/}" rev-parse HEAD 2>/dev/null || true)
  if _is_sha "$sha"; then printf '%s' "$sha"; fi
}

# The installed version of a tools.lock tool (from its check command), or "".
tool_installed_version() {
  local check
  check=$(lock_lines "$ROOT/tools/tools.lock" | awk -F '\t' -v n="$1" -v os="$OS" '$1 == n && ($4 == "" || $4 == "all" || index("," $4 ",", "," os ",")) { print $3; exit }')
  [ -n "$check" ] || return 0
  bash -c "$check" 2>/dev/null </dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true
}

# Approve every item that has no approved version yet: the installed version
# when there is one, else the newest upstream. Tools are approved only when
# installed or when the tools step runs.
approve_missing() {
  local name kind src extra v t r how inst
  while IFS=$'\t' read -r name kind src extra <&3; do
    [ -n "$name" ] && [ -z "$(approved "$name")" ] || continue
    v="" t="" how="installed"
    case $kind in
      git | tag | official) v=$(_installed_commit "$src") ;;
      release)
        inst=$(tool_installed_version "$name")
        if [ -n "$inst" ]; then
          r=$(resolve_latest "$kind" "$src" "$extra" | cut -f1) || r=""
          case $r in "$inst") v=$inst ;; *) v="v$inst" ;; esac
        elif [ "${SKIP_TOOLS:-0}" = 1 ]; then
          continue
        fi ;;
    esac
    if [ -z "$v" ]; then
      how="newest upstream"
      if r=$(resolve_latest "$kind" "$src" "$extra"); then v=$(printf '%s' "$r" | cut -f1) t=$(printf '%s' "$r" | cut -f2); fi
    fi
    if [ -z "$v" ]; then
      warn "could not resolve $name ($src; offline?); it is not installed or changed until it can be approved"
      continue
    fi
    set_approved "$name" "$v" "$t"
    log "approve $name $(show_version "$kind" "$v" "$t") ($how)"
  done 3< <(update_items)
  save_approved
}

# At the end of a run: the pending updates from the cache (no network).
pending_summary() {
  local p
  p=$(pending_updates | awk -F '\t' '$5 != "skipped"')
  [ -n "$p" ] || return 0
  section "Updates available (not installed)"
  printf '%s\n' "$p" | while IFS=$'\t' read -r name old new url state _; do
    [ -n "$name" ] || continue
    case $state in -) state="" ;; *) state=" ($state)" ;; esac
    log "$name: $old -> $new $url$state"
  done
  log "Approve with: ~/.agent-setup/install.sh --update <names|all>   (or --skip <name>@<version>, --snooze <names>)"
}
