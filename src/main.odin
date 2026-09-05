package sindri

import "core:fmt"

VERSION :: #config(VERSION, "dev")

// -----------------------------------------

main :: proc() {
	fmt.println("hello world!")

	instance_init()
}
