package main

import "core:fmt"

import "src:cli"
import "src:file"

VERSION :: #config(VERSION, "dev")

main :: proc() {
	opts := cli.parse()

	fmt.println("verbose:", opts.verbose)
	fmt.println("compression:", opts.compression)
	fmt.println("size:", opts.size)

	asset := file.read("./odinfmt.json")
	fmt.println("path:", asset.path)
	fmt.println("size:", asset.size)
	fmt.println("data:", asset.data)
}
