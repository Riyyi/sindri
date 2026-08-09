package file

import "core:fmt"
import "core:os"

// -----------------------------------------

Error :: union #shared_nil {
	os.Error,
	File_Error,
}

File_Error :: enum u8 {
	None            = 0,
	Not_A_Directory = 1,
	Unimplemented   = 127,
	Okay            = None,
}

// -----------------------------------------

get_working_dir :: proc(allocator := context.allocator) -> (string, Error) {
	wd, err := os.get_working_directory(allocator)
	if err != nil {
		fmt.eprintln("error: get working directory failed:", err)
		return {}, err
	}

	return wd, nil
}
