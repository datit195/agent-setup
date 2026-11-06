# shellcheck shell=bash
# Lock files: consistency check between core/skills.lock and
# agents/claude/plugins.lock, and --update (bump both to the latest upstream).

PLUGINS_LOCK="$ROOT/agents/claude/plugins.lock"
SKILLS_LOCK="$ROOT/core/skills.lock"
OFFICIAL_MARKETPLACE_REPO=anthropics/claude-plugins-official

# The plugins.lock line (id, repo, sha, version, how) whose repo is REPO.
_plugin_for_repo() { lock_lines "$PLUGINS_LOCK" | awk -F '\t' -v r="$1" '$2 == r { print; exit }'; }

# Every skills.lock entry that skips Claude must be a copy of a plugin in
# plugins.lock and sit on the same commit, so Claude and the other agents
# run the same version. Warns per mismatch; returns 1 when there is one.
check_locks() {
  local name repo sha path opts skip p rc=0
  while IFS=$'\t' read -r name repo sha path opts <&3; do
    [ -n "$name" ] || continue
    skip=$(opt_value "$opts" skip)
    case ",$skip," in *,claude,*) ;; *) continue ;; esac
    p=$(_plugin_for_repo "$repo")
    if [ -z "$p" ]; then
      warn "skills.lock: $name skips Claude, but no plugin in plugins.lock comes from $repo"
      rc=1
    elif [ "$(printf '%s' "$p" | cut -f3)" != "$sha" ]; then
      warn "skills.lock: $name is at ${sha:0:12} but plugin $(printf '%s' "$p" | cut -f1) is pinned to $(printf '%s' "$p" | cut -f3 | cut -c1-12); run install.sh --update or fix the locks"
      rc=1
    fi
  done 3< <(lock_lines "$SKILLS_LOCK")
  return $rc
}

_gh_url() { printf 'https://github.com/%s.git' "$1"; }
_raw() { curl -fsSL "https://raw.githubusercontent.com/$1/$2/$3" 2>/dev/null; }

# remote_sha REPO [TAG_GLOB]: the commit of REPO's default branch, or of its
# highest version tag matching TAG_GLOB.
remote_sha() {
  if [ -z "${2:-}" ]; then
    git ls-remote "$(_gh_url "$1")" HEAD 2>/dev/null | awk 'NR == 1 { print $1 }'
    return
  fi
  git ls-remote --tags --sort=-v:refname "$(_gh_url "$1")" "refs/tags/$2" 2>/dev/null | awk '
    { r = $2; sub("^refs/tags/", "", r); peeled = sub(/\^\{\}$/, "", r)
      if (top == "") top = r
      if (r == top) { if (peeled) p = $1; else d = $1 } }
    END { print (p != "" ? p : d) }'
}

# plugin_version REPO SHA NAME: the plugin's version at SHA: plugin.json, then
# its marketplace entry, else the short commit (as Claude Code does).
plugin_version() {
  local v
  v=$(_raw "$1" "$2" .claude-plugin/plugin.json | jq -r '.version // empty' 2>/dev/null || true)
  [ -n "$v" ] || v=$(_raw "$1" "$2" .claude-plugin/marketplace.json |
    jq -r --arg n "$3" '.plugins[]? | select(.name == $n) | .version // empty' 2>/dev/null || true)
  printf '%s' "${v:-${2:0:12}}"
}

# official_sha NAME REPO: the commit the official marketplace pins plugin NAME
# to (its source sha, else the head of its ref).
official_sha() {
  local head entry sha ref
  head=$(remote_sha "$OFFICIAL_MARKETPLACE_REPO") && [ -n "$head" ] || return 1
  entry=$(_raw "$OFFICIAL_MARKETPLACE_REPO" "$head" .claude-plugin/marketplace.json |
    jq -c --arg n "$1" '.plugins[] | select(.name == $n)' 2>/dev/null) && [ -n "$entry" ] || return 1
  sha=$(printf '%s' "$entry" | jq -r '.source.sha // empty')
  if [ -z "$sha" ]; then
    ref=$(printf '%s' "$entry" | jq -r '.source.ref // empty')
    if [ -n "$ref" ]; then
      sha=$(git ls-remote "$(_gh_url "$2")" "$ref" 2>/dev/null | awk 'NR == 1 { print $1 }')
    else
      sha=$(remote_sha "$2")
    fi
  fi
  printf '%s' "$sha"
}

_compare() { if [ "$2" = "$3" ]; then printf 'up to date'; else printf '%s -> %s  https://github.com/%s/compare/%s...%s' "${2:0:12}" "${3:0:12}" "$1" "${2:0:12}" "${3:0:12}"; fi; }

