#!/usr/bin/env sh
#
# Build and sign a train manifest.
#
# The update server hands out files over plain HTTPS. TLS proves you talked to
# the right host; it says nothing about what the host was given to serve. A
# signed manifest moves the trust onto our key, which lives nowhere near the
# server: whoever gets write access to the server still cannot forge an update.
#
# The manifest describes one state of one train: which version it is, when it
# was released, and the artifacts belonging to it with their SHA-256 sums. A
# client fetches manifest.json plus manifest.json.asc, checks the signature
# against the bundled public key, and only then trusts anything it lists.
#
# Usage:
#   tools/make-train-manifest.sh <release-dir> <train> [output-dir]
#
# The passphrase is passed by environment only: BSDNAS_PASSFILE points at a
# file holding it. Where the key and that file live is not documented here.
#
# The addresses of the package repositories come from the environment too:
#   BSDNAS_PKGBASE_URL   base as pkg packages
#   BSDNAS_PORTS_URL     our own software
# Both are optional; whichever is given goes into the signed manifest, which
# is how a client learns where to fetch an update from.

set -eu

KEYID="${BSDNAS_SIGNKEY:-1E2F7A792066322D}"
PASSFILE="${BSDNAS_PASSFILE:?set BSDNAS_PASSFILE (file holding the passphrase)}"
DIR="${1:?usage: make-train-manifest.sh <release-dir> <train> [output-dir]}"
TRAIN="${2:?usage: make-train-manifest.sh <release-dir> <train> [output-dir]}"
OUT="${3:-$DIR}"

[ -d "$DIR" ] || { echo "no such directory: $DIR" >&2; exit 1; }
[ -f "$PASSFILE" ] || { echo "passphrase file not found: $PASSFILE" >&2; exit 1; }
mkdir -p "$OUT"

# The version is the release directory name: that is how the build names it.
VERSION="${BSDNAS_VERSION:-$(basename "$DIR")}"
RELEASED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Package repositories belonging to this train. The updater takes base from
# the first and our own software from the second, so the addresses have to
# arrive the same way the checksums do: inside the signed manifest. Nothing
# here is a default — an address is part of an installation, not of the
# source tree, and a manifest without them simply carries none.
PKGBASE_URL="${BSDNAS_PKGBASE_URL:-}"
PORTS_URL="${BSDNAS_PORTS_URL:-}"

echo "==> collecting artifacts from $DIR"
artifacts=""
for f in "$DIR"/*.iso "$DIR"/*.txz "$DIR"/*.img; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    size="$(stat -c %s "$f" 2>/dev/null || stat -f %z "$f")"
    sum="$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1 || sha256 -q "$f")"
    echo "    $name  $size bytes"
    artifacts="${artifacts}${artifacts:+,}
    {\"name\": \"$name\", \"size\": $size, \"sha256\": \"$sum\"}"
done
[ -n "$artifacts" ] || { echo "no artifacts found in $DIR" >&2; exit 1; }

repos=""
add_repo() {
    # $1 name, $2 url
    [ -n "$2" ] || return 0
    echo "    repo $1: $2"
    repos="${repos}${repos:+,}
    \"$1\": {\"url\": \"$2\"}"
}
echo "==> repositories"
add_repo base "$PKGBASE_URL"
add_repo ports "$PORTS_URL"
[ -n "$repos" ] || echo "    none given (BSDNAS_PKGBASE_URL, BSDNAS_PORTS_URL)"

cat > "$OUT/manifest.json" <<JSON
{
  "format": 1,
  "train": "$TRAIN",
  "version": "$VERSION",
  "released": "$RELEASED",
  "artifacts": [$artifacts
  ],
  "repos": {$repos
  }
}
JSON

echo "==> signing"
rm -f "$OUT/manifest.json.asc"
gpg --batch --yes --pinentry-mode loopback --passphrase-file "$PASSFILE" \
    --local-user "$KEYID" --armor --detach-sign "$OUT/manifest.json"

echo "==> verifying the way a client will"
gpg --verify "$OUT/manifest.json.asc" "$OUT/manifest.json"

echo "==> done: $OUT/manifest.json (+ .asc)"
