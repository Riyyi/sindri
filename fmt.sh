#!/bin/sh

set -e

odinfmt -w src/ > /dev/null
odinfmt -w tests/ > /dev/null
