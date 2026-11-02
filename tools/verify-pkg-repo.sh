#!/bin/sh
#
# Check that a pkg repository catalogue is signed, before it is published.
#
# Installed systems read the catalogue with `signature_type: fingerprints` and
# refuse one nobody signed, so publishing it unsigned would only stop their
# updates. tools/publish-pkgbase.sh and tools/publish-ports.sh run this first
# and publish nothing if it fails; there is deliberately no switch to publish
# without a signature.
#
# Usage:
#   verify-pkg-repo.sh <repo-dir>
#
#   repo-dir   the directory holding meta.conf and packagesite.pkg
#
# What a signed catalogue looks like, as pkg-repo(8) writes it with a signing
# command (tools/pkg-repo-sign.sh): each archive of the catalogue holds its
# file and, beside it, <file>.sig and <file>.pub -- data, data.sig, data.pub
# in data.pkg; packagesite.yaml and its two in packagesite.pkg. The signature
# is over the SHA256 of the file, written out in hex.
#
# Their presence alone proves nothing. When the signing command fails, pkg
# repo still exits 0 and still writes both files -- empty. So every signature
# is checked here against the public key beside it, the way pkg checks it.
# Whether that key is one the clients trust is for the clients to decide; the
# SHA256 printed at the end is what their trusted/ directory has to list.

set -eu

DIR="${1:-}"
[ -n "${DIR}" ] || { sed -n '3,26p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
[ -f "${DIR}/packagesite.pkg" ] || { echo "no catalogue in ${DIR}" >&2; exit 1; }

fail() {
    echo "$*" >&2
    echo "refusing to publish a catalogue without a valid signature. Build with" >&2
    echo "BSDNAS_PKG_SIGNING_KEY set, or sign it with" >&2
    echo "  pkg repo <dir> signing_command: tools/pkg-repo-sign.sh <key>" >&2
    exit 1
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/verify-pkg-repo.XXXXXX")
trap 'rm -rf "${WORK}"' EXIT

KEYS=""
for archive in packagesite.pkg data.pkg filesite.pkg; do
    [ -f "${DIR}/${archive}" ] || continue
    rm -rf "${WORK:?}/x"
    mkdir "${WORK}/x"
    tar -xf "${DIR}/${archive}" -C "${WORK}/x" || fail "cannot unpack ${archive}"

    found=0
    for f in "${WORK}/x"/*; do
        case "${f}" in
        *.sig|*.pub) continue ;;
        "${WORK}/x/*") break ;;
        esac
        name="${archive}: $(basename "${f}")"
        [ -s "${f}.sig" ] && [ -s "${f}.pub" ] || fail "${name} is not signed"
        sum=$(openssl dgst -sha256 -r "${f}" | cut -d' ' -f1)
        printf '%s' "${sum}" | openssl dgst -sha256 -verify "${f}.pub" -signature "${f}.sig" \
            >/dev/null 2>&1 || fail "${name}: the signature does not verify"
        KEYS="${KEYS}$(openssl dgst -sha256 -r "${f}.pub" | cut -d' ' -f1)
"
        found=1
    done
    [ "${found}" = 1 ] || fail "${archive} holds nothing to check"
done

echo "catalogue signed, key sha256: $(printf '%s' "${KEYS}" | sort -u | tr '\n' ' ')"
