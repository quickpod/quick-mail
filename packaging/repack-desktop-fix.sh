#!/usr/bin/env bash
# repack-desktop-fix.sh — rebuild a shipped Quick Mail .deb with ONLY the
# desktop entry replaced from this repo's source of truth, and the revision
# bumped.
#
#   packaging/repack-desktop-fix.sh <shipped.deb> [outdir]
#
# ---------------------------------------------------------------------------
# HONESTY NOTE — WHAT 140.13.0esr-6 ACTUALLY IS
#
# esr-6 is a PACKAGING-ONLY REPACK of esr-5. Every binary in it — quickmail,
# libxul.so, omni.ja, the whole /opt/quick-mail tree — is byte-for-byte the
# esr-5 build. Nothing was recompiled. The only difference in the payload is
# /usr/share/applications/quick-mail.desktop, taken from
# applications/quick-mail.desktop in this repo (commit 4f0f15a:
# StartupWMClass=quickmail-default, the Quick OS 0.1.12 field defect), plus
# the Version field in DEBIAN/control.
#
# WHY: the fix is one line in one text file, but `mach package`'s output tree
# (dist/quickmail) had already been cleaned off the build host and a
# from-source engine rebuild is hours of machine time. Fielded 0.1.12 installs
# needed the icon fix over apt without waiting for the 0.1.13 image.
#
# WHAT IS OWED: the next full engine build must regenerate this package from
# source with packaging/build-deb.sh (which reads the same desktop entry, so
# the fix carries) — esr-6 is a stopgap, not a build artifact. Do not treat
# its presence in dist/ as evidence that a build ran.
#
# Installed-Size is deliberately NOT recomputed: the desktop entry grew by
# ~0.7 KB against a 282 MB installed tree, du -sk rounds it away, and leaving
# it untouched keeps the "control differs only in Version" assertion honest
# and mechanically checkable.
# ---------------------------------------------------------------------------
#
# The script REFUSES to produce a deb if anything other than the desktop entry
# and the control Version differs between the input and the output. A repack
# that quietly changed a binary would be far worse than a wrong icon.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
SRC_DESKTOP="$REPO/applications/quick-mail.desktop"
IN="${1:?usage: repack-desktop-fix.sh <shipped.deb> [outdir]}"
OUT="${2:-$REPO/dist}"

[ -f "$IN" ] || { echo "no such deb: $IN" >&2; exit 1; }
[ -f "$SRC_DESKTOP" ] || { echo "no source-of-truth desktop entry at $SRC_DESKTOP" >&2; exit 1; }
command -v dpkg-deb >/dev/null || { echo "dpkg-deb missing (apt install dpkg-dev)" >&2; exit 1; }

# Ownership inside a .deb is root:root. Extracting and rebuilding as a normal
# user silently re-owns every file to the builder, so require root (or
# fakeroot, which lies convincingly enough for dpkg-deb).
if [ "$(id -u)" != 0 ] && ! command -v fakeroot >/dev/null; then
  echo "run as root or install fakeroot — otherwise the repack re-owns the payload" >&2
  exit 1
fi

PKG="$(dpkg-deb -f "$IN" Package)"
OLDVER="$(dpkg-deb -f "$IN" Version)"
# 140.13.0esr-5 -> 140.13.0esr-6.  Override with QUICK_MAIL_DEB_VERSION.
NEWVER="${QUICK_MAIL_DEB_VERSION:-${OLDVER%-*}-$(( ${OLDVER##*-} + 1 ))}"
echo "== $PKG  $OLDVER -> $NEWVER"

DECLARED="$(sed -n 's/^StartupWMClass=//p' "$SRC_DESKTOP" | head -1)"
[ -n "$DECLARED" ] || { echo "source desktop entry declares no StartupWMClass" >&2; exit 1; }
echo "   source of truth: $SRC_DESKTOP (StartupWMClass=$DECLARED)"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# The compression of the rebuilt deb must match the shipped one — a deb whose
# members change format is not "the same package with one file swapped".
# Format parity, not byte parity: the shipped esr-5 was compressed by the build
# host's dpkg (noble, 1.22.x, XXH64-checked zstd frame) and this may run on a
# different dpkg, so the .zst can land a few hundred KB apart for identical
# input. That is why fidelity is proven by per-file sha256 below and never by
# comparing deb sizes.
OLD_MEMBERS="$(ar t "$IN" | tr '\n' ' ')"
case "$OLD_MEMBERS" in
  *data.tar.zst*) ZFLAGS=(-Z zstd) ;;
  *data.tar.xz*)  ZFLAGS=(-Z xz) ;;
  *data.tar.gz*)  ZFLAGS=(-Z gzip) ;;
  *) echo "unrecognised deb members: $OLD_MEMBERS" >&2; exit 1 ;;
esac

# ------------------------------------------------------------------ 1. unpack
echo "== unpacking"
dpkg-deb -R "$IN" "$WORK/stage"

# --------------------------------------------------------- 2. the ONE change
install -m 0644 "$SRC_DESKTOP" "$WORK/stage/usr/share/applications/quick-mail.desktop"
[ "$(id -u)" = 0 ] && chown root:root "$WORK/stage/usr/share/applications/quick-mail.desktop"

# ------------------------------------------------------------- 3. the version
sed -i "s/^Version: .*/Version: $NEWVER/" "$WORK/stage/DEBIAN/control"
[ "$(dpkg-deb -f "$IN" Version)" != "$(sed -n 's/^Version: //p' "$WORK/stage/DEBIAN/control")" ] \
  || { echo "version bump did not take" >&2; exit 1; }

