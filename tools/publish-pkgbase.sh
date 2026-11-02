#!/bin/sh
#
# Publish the base package repository built by `make packages`.
#
# The build leaves the repository under OBJDIR/pkgbase-repo, one directory per
# build plus a `latest` symlink. This copies the current one to the update
# server, where installed systems fetch it from to update their base with pkg
# instead of unpacking a whole image.
#
# The server is given on the command line: nothing about the project's
# infrastructure belongs in this repository.
#
# Usage:
#   publish-pkgbase.sh <user@host> [remote-path] [repo-dir]
#
#   user@host     where to publish, over ssh
#   remote-path   directory served as /pkgbase/  (default /var/www/updates/pkgbase)
#   repo-dir      local repository              (default from the build tree)
#
# Example:
#   tools/publish-pkgbase.sh deploy@updates.example.com
#
# What it does, in order:
#   * refuses to publish a repository without a catalogue — a half-copied
#     repository is worse than none, because clients see it and fail;
#   * refuses to publish a catalogue whose signature does not verify (see
#     tools/verify-pkg-repo.sh): installed systems would refuse it anyway;
#   * copies packages first and the catalogue last, so a client that fetches
#     mid-copy never sees a catalogue referring to packages that are not there
#     yet;
#   * keeps the previous build on the server until the new one is complete.

set -eu

usage() {
    sed -n '3,31p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
}

[ $# -ge 1 ] || usage

TARGET="$1"
REMOTE="${2:-/var/www/updates/pkgbase}"
REPO="${3:-}"

if [ -z "${REPO}" ]; then
    # Look for the repository in the build tree: build/... -> freenas/_BE/objs
    _root=$(cd "$(dirname "$0")/.." && pwd)
    REPO="${_root}/freenas/_BE/objs/pkgbase-repo"
fi

[ -d "${REPO}" ] || { echo "no repository: ${REPO}" >&2; exit 1; }

# Inside the repository the directory is named after the ABI (FreeBSD:15:amd64),
# and inside it are the builds with a latest symlink pointing at the current one.
ABI_DIR=$(find "${REPO}" -maxdepth 1 -mindepth 1 -type d | head -1)
[ -n "${ABI_DIR}" ] || { echo "no ABI directory in ${REPO}" >&2; exit 1; }
ABI=$(basename "${ABI_DIR}")

LATEST="${ABI_DIR}/latest"
[ -e "${LATEST}" ] || { echo "no ${LATEST}: the pkgbase build did not finish" >&2; exit 1; }

# Resolved once, to the physical directory, and everything below -- the check
# of the catalogue, its signature, the copy -- uses that path. Following
# `latest` again later would publish whatever a build that finished in the
# meantime pointed it at, which nobody verified.
SRC=$(cd -P "${LATEST}" && pwd -P) || { echo "cannot resolve ${LATEST}" >&2; exit 1; }
BUILD=$(basename "${SRC}")

# The catalogue that is checked is the catalogue that is sent. It is copied
# out of the build into a private directory first; that copy is what
# verify-pkg-repo.sh checks and what goes to the server, so nothing that
# happens to the build directory meanwhile -- `pkg repo` run there again
# without a key, say -- changes what is published. The packages are still
# sent from the build directory: the catalogue pins each of them by its
# checksum, and a client refuses a package that does not match.
CAT=$(mktemp -d "${TMPDIR:-/tmp}/publish-catalogue.XXXXXX")
trap 'rm -rf "${CAT}"' EXIT
for f in "${SRC}"/meta "${SRC}"/meta.* "${SRC}"/packagesite.* "${SRC}"/data.* "${SRC}"/filesite.*; do
    [ -f "${f}" ] || continue
    cp -pL "${f}" "${CAT}/"
done

# The catalogue is what a client uses to learn what the repository holds.
# Without it there is nothing to publish.
for f in meta.conf packagesite.pkg; do
    [ -f "${CAT}/${f}" ] || { echo "the build has no ${f}: the repository is incomplete" >&2; exit 1; }
done

# The catalogue has to be signed, and the signature has to check out: clients
# refuse anything else. See tools/verify-pkg-repo.sh.
"$(dirname "$0")/verify-pkg-repo.sh" "${CAT}"

COUNT=$(find "${SRC}" -name '*.pkg' | wc -l | tr -d ' ')
SIZE=$(du -sh "${SRC}" | awk '{print $1}')
echo "publishing ${ABI}/${BUILD}: ${COUNT} packages, ${SIZE} -> ${TARGET}:${REMOTE}"

ssh "${TARGET}" "mkdir -p '${REMOTE}/${ABI}'"

# Packages first, catalogue second: a client arriving mid-copy sees the old
# catalogue and the old packages, that is, a consistent picture.
rsync -a --info=progress2 \
    --exclude 'meta' --exclude 'meta.*' \
    --exclude 'packagesite.*' --exclude 'data.*' --exclude 'filesite.*' \
    "${SRC}/" "${TARGET}:${REMOTE}/${ABI}/${BUILD}/"

# The files, not the directory: rsync of "${CAT}/" would also give the
# published build directory the private permissions of the copy.
rsync -a "${CAT}"/* "${TARGET}:${REMOTE}/${ABI}/${BUILD}/"

# Switch latest once everything is in place. Replacing a symlink that points
# at a directory needs the "do not follow the target" flag, and the two systems
# spell it differently: -T on GNU coreutils, -h on FreeBSD. Without it mv
# follows the old symlink and moves the new one INTO the published build,
# leaving latest/latest.new behind and latest still pointing at the old one.
# The flag is tried both ways before falling back to a plain replace, so this
# works whichever system the update server runs.
ssh "${TARGET}" "cd '${REMOTE}/${ABI}' && ln -sfn '${BUILD}' latest.new && \
    { mv -Tf latest.new latest 2>/dev/null \
      || mv -hf latest.new latest 2>/dev/null \
      || { rm -f latest && mv latest.new latest; }; }"

echo "published: ${REMOTE}/${ABI}/${BUILD}, latest switched"
echo
echo "on the client:"
echo "  /usr/local/etc/pkg/repos/bsdnas-base.conf"
echo "  bsdnas-base: { url: \"https://<server>/pkgbase/${ABI}/latest\", enabled: yes,"
echo "    signature_type: \"fingerprints\", fingerprints: \"/usr/local/share/keys/bsdnas-pkg\" }"
