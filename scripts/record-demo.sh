#!/bin/zsh
# Records the README demo: Snapback Dev marks up a demo page, sends it to Claude Code, Claude fixes the page,
# and the page reloads by itself. Makes build/demo/<name>.gif and .mp4, with Claude's working time sped up.
#
#   scripts/record-demo.sh <name> --serve       serve demo/, open the page and lay out the windows (leave it running)
#   scripts/record-demo.sh <name> --save-take   save your latest capture's markers as the take to replay
#   scripts/record-demo.sh <name>               record a take
#
# Once: install Snapback Dev with scripts/dev.sh and run --serve; the page must come from it, not a file, to reload
# itself. Then mark the page up once by hand with Snapback Dev and run --save-take.
#
# Every take puts Claude in the left half of LAYOUT and the page in the right, and records just that area.
# LAYOUT=x,y,w,h (points from the top left of the main display; default up to 1280×800, centred on screen);
# BROWSER (default Google Chrome); PROMPT (default "Fix these") is typed with the image; WIDTH (default 960) is the
# output width. Each take resets demo/<name> to its committed version and starts a new Claude Code session there.
set -euo pipefail
zmodload zsh/datetime
cd "$(dirname "$0")/.."

NAME=${1:?usage: scripts/record-demo.sh <name> [--serve | --save-take]}
DEMO=$PWD/demo/$NAME
TAKE=$PWD/demo/takes/$NAME.json
OUT=$PWD/build/demo
PAGE=$DEMO/index.html
TIMES=$OUT/$NAME.times
PORT=8765
BROWSER=${BROWSER:-Google Chrome}
TITLE=$(sed -n 's:.*<title>\(.*\)</title>.*:\1:p' "$PAGE")
if [[ -z ${LAYOUT:-} ]]; then
  # Up to 1280×800, centred in the main display below the menu bar and above the Dock.
  LAYOUT=$(osascript -l JavaScript -e 'ObjC.import("AppKit"); const screen = $.NSScreen.screens.objectAtIndex(0);
    const f = screen.frame, v = screen.visibleFrame, w = Math.min(1280, v.size.width), h = Math.min(800, v.size.height);
    const top = f.size.height - (v.origin.y + v.size.height);
    [Math.round(v.origin.x + (v.size.width - w) / 2), Math.round(top + (v.size.height - h) / 2), w, h].join(",")')
fi
mkdir -p "$OUT"

# Asks Snapback Dev to lay out the windows and, given a take, play it.
post() {
  rm -f "$TIMES"
  osascript -l JavaScript - "$LAYOUT" "$BROWSER" "$TITLE" "${1:-}" "$DEMO" "${PROMPT:-Fix these}" "$TIMES" <<'JS'
ObjC.import("Foundation")
function run([layout, browser, title, take, folder, prompt, times]) {
  $.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately(
    "com.oralart.snapback.dev.take", "record-demo", $({ layout, browser, title, take, folder, prompt, times }), true)
}
JS
}

wait_for() {  # wait_for <seconds> <what> <condition…>
  local deadline=$(( EPOCHREALTIME + $1 )) what=$2; shift 2
  until "$@"; do
    if grep -q '^failed ' "$TIMES" 2>/dev/null; then
      echo "Snapback: $(sed -n 's/^failed \(.*\) [0-9.]*$/\1/p' "$TIMES")" >&2; exit 1
    fi
    (( EPOCHREALTIME < deadline )) || { echo "Timed out: $what" >&2; exit 1; }
    sleep 0.25
  done
}
logged() { grep -q "^$1 " "$TIMES" 2>/dev/null; }
NOT_RUNNING="Snapback Dev didn't answer; is it running? (scripts/dev.sh)"

cleanup() {
  [[ -n ${SERVER:-} ]] && kill $SERVER 2>/dev/null
  [[ -n ${RECORDER:-} ]] && kill -INT $RECORDER 2>/dev/null
  return 0
}
trap cleanup EXIT

serve() {
  if ! curl -s -o /dev/null "http://localhost:$PORT/"; then
    python3 -m http.server $PORT --directory demo >/dev/null 2>&1 &
    SERVER=$!
    sleep 0.5
  fi
}

if [[ ${2:-} == --serve ]]; then
  serve
  URL=http://localhost:$PORT/$NAME/
  # Chrome opens the page in a window without tabs or toolbar.
  if [[ $BROWSER == "Google Chrome" ]]; then
    open -na "Google Chrome" --args --app="$URL"
  else
    open -a "$BROWSER" "$URL"
  fi
  sleep 2
  post
  wait_for 3 "$NOT_RUNNING" logged arranged
  [[ -n ${SERVER:-} ]] || { echo "Windows laid out in $LAYOUT; demo/ was already being served."; exit; }
  echo "Serving demo/ at http://localhost:$PORT/ with the windows laid out in $LAYOUT. Ctrl-C to stop."
  wait $SERVER
fi

if [[ ${2:-} == --save-take ]]; then
  latest=$(ls -t "$HOME/Library/Application Support/Snapback/Captures"/*/capture.json | head -1)
  mkdir -p "${TAKE:h}"
  jq '{markers}' "$latest" > "$TAKE"
  echo "Saved $(jq '.markers | length' "$TAKE") markers to $TAKE"
  exit
fi

[[ -f $TAKE ]] || { echo "No take yet: mark the page up by hand, then run with --save-take." >&2; exit 1; }
git ls-files --error-unmatch "$PAGE" >/dev/null 2>&1 || { echo "Commit $PAGE first; each take resets it." >&2; exit 1; }
MOVIE=$OUT/$NAME.mov
serve

# Put the bugs back; the open page reloads itself to show them.
git checkout -- "$PAGE"
sleep 2

rm -f "$MOVIE"
screencapture -v -C -k -x -R"$LAYOUT" "$MOVIE" &
RECORDER=$!
sleep 2

post "$TAKE"
wait_for 3 "$NOT_RUNNING" logged received
wait_for 90 "the take didn't finish" logged submitted
echo "Submitted to Claude; waiting for the fix…"

# Claude may edit more than once: wait for the first change, then until the file has been still for 5 seconds.
original=$(stat -f %Fm "$PAGE")
changed() { [[ $(stat -f %Fm "$PAGE") != $original ]]; }
wait_for 300 "Claude didn't change $PAGE" changed
last=$(stat -f %Fm "$PAGE")
still_since=$EPOCHREALTIME
while (( EPOCHREALTIME - still_since < 5 )); do
  sleep 0.25
  now=$(stat -f %Fm "$PAGE")
  if [[ $now != $last ]]; then last=$now; still_since=$EPOCHREALTIME; fi
done
EDITED=$last

# Hold on the fixed page, then stop. The movie began `duration` seconds before it stopped.
sleep 2
STOPPED=$EPOCHREALTIME
kill -INT $RECORDER
wait $RECORDER || true
RECORDER=
STARTED=$(( STOPPED - $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$MOVIE") ))

at() { echo $(( $(awk -v s="$1" '$1 == s { print $2 }' "$TIMES") - STARTED )); }
FROM=$(( $(at start) - 0.8 )); (( FROM > 0 )) || FROM=0
FAST=$(( $(at submitted) + 1.5 ))
UNTIL=$(( EDITED - STARTED ))
(( UNTIL > FAST )) || UNTIL=$FAST
# Claude's working time plays in 2.5 seconds.
SPEED=$(( (UNTIL - FAST) / 2.5 )); (( SPEED >= 1 )) || SPEED=1

CUT="[0:v]trim=start=${FROM}:end=${FAST},setpts=PTS-STARTPTS[a];[0:v]trim=start=${FAST}:end=${UNTIL},setpts=(PTS-STARTPTS)/${SPEED}[b];"\
"[0:v]trim=start=${UNTIL},setpts=PTS-STARTPTS[c];[a][b][c]concat=n=3:v=1,scale=${WIDTH:-960}:-2:flags=lanczos"
ffmpeg -loglevel error -y -i "$MOVIE" -filter_complex "$CUT,format=yuv420p" -c:v libx264 -crf 20 -movflags +faststart "$OUT/$NAME.mp4"
ffmpeg -loglevel error -y -i "$MOVIE" -filter_complex "$CUT,fps=20,split[s][p];[p]palettegen=stats_mode=diff[pal];[s][pal]paletteuse=dither=bayer:bayer_scale=4" "$OUT/$NAME.gif"

echo "Made $OUT/$NAME.gif ($(du -h "$OUT/$NAME.gif" | cut -f1)) and $OUT/$NAME.mp4 ($(du -h "$OUT/$NAME.mp4" | cut -f1))"
