package main

import "core:fmt"

VERSION :: #config(VERSION, "dev")

main :: proc() {
	fmt.println("Hellope!")
	fmt.println(VERSION)
}
