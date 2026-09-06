#!/bin/sh

set -eu

PROJECT="sindri"
VERSION="dev-$(date -u '+%Y-%m-%d')-$(git rev-parse --short HEAD)"

# ------------------------------------------

# Setup compiled wgpu binary
./scripts/wgpu-init.sh

# ------------------------------------------

mkdir -p build

# Game.dll
odin build game/ -show-timings \
    -collection:sindri=src \
    -build-mode:dynamic \
    -out:build/game -microarch:native -define:VERSION="$VERSION-debug" -debug "$@"

if [ "$1" = "debug" ]; then
    shift

    odin build src/ -show-timings \
        -collection:sindri=src \
        -collection:gram=vendor/gram/src \
        -collection:wgpu=vendor \
        -out:build/$PROJECT -microarch:native -use-separate-modules -define:VERSION="$VERSION-debug" -debug "$@"
    exit 0
fi

odin build src/ -show-timings \
    -collection:sindri=src \
    -collection:gram=vendor/gram/src \
    -collection:wgpu=vendor \
    -out:build/$PROJECT -microarch:native -o:speed -define:VERSION="$VERSION" "$@"
