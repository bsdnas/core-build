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

cat > "$OUT/manifest.json" <<JSON
{
  "format": 1,
  "train": "$TRAIN",
  "version": "$VERSION",
  "released": "$RELEASED",
  "artifacts": [$artifacts
  ],
  "repos": {}
}
JSON

echo "==> signing"
rm -f "$OUT/manifest.json.asc"
gpg --batch --yes --pinentry-mode loopback --passphrase-file "$PASSFILE" \
    --local-user "$KEYID" --armor --detach-sign "$OUT/manifest.json"

echo "==> verifying the way a client will"
gpg --verify "$OUT/manifest.json.asc" "$OUT/manifest.json"

echo "==> done: $OUT/manifest.json (+ .asc)"
