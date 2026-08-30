#!/bin/sh

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
VENDOR_DIR="$SCRIPT_DIR/../vendor"

# ------------------------------------------
# Platform detection

# OS detection
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

# ------------------------------------------
# WGPU version detection

# Detect the wgpu-native version the bundled bindings expect, can be overridden
if [ "$1" != "" ]; then
	WGPU_VERSION="$1"
else
	WGPU_VERSION="v$(sed -n 's/.*BINDINGS_VERSION_STRING :: "\([^"]*\)".*/\1/p' "$(odin root)/vendor/wgpu/wgpu_native_types.odin")"
fi

if [ "$WGPU_VERSION" = "v" ]; then
	echo "wgpu setup: could not detect the wgpu-native version" >&2
	exit 1
fi

# Detect the version of the vendored wgpu bindings
current="v$(sed -n 's/.*BINDINGS_VERSION_STRING :: "\([^"]*\)".*/\1/p' "$VENDOR_DIR/wgpu/wgpu_native_types.odin" 2> /dev/null)"

# Check if the vendored wgpu is already up to date
if [ "$current" = "$WGPU_VERSION" ] && [ -d "$target" ]; then
	exit 0
fi

# ------------------------------------------
# Copy vendor/wgpu

# Remove any stale copy
rm -rf "$VENDOR_DIR/wgpu"

# Copy wgpu
wgpu_path="$(odin root)/vendor/wgpu"
cp -r "$wgpu_path" "$VENDOR_DIR"
chmod -R +w "$VENDOR_DIR/wgpu"

# Point imports at the copied vendor wgpu package
grep -rl '"vendor:wgpu"' "$VENDOR_DIR/wgpu" --include='*.odin' |
	while IFS= read -r file; do
		sed 's|"vendor:wgpu"|"wgpu:wgpu"|g' "$file" >"$file.tmp" && mv "$file.tmp" "$file"
	done

# ------------------------------------------
# Download

ASSET_BASE="https://github.com/gfx-rs/wgpu-native/releases/download/${WGPU_VERSION}"

# Download
if [ ! -d "$target" ]; then
	url="${ASSET_BASE}/${name}.zip"
	echo "wgpu setup: downloading $url"
	tmp=$(mktemp -d)
	trap 'rm -rf "$tmp"' EXIT
	curl -fL --retry 3 -o "$tmp/wgpu.zip" "$url"
	unzip -o -q "$tmp/wgpu.zip" -d "$target"
fi
