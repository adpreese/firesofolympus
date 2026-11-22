#!/usr/bin/env bash
# Headless builds for Fires of Olympus.
#   tools/build.sh web     -> build/web/        (static site)
#   tools/build.sh serve   -> build web, then serve at http://localhost:8060
#   tools/build.sh ios     -> build/ios/        (Xcode project; open the .xcodeproj to run on device)
#   tools/build.sh sim     -> build iOS, compile for Simulator (x86_64/Rosetta; official templates
#                             have no arm64-sim slice), install + launch on a booted iPad sim
#   tools/build.sh check   -> import + parse all scripts, fail on errors
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
MODE="${2:-release}"   # pass "debug" as 2nd arg for debug builds

case "${1:-}" in
  check)
    "$GODOT" --headless --import --quit
    ;;
  web)
    rm -rf build/web && mkdir -p build/web
    "$GODOT" --headless --export-"$MODE" "Web" build/web/index.html
    ;;
  serve)
    "$0" web "$MODE"
    echo "Serving http://localhost:8060"
    python3 -m http.server 8060 --directory build/web
    ;;
  ios)
    rm -rf build/ios && mkdir -p build/ios
    "$GODOT" --headless --export-"$MODE" "iOS" build/ios/FiresOfOlympus.ipa
    echo "Open build/ios/FiresOfOlympus.xcodeproj in Xcode to sign and run."
    ;;
  sim)
    "$0" ios debug
    xcodebuild -project build/ios/FiresOfOlympus.xcodeproj -scheme FiresOfOlympus \
      -sdk iphonesimulator -configuration Debug -derivedDataPath build/ios/dd \
      ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO -quiet build
    DEV="${SIM_DEVICE:-$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)}"
    if [ -z "$DEV" ]; then
      DEV=$(xcrun simctl list devices available | grep -i ipad | grep -oE '[0-9A-F-]{36}' | head -1)
      xcrun simctl boot "$DEV"; open -a Simulator
    fi
    BUNDLE=$(grep bundle_identifier export_presets.cfg | cut -d'"' -f2)
    xcrun simctl install "$DEV" build/ios/dd/Build/Products/Debug-iphonesimulator/FiresOfOlympus.app
    xcrun simctl launch --console --terminate-running-process "$DEV" "$BUNDLE"
    ;;
  *)
    sed -n '2,9p' "$0"; exit 1
    ;;
esac
