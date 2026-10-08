#!/bin/zsh
# Builds the Debug app, installs it as /Applications/Snapback Dev.app and relaunches it.
# It has its own bundle ID (com.oralart.snapback.dev) and stays Apple Development signed,
# so Screen Recording and Accessibility grants survive every rebuild.
set -euo pipefail

BUNDLE_ID=com.oralart.snapback.dev
APP="/Applications/Snapback Dev.app"
DERIVED=build/DerivedData-dev
cd "$(dirname "$0")/.."

xcodegen generate -q
xcodebuild -project Snapback.xcodeproj -scheme Snapback -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates -quiet build

# Quit gracefully and wait, so the bundle isn't replaced under a running app.
osascript -e "quit app id \"$BUNDLE_ID\"" 2>/dev/null || true
for _ in {1..50}; do
  pgrep -f "$APP/Contents/MacOS/" >/dev/null || break
  sleep 0.1
done
pkill -f "$APP/Contents/MacOS/" || true

rm -rf "$APP"
ditto "$DERIVED/Build/Products/Debug/Snapback.app" "$APP"
# By path: the build products copy has the same bundle ID.
open "$APP"
