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
sudo perf record -F 499 -p "$pid" -o /tmp/d3.perf -- sleep 20 2>/dev/null

OUT=~/d3-profile.txt
{
  echo "### per thread"
  sudo perf report -i /tmp/d3.perf --stdio --no-children --sort tid 2>/dev/null | grep -v '^#' | grep -v '^$' | head -15
  echo "### top functions"
  sudo perf report -i /tmp/d3.perf --stdio --no-children --sort dso,sym --percent-limit 0.4 2>/dev/null | grep -v '^#' | grep -v '^$' | head -70
} > "$OUT"
echo
echo "Done! Results saved to $OUT"
echo "Send it with:  cat $OUT"