# -------------------------------------------------------------- 4. rebuild
mkdir -p "$OUT"
DEB="$OUT/${PKG}_${NEWVER}_amd64.deb"
echo "== building $(basename "$DEB") (${ZFLAGS[*]})"
if [ "$(id -u)" = 0 ]; then
  dpkg-deb "${ZFLAGS[@]}" --build "$WORK/stage" "$DEB" >/dev/null
else
  fakeroot dpkg-deb "${ZFLAGS[@]}" --build "$WORK/stage" "$DEB" >/dev/null
fi

NEW_MEMBERS="$(ar t "$DEB" | tr '\n' ' ')"
[ "$NEW_MEMBERS" = "$OLD_MEMBERS" ] \
  || { echo "FAIL: member layout changed ($OLD_MEMBERS -> $NEW_MEMBERS)" >&2; rm -f "$DEB"; exit 4; }

# ------------------------------------------------- 5. ASSERT the payload diff
# Nothing but the desktop entry (content) and the control Version may differ.
# Compared on: the full path/mode/owner/size listing, and a sha256 of every
# regular file. Refuse to publish otherwise.
echo "== diffing payloads"
dpkg-deb -R "$DEB" "$WORK/new"

listing() {  # path/mode/owner/size, mtimes stripped (a repack legitimately restamps)
  ( cd "$1" && find . -mindepth 1 \( -path ./DEBIAN -prune -o -true \) -printf '%y %m %u %g %s %p -> %l\n' \
    | grep -v '^d .* ./DEBIAN$' | LC_ALL=C sort )
}
hashes() {
  ( cd "$1" && find . -mindepth 1 -path ./DEBIAN -prune -o -type f -print0 \
    | LC_ALL=C sort -z | xargs -0 sha256sum )
}

listing "$WORK/stage" > "$WORK/l.new"; listing "$WORK/new" > "$WORK/l.chk"
diff -u "$WORK/l.chk" "$WORK/l.new" >/dev/null \
  || { echo "FAIL: rebuilt deb does not round-trip its own stage" >&2; rm -f "$DEB"; exit 5; }

dpkg-deb -R "$IN" "$WORK/old"
listing "$WORK/old" > "$WORK/l.old"
if ! diff -u "$WORK/l.old" "$WORK/l.chk" > "$WORK/d.list"; then
  echo "NOTE: the path/mode/owner/size listing differs — it must differ by" >&2
  echo "      EXACTLY the desktop entry's size and nothing else:" >&2
  sed -n '1,40p' "$WORK/d.list" >&2
  # a size change on the desktop entry alone is expected; anything else is not
  if [ "$(grep -c '^[+-][^+-]' "$WORK/d.list")" != 2 ] \
     || [ "$(grep -c 'quick-mail.desktop' "$WORK/d.list")" != 2 ]; then
    echo "FAIL: something other than the desktop entry changed — REFUSING." >&2
    rm -f "$DEB"; exit 6
  fi
  echo "   (accepted: the only listing change is the desktop entry's size)"
fi

hashes "$WORK/old" > "$WORK/h.old"; hashes "$WORK/new" > "$WORK/h.new"
# `|| true`: diff exits 1 when it finds differences and under `pipefail` that
# failure is the WHOLE pipeline's status, so without this `set -e` kills the
# script at the exact moment the check starts doing its job. Same trap the
# build script hit with `unzip | grep`.
CHANGED="$( { diff "$WORK/h.old" "$WORK/h.new" || true; } | grep '^[<>]' | awk '{print $3}' | LC_ALL=C sort -u)"
echo "   payload files changed: ${CHANGED:-<none>}"
if [ "$CHANGED" != "./usr/share/applications/quick-mail.desktop" ]; then
  echo "FAIL: files other than the desktop entry changed — REFUSING to publish." >&2
  rm -f "$DEB"; exit 7
fi
cmp -s "$WORK/new/usr/share/applications/quick-mail.desktop" "$SRC_DESKTOP" \
  || { echo "FAIL: shipped desktop entry is not the repo's file" >&2; rm -f "$DEB"; exit 8; }

# control: only Version
CTLDIFF="$( { diff "$WORK/old/DEBIAN/control" "$WORK/new/DEBIAN/control" || true; } | grep '^[<>]' || true)"
NCTL="$(printf '%s\n' "$CTLDIFF" | grep -c '^[<>]' || true)"
if [ "$NCTL" != 2 ] || [ "$(printf '%s\n' "$CTLDIFF" | grep -c 'Version: ')" != 2 ]; then
  echo "FAIL: DEBIAN/control differs by more than Version:" >&2
  printf '%s\n' "$CTLDIFF" >&2
  rm -f "$DEB"; exit 9
fi
OLDCTL_FILES="$(cd "$WORK/old/DEBIAN" && ls | LC_ALL=C sort | tr '\n' ' ')"
NEWCTL_FILES="$(cd "$WORK/new/DEBIAN" && ls | LC_ALL=C sort | tr '\n' ' ')"
[ "$OLDCTL_FILES" = "$NEWCTL_FILES" ] \
  || { echo "FAIL: control archive gained/lost files ($OLDCTL_FILES -> $NEWCTL_FILES)" >&2
       rm -f "$DEB"; exit 10; }

echo "   control: Version only ($OLDVER -> $NEWVER); control members unchanged ($NEWCTL_FILES)"
echo
echo "OK: $DEB"
echo "    $(du -h "$DEB" | cut -f1), payload identical to $(basename "$IN") except the desktop entry"
echo
echo "Next:"
echo "  packaging/verify-wmclass.sh $DEB    # PROVE StartupWMClass matches the window"
