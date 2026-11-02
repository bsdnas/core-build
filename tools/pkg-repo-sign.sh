#!/bin/sh
#
# Sign a pkg repository catalogue: the signing command of pkg-repo(8).
#
# `pkg repo <dir> signing_command: <command>` runs the command once per
# catalogue file, writes the SHA256 of that file to its standard input and
# expects back, on standard output,
#
#   SIGNATURE
#   <signature bytes>
#   CERT
#   <public key, PEM>
#   END
#
# This is that command, the one from the EXAMPLES section of pkg-repo(8). The
# public key travels in the catalogue next to the signature, and a client
# configured with `signature_type: fingerprints` accepts it only if the SHA256
# of that public key is listed in its `trusted/` directory and not in
# `revoked/`. That is what lets the key be replaced later: a new fingerprint is
# shipped in an image first, the old one moved to revoked/ after.
#
# The key is never named in this repository. The operator gives its path:
#
# Usage:
#   pkg-repo-sign.sh [key]
#
#   key   RSA private key, PEM  (default: $BSDNAS_PKG_SIGNING_KEY)
#
# pkg runs it, not a person. The build hands it to pkg when
# BSDNAS_PKG_SIGNING_KEY is set: build/tools/build-os.py for the base packages
# (through PKG_REPO_SIGNING_KEY of FreeBSD's Makefile.inc1),
# build/tools/build-ports.py for poudriere (through SIGNING_COMMAND in
# poudriere.conf). To sign an already built repository:
#
#   pkg repo <dir> signing_command: tools/pkg-repo-sign.sh /path/to/repo.key
#
# The public key is derived from the private one rather than read from a file
# of its own, so the certificate in the catalogue can never belong to a
# different key than the signature beside it.

set -eu

KEY="${1:-${BSDNAS_PKG_SIGNING_KEY:-}}"

[ -n "${KEY}" ] || { echo "pkg-repo-sign: no key: pass it or set BSDNAS_PKG_SIGNING_KEY" >&2; exit 1; }
[ -r "${KEY}" ] || { echo "pkg-repo-sign: cannot read ${KEY}" >&2; exit 1; }

# pkg writes the checksum and closes the pipe; an empty read means the caller
# is not pkg, and signing nothing must not look like success.
read -r sum || :
[ -n "${sum:-}" ] || { echo "pkg-repo-sign: no checksum on standard input" >&2; exit 1; }

# Both commands run before anything is printed: if either fails, pkg gets no
# half-written answer, only a non-zero exit, and the repository stays unsigned
# instead of carrying a broken signature.
sig=$(mktemp "${TMPDIR:-/tmp}/pkg-repo-sign.XXXXXX")
trap 'rm -f "${sig}"' EXIT
printf '%s' "${sum}" | openssl dgst -sign "${KEY}" -sha256 -binary > "${sig}"
pub=$(openssl rsa -in "${KEY}" -pubout 2>/dev/null)

echo SIGNATURE
cat "${sig}"
echo
echo CERT
printf '%s\n' "${pub}"
echo END
