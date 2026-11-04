#!/usr/bin/env bash
# Build a private copy of the Mesa graphics driver tuned for the Raspberry Pi 4.
# It installs into ~/mesa-pi4 only; the system driver is never touched.
# Use it with pi4/run.sh. Delete ~/mesa-pi4 to remove it completely.
#
#   bash pi4/mesa.sh night     tuned build + PGO-recording build (~1-1.5 h total)
#   bash pi4/mesa.sh tuned     only the tuned build          -> ~/mesa-pi4/tuned
#   bash pi4/mesa.sh pgo-gen   PGO recording build           -> ~/mesa-pi4/pgo
#   bash pi4/mesa.sh pgo-use   rebuild with recorded profile -> ~/mesa-pi4/pgo
#
# Optional: MESA_SRC=/path/to/mesa-source skips fetching the source.
set -e -o pipefail

BASE=~/mesa-pi4
PATCHDIR="$(cd "$(dirname "$0")" && pwd)/mesa-patches"
LOG=$BASE/build.log
mkdir -p "$BASE"

if [ "$(uname -m)" = "aarch64" ]; then
	# -mno-outline-atomics: the A72 has no LSE atomics, so call the LL/SC
	# instructions directly instead of a runtime-dispatch helper function
	CPUFLAGS="-mcpu=cortex-a72 -mtune=cortex-a72 -mno-outline-atomics"
else
	CPUFLAGS=""	# only for testing the script on a non-Pi machine
fi

# With a profile GCC analyses more deeply and flags harmless debug-trace
# format strings, which Mesa's -Werror=format turns into build errors.
PGO_WARN="-Wno-error=format-overflow -Wno-error=format-truncation -Wno-coverage-mismatch"

OPTS=(
	-Dbuildtype=release			# -O3
	-Dgallium-drivers=v3d,vc4	# Pi 4 GPU (v3d) + display (vc4)
	-Dvulkan-drivers=
	-Dplatforms=x11,wayland
	-Dglx=dri -Degl=enabled -Dgbm=enabled
	-Dgles1=disabled -Dgles2=enabled
	-Dglvnd=enabled
	-Dllvm=disabled -Dvalgrind=disabled -Dlibunwind=disabled -Dlmsensors=disabled
	-Dbuild-tests=false -Dvideo-codecs= -Dgallium-va=disabled
)

deps() {
	echo "== Installing build tools =="
	sudo apt-get install -y dpkg-dev meson ninja-build python3-mako python3-yaml python3-ply \
		python3-packaging bison flex glslang-tools pkg-config libdrm-dev libexpat1-dev \
		zlib1g-dev libzstd-dev libx11-dev libxext-dev libxfixes-dev libxcb-glx0-dev \
		libxcb-shm0-dev libx11-xcb-dev libxcb-dri2-0-dev libxcb-dri3-dev libxcb-present-dev \
		libxcb-randr0-dev libxcb-sync-dev libxcb-xfixes0-dev libxshmfence-dev libxxf86vm-dev \
		libxrandr-dev libwayland-dev wayland-protocols libwayland-egl-backend-dev \
		libglvnd-dev libelf-dev libudev-dev
}

source_dir() {
	if [ -n "$MESA_SRC" ]; then echo "$MESA_SRC"; return; fi
	local d
	d=$(ls -d "$BASE"/src/mesa-*/ 2>/dev/null | head -1)
	if [ -n "$d" ]; then echo "${d%/}"; return; fi

	# Fetch the exact source of the installed driver (with Raspberry Pi patches)
	local ver
	ver=$(dpkg-query -W -f='${Version}' libgl1-mesa-dri 2>/dev/null || true)
	echo "== Installed Mesa package: ${ver:-unknown} ==" >&2
	for f in /etc/apt/sources.list.d/raspi.sources /etc/apt/sources.list.d/debian.sources; do
		[ -f "$f" ] && sed 's/^Types: deb$/Types: deb-src/' "$f" | sudo tee "${f%.sources}-src.sources" >/dev/null
	done
	for f in /etc/apt/sources.list.d/raspi.list /etc/apt/sources.list; do
		[ -f "$f" ] && grep '^deb ' "$f" | sed 's/^deb /deb-src /' | sudo tee "/etc/apt/sources.list.d/$(basename "$f" .list)-src.list" >/dev/null
	done
	sudo apt-get update >&2
	mkdir -p "$BASE/src" && cd "$BASE/src"
	if [ -n "$ver" ] && apt-get source "mesa=$ver" >&2; then :; else
		echo "== Exact version not available, fetching latest packaged mesa ==" >&2
		apt-get source mesa >&2
	fi
	d=$(ls -d "$BASE"/src/mesa-*/ | head -1)
	echo "${d%/}"
}

build() {	# build <dir name> <install name> [extra meson args...]
	local bdir=$BASE/$1 prefix=$BASE/$2; shift 2
	local src; src=$(source_dir)
	# Pi 4 driver patches (each checks the source and skips itself if it doesn't fit)
	for patch in "$PATCHDIR"/*.py; do
		python3 "$patch" "$src" || echo "== $(basename "$patch") skipped =="
	done
	echo "== Building Mesa from $src into $prefix =="
	if [ -f "$bdir/build.ninja" ]; then
		meson configure "$bdir" "$@"
	else
		meson setup "$bdir" "$src" --prefix="$prefix" "${OPTS[@]}" \
			-Dc_args="$CPUFLAGS" -Dcpp_args="$CPUFLAGS" "$@"
	fi
	ninja -C "$bdir"
	ninja -C "$bdir" install
}

case "$1" in
	tuned)
		deps; build build-tuned tuned ;;
	pgo-gen)
		deps
		build build-pgo pgo -Db_pgo=generate \
			-Dc_args="$CPUFLAGS -fprofile-update=atomic" -Dcpp_args="$CPUFLAGS -fprofile-update=atomic" ;;
	pgo-use)
		n=$(find "$BASE/build-pgo" -name '*.gcda' 2>/dev/null | wc -l)
		if [ "$n" -eq 0 ]; then
			echo "No profile yet. Run: bash pi4/run.sh pgo  then play and quit with the 'quit' command."
			exit 1
		fi
		echo "== Found $n profile files =="
		build build-pgo pgo -Db_pgo=use \
			-Dc_args="$CPUFLAGS -fprofile-correction -Wno-missing-profile $PGO_WARN" \
			-Dcpp_args="$CPUFLAGS -fprofile-correction -Wno-missing-profile $PGO_WARN" ;;
	night)
		{ deps; build build-tuned tuned
		  build build-pgo pgo -Db_pgo=generate \
			-Dc_args="$CPUFLAGS -fprofile-update=atomic" -Dcpp_args="$CPUFLAGS -fprofile-update=atomic"
		  echo; echo "ALL DONE $(date)"; } 2>&1 | tee "$LOG"
		;;
	*)
		echo "Usage: bash pi4/mesa.sh night|tuned|pgo-gen|pgo-use"; exit 1 ;;
esac
