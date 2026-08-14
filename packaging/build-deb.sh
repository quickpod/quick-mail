#!/usr/bin/env bash
# build-deb.sh — package the built Quick Mail as quickopen-quick-mail.
#
#   packaging/build-deb.sh [outdir] [distdir]
#
#   outdir   default <repo>/dist
#   distdir  default <src>/obj-quickmail/dist   (run build.sh first)
#
# SHAPE
#   quickopen-quick-mail  Architecture: amd64
#     /opt/quick-mail/...                     the built application
#     /usr/bin/quick-mail                     launcher wrapper
#     /usr/share/applications/quick-mail.desktop
#     /usr/share/icons/hicolor/<size>/apps/quick-mail.png
#                                    (+ the themed quickopen-quick-mail alias
#                                       and a scalable SVG for both names)
#     /usr/share/doc/quickopen-quick-mail/{NOTICE,LICENSING.md,licenses/}
#
# Depends are computed with dpkg-shlibdeps against the real binary, never
# hand-written: noble renamed a swathe of runtime deps for the 64-bit time_t
# transition, and a hand list rots into a package that either will not install
# or installs and then will not start.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
OUT="${1:-$REPO/dist}"

VER="$(awk -F= '/^thunderbird_version=/{print $2}' "$REPO/pin.txt" | tr -d ' \r')"
[ -n "$VER" ] || { echo "no thunderbird_version in pin.txt" >&2; exit 1; }
SRC="$REPO/../../mail/thunderbird-${VER%esr}"
DIST="${2:-$SRC/obj-quickmail/dist}"
# The upstream release IS the product version — a mail client's version number
# is a security claim, so it must name the release its fixes came from. REV
# distinguishes a repackage of the same source.
REV="${QUICK_MAIL_DEB_REV:-1}"
DEB_VERSION="${VER}-${REV}"
PKG="quickopen-quick-mail"

command -v dpkg-deb >/dev/null || { echo "dpkg-deb missing (apt install dpkg-dev)" >&2; exit 1; }
# `mach package` output (dist/quickmail) is the canonical shippable tree:
# stripped, omni.ja built, dev-only binaries dropped — 276 MB. dist/bin is the
# raw build tree: 2.7 GB, unstripped libxul, no omni.ja at all, and carrying
# xpcshell/certutil/ssltunnel that must never reach a user. Prefer the packaged
# tree; fall back to dist/bin only if `mach package` was not run.
APPDIR="$DIST/quickmail"
[ -x "$APPDIR/quickmail" ] && PKGSRC="mach package tree" || {
  APPDIR="$DIST/bin"; PKGSRC="raw build tree (run ./mach package for a smaller deb)"; }
[ -x "$APPDIR/quickmail" ] || {
  echo "no built app at $DIST/{quickmail,bin}/quickmail — run ./build.sh first" >&2; exit 1; }

echo "== $PKG $DEB_VERSION"
echo "   from $APPDIR ($PKGSRC)"

STAGE="$OUT/stage"
rm -rf "$STAGE"
OPT="$STAGE/opt/quick-mail"
mkdir -p "$OPT" "$STAGE/DEBIAN" "$STAGE/usr/bin" \
         "$STAGE/usr/share/applications" \
         "$STAGE/usr/share/doc/$PKG" \
         "$STAGE/usr/share/icons/hicolor/scalable/apps"

# ---------------------------------------------------------------- the payload
# The packaged tree is the runnable application (binary, omni.ja, libxul, the
# gtk/wayland glue). Copy it wholesale rather than allow-listing: an allow-list
# would silently drop a component on the next ESR. Note omni.ja exists ONLY
# after `mach package` — in dist/bin the chrome is still unpacked, which is why
# that fallback path yields a far bigger, non-canonical package.
cp -a "$APPDIR/." "$OPT/"
# strip the staged binaries, never the ones in the build tree
if command -v strip >/dev/null; then
  find "$OPT" -maxdepth 1 -type f \( -name 'quickmail' -o -name '*.so' \) \
    -exec strip --strip-unneeded {} + 2>/dev/null || true
