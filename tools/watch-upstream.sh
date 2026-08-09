#!/usr/bin/env bash
#
# Upstream watcher: shows what has changed outside and needs a reaction from us.
# It changes nothing, it only reports. The decision is made by a human (or by an
# agent trusted with it).
#
# The point is to keep the fork from rotting silently. The ports tree, the
# FreeBSD base, OpenZFS and the security advisories all live their own lives; an
# upstream missed for half a year turns into exactly the gap between CORE 13.3
# and FreeBSD 15 that had to be dug out at the start of the project.
#
# Four observations:
#   1. FreeBSD base   - has stable/15 moved under our patch set
#   2. security       - fresh FreeBSD SA/EN advisories
#   3. ports tree     - has the next quarterly branch been opened
#   4. OpenZFS        - has a release newer than the built one appeared
#
# An "always red" report stops being read, so the watcher keeps a journal of what
# has been dealt with (.upstream-seen) and reports only what is new since the
# last time.
#
# Usage:
#   tools/watch-upstream.sh              report to the terminal
#   tools/watch-upstream.sh --quiet      stay silent when there is nothing new (for cron)
#   tools/watch-upstream.sh --ack        mark the current state as dealt with
#
# Exit codes: 0 nothing new, 10 something to report, 1 an error.

set -u

QUIET=0
ACK=0
case "${1:-}" in
--quiet) QUIET=1 ;;
--ack)   ACK=1 ;;
"")      ;;
*)       echo "unknown option: $1" >&2; exit 1 ;;
esac

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPOS="$ROOT/build/profiles/freenas/repos.pyd"
SEEN="${SEEN_FILE:-$ROOT/.upstream-seen}"
[ -f "$REPOS" ] || { echo "not found: $REPOS" >&2; exit 1; }

FINDINGS=0
OUT=""
STATE=""            # the state of this run, written to the journal on --ack

