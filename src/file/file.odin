package file

import "core:fmt"
import "core:os"

// -----------------------------------------

working_dir: string

// -----------------------------------------

store_working_dir :: proc(allocator := context.allocator) {
	wd, err := os.get_working_directory(allocator)
	if err != nil {
		fmt.eprintln("error: get working directory failed:", err)
		os.exit(1)
	}
	working_dir = wd
}

remove_working_dir :: proc(allocator := context.allocator) {
	if working_dir != "" {
		delete(working_dir, allocator)
		working_dir = ""
	}
}
