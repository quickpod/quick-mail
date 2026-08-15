#!/usr/bin/env bash
# Build QuickMail-Setup.exe — the Windows installer.
#
#   packaging/windows/build.sh [downloads_dir] [outdir]
#
# v1 policy: the payload is the OFFICIAL Thunderbird ESR win64 en-US release
# pinned in windows-pin.txt (extracted from Mozilla's own installer with 7z),
# shipped byte-identical, plus our distribution/ dir (policies.json +
# distribution.ini) mirroring the Linux build's branding prefs. The from-source
# Windows rebrand is a later phase. Runs on a Linux build host: makensis + 7z +
# ImageMagick only.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
ROOT="$(cd "$REPO/../.." && pwd)"
DL="${1:-$ROOT/winbuild/downloads}"
OUT="${2:-$ROOT/winbuild/dist}"
WORK="$ROOT/winbuild/work/quick-mail"

pin(){ awk -F= -v k="$1" '$1==k{print $2}' "$HERE/windows-pin.txt" | tr -d ' \r'; }
VER="$(pin thunderbird_version)"          # e.g. 140.13.0esr
SHA512="$(pin sha512)"
NUMVER="${VER%esr}"                        # 140.13.0
REV="${QUICK_MAIL_WIN_REV:-1}"
DISPLAYVER="$VER-$REV"
SETUP="$DL/ThunderbirdSetup-$VER.exe"

command -v makensis >/dev/null || { echo "makensis missing (apt install nsis)" >&2; exit 1; }
command -v 7z >/dev/null       || { echo "7z missing (apt install p7zip-full)" >&2; exit 1; }
command -v convert >/dev/null  || { echo "ImageMagick convert missing" >&2; exit 1; }
[ -f "$SETUP" ] || { echo "missing $SETUP — download the pinned upstream installer first" >&2; exit 1; }

echo "== QuickMail-Setup.exe  $DISPLAYVER"
echo "$SHA512  $SETUP" | sha512sum -c - >/dev/null || { echo "!! sha512 mismatch on $SETUP" >&2; exit 1; }
echo "   upstream sha512 ok (Mozilla SHA512SUMS)"

rm -rf "$WORK" && mkdir -p "$WORK" "$OUT"
7z x -y -o"$WORK/unz" "$SETUP" >/dev/null
PAYLOAD="$WORK/unz/core"
[ -f "$PAYLOAD/thunderbird.exe" ] || { echo "no core/thunderbird.exe in upstream installer" >&2; exit 1; }

# our distribution dir: policies + branding prefs (the Windows mirror of
# branding/quickmail/pref/thunderbird-branding.js)
mkdir -p "$PAYLOAD/distribution"
python3 -c "import json;json.load(open('$HERE/distribution/policies.json'))"  # gate: well-formed
cp "$HERE/distribution/policies.json" "$HERE/distribution/distribution.ini" "$PAYLOAD/distribution/"

# our licences + notices ride INSIDE the install dir
mkdir -p "$PAYLOAD/licenses"
cp "$REPO/NOTICE" "$REPO/LICENSING.md" "$PAYLOAD/"
cp "$REPO/LICENSE" "$PAYLOAD/LICENSE-quickopen.txt"
cp "$REPO"/licenses/* "$PAYLOAD/licenses/"

# THICK icon set -> multi-res .ico
ICO="$WORK/quick-mail.ico"
convert "$ROOT/publish/icons/quick-mail.png" -define icon:auto-resize=256,128,64,48,32,16 "$ICO"

EST_KB="$(du -sk "$PAYLOAD" | cut -f1)"
LICENSEFILE="$REPO/licenses/MPL-2.0.txt"
makensis -V2 \
  -DPAYLOAD="$PAYLOAD" \
  -DVERSION="$NUMVER.0" \
  -DDISPLAYVERSION="$DISPLAYVER" \
  -DESTSIZE_KB="$EST_KB" \
  -DICOFILE="$ICO" \
  -DLICENSEFILE="$LICENSEFILE" \
  -DOUTFILE="$OUT/QuickMail-Setup.exe" \
  "$HERE/installer.nsi"

echo "   $(du -h "$OUT/QuickMail-Setup.exe" | cut -f1)  $OUT/QuickMail-Setup.exe"
