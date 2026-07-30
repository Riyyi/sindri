#!/bin/sh

PROJECT="hello-world"
VERSION="dev-$(date -u '+%Y-%m-%d')-$(git rev-parse --short HEAD)"

if [[ $1 == "debug" ]]
then
    shift

    odin build src/ -show-timings -collection:src=src -out:$PROJECT -microarch:native -use-separate-modules -define:VERSION=$VERSION-debug -debug $@
    exit 0
fi

odin build src/ -show-timings -collection:src=src -out:$PROJECT -microarch:native -o:speed -define:VERSION=$VERSION $@
