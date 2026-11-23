#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
dest=build/Dependencies
mkdir -p "$dest"
tmp=$(mktemp -d "$dest/.sparkle.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
curl --fail --location --silent --show-error --retry 2 --output "$tmp/Sparkle.tar.xz" https://github.com/sparkle-project/Sparkle/releases/download/2.9.6/Sparkle-2.9.6.tar.xz
echo "52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192  $tmp/Sparkle.tar.xz" | shasum -a 256 -c -
tar -xf "$tmp/Sparkle.tar.xz" -C "$dest" Sparkle.framework bin LICENSE
