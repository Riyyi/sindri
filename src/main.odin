package main

import "core:fmt"

import "src:cli"

VERSION :: #config(VERSION, "dev")

main :: proc() {
	opts := cli.parse()

	fmt.println("verbose:", opts.verbose)
	fmt.println("compression:", opts.compression)
	fmt.println("size:", opts.size)
}
