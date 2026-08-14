#!/usr/bin/env bash
# build.sh — build Quick Mail from the pinned Thunderbird ESR source.
#
#   build.sh [srcdir]        default ../../mail/thunderbird-<ver>
#
# Run fetch-source.sh first. This script owns everything that turns the pinned
# upstream tree into Quick Mail, and it is the ONLY thing that should write into
# that tree — the source tree is a build artifact, not source of truth. Anything
# of ours that lives in it (branding, mozconfig, patches) is installed FROM this
# repo on every run, so re-extracting the tarball loses nothing.
#
# That direction matters: the branding was authored directly in the extracted
# tree once, where a re-extract would have destroyed 54 files with no copy
# anywhere. branding/quickmail/ in this repo is now the original.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VER="$(awk -F= '/^thunderbird_version=/{print $2}' "$HERE/pin.txt" | tr -d ' \r')"
[ -n "$VER" ] || { echo "no thunderbird_version in pin.txt" >&2; exit 1; }
SRC="${1:-$HERE/../../mail/thunderbird-${VER%esr}}"
[ -d "$SRC/comm" ] || { echo "not a Thunderbird tree: $SRC (run fetch-source.sh)" >&2; exit 1; }
SRC="$(cd "$SRC" && pwd)"

# Reuse the bootstrapped toolchains (clang, rust, node, sccache, cbindgen)
# rather than re-downloading them into ~/.mozbuild.
export MOZBUILD_STATE_PATH="${MOZBUILD_STATE_PATH:-$(cd "$SRC/.." && pwd)/.mozbuild}"
export SHELL="${SHELL:-/bin/bash}"

echo "== Quick Mail build =="
echo "   source:   $SRC"
echo "   mozbuild: $MOZBUILD_STATE_PATH"

# ---- 1. our branding into the tree ----------------------------------------
# The branding directory name is load-bearing: mozconfig passes
# --with-branding=comm/mail/branding/quickmail.
echo "== installing branding =="
rm -rf "$SRC/comm/mail/branding/quickmail"
cp -a "$HERE/branding/quickmail" "$SRC/comm/mail/branding/quickmail"
echo "   $(find "$SRC/comm/mail/branding/quickmail" -type f | wc -l) files"

# ---- 2. mozconfig ----------------------------------------------------------
# An EMPTY mozconfig is why an earlier attempt built into the default objdir
# with none of the Quick Mail identity applied — assert it landed non-empty.
echo "== installing mozconfig =="
cp "$HERE/mozconfig" "$SRC/mozconfig"
[ -s "$SRC/mozconfig" ] || { echo "mozconfig is empty after copy" >&2; exit 1; }
grep -q "with-app-name=quickmail" "$SRC/mozconfig" \
  || { echo "mozconfig lost --with-app-name=quickmail" >&2; exit 1; }

# ---- 3. source patches -----------------------------------------------------
echo "== applying patches =="
python3 "$HERE/patches/apply-patches.py" "$SRC"

# ---- 4. build --------------------------------------------------------------
echo "== mach build (this is the long one) =="
cd "$SRC"
./mach build

# ---- 5. verify the identity actually took ----------------------------------
# Assert on the BUILT ARTIFACT, not on the config we passed in: a mozconfig can
# be silently ignored (that is exactly how the first attempt failed).
OBJ="$SRC/obj-quickmail"
[ -d "$OBJ" ] || { echo "no obj-quickmail — mozconfig was ignored" >&2; exit 1; }
BIN="$OBJ/dist/bin/quickmail"
[ -x "$BIN" ] || { echo "no quickmail binary at $BIN" >&2; exit 1; }
echo "== built: $BIN ($(du -h "$BIN" | cut -f1)) =="

echo
echo "Next:"
echo "  ./mach package                     # -> obj-quickmail/dist/quickmail-*.tar.xz"
echo "  packaging/build-deb.sh             # -> dist/quickopen-quick-mail_*.deb"
