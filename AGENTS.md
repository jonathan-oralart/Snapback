# Agent Instructions

Snapback is a menu bar app: press a shortcut, annotate the front window with numbered pins and boxes, send it to a new Claude Code session as one image (notes are drawn into it, not sent as text). Keep one implementation, no fallbacks unless asked, no tests unless asked.

## Builds

Test by hand; screen automation is unreliable with the overlay. Build, install and relaunch with `scripts/dev.sh`. It installs the Debug build as `/Applications/Snapback Dev.app` (bundle ID `com.oralart.snapback.dev`, the user's day-to-day copy) and relaunches it. Writing to /Applications needs the sandbox off.

Keep Apple Development signing and the separate Debug bundle ID: Screen Recording and Accessibility grants are tied to the signature, so they survive rebuilds but break if a release and a dev build share an ID.

The Xcode project is generated from `project.yml` with XcodeGen; edit that and run `xcodegen generate`.

## Releasing

When a set of changes is done, commit and push it without asking.

Push main with `scripts/push.sh`, not `git push`: it pushes, then releases the next patch version (1.0.6 → 1.0.7) through `release.sh` if there are `feat:`, `fix:` or `perf:` commits since the last release tag. It needs the sandbox off. Run `release.sh` by hand for a bigger version jump.

`scripts/release.sh <version>` archives, signs with Developer ID (Xcode's cloud-managed certificate), notarizes, makes the DMG, writes Sparkle's `appcast.xml` and publishes both to a GitHub Release. Commit first; the build number is the commit count. Release notes are the `feat:`, `fix:` and `perf:` commit subjects since the last release, so write those for users. Setup and details are in README.md.

## Demo

`demo/<name>` are templates for the README GIF. The working demo is a separate Git repo at `../snapback-demo`, served on port 8766; select that folder in Claude before recording. `scripts/record-demo.sh <name>` replays `demo/takes/<name>.json` through the real annotation session (Debug builds only), using the take's exact window size. Click the visible Send to Claude button, then verify the single attached image and submit with no text after a short pause. The page reloads after Claude edits it. Read `demo/HANDOFF.md` for practical lessons and `demo/README.md` for setup and the tracked GIF exporter.

## App icon

`Snapback/AppIcon.icon` is an Icon Composer icon: the background colour is the `fill` in its `icon.json`, and the artwork layers are drawn by `Icon/render-icon.swift` (run command at the top of that file). Edit the script and re-run it rather than editing the PNGs. The Debug build uses `Snapback/AppIconDev.icon`, the same artwork on orange; the script writes both.

## Architecture

- `App`: entry point and menu, shortcut, permissions window, `AppWindows` (open windows through it so they come to the front), and `CaptureCoordinator` (capture → overlay → save/send).
- `Capture`: front window capture with ScreenCaptureKit, and `ScreenRecorder`, which records the front window's display to a temporary HEVC movie (pointer shown, Snapback's own windows such as the stop pill left out, 60s limit).
- `Overlay`: `Marker` and `AnnotationSession` (frames, crop, selection, undo), `MarkerStyle` (marker drawing, shared with the image), the overlay view, note bubble, toolbar and panel. A screenshot is one frame; a recording (`Recording`: frame times and exact frame decoding) has up to six kept frames, picked on `RecordingTimeline`, with markers numbered across them.
- `Output`: `FeedbackImage` renders the PNG that's sent: shadowed window (or a recording's frames in a grid) with markers, notes in a card underneath.
- `Send`: opens `claude://code/new`, then pastes the image using Claude's Paste menu action and plays the sound chosen in Settings (Copy plays it too). The sounds are SND01 "sine" from snd.dev; keep the files unmodified (their terms).
- `Storage`: the last 20 sent or saved captures in `~/Library/Application Support/Snapback/Captures`, reopened from the menu's Recent submenu or the history window (`UI`). `capture.json` stores markers as `{kind, rect, note}`; keep that format readable. A recording keeps `recording.mov` instead of `window.png`, and its crop and frames (exact movie times) in `capture.json`.
