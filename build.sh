#!/bin/sh

set -eu

cd -- "$(dirname -- "$0")"

if [ ! -x ./build ]; then
	odin build compile/build.odin -file -out:build
fi

./build "$@"

cd - > /dev/null
