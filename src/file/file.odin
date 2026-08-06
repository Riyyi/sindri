package file

import "core:fmt"
import "core:os"

// -----------------------------------------

get_working_dir :: proc(allocator := context.allocator) -> string {
	wd, err := os.get_working_directory(allocator)
	if err != nil {
		fmt.eprintln("error: get working directory failed:", err)
		os.exit(1)
	}

	return wd
}
