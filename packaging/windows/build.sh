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
SYSCA="${QUICKOPEN_SYSCA:-/etc/ssl/certs/ca-certificates.crt}"  # public roots, to READ the EV signer

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

# SIGNED PAYLOAD BINARIES. thunderbird.exe is MODIFIED — the taskbar shows the
# window icon, which comes from the exe's OWN icon group, so icon-patch.ps1
# rebuilds group 32512 from our .ico on a real Windows box. That invalidates
# Mozilla's Authenticode signature, which is stripped first; the result is
# EV-signed on the sansan token, so one trusted signature replaces another.
# (Before 2026-08-21 the replacement was the QuickOpen Root CA, which no
# Windows machine trusts — the trade windows-pin.txt claimed did not hold.)
#
# Every OTHER exe in this payload keeps Mozilla's own signature: none of them
# ships unsigned, so there is nothing here for us to improve and stripping a
# vendor signature to substitute ours would be a downgrade.
#
# apply-overrides.sh applies the tree and then GATES: if any exe in the payload
# is unsigned, the build fails rather than shipping it.
"$ROOT/publish/scripts/apply-overrides.sh" "$PAYLOAD" "$ROOT/winbuild/overrides/quick-mail"

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

# THE SIGNED UNINSTALLER — see installer.nsi's two-pass note. NSIS emits an
# uninstaller only when a built installer RUNS, so it cannot be produced here;
# the generator stub has to execute on Windows. Two modes over ONE argument
# list, so the passes cannot drift in the defines they see:
#
#   QUICKOPEN_UNINST_STUB_ONLY=1   compile the payload-free pass-1 stub, stop
#   (default)                      the real installer, embedding the signed one
NSIARGS=(
  -DPAYLOAD="$PAYLOAD"
  -DVERSION="$NUMVER.0"
  -DDISPLAYVERSION="$DISPLAYVER"
  -DESTSIZE_KB="$EST_KB"
  -DICOFILE="$ICO"
  -DPLUGINDIR="$WINSHELL"
  -DLICENSEFILE="$LICENSEFILE"
)

if [ "${QUICKOPEN_UNINST_STUB_ONLY:-0}" = "1" ]; then
  STUB="$ROOT/winbuild/uninstallers/quick-mail/stub.exe"
  mkdir -p "$(dirname "$STUB")"
  # -DUNINSTALLER must exist even though pass 1 skips the branch that uses it:
  # makensis resolves ${...} at parse time, so an undefined symbol is an error.
  makensis -V2 -DUNINSTALLER_ONLY -DUNINSTALLER=/dev/null \
    "${NSIARGS[@]}" -DOUTFILE="$STUB" "$HERE/installer.nsi"
  echo "   pass-1 stub: $STUB ($(du -h "$STUB" | cut -f1))"
  exit 0
fi

UNINST="$ROOT/winbuild/uninstallers/quick-mail/Uninstall.exe"
[ -f "$UNINST" ] || { echo "!! missing signed uninstaller at $UNINST" >&2
  echo "!! build it: QUICKOPEN_UNINST_STUB_ONLY=1 $0" >&2; exit 1; }
EVOUT="$(osslsigncode verify -in "$UNINST" -CAfile "$SYSCA" 2>&1 || true)"
printf '%s' "$EVOUT" | grep -qi "CN=Dosvak LLC" || {
  echo "!! uninstaller is NOT EV-signed — refusing to build" >&2
  echo "!!   publish/scripts/sign-windows-artifact.sh $UNINST" >&2; exit 1; }
echo "   uninstaller: $(sha256sum "$UNINST" | cut -c1-16)... (EV: CN=Dosvak LLC)"

makensis -V2 "${NSIARGS[@]}" \
  -DUNINSTALLER="$UNINST" \
  -DOUTFILE="$OUT/QuickMail-Setup.exe" \
  "$HERE/installer.nsi"

echo "   $(du -h "$OUT/QuickMail-Setup.exe" | cut -f1)  $OUT/QuickMail-Setup.exe"
