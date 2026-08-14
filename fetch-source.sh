#!/usr/bin/env bash
# Fetch the pinned Thunderbird source for Quick Mail.
#
#   fetch-source.sh [workdir]     default ../../mail
#
# One artifact, not two repos: the release source tarball bundles
# mozilla-central AND comm-central at the release-matched revisions, so there
# is no version-skew failure mode like Quick Browser's fetch-vs-ungoogled trap.
# Verified against the SHA256SUMS published beside the tarball.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${1:-$HERE/../../mail}"
mkdir -p "$WORK"; WORK="$(cd "$WORK" && pwd)"

VER="$(awk -F= '/^thunderbird_version=/{print $2}' "$HERE/pin.txt" | tr -d ' \r')"
URL="$(awk -F= '/^source_url=/{print $2}' "$HERE/pin.txt" | tr -d ' \r')"
[ -n "$VER" ] && [ -n "$URL" ] || { echo "pin.txt incomplete"; exit 1; }
TAR="$WORK/thunderbird-$VER.source.tar.xz"
SRC="$WORK/thunderbird-${VER%esr}"   # the tarball top dir drops the esr suffix

echo "== Quick Mail source: $VER"
if [ ! -s "$TAR" ]; then
  echo "== downloading $(basename "$TAR")"
  curl -fL --retry 3 -o "$TAR.part" "$URL"
  mv "$TAR.part" "$TAR"
fi

echo "== verifying against upstream SHA256SUMS"
SUMS_URL="${URL%/source/*}/SHA256SUMS"   # sums sit at the RELEASE root, not under source/
curl -fsSL --retry 3 -o "$WORK/SHA256SUMS" "$SUMS_URL"
WANT="$(grep "source/$(basename "$TAR")\$" "$WORK/SHA256SUMS" | awk '{print $1}' | head -1)"
[ -n "$WANT" ] || { echo "tarball not in SHA256SUMS"; exit 1; }
GOT="$(sha256sum "$TAR" | awk '{print $1}')"
[ "$WANT" = "$GOT" ] || { echo "SHA256 MISMATCH: want $WANT got $GOT"; exit 1; }
echo "   sha256 ok"

if [ ! -d "$SRC" ]; then
  echo "== extracting (~5 GB)"
  tar -xJf "$TAR" -C "$WORK"
fi
[ -d "$SRC/comm" ] || { echo "comm/ missing — not a Thunderbird source tarball?"; exit 1; }
echo "== source ready: $SRC"
