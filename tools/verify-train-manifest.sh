#!/usr/bin/env sh
#
# Fetch a train manifest and verify its signature.
#
# This is what a client does before trusting anything an update server says.
# It is deliberately small and free of the middleware: if it cannot verify, it
# exits non-zero and prints why, and nothing downstream should proceed.
#
# Usage:
#   tools/verify-train-manifest.sh <base-url> [public-key.asc]
#
# Example:
#   tools/verify-train-manifest.sh https://updates.bsdnas.com/BSDnas/BSDnas-15-MASTER
#
# The public key ships with the product as
# /usr/local/share/licenses/BSDnas/BSDnas-signing-key.asc and is published on
# the project site; pass another path to check against a different key.

set -eu

BASE="${1:?usage: verify-train-manifest.sh <base-url> [public-key.asc]}"
KEY="${2:-/usr/local/share/licenses/BSDnas/BSDnas-signing-key.asc}"
BASE="${BASE%/}"

[ -f "$KEY" ] || { echo "public key not found: $KEY" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "==> fetching $BASE/manifest.json"
fetch_to() {
    if command -v fetch >/dev/null 2>&1; then
        fetch -q -o "$2" "$1"
    else
        curl -fsS -o "$2" "$1"
    fi
}
fetch_to "$BASE/manifest.json" "$tmp/manifest.json"
fetch_to "$BASE/manifest.json.asc" "$tmp/manifest.json.asc"

# A throwaway keyring: we check against the key we shipped, not against
# whatever happens to sit in the caller's keyring.
export GNUPGHOME="$tmp/gnupg"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"
gpg --batch --quiet --import "$KEY"

echo "==> verifying signature"
if ! gpg --batch --quiet --verify "$tmp/manifest.json.asc" "$tmp/manifest.json" 2>"$tmp/err"; then
    echo "SIGNATURE CHECK FAILED — refusing to trust this manifest" >&2
    cat "$tmp/err" >&2
    exit 2
fi

echo "==> signature is good"
sed -n 's/^  "\(train\|version\|released\)": "\(.*\)",\?$/    \1: \2/p' "$tmp/manifest.json"
echo "==> artifacts"
sed -n 's/.*"name": "\([^"]*\)".*"sha256": "\([^"]*\)".*/    \1  \2/p' "$tmp/manifest.json"
