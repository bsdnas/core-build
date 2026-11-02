#!/bin/sh
#
# Check a pkg repository catalogue the way an installed system will, before
# it is published.
#
# Installed systems read the catalogue with `signature_type: fingerprints`:
# they accept it only if it is signed and the key it is signed with has its
# SHA256 in their trusted/ directory and not in revoked/. A catalogue that
# fails that would only stop their updates, so tools/publish-pkgbase.sh and
# tools/publish-ports.sh run this first and publish nothing if it fails. There
# is deliberately no switch to publish without it.
#
# Usage:
#   verify-pkg-repo.sh <repo-dir> [fingerprints]
#
#   repo-dir      the directory holding meta.conf and packagesite.pkg
#   fingerprints  the directory with trusted/ and revoked/ that the clients
#                 ship, default $BSDNAS_PKG_FINGERPRINTS, and failing that the
#                 copy in the middleware checkout of this build tree
#                 (freenas/_BE/freenas/src/freenas/usr/local/share/keys/bsdnas-pkg).
#                 None of them there is an error, not a reason to skip.
#
# What a signed catalogue looks like, as pkg 2.7.5 writes it with a signing
# command (tools/pkg-repo-sign.sh): packagesite.pkg holds packagesite.yaml,
# packagesite.yaml.sig and packagesite.yaml.pub; data.pkg holds data, data.sig
# and data.pub; filesite.pkg, when there is one, filesite.yaml and its two.
# The signature is over the SHA256 of the file, written out in hex; the .pub
# is the signing key, and its SHA256 is the fingerprint. meta.conf is not
# signed by pkg at all.
#
# The presence of those files proves nothing. When the signing command fails,
# pkg repo still exits 0 and still writes both -- empty. So each archive has
# to hold exactly its catalogue file and that file's signature and key, every
# signature has to verify against its key, every archive has to be signed by
# the same key, and that key has to be trusted and not revoked.

set -eu

