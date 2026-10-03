#!/bin/sh
#
# Publish the package repository poudriere built for the image.
#
# These are the same packages the image is made of — our middleware, the web
# interface and everything they need. An installed system updates its own
# software from here, exactly as it updates the base from the pkgbase
# repository (tools/publish-pkgbase.sh).
#
# Poudriere keeps its repository as a farm of symlinks: `All` and the
# catalogue point into `.latest`, which points at the directory of the newest
# build. The published tree is flat instead, one directory per build with a
# `latest` symlink beside it, the same shape the base repository is published
# in, so a client configuration differs only in the path.
#
# The server is given on the command line: nothing about the project's
# infrastructure belongs in this repository.
#
# Usage:
#   publish-ports.sh <user@host> [remote-path] [repo-dir] [abi]
#
#   user@host     where to publish, over ssh
#   remote-path   directory served as /ports/   (default /var/www/updates/ports)
#   repo-dir      local repository              (poudriere's <jail>-p directory)
#   abi           name of the directory inside  (default FreeBSD:15:amd64)
#
# Example:
#   tools/publish-ports.sh deploy@updates.example.com
#
# What it does, in order:
#   * refuses to publish a repository without a catalogue — a half-copied
#     repository is worse than none, because clients see it and fail;
#   * copies packages first and the catalogue last, so a client that fetches
#     mid-copy never sees a catalogue referring to packages that are not there
#     yet;
#   * switches `latest` only when everything is in place, and keeps the
#     previous build on the server until then.

set -eu

usage() {
    sed -n '3,37p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
}

[ $# -ge 1 ] || usage

TARGET="$1"
REMOTE="${2:-/var/www/updates/ports}"
REPO="${3:-}"
ABI="${4:-FreeBSD:15:amd64}"

if [ -z "${REPO}" ]; then
    echo "no repository given: pass poudriere's <jail>-p directory" >&2
    exit 1
fi

[ -d "${REPO}" ] || { echo "no repository: ${REPO}" >&2; exit 1; }

# The build is named by poudriere and kept in .buildname; it is what the
# published directory is called, so two publications of the same build land
# in the same place and a client can tell them apart.
BUILD=$(cat "${REPO}/.buildname" 2>/dev/null || true)
[ -n "${BUILD}" ] || { echo "no .buildname in ${REPO}: not a poudriere repository" >&2; exit 1; }

# The catalogue is what a client uses to learn what the repository holds.
# Without it there is nothing to publish. Poudriere writes it at the end of a
# successful build, so its absence also means the build did not finish.
for f in meta.conf packagesite.pkg; do
    [ -f "${REPO}/${f}" ] || { echo "the build has no ${f}: the repository is incomplete" >&2; exit 1; }
done

COUNT=$(find "${REPO}/All/" -name '*.pkg' | wc -l | tr -d ' ')
SIZE=$(du -shL "${REPO}/All" | awk '{print $1}')
echo "publishing ${ABI}/${BUILD}: ${COUNT} packages, ${SIZE} -> ${TARGET}:${REMOTE}"

ssh "${TARGET}" "mkdir -p '${REMOTE}/${ABI}/${BUILD}'"

# -L dereferences poudriere's symlink farm: the published tree is plain files
# and does not depend on anything outside itself. `logs` is the build's own
# bookkeeping and has no business on a public server.
#
# Packages first, catalogue second: a client arriving mid-copy sees the old
# catalogue and the old packages, that is, a consistent picture.
rsync -aL --info=progress2 \
    --exclude 'logs' --exclude '.real_*' --exclude '.latest' \
    --exclude 'meta' --exclude 'meta.conf' \
    --exclude 'packagesite.*' --exclude 'data.*' \
    "${REPO}/" "${TARGET}:${REMOTE}/${ABI}/${BUILD}/"

rsync -aL \
    --include 'meta' --include 'meta.*' --include 'packagesite.*' --include 'data.*' \
    --exclude '*' \
    "${REPO}/" "${TARGET}:${REMOTE}/${ABI}/${BUILD}/"

# Switch latest once everything is in place.
ssh "${TARGET}" "cd '${REMOTE}/${ABI}' && ln -sfn '${BUILD}' latest.new && mv -Tf latest.new latest"

echo "published: ${REMOTE}/${ABI}/${BUILD}, latest switched"
echo
echo "on the client:"
echo "  /usr/local/etc/pkg/repos/bsdnas-ports.conf"
echo "  bsdnas-ports: { url: \"https://<server>/ports/${ABI}/latest\", enabled: yes }"
