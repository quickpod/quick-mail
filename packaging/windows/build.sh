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

# BRANDED thunderbird.exe (field defect: the taskbar shows the window icon,
# which comes from the exe's OWN icon group). Mozilla's Authenticode signature
# is stripped first (a resource rewrite invalidates it anyway and leaves a
# stale cert directory), icon-patch.ps1 rebuilds icon group 32512 from our
# .ico ON A REAL WINDOWS BOX, and the result is EV-signed on the sansan token.
# Tradeoff recorded in windows-pin.txt. Every OTHER payload binary keeps
# Mozilla's signature. This build refuses to pack an unbranded thunderbird.exe.
OVERRIDE="$ROOT/winbuild/overrides/quick-mail/thunderbird.exe"
[ -f "$OVERRIDE" ] || { echo "!! missing branded+signed thunderbird.exe at $OVERRIDE" >&2
  echo "!! prepare it with packaging/windows/icon-patch.ps1, then EV-sign it:" >&2
  echo "!!   publish/scripts/sign-windows-artifact.sh $OVERRIDE" >&2; exit 1; }

# GATE: the payload must be EV-signed, not merely present. This one matters
# more than the browser's — here we STRIP Mozilla's signature to rewrite the
# icon group, so a payload that is not re-signed with a trusted certificate is
# strictly worse than what upstream shipped. Until 2026-08-21 it carried the
# QuickOpen Root CA, which Windows does not trust: the trade recorded in
# windows-pin.txt ("a signature for a signature") did not actually hold.
#
# CAPTURE, THEN GREP: `osslsigncode verify` exits non-zero on this box even for
# a good EV signature (it cannot chain the Sectigo timestamp), so a
# `... | grep -q` pipeline under `set -o pipefail` is always false and would
# reject every correctly-signed payload. -CAfile is required to name the signer.
SYSCA="${QUICKOPEN_SYSCA:-/etc/ssl/certs/ca-certificates.crt}"
EVOUT="$(osslsigncode verify -in "$OVERRIDE" -CAfile "$SYSCA" 2>&1 || true)"
printf '%s' "$EVOUT" | grep -qi "CN=Dosvak LLC" || {
  echo "!! thunderbird.exe override is NOT EV-signed — refusing to build" >&2
  echo "!!   publish/scripts/sign-windows-artifact.sh $OVERRIDE" >&2; exit 1; }

cp "$OVERRIDE" "$PAYLOAD/thunderbird.exe"
echo "   branded thunderbird.exe: $(sha256sum "$PAYLOAD/thunderbird.exe" | cut -c1-16)... (EV: CN=Dosvak LLC)"

# WinShell NSIS plug-in (shortcut AUMID), pinned in windows-pin.txt
WINSHELL="$ROOT/winbuild/tools/WinShell/Plugins/x86-unicode"
if [ ! -f "$WINSHELL/WinShell.dll" ]; then
  mkdir -p "$ROOT/winbuild/tools" && cd "$ROOT/winbuild/tools"
  curl -sL -o WinShell.zip "$(pin winshell_url)"
  echo "$(pin winshell_sha256)  WinShell.zip" | sha256sum -c - >/dev/null || { echo "!! WinShell.zip sha mismatch" >&2; exit 1; }
  unzip -o -q WinShell.zip -d WinShell
  cd - >/dev/null
fi

EST_KB="$(du -sk "$PAYLOAD" | cut -f1)"
LICENSEFILE="$REPO/licenses/MPL-2.0.txt"
makensis -V2 \
  -DPAYLOAD="$PAYLOAD" \
  -DVERSION="$NUMVER.0" \
  -DDISPLAYVERSION="$DISPLAYVER" \
  -DESTSIZE_KB="$EST_KB" \
  -DICOFILE="$ICO" \
  -DPLUGINDIR="$WINSHELL" \
  -DLICENSEFILE="$LICENSEFILE" \
  -DOUTFILE="$OUT/QuickMail-Setup.exe" \
  "$HERE/installer.nsi"

echo "   $(du -h "$OUT/QuickMail-Setup.exe" | cut -f1)  $OUT/QuickMail-Setup.exe"
