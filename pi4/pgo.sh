#!/usr/bin/env bash
# Profile-guided optimization build for Raspberry Pi 4.
#   bash pi4/pgo.sh gen   -> builds an instrumented game into build-pgo
#   (play it, then type "quit" in the console)
#   bash pi4/pgo.sh use   -> rebuilds build-pgo using the recorded profile
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build-pgo"
PROFILE="$ROOT/pgo-profile"

case "$1" in
  gen)
    rm -rf "$BUILD" "$PROFILE"
    mkdir -p "$BUILD" && cd "$BUILD"
    cmake ../neo -DCMAKE_BUILD_TYPE=Release -DPI4=ON -DPGO=GEN -DPGO_DIR="$PROFILE"
    make -j4
    echo
    echo "Step 1 done. Now record a profile:"
    echo "  cd $BUILD && ./dhewm3 +set r_multithread 1"
    echo "  - console: timedemo demo1 usecache"
    echo "  - then start a game and play ~5 minutes, including a fight"
    echo "  - quit with the console command:  quit   (needed to save the profile)"
    echo "Then run:  bash $ROOT/pi4/pgo.sh use"
    ;;
  use)
    n=$(find "$PROFILE" -name '*.gcda' 2>/dev/null | wc -l)
    if [ "$n" -eq 0 ]; then
      echo "No profile found in $PROFILE. Run 'gen', play, and quit with the 'quit' command first."
      exit 1
    fi
    echo "== Found $n profile files =="
    cd "$BUILD"
    cmake . -DPGO=USE
    make clean
    make -j4
    echo
    echo "Done! Benchmark it:  cd $BUILD && ./dhewm3 +set r_multithread 1"
    ;;
  *)
    echo "Usage: bash pi4/pgo.sh gen|use"; exit 1 ;;
esac
