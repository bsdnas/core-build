#!/usr/bin/env bash
#
# Signing a released image.
#
# A checksum without a signature protects only against a corrupted download:
# whoever is able to replace the image will replace the checksum file as well.
# A signature moves the trust onto a key kept somewhere other than the images.
#
# Usage:
#   tools/sign-release.sh <image directory>           sign
#   tools/sign-release.sh <directory> --upload <tag>  sign and attach to a release
#
# Key: BSDnas release signing <bsd@22r.tech>, ed25519, fingerprint
#   58528D1CDBDAAF7B01ED2BBE1E2F7A792066322D
#
# The passphrase is passed through the environment only: BSDNAS_PASSFILE points
# at a file holding the phrase. Where the key and that file live is not
# documented.

set -eu

KEYID="${BSDNAS_SIGNKEY:-1E2F7A792066322D}"
PASSFILE="${BSDNAS_PASSFILE:?set BSDNAS_PASSFILE (a file holding the passphrase)}"
DIR="${1:-}"

[ -n "$DIR" ] && [ -d "$DIR" ] || { echo "specify the directory holding the image" >&2; exit 1; }
[ -f "$PASSFILE" ] || { echo "passphrase not found: $PASSFILE" >&2; exit 1; }

cd "$DIR"

iso=$(ls -1 *.iso 2>/dev/null | head -1)
[ -n "$iso" ] || { echo "no .iso in the directory" >&2; exit 1; }

echo "==> computing the checksum: $iso"
sha256sum "$iso" > SHA256SUMS

echo "==> signing"
rm -f SHA256SUMS.asc
gpg --batch --yes --pinentry-mode loopback --passphrase-file "$PASSFILE" \
    --local-user "$KEYID" --armor --detach-sign SHA256SUMS

echo "==> exporting the public key"
gpg --armor --export "$KEYID" > BSDnas-signing-key.asc

echo "==> verifying the signature the same way a user will"
gpg --verify SHA256SUMS.asc SHA256SUMS

if [ "${2:-}" = "--upload" ]; then
    tag="${3:?specify the release tag}"
    echo "==> attaching to release $tag"
    gh release upload "$tag" "$iso" SHA256SUMS SHA256SUMS.asc BSDnas-signing-key.asc \
        --repo bsdnas/core-build --clobber
fi

echo "done: $iso, SHA256SUMS, SHA256SUMS.asc, BSDnas-signing-key.asc"
