#!/usr/bin/env bash
# Launch Doom 3 (build-pgo) with a chosen graphics driver.
#   bash pi4/run.sh            system driver (normal)
#   bash pi4/run.sh tuned      Pi 4 tuned Mesa from pi4/mesa.sh
#   bash pi4/run.sh pgo        PGO Mesa (recording or optimized, whichever was built last)
# Extra game arguments can follow, e.g.:  bash pi4/run.sh tuned +map game/alphalabs1
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WHICH=${1:-system}; [ $# -gt 0 ] && shift

if [ "$WHICH" != "system" ]; then
	P=~/mesa-pi4/$WHICH
	LIB=$(ls -d "$P"/lib/*-linux-gnu 2>/dev/null | head -1)
	if [ -z "$LIB" ]; then echo "No Mesa build in $P yet. Run pi4/mesa.sh first."; exit 1; fi
	export LD_LIBRARY_PATH="$LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
	export LIBGL_DRIVERS_PATH="$LIB/dri"
	export __GLX_VENDOR_LIBRARY_NAME=mesa
	export __EGL_VENDOR_LIBRARY_FILENAMES="$P/share/glvnd/egl_vendor.d/50_mesa.json"
	export GBM_BACKENDS_PATH="$LIB/gbm"
fi

gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
if [ "$gov" != "performance" ]; then
	echo "Tip: CPU governor is '$gov'. For steadier fps run once per boot:"
	echo "  echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"
fi

cd "$ROOT/build-pgo" || exit 1
if [ "$WHICH" != "system" ]; then
	# check (in the background) that the game really loaded our driver
	( sleep 10
	  pid=$(pgrep -n dhewm3)
	  if grep -q "mesa-pi4/$WHICH" /proc/$pid/maps 2>/dev/null; then
		echo "== Using Mesa from ~/mesa-pi4/$WHICH =="
	  else
		echo "!! WARNING: game is NOT using ~/mesa-pi4/$WHICH (still on the system driver)"
	  fi ) &
fi
exec ./dhewm3 +set r_multithread 1 "$@"
