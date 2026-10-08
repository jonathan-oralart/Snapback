# Recording the GitHub demo

The demo is a separate repository, so Claude can find the page from the screenshot alone. The pages in this directory are source templates; Claude edits the working copy outside Snapback.

Agents: read [HANDOFF.md](HANDOFF.md) first for the recording pitfalls and manual steps from the successful take.

One-time setup (from the Snapback repository, with the destination not yet created):

```sh
mkdir ../snapback-demo
cp demo/player/index.html ../snapback-demo/index.html
cp demo/CLAUDE.md ../snapback-demo/CLAUDE.md
git -C ../snapback-demo init
git -C ../snapback-demo add index.html CLAUDE.md
git -C ../snapback-demo commit -m "Add demo baseline"
scripts/dev.sh
scripts/record-demo.sh player --serve
```

The small `CLAUDE.md` keeps replies to one sentence and tells Claude to leave the browser closed. Select `../snapback-demo` as the folder in Claude. For readable notes in Claude’s image preview, set **Settings → Exported image → Annotation text size** to **Extra large**. Leave the server running, then in another terminal:

```sh
scripts/record-demo.sh player
```

In CleanShot X, enable **Settings → Advanced → API → Allow applications to control CleanShot**. The recording area can then be opened from the terminal (coordinates start at the bottom left):

```sh
open 'cleanshot://record-screen?x=0&y=0&width=1280&height=803&display=1'
```

Press Return in the recorder to start video. On CleanShot 4.8.11, invoking `open 'cleanshot://record-screen'` again during a recording stops it and opens the export window.

The script arranges the windows and arms the take. Start a CleanShot X video recording with **Highlight clicks** and **Show keystrokes** enabled, covering the display below the menu bar. Press Snapback's capture shortcut (**⇧⌘2** by default). The take adds two boxes and types their notes through Snapback's real annotation session, then waits with the toolbar visible. Click **Send to Claude**. Once Claude shows **one image and an empty prompt**, pause for three seconds, then click Send. No text is needed. Hold on the updated page and Claude's response, then stop CleanShot and save the video under `build/demo/`. Trim idle time and export the README GIF with `ffmpeg`.

`player.json` is calibrated for a regular 600 × 700 point Chrome window, including its tabs and address bar. The default layout is 1224 × 700, with Claude on the left, Chrome on the right, and a 24-point gap between them. The layout is centered with space around the windows. Before capture starts, the script raises both windows and hides other apps. Replay refuses a different capture size rather than placing a box incorrectly. Keep the display large enough for that layout. The take format stores `windowSize` and ordinary capture markers (`kind`, `rect`, `note`).

To repeat, deliberately restore the demo baseline first:

```sh
git -C ../snapback-demo restore index.html
```

Recording refuses uncommitted edits instead of overwriting them. `DEMO_DIR`, `PORT`, `LAYOUT`, and `BROWSER` can be overridden. To record a different annotation, mark up the same-sized window by hand, save it, and run `scripts/record-demo.sh player --save-take` (requires `jq`).

## Exporting

Run these commands from the Snapback repository. The exporter requires Python 3 and `ffmpeg`. Create a JSON list of `[start_seconds, end_seconds, speed]` cuts for your new recording; speed `1` preserves real time. Choose cuts after reviewing the footage, keeping the shortcut, both annotations, Send click, paste pause and final result.

The checked-in `demo/cuts/player-cleanshot.json` preserves the approved October 2026 edit for `build/demo/chrome-cleanshot-raw.mp4`. Its timestamps apply only to that original recording:

```sh
python3 scripts/export-demo.py build/demo/chrome-cleanshot-raw.mp4 demo/cuts/player-cleanshot.json
```

This writes `demo.mp4`, `demo.gif` and `contact.jpg` to ignored `build/demo/export/` (override with `--output`). It preserves the recording's aspect ratio, exports at 1280 pixels wide and holds the last frame for three seconds. Re-running overwrites those previews. Review the motion and final frame, then publish:

```sh
cp build/demo/export/demo.gif docs/demo.gif
```

The README already embeds `docs/demo.gif`. Keep raw footage and editing intermediates under ignored `build/demo/`; commit the final GIF and any reusable take/cut changes.