# _rewrite LOCK MAP COLS: copy LOCK with columns replaced from MAP lines
# "key<TAB>col3[<TAB>col4]" (key = column 1); comments are kept as they are.
_rewrite() {
  awk -F '\t' -v OFS='\t' -v cols="$3" '
    NR == FNR { m3[$1] = $2; m4[$1] = $3; next }
    /^[[:space:]]*#/ || NF < 3 { print; next }
    ($1 in m3) { $3 = m3[$1]; if (cols == 4) $4 = m4[$1] }
    { print }' "$2" "$1"
}

# --update: point every plugins.lock and skills.lock entry at the latest
# upstream commit (skills that copy a plugin follow the plugin), print old ->
# new per entry, and write the lock files unless this is a dry run.
update_locks() {
  local id repo sha ver how name nsha nver pmap="" smap="" seen=$'\n' key track n changed=0 tmp
  has_cmd curl || die "--update needs curl"
  log "Resolving the latest upstream versions..."
  while IFS=$'\t' read -r id repo sha ver how <&3; do
    [ -n "$id" ] || continue
    name=${id%@*}
    if [ "$how" = official ]; then nsha=$(official_sha "$name" "$repo" || true); else nsha=$(remote_sha "$repo" || true); fi
    if ! printf '%s' "$nsha" | grep -Eq '^[0-9a-f]{40}$'; then
      warn "update: could not resolve $id from $repo; kept ${sha:0:12}"
      nsha=$sha nver=$ver
    elif [ "$nsha" = "$sha" ]; then
      nver=$ver
    else
      nver=$(plugin_version "$repo" "$nsha" "$name")
    fi
    pmap="$pmap$id"$'\t'"$nsha"$'\t'"$nver"$'\n'
    if [ "$nsha" = "$sha" ]; then
      log "  plugin $id: up to date ($ver, ${sha:0:12})"
    else
      log "  plugin $id: $ver -> $nver  $(_compare "$repo" "$sha" "$nsha")"
      changed=$((changed + 1))
    fi
  done 3< <(lock_lines "$PLUGINS_LOCK")

  local opts path pid
  : >"$TMP_DIR/skills.map"
  while IFS=$'\t' read -r name repo sha path opts <&3; do
    [ -n "$name" ] || continue
    track=$(opt_value "$opts" track)
    key="$repo $track"
    pid=$(_plugin_for_repo "$repo" | cut -f1)
    case ",$(opt_value "$opts" skip)," in *,claude,*) ;; *) pid="" ;; esac
    if [ -n "$pid" ]; then
      nsha=$(printf '%s' "$pmap" | awk -F '\t' -v i="$pid" '$1 == i { print $2; exit }')
    else
      nsha=$(printf '%s' "$smap" | awk -F '\t' -v k="$key" '$1 == k { print $2; exit }')
      if [ -z "$nsha" ]; then
        nsha=$(remote_sha "$repo" "$track" || true)
        if ! printf '%s' "$nsha" | grep -Eq '^[0-9a-f]{40}$'; then
          warn "update: could not resolve $repo${track:+ (tag $track)}; kept ${sha:0:12}"
          nsha=$sha
        fi
        smap="$smap$key"$'\t'"$nsha"$'\n'
      fi
    fi
    printf '%s\t%s\n' "$name" "$nsha" >>"$TMP_DIR/skills.map"
    in_list "$seen" "$key $sha $nsha" && continue
    seen="$seen$key $sha $nsha"$'\n'
    n=$(lock_lines "$SKILLS_LOCK" | awk -F '\t' -v r="$repo" -v s="$sha" '$2 == r && $3 == s' | wc -l | tr -d ' ')
    log "  skills $repo${track:+ (tag $track)}${pid:+ (copies of $pid)}, $n entr$(if [ "$n" = 1 ]; then printf y; else printf ies; fi): $(_compare "$repo" "$sha" "$nsha")"
    [ "$sha" = "$nsha" ] || changed=$((changed + 1))
  done 3< <(lock_lines "$SKILLS_LOCK")
  printf '%s' "$pmap" >"$TMP_DIR/plugins.map"

  local lock map cols
  for lock in "$PLUGINS_LOCK" "$SKILLS_LOCK"; do
    if [ "$lock" = "$PLUGINS_LOCK" ]; then map=plugins.map cols=4; else map=skills.map cols=3; fi
    tmp="$TMP_DIR/$map.lock"
    _rewrite "$lock" "$TMP_DIR/$map" "$cols" >"$tmp" || die "update: could not rewrite ${lock#"$ROOT"/}"
    cmp -s "$tmp" "$lock" || act "write ${lock#"$ROOT"/}" cp "$tmp" "$lock"
  done
  [ "$changed" != 0 ] || log "Every lock entry is up to date."
  UPDATED=$changed
}