DIR="${1:-}"
[ -n "${DIR}" ] || { sed -n '3,35p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

fail() {
    echo "$*" >&2
    echo "refusing to publish this catalogue." >&2
    exit 1
}

unsigned() {
    echo "$*" >&2
    echo "refusing to publish a catalogue without a valid signature. Build with" >&2
    echo "BSDNAS_PKG_SIGNING_KEY set, or sign it with" >&2
    echo "  pkg repo <dir> signing_command: tools/pkg-repo-sign.sh <key>" >&2
    exit 1
}

[ -f "${DIR}/packagesite.pkg" ] || fail "no catalogue in ${DIR}"

FP="${2:-${BSDNAS_PKG_FINGERPRINTS:-}}"
if [ -z "${FP}" ]; then
    _root=$(cd "$(dirname "$0")/.." && pwd)
    FP="${_root}/freenas/_BE/freenas/src/freenas/usr/local/share/keys/bsdnas-pkg"
fi
[ -d "${FP}/trusted" ] || fail "no trusted/ in ${FP}: give the fingerprints the clients ship, as the second argument or in BSDNAS_PKG_FINGERPRINTS"

# A fingerprint file is pkg's: `function: sha256` and `fingerprint: "<hex>"`.
# One that cannot be read that way is an error, not a file to pass over: a
# revoked key nobody can read here is still revoked on the clients.
fingerprints() {
    # pkg reads every entry of the directory, dot files included.
    for _f in "$1"/* "$1"/.[!.]* "$1"/..?*; do
        [ -e "${_f}" ] || continue
        [ -f "${_f}" ] || fail "not a fingerprint file: ${_f}"
        grep -Eq '^[[:space:]]*function[[:space:]]*[:=][[:space:]]*"?sha256"?[[:space:]]*;?[[:space:]]*$' "${_f}" \
            || fail "not a sha256 fingerprint file: ${_f}"
        _hex=$(sed -n 's/^[[:space:]]*fingerprint[[:space:]]*[:=][[:space:]]*"\{0,1\}\([0-9a-fA-F]\{64\}\)"\{0,1\}[[:space:]]*;\{0,1\}[[:space:]]*$/\1/p' "${_f}")
        [ "$(printf '%s\n' "${_hex}" | grep -c .)" = 1 ] || fail "cannot read the fingerprint in ${_f}"
        printf '%s\n' "${_hex}" | tr 'A-F' 'a-f'
    done
}

TRUSTED=$(fingerprints "${FP}/trusted")
REVOKED=""
if [ -d "${FP}/revoked" ]; then
    REVOKED=$(fingerprints "${FP}/revoked")
fi
[ -n "${TRUSTED}" ] || fail "no fingerprint in ${FP}/trusted"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/verify-pkg-repo.XXXXXX")
trap 'rm -rf "${WORK}"' EXIT

# archive:catalogue file. The first two are what every client reads; the
# third only exists when the repository was made with pkg repo -l.
KEYS=""
for entry in packagesite.pkg:packagesite.yaml data.pkg:data filesite.pkg:filesite.yaml; do
    archive="${entry%%:*}"
    member="${entry#*:}"
    if [ ! -f "${DIR}/${archive}" ]; then
        [ "${archive}" = filesite.pkg ] && continue
        fail "no ${archive} in ${DIR}"
    fi

    # Exactly the catalogue file, its signature and its key: anything else in
    # the archive is something no signature here vouches for.
    _list=$(tar -tf "${DIR}/${archive}") || fail "cannot read ${archive}"
    _want=$(printf '%s\n' "${member}" "${member}.pub" "${member}.sig" | sort)
    if [ "$(printf '%s\n' "${_list}" | sort)" != "${_want}" ]; then
        printf '%s\n' "${_list}" | grep -Fqx "${member}" || fail "${archive} does not hold ${member}"
        printf '%s\n' "${_list}" | grep -Fqx -e "${member}.sig" -e "${member}.pub" \
            || unsigned "${archive}: ${member} is not signed"
        fail "${archive} holds more than ${member} and its signature: $(printf '%s' "${_list}" | tr '\n' ' ')"
    fi

    # And all three plain files. A member that is a symlink unpacks as one,
    # and the checks below would follow it: a link to a correctly signed file
    # kept somewhere else would verify that file, not what the archive holds.
    # Hard links are refused too; the listing marks them " link to ".
    _verbose=$(tar -tvf "${DIR}/${archive}") || fail "cannot read ${archive}"
    if [ "$(printf '%s\n' "${_verbose}" | cut -c1 | sort -u)" != "-" ] \
        || printf '%s\n' "${_verbose}" | grep -Fq ' link to '; then
        fail "${archive} holds members that are not plain files: $(printf '%s' "${_verbose}" | tr '\n' ';')"
    fi

    rm -rf "${WORK:?}/x"
    mkdir "${WORK}/x"
    tar -xf "${DIR}/${archive}" -C "${WORK}/x" || fail "cannot unpack ${archive}"
    f="${WORK}/x/${member}"
    name="${archive}: ${member}"
    for _m in "${f}" "${f}.sig" "${f}.pub"; do
        [ ! -L "${_m}" ] || fail "${archive}: $(basename "${_m}") is a symlink"
    done
    [ -f "${f}" ] && [ -s "${f}.sig" ] && [ -s "${f}.pub" ] || unsigned "${name} is not signed"
    sum=$(openssl dgst -sha256 -r "${f}" | cut -d' ' -f1)
    printf '%s' "${sum}" | openssl dgst -sha256 -verify "${f}.pub" -signature "${f}.sig" \
        >/dev/null 2>&1 || unsigned "${name}: the signature does not verify"
    KEYS="${KEYS}$(openssl dgst -sha256 -r "${f}.pub" | cut -d' ' -f1)
"
done

KEY=$(printf '%s' "${KEYS}" | sort -u)
[ "$(printf '%s\n' "${KEY}" | grep -c .)" = 1 ] || fail "the archives are signed by different keys: $(printf '%s' "${KEY}" | tr '\n' ' ')"

if printf '%s\n' "${REVOKED}" | grep -qx "${KEY}"; then
    fail "the catalogue is signed by a revoked key, sha256 ${KEY} (${FP}/revoked)"
fi
printf '%s\n' "${TRUSTED}" | grep -qx "${KEY}" \
    || fail "the catalogue is signed by a key the clients do not trust, sha256 ${KEY} (not in ${FP}/trusted)"

echo "catalogue signed by a trusted key, sha256 ${KEY}"
