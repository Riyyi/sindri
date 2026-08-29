#!/bin/sh

set -e

PROJECT="sindri"
VERSION="dev-$(date -u '+%Y-%m-%d')-$(git rev-parse --short HEAD)"
WGPU_VERSION="v29.0.1.1"

# ------------------------------------------

# Setup compiled wgpu binary
./scripts/wgpu-init.sh "$WGPU_VERSION"

# ------------------------------------------

mkdir -p build

if [ "$1" = "debug" ]; then
    shift

    odin build src/ -show-timings -collection:sindri=src -collection:gram=vendor/gram/src -out:build/$PROJECT -microarch:native -use-separate-modules -define:VERSION="$VERSION-debug" -debug "$@"
    exit 0
fi

odin build src/ -show-timings -collection:sindri=src -collection:gram=vendor/gram/src -out:build/$PROJECT -microarch:native -o:speed -define:VERSION="$VERSION" "$@"
