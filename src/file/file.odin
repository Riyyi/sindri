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

file_error_strings := #sparse[File_Error]string { 	// enumerated array
	.None            = "",
	.Not_A_Directory = "path is not a directory",
	.Unimplemented   = "feature is unimplemented",
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

@(require_results)
format_error :: proc(ferr: Error) -> string {
	if ferr == nil do return ""

	switch e in ferr {
		case nil:
			return ""
		case os.Error:
			return fmt.tprintf("os: {}", e)
		case File_Error:
			return fmt.tprintf("file: {}", file_error_strings[e])
	}

	return "unknown error"
}
