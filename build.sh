#!/bin/sh

set -eu

PROJECT="sindri"
VERSION="dev-$(date -u '+%Y-%m-%d')-$(git rev-parse --short HEAD)"

OPTION="${1:-}"
shift

# ------------------------------------------

# Setup compiled wgpu binary
./scripts/wgpu-init.sh

# ------------------------------------------
# Game compile

mkdir -p build

# Game.dll
odin build game/ -show-timings \
	-collection:sindri=src \
	-collection:gram=vendor/gram/src \
	-collection:wgpu=vendor \
	-build-mode:dynamic \
	-out:build/game_tmp -microarch:native -o:minimal -use-separate-modules -define:VERSION="$VERSION-debug" -debug "$@"

# Need to use a temp file on Linux/macOS because it first writes an empty file,
# which the engine will load before it is actually fully written.
[ "$(uname -s)" = "Darwin" ] && LIB_EXT="dylib" || LIB_EXT="so"
[ -f "build/game_tmp.$LIB_EXT" ] || {
	echo "error: build produced no game lib.$LIB_EXT" >&2
	exit 1
}
mv -f "build/game_tmp.$LIB_EXT" "build/game.$LIB_EXT"

# ------------------------------------------
# Engine compile

# If the executable is already running, then don't try to build and start it.
if pgrep -x $PROJECT >/dev/null; then
	echo "Hot reloading..."
	exit 0
fi

if [ "$OPTION" = "debug" ]; then
	odin build src/ -show-timings \
		-collection:sindri=src \
		-collection:gram=vendor/gram/src \
		-collection:wgpu=vendor \
		-out:build/$PROJECT -microarch:native -o:minimal -use-separate-modules -define:VERSION="$VERSION-debug" -debug "$@"
	exit 0
fi

odin build src/ -show-timings \
	-collection:sindri=src \
	-collection:gram=vendor/gram/src \
	-collection:wgpu=vendor \
	-out:build/$PROJECT -microarch:native -o:speed -define:VERSION="$VERSION" "$@"
