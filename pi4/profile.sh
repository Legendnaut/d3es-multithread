#!/usr/bin/env bash
# CPU profile of a running game. Start dhewm3 first, then run this in a
# terminal, switch back to the game and get into a fight.
# Usage: bash ~/d3es/pi4/profile.sh
set -e
if ! command -v perf >/dev/null; then
  echo "== Installing perf =="
  sudo apt install -y linux-perf
fi
pid=$(pgrep -n dhewm3 || true)
if [ -z "$pid" ]; then echo "Start the game first."; exit 1; fi

echo "Switch back to the game now and get into a fight."
for i in 15 10 5; do echo "Recording starts in $i s..."; sleep 5; done
echo "== Recording 20 seconds, keep fighting =="
top -H -b -d 10 -n 2 -p "$pid" > /tmp/d3-threads.txt &
sudo perf record -F 499 -p "$pid" -o /tmp/d3.perf -- sleep 20 2>/dev/null
wait

OUT=~/d3-profile.txt
R="sudo perf report -i /tmp/d3.perf --stdio --no-children"
{
  echo "### thread CPU % (100 = one full core)"
  awk '/^top -/{n++} n==2' /tmp/d3-threads.txt | grep -E "PID|renderT|dhewm3|ALSoft|SDLTimer" | head -8
  echo "### per thread"
  $R --sort comm 2>/dev/null | grep -v '^#' | grep -v '^$' | head -10
  echo "### render thread: by library"
  $R --sort comm,dso 2>/dev/null | grep -v '^#' | grep -v '^$' | grep renderThread | head -12
  echo "### render thread: top functions"
  $R --sort comm,dso,sym 2>/dev/null | grep -v '^#' | grep -v '^$' | grep renderThread | head -40
  echo "### main thread: top functions"
  $R --sort comm,dso,sym 2>/dev/null | grep -v '^#' | grep -v '^$' | grep -v renderThread | head -25
} > "$OUT"
echo
echo "Done! Results saved to $OUT"
echo "Send it with:  cat $OUT"
