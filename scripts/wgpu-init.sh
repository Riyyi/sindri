#!/bin/sh

WGPU_VERSION="$1"

if [ "$1" = "" ]; then
	echo "error: WGPU_VERSION was not set"
	exit 1
fi

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
VENDOR_DIR="$SCRIPT_DIR/../vendor"

# ------------------------------------------
# Copy vendor/wgpu

# Check if wgpu was copied already
if [ -d "$VENDOR_DIR/wgpu" ]; then
	exit 0
fi

# Copy wgpu
wgpu_path="$(odin root)/vendor/wgpu"
cp -r "$wgpu_path" "$VENDOR_DIR"
chmod +w "$VENDOR_DIR/wgpu/lib"

# ------------------------------------------
# Download

ASSET_BASE="https://github.com/gfx-rs/wgpu-native/releases/download/${WGPU_VERSION}"

# Platform detection
case "$(uname -s)" in
	Darwin)
		os="macos"
		;;
	Linux)
		os="linux"
		;;
	MINGW* | MSYS* | CYGWIN*)
		os="windows"
		extra="-msvc"
		;;
	*)
		echo "wgpu setup: unsupported OS '$(uname -s)'" >&2
		exit 1
		;;
esac

# Arch detection
case "$(uname -m)" in
	arm64 | aarch64)
		arch="aarch64"
		;;
	x86_64 | amd64)
		arch="x86_64"
		;;
	*)
		echo "wgpu setup: unsupported arch '$(uname -m)'" >&2
		exit 1
		;;
esac

# Download filename
name="wgpu-${os}-${arch}${extra:-}-release"

# Compiler filename: lib/wgpu-macos-aarch64-release/lib/libwgpu_native.a
target="$VENDOR_DIR/wgpu/lib/$name"

# Download
if [ ! -d "$target" ]; then
	url="${ASSET_BASE}/${name}.zip"
	echo "wgpu setup: downloading $url"
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	curl -fL --retry 3 -o "$tmp/wgpu.zip" "$url"
	unzip -o -q "$tmp/wgpu.zip" -d "$VENDOR_DIR/wgpu/lib/$name"
fi