fi
# build leftovers that are not part of a shipped app
rm -rf "$OPT/gtest" "$OPT/tests" "$OPT"/*.chk

# ---------------------------------------------------------------- the wrapper
cat > "$STAGE/usr/bin/quick-mail" <<'WRAP'
#!/bin/sh
# Quick Mail launcher
exec /opt/quick-mail/quickmail "$@"
WRAP
chmod 0755 "$STAGE/usr/bin/quick-mail"

# ------------------------------------------------------- desktop entry + icons
install -m 0644 "$REPO/applications/quick-mail.desktop" \
        "$STAGE/usr/share/applications/quick-mail.desktop"

# The full hicolor ladder, under BOTH names. The desktop entry uses the themed
# quickopen-* name; the OS build used to sed that in after install, so a package
# upgrade silently reverted it — ship the alias here instead.
for size in 16 24 32 48 64 128 256; do
  d="$STAGE/usr/share/icons/hicolor/${size}x${size}/apps"
  mkdir -p "$d"
  python3 - "$REPO/quick-mail.png" "$d" "$size" <<'PY'
import sys
from PIL import Image
src, d, size = sys.argv[1], sys.argv[2], int(sys.argv[3])
im = Image.open(src).convert("RGBA").resize((size, size), Image.LANCZOS)
for n in ("quick-mail", "quickopen-quick-mail"):
    im.save(f"{d}/{n}.png")
PY
done
# A scalable SVG is mandatory: with only Fixed-size raster dirs the icon is
# unresolvable at any size the theme does not declare — every custom panel
# height and HiDPI scale (field defect H). Quick Mail was the last app with no
# SVG anywhere, which is why it was still a lightning bolt.
for n in quick-mail quickopen-quick-mail; do
  install -m 0644 "$REPO/quick-mail.svg" \
    "$STAGE/usr/share/icons/hicolor/scalable/apps/$n.svg"
done

# ---------------------------------------------------------------- the licences
# Installed TWICE, deliberately. AIQuick OS ships path-exclude=/usr/share/doc/*
# in /etc/dpkg/dpkg.cfg.d, which strips all of /usr/share/doc at unpack time. A
# licence file the target OS deletes on install is not shipped — so the
# authoritative copy lives beside the binary in /opt, which no path-exclude
# touches, and the /usr/share/doc copy stays for Debian convention elsewhere.
# MPL-2.0 obliges us to carry these; do not drop them.
for f in NOTICE LICENSING.md; do
  install -m 0644 "$REPO/$f" "$STAGE/usr/share/doc/$PKG/$f"
  install -m 0644 "$REPO/$f" "$OPT/$f"
done
cp -a "$REPO/licenses" "$STAGE/usr/share/doc/$PKG/licenses"
cp -a "$REPO/licenses" "$OPT/licenses"

# ---------------------------------------------------------------- the control
echo "   computing Depends with dpkg-shlibdeps"
SHLIBDEPS=""
if command -v dpkg-shlibdeps >/dev/null; then
  TMPD="$(mktemp -d)"
  mkdir -p "$TMPD/debian"
  printf 'Source: %s\nPackage: %s\nArchitecture: amd64\n' "$PKG" "$PKG" \
    > "$TMPD/debian/control"
  : > "$TMPD/debian/substvars"
  # EVERY shipped object gets analyzed, not just the launcher. `quickmail` is a
  # ~570 KB stub that dlopens libxul via dependentlibs.list, so on its own it
  # yields "libc6, libgcc-s1, libstdc++6" — a package that installs on stock
  # noble and then will not start. GTK, NSS, pango and the X libraries are all
  # reached through libxul.so.
  #
  # -l points at the staged app dir so the bundled libs resolve each other
  # (libsoftokn3 -> libmozsqlite3); without it dpkg-shlibdeps errors out
  # entirely and SHLIBDEPS silently ends up short.
  #
  # This needs the RUNTIME libraries installed on the packaging host: the build
  # links against the sysroot in .mozbuild, so a headless box can BUILD Quick
  # Mail and still be unable to resolve libgtk-3.so.0 to a package. If Depends
  # comes back suspiciously thin, that is the cause — install libgtk-3-0t64.
  ( cd "$TMPD" && dpkg-shlibdeps -O --ignore-missing-info -l"$OPT" \
      "$OPT/quickmail" "$OPT"/*.so 2>/dev/null ) > "$TMPD/out" || true
  SHLIBDEPS="$(sed -n 's/^shlibs:Depends=//p' "$TMPD/out" | head -1)"
  rm -rf "$TMPD"
fi
# A non-empty answer is not a correct answer. The failure that actually happened
# was a SHORT list, not an empty one, and short sails straight past an empty
# check into a package that installs and then will not start. A mail client that
# cannot resolve GTK is not shippable, so treat a toolkit-less result as no
# result at all.
case "$SHLIBDEPS" in
  *libgtk-3-0*) : ;;
  *) [ -z "$SHLIBDEPS" ] || echo "   !! Depends has no GTK — packaging host is missing runtime libs"
     SHLIBDEPS="" ;;
esac
if [ -z "$SHLIBDEPS" ]; then
  echo "   !! dpkg-shlibdeps produced nothing usable — falling back to a static list"
  echo "      (verify with: dpkg -I <deb> and a test install on stock noble)"
  SHLIBDEPS="libc6, libstdc++6, libgcc-s1, libglib2.0-0t64, libnss3, libnspr4, libdbus-1-3, libgtk-3-0t64, libx11-6, libxext6, libxdamage1, libxfixes3, libxcomposite1, libxrandr2, libpango-1.0-0, libcairo2, libfreetype6, libfontconfig1, libasound2t64"
fi

INSTALLED_SIZE=$(du -sk "$STAGE" | cut -f1)
TAGLINE="$(python3 -c "import json;print(json.load(open('$REPO/.quickopen.json'))['tagline'])")"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PKG
Version: $DEB_VERSION
Section: mail
Priority: optional
Architecture: amd64
Maintainer: QuickOpen <help@quickpod.io>
Depends: $SHLIBDEPS
Installed-Size: $INSTALLED_SIZE
Description: Quick Mail — mail, calendar and contacts
 $TAGLINE
 .
 Built from the Thunderbird open-source project (MPL-2.0). Not Thunderbird,
 and neither produced nor endorsed by Mozilla or MZLA Technologies.
EOF

mkdir -p "$OUT"
DEB="$OUT/${PKG}_${DEB_VERSION}_amd64.deb"
fakeroot dpkg-deb --build "$STAGE" "$DEB" >/dev/null 2>&1 \
  || dpkg-deb --build --root-owner-group "$STAGE" "$DEB" >/dev/null
rm -rf "$STAGE"
echo "   built $(basename "$DEB") ($(du -h "$DEB" | cut -f1))"

echo
echo "Next:"
echo "  packaging/verify-wmclass.sh $DEB    # PROVE StartupWMClass matches the window"
