#!/usr/bin/env bash
# Usage: patch_duo.sh <in.ipa> <out.ipa>   (macOS + Xcode with vtool)
#
# Follows Apple's iPhone Duo guidance ("Prepare your app for iPhone Duo"): an app linked against the
# iOS 27.1 SDK gets the full-edge inner-display layout, while a 27.0-linked app only extends left of the
# status bar — which is exactly the half-letterbox TikTok shows. TikTok's binary is linked at 27.0, so
# raise its Mach-O linked-SDK to 27.1 (keeping platform iOS and the 15.0 deployment target). This opts
# TikTok into the 27.1 Duo layout at the system level, the right way per the guidelines, rather than
# forcing window frames at runtime. Same technique as LiquidBird's patch_glass.sh.
set -euo pipefail
IN="$(realpath "$1")"
mkdir -p "$(dirname "$2")"
OUT="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
TARGET=27.1

unzip -q "$IN" -d "$WORK"
APP="$(find "$WORK/Payload" -maxdepth 1 -name '*.app' | head -1)"
BIN="$APP/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")"

BUILD="$(xcrun vtool -show-build "$BIN")"
MINOS="$(awk '$1 == "minos" { print $2; exit }' <<<"$BUILD")"
SDK="$(awk '$1 == "sdk" { print $2; exit }' <<<"$BUILD")"
[[ -n "$MINOS" && -n "$SDK" ]] || { echo "no LC_BUILD_VERSION in $BIN" >&2; exit 1; }

if [[ "$SDK" == "$TARGET" ]]; then
  echo "SDK already $TARGET: $BIN"
elif [[ "$(printf '%s\n%s\n' "$SDK" "$TARGET" | sort -V | head -1)" == "$SDK" ]]; then
  xcrun vtool -set-build-version ios "$MINOS" "$TARGET" -replace -output "$BIN.new" "$BIN"
  mv "$BIN.new" "$BIN"
  xcrun vtool -show-build "$BIN" | grep -q "sdk $TARGET" || { echo "SDK bump failed: $BIN" >&2; exit 1; }
  echo "SDK $SDK -> $TARGET (minos $MINOS, Duo full-edge): $BIN"
else
  echo "SDK $SDK already > $TARGET, left as is: $BIN"
fi

# Keep the metadata consistent with the raised linked SDK (harmless if a key is absent).
/usr/libexec/PlistBuddy -c "Set :DTSDKName iphoneos$TARGET" "$APP/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :DTPlatformVersion $TARGET" "$APP/Info.plist" 2>/dev/null || true

rm -f "$OUT"
( cd "$WORK" && zip -qry "$OUT" Payload )
echo "wrote $OUT"