say()  { OUT="${OUT}$1
"; }
note() { FINDINGS=$((FINDINGS + 1)); say "$1"; }

# Remember an observed value and report whether it is new
track() {
    STATE="${STATE}$1
"
    grep -qxF "$1" "$SEEN" 2>/dev/null && return 1
    return 0
}

# The branch value for the repository with the given name in repos.pyd
repo_branch() {
    python3 - "$REPOS" "$1" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
name = sys.argv[2]
for block in text.split("repos +="):
    if f'"name": "{name}"' in block:
        m = re.search(r'"branch":\s*"([^"]+)"', block)
        if m:
            print(m.group(1))
            break
PY
}

# --- 1. FreeBSD base -------------------------------------------------------
watch_base() {
    local _branch _ours _theirs
    _branch=$(repo_branch os)
    _ours=$(git ls-remote https://github.com/bsdnas/os.git "refs/heads/${_branch}" 2>/dev/null | cut -f1)
    _theirs=$(git ls-remote https://github.com/freebsd/freebsd-src.git refs/heads/stable/15 2>/dev/null | cut -f1)

    if [ -z "$_ours" ] || [ -z "$_theirs" ]; then
        say "  could not query (network?)"
        return
    fi
    say "  our branch: ${_branch} @ ${_ours:0:9}"
    say "  upstream stable/15 @ ${_theirs:0:9}"

    # Measuring the exact lag needs a clone; here the fact that the head has
    # moved is enough, the decision to port is taken with the tree at hand.
    if track "base:${_theirs}"; then
        note "  -> stable/15 has moved: port the patch set"
        say  "    git rebase --onto up/stable/15 <previous-base> ${_branch}"
    fi
}

# --- 2. Security advisories ------------------------------------------------
watch_security() {
    local _feed _recent _new=""
    # The advisories.rdf from the old instructions returns 404; the working
    # address is feed.xml. The feed carries both SA (security) and EN (errata).
    _feed=$(curl -s --max-time 25 https://www.freebsd.org/security/feed.xml 2>/dev/null)
    if [ -z "$_feed" ]; then
        say "  the feed is not available"
        return
    fi
    _recent=$(printf '%s' "$_feed" |
        grep -oE 'FreeBSD-(SA|EN)-[0-9]{2}:[0-9]+\.[a-zA-Z0-9_]+' | awk '!seen[$0]++' | head -6)
    if [ -z "$_recent" ]; then
        say "  could not parse the feed (has the format changed?)"
        return
    fi

    say "  latest:"
    while read -r a; do
        [ -n "$a" ] || continue
        say "    $a"
        track "adv:${a}" && _new="${_new}${a} "
    done <<EOF
$_recent
EOF

    if [ -n "$_new" ]; then
        note "  -> new since the last check: ${_new% }"
        say  "    check against stable/15 and mark: tools/watch-upstream.sh --ack"
    fi
}

# --- 3. Ports tree ---------------------------------------------------------
watch_ports() {
    local _cur _year _q _next
    _cur=$(repo_branch ports)
    say "  our branch: ${_cur}"

    _year=${_cur%Q*}; _q=${_cur#*Q}
    if [ "$_q" -ge 4 ]; then _next="$((_year + 1))Q1"; else _next="${_year}Q$((_q + 1))"; fi

    if git ls-remote --exit-code --heads \
        https://github.com/freebsd/freebsd-ports.git "$_next" >/dev/null 2>&1; then
        if track "ports:${_next}"; then
            note "  -> the next quarterly branch is open: ${_next}"
            say  "    change the branch in repos.pyd only together with a full rebuild"
        else
            say "  the next one (${_next}) is open, the move is deliberately deferred"
        fi
    else
        say "  the next one (${_next}) is not open yet"
    fi
}

# --- 4. OpenZFS ------------------------------------------------------------
watch_openzfs() {
    local _mk _ours _tag _latest
    _mk=$(curl -s --max-time 25 \
        https://raw.githubusercontent.com/bsdnas/middleware/bsdnas/nas_ports/filesystems/openzfs/Makefile 2>/dev/null)
    _ours=$(printf '%s' "$_mk" | sed -n 's/^PORTVERSION=[[:space:]]*//p' | head -1)
    _tag=$(curl -s --max-time 25 https://api.github.com/repos/openzfs/zfs/releases/latest 2>/dev/null |
        python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name",""))' 2>/dev/null)
    # OpenZFS releases are tagged as zfs-2.4.3, and the port version is the
    # same tag without the prefix. The stripped values have to be compared,
    # otherwise the watcher forever demands an update to a version that is
    # already built.
    _latest=${_tag#zfs-}
    _latest=${_latest#v}

    if [ -z "$_ours" ] || [ -z "$_latest" ]; then
        say "  could not compare the versions"
        return
    fi
    say "  ours is ${_ours}, the latest release is ${_latest}"
    if [ "$_ours" != "$_latest" ] && track "openzfs:${_latest}"; then
        note "  -> an update to ${_latest} is available"
        say  "    middleware: tools/update_openzfs_ports.py ${_latest} <tag sha>"
    fi
}

say "Upstream watch - $(date '+%Y-%m-%d %H:%M')"
say ""
say "FreeBSD base:";  watch_base
say ""
say "Security:";      watch_security
say ""
say "Ports tree:";    watch_ports
say ""
say "OpenZFS:";       watch_openzfs
say ""

if [ "$ACK" -eq 1 ]; then
    printf '%s' "$STATE" > "$SEEN"
    printf '%s' "$OUT"
    echo "state marked as dealt with: $SEEN"
    exit 0
fi

say "Need attention: ${FINDINGS}"
if [ "$QUIET" -eq 1 ] && [ "$FINDINGS" -eq 0 ]; then
    exit 0
fi
printf '%s' "$OUT"
[ "$FINDINGS" -gt 0 ] && exit 10
exit 0
