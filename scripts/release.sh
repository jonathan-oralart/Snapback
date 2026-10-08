#!/bin/zsh
# Builds a Developer ID signed, notarized release and publishes it to GitHub Releases with a Sparkle appcast.
# Usage: scripts/release.sh 1.0.0
# One-time setup is in README.md under "Releasing".
set -euo pipefail

VERSION=${1:?Usage: scripts/release.sh <version, e.g. 1.0.0>}
REPO=jonathan-oralart/snapback
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

echo "› Notarizing the app (a few minutes)"
# Stapled to the app itself, so it opens offline and Sparkle updates (which unpack the app) carry the ticket.
ditto -c -k --keepParent "$OUT/Snapback.app" "$OUT/Snapback.zip"
xcrun notarytool submit "$OUT/Snapback.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$OUT/Snapback.app"

echo "› Making the disk image"
STAGE=$OUT/dmg
mkdir -p "$STAGE" && cp -R "$OUT/Snapback.app" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
DMG=$OUT/Snapback-$VERSION.dmg
hdiutil create -quiet -volname Snapback -srcfolder "$STAGE" -ov -format UDZO "$DMG"
IDENTITY=$(security find-identity -v -p codesigning | grep -o 'Developer ID Application: [^"]*' | head -1 || true)
[[ -n "$IDENTITY" ]] && codesign --sign "$IDENTITY" --timestamp "$DMG"

echo "› Notarizing the disk image"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

echo "› Writing the update feed"
# Release notes: user-facing commit subjects (feat/fix/perf) since the previous release, without the prefix.
PREVIOUS=$(git describe --tags --abbrev=0 2>/dev/null || true)
NOTES=$(git log --format=%s ${PREVIOUS:+$PREVIOUS..}HEAD | grep -E '^(feat|fix|perf)(\(.*\))?: ' \
  | sed -E 's/^[a-z]+(\(.*\))?: //' | perl -CS -pe 's/^(.)/\u$1/' || true)
[[ -n "$NOTES" ]] || NOTES="Small improvements and fixes."
NOTES_HTML=$(print -r -- "$NOTES" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's|^|<li>|' -e 's|$|</li>|')
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
      <description><![CDATA[
        <style>:root { color-scheme: light dark; } body { font: 13px -apple-system, sans-serif; margin: 4px 8px; } li { margin: 4px 0; }</style>
        <ul>$NOTES_HTML</ul>
      ]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/Snapback-$VERSION.dmg" $SIGNATURE type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML

echo "› Publishing v$VERSION"
git tag "v$VERSION" && git push origin "v$VERSION"
gh release create "v$VERSION" "$DMG" "$OUT/appcast.xml" --repo "$REPO" --title "Snapback $VERSION for Claude Code" --notes "$(print -r -- "$NOTES" | sed 's/^/- /')"
# Remove the loose app copies so macOS never opens one of these instead of the installed app.
rm -rf "$OUT/Snapback.app" "$STAGE"
echo "Done: https://github.com/$REPO/releases/tag/v$VERSION"
