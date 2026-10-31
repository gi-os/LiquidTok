#!/usr/bin/env bash
# Usage: build.sh [--ipa TikTok.ipa] [--flex FLEXing.deb]
# Fetches the decrypted TikTok base IPA (unless --ipa gives one), checks it is still Apple's build with
# scripts/verify_ipa.py (it comes from a stranger's GitHub release), builds the tweak and injects it with
# cyan. Output: out/LiquidTok.ipa (unsigned). macOS only.
set -euo pipefail
cd "$(dirname "$0")/.."
IPA=""; FLEX=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ipa)  IPA="$2"; shift 2 ;;
    --flex) FLEX="$2"; shift 2 ;;
    *) echo "unknown arg $1"; exit 1 ;;
  esac
done

mkdir -p out
# The base decrypted App Store IPA. Overridable with BASE_IPA_URL (a release of a decrypted
# com.zhiliaoapp.musically); the tweak targets 47.5's class names.
: "${BASE_IPA_URL:=https://github.com/talhaeenss/TweakiTok/releases/download/base-ipa-47.5.0/com.zhiliaoapp.musically-47.5.0-Decrypted.ipa}"
if [[ -z "$IPA" ]]; then
  IPA="out/TikTok-base.ipa"
  echo "Fetching the base IPA..."
  curl -fL --retry 4 --retry-delay 2 -o "$IPA" "$BASE_IPA_URL"
fi

# Trust gate: the base IPA must still be Apple's signed build (header, unencrypted pages and sealed
# resources), or we don't inject into it. Runs on the ORIGINAL, before any patching.
python3 -I scripts/verify_ipa.py "$IPA"

# Follow Apple's iPhone Duo guidance: raise the linked SDK to 27.1 so the system gives TikTok the
# full-edge inner-display layout (no half-letterbox). Modifies the binary, so it runs after verify.
./scripts/patch_duo.sh "$IPA" out/TikTok-duo.ipa
IPA="out/TikTok-duo.ipa"

rm -rf packages   # make clean keeps old debs, and every deb here gets injected
make clean package FINALPACKAGE=1

DEBS=(packages/*.deb)
[[ -n "$FLEX" ]] && DEBS+=("$FLEX")
# Inject the tweak(s) and fakesign; the workflow's sign job strips app extensions and re-signs ad-hoc.
cyan -i "$IPA" -o out/LiquidTok.ipa -f "${DEBS[@]}" -s --overwrite
echo "done: out/LiquidTok.ipa (unsigned, sign with the workflow / Sideloadly / Feather)"
