# Agent Instructions

Snapback is a menu bar app: press a shortcut, annotate the front window with numbered pins and boxes, send it to a new Claude Code session as one image (notes are drawn into it, not sent as text). Keep one implementation, no fallbacks unless asked, no tests unless asked.

## Builds

Test by hand; screen automation is unreliable with the overlay. Build, install and relaunch:

```sh
pkill -x Snapback || true
xcodebuild -project Snapback.xcodeproj -scheme Snapback -configuration Debug -derivedDataPath /tmp/snapback-derived -allowProvisioningUpdates build
rm -rf /Applications/Snapback.app && ditto /tmp/snapback-derived/Build/Products/Debug/Snapback.app /Applications/Snapback.app
open /Applications/Snapback.app
```

Keep Apple Development signing: Screen Recording and Accessibility grants are tied to the signature.

The Xcode project is generated from `project.yml` with XcodeGen; edit that and run `xcodegen generate`.

## Releasing

`scripts/release.sh <version>` archives, signs with Developer ID (Xcode's cloud-managed certificate), notarizes, makes the DMG, writes Sparkle's `appcast.xml` and publishes both to a GitHub Release. Commit first; the build number is the commit count. Setup and details are in README.md.

## App icon

`Snapback/AppIcon.icon` is an Icon Composer icon: the background colour is the `fill` in its `icon.json`, and the artwork layers are drawn by `Icon/render-icon.swift` (run command at the top of that file). Edit the script and re-run it rather than editing the PNGs.

## Architecture

- `App`: entry point and menu, shortcut, permissions window, `AppWindows` (open windows through it so they come to the front), and `CaptureCoordinator` (capture → overlay → save/send).
- `Capture`: front window capture with ScreenCaptureKit.
- `Overlay`: `Marker` and `AnnotationSession` (selection, undo), `MarkerStyle` (marker drawing, shared with the image), the overlay view, note bubble, toolbar and panel.
- `Output`: `FeedbackImage` renders the PNG that's sent: shadowed window with markers, notes in a card underneath.
- `Send`: opens `claude://code/new`, then pastes the image with a synthetic ⌘V.
- `Storage`: the last 20 sent or saved captures in `~/Library/Application Support/Snapback/Captures`, reopened from the menu's Recent submenu or the history window (`UI`). `capture.json` stores markers as `{kind, rect, note}`; keep that format readable.
