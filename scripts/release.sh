#!/bin/zsh
# Builds a Developer ID signed, notarized release and publishes it to GitHub Releases with a Sparkle appcast.
# Usage: scripts/release.sh 1.0.0
# One-time setup is in README.md under "Releasing".
set -euo pipefail

VERSION=${1:?Usage: scripts/release.sh <version, e.g. 1.0.0>}
REPO=jonathan-oralart/Snapback
NOTARY_PROFILE=snapback
cd "$(dirname "$0")/.."

[[ -z "$(git status --porcelain)" ]] || { echo "Commit your changes first."; exit 1; }
BUILD=$(git rev-list --count HEAD)   # Sparkle compares this to decide what's newer.
OUT=build/release-$VERSION
DERIVED=build/DerivedData
rm -rf "$OUT" && mkdir -p "$OUT"

echo "› Archiving $VERSION ($BUILD)"
xcodegen generate -q
xcodebuild archive -project Snapback.xcodeproj -scheme Snapback -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" -archivePath "$OUT/Snapback.xcarchive" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" -allowProvisioningUpdates -quiet
xcodebuild -exportArchive -archivePath "$OUT/Snapback.xcarchive" -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$OUT" -allowProvisioningUpdates -quiet

echo "› Making the disk image"
STAGE=$OUT/dmg
mkdir -p "$STAGE" && cp -R "$OUT/Snapback.app" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
DMG=$OUT/Snapback-$VERSION.dmg
hdiutil create -quiet -volname Snapback -srcfolder "$STAGE" -ov -format UDZO "$DMG"
IDENTITY=$(security find-identity -v -p codesigning | grep -o 'Developer ID Application: [^"]*' | head -1 || true)
[[ -n "$IDENTITY" ]] && codesign --sign "$IDENTITY" --timestamp "$DMG"

echo "› Notarizing (a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

echo "› Writing the update feed"
SIGNATURE=$("$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" "$DMG")
cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Snapback</title>
    <item>
      <title>Snapback $VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.4</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$REPO/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/Snapback-$VERSION.dmg" $SIGNATURE type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML

echo "› Publishing v$VERSION"
git tag "v$VERSION" && git push origin "v$VERSION"
gh release create "v$VERSION" "$DMG" "$OUT/appcast.xml" --repo "$REPO" --title "Snapback $VERSION" --generate-notes
echo "Done: https://github.com/$REPO/releases/tag/v$VERSION"
