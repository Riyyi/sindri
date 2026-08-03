#!/bin/sh

mkdir -p build

odin test tests/ -collection:src=src -out:build/tests.bin \
	-define:ODIN_TEST_THREADS=1 \
	-define:ODIN_TEST_TRACK_MEMORY=false \
	-define:ODIN_TEST_RANDOM_SEED=1 \
	"$@"
