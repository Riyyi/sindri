package file

import "core:fmt"
import "core:os"
import "core:strings"

// -----------------------------------------

Asset :: struct #all_or_none {
	relpath: string,
	size:    i64,
	data:    []u8,
}

// -----------------------------------------

read_by_path :: proc(path: string) -> []u8 {
	f, open_err := os.open(path, {.Read})
	if open_err != nil {
		fmt.eprintln("error: open failed:", open_err)
		os.exit(1)
	}
	defer os.close(f)

	if !os.is_file(path) {
		fmt.eprintln("error: path is not a file:", path)
		os.exit(1)
	}

	path := path // shadow parameter
	path = strings.clone(path)

	size, size_err := os.file_size(f)
	if size_err != nil {
		fmt.eprintln("error: get file size failed:", size_err)
		os.exit(1)
	}

	data := make([]u8, size)

	n, read_err := os.read_full(f, data)
	if read_err != nil {
		delete(data)
		fmt.eprintln(
			"error: file read failed:",
			read_err,
			"got",
			n,
			"of",
			size,
			"bytes",
		)
		os.exit(1)
	}

	return data
}

get_asset_by_path :: proc(path: string) -> Asset {
	data := read_by_path(path)
	return Asset{relpath = path, size = cast(i64)len(data), data = data}
}
