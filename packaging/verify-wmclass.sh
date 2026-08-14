#!/usr/bin/env bash
# verify-wmclass.sh — PROVE the packaged Quick Mail's window reports the class
# its desktop entry declares.
#
#   packaging/verify-wmclass.sh <quickopen-quick-mail_*.deb>
#
# WHY THIS EXISTS. Field defect F, Quick OS 0.1.3: four apps declared a
# StartupWMClass their windows never reported. The symptom is deceptive —
# "on launch the icon is ok but the taskbar/pinned icon is not" — because the
# launcher icon comes from Icon= and needs no window at all, while the taskbar
# icon requires Plasma to bind the running window to the desktop entry via
# WM_CLASS. Every static check passed; only a running window disagreed.
#
# So this reads the class off a REAL window: it unpacks the deb, runs the
# packaged binary under Xvfb, and asks X what the window actually says.
set -euo pipefail

DEB="${1:?usage: verify-wmclass.sh <deb>}"
[ -f "$DEB" ] || { echo "no such deb: $DEB" >&2; exit 1; }
for t in xvfb-run xprop xdotool; do
  command -v "$t" >/dev/null || { echo "$t missing (apt install xvfb x11-utils xdotool)" >&2; exit 1; }
done

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
dpkg-deb -x "$DEB" "$WORK/x"

DESKTOP="$WORK/x/usr/share/applications/quick-mail.desktop"
[ -f "$DESKTOP" ] || { echo "no desktop entry in the package" >&2; exit 1; }
DECLARED="$(sed -n 's/^StartupWMClass=//p' "$DESKTOP" | head -1)"
[ -n "$DECLARED" ] || { echo "FAIL: the desktop entry declares no StartupWMClass" >&2; exit 1; }
echo "== declared: StartupWMClass=$DECLARED"

BIN="$WORK/x/opt/quick-mail/quickmail"
[ -x "$BIN" ] || { echo "no binary at $BIN" >&2; exit 1; }

# A fresh profile, so the run cannot touch anything real and cannot be short-
# circuited by an existing profile's state.
export HOME="$WORK/home"; mkdir -p "$HOME"

echo "== launching under Xvfb"
REPORTED=""
xvfb-run -a --server-args="-screen 0 1280x900x24" bash -c '
  "'"$BIN"'" -profile "'"$WORK"'/profile" >/dev/null 2>&1 &
  APP=$!
  for i in $(seq 1 60); do
    W=$(xdotool search --onlyvisible --name . 2>/dev/null | head -1 || true)
    if [ -n "$W" ]; then
      xprop -id "$W" WM_CLASS 2>/dev/null && break
    fi
    sleep 1
  done
  kill $APP 2>/dev/null || true
  wait $APP 2>/dev/null || true
' > "$WORK/xprop.out" 2>/dev/null || true

REPORTED="$(sed -n 's/^WM_CLASS(STRING) = //p' "$WORK/xprop.out" | head -1)"
if [ -z "$REPORTED" ]; then
  echo "FAIL: no window appeared, so the class could not be read." >&2
  echo "      (an app that never maps a window cannot bind a taskbar icon either)" >&2
  exit 2
fi
echo "== reported: WM_CLASS = $REPORTED"

# xprop prints:  WM_CLASS(STRING) = "instance", "Class"
INSTANCE="$(echo "$REPORTED" | sed 's/^"\([^"]*\)".*/\1/')"
CLASS="$(echo "$REPORTED" | sed 's/.*, *"\([^"]*\)".*/\1/')"

# Plasma matches StartupWMClass against EITHER half, so either is a pass.
if [ "$DECLARED" = "$INSTANCE" ] || [ "$DECLARED" = "$CLASS" ]; then
  echo "OK: the window reports the declared class (instance=$INSTANCE class=$CLASS)"
  exit 0
fi
echo "FAIL: StartupWMClass=$DECLARED matches NEITHER half of the window's" >&2
echo "      WM_CLASS (instance=$INSTANCE, class=$CLASS)." >&2
echo "      The taskbar and pinned icons will fall back to a generic icon." >&2
echo "      Set StartupWMClass to '$INSTANCE' or '$CLASS' in" >&2
echo "      applications/quick-mail.desktop and rebuild." >&2
exit 3
