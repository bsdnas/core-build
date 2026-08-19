#!/bin/sh
#
# Cleaning up the artefacts of past builds on the build machine.
#
# Every `make release` run leaves a directory of about 1.3 GB in _BE/release
# and an ISO next to it. Nothing removes them. Over a week of debugging this
# added up to 29 directories and 44 GB, the root partition ran out, and the
# build failed after 4 hours 50 minutes on rust, on grub2-efi and on the Angular
# build, with every failure looking like a separate breakage. The real cause was
# a single one: ENOSPC.
#
# So the cleanup is part of the routine, not a one-off action.
#
# Usage:
#   tools/prune-builds.sh            show what would be removed
#   tools/prune-builds.sh --apply    remove
#   KEEP=5 tools/prune-builds.sh     how many recent builds to keep (default 3)

set -u

KEEP="${KEEP:-3}"
BE="${BE:-/usr/build/freenas/_BE}"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

[ -d "$BE/release" ] || { echo "not found: $BE/release" >&2; exit 1; }
cd "$BE/release" || exit 1

# Sorted by the actual time rather than by the stamp in the directory name.
# ONLY the BSDnas-15-MASTER-* build directories are counted: on 2026-08-19 the
# script took the auxiliary directories (Nightlies-Update) for the "most recent"
# ones and removed the directory of the fresh build together with its ISO.
total=$(ls -1dt BSDnas-15-MASTER-*/ 2>/dev/null | wc -l | tr -d ' ')
if [ "$total" -le "$KEEP" ]; then
    echo "builds: ${total}, keeping ${KEEP}, nothing to remove"
    exit 0
fi

doomed=$(ls -1dt BSDnas-15-MASTER-*/ 2>/dev/null | sed 's,/$,,' | tail -n +$((KEEP + 1)))
freed=$(echo "$doomed" | while read -r d; do
    [ -n "$d" ] && du -sk "$d" 2>/dev/null | cut -f1
done | awk '{s += $1} END {printf "%d", s / 1048576}')

printf 'builds: %s, keeping %s, removing %s (about %s GB)\n' \
    "$total" "$KEEP" "$(echo "$doomed" | wc -l | tr -d ' ')" "$freed"

echo "$doomed" | while read -r d; do
    [ -n "$d" ] || continue
    if [ "$APPLY" -eq 1 ]; then
        rm -rf "$d" && echo "  removed: $d"
    else
        echo "  would be removed: $d"
    fi
done

if [ "$APPLY" -eq 1 ]; then
    # the images sit next to the object directory and live a life of their own
    ls -1t "$BE"/objs/*.iso 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r iso; do
        rm -f "$iso" && echo "  image removed: $(basename "$iso")"
    done
    echo "free on the partition: $(df -h "$BE" | tail -1 | awk '{print $4}')"
else
    echo "run with --apply to remove"
fi
