package file

import "core:fmt"
import "core:os"
import "core:strings"

// TODO:
// - list files in directory
//   - get relative path
// - read file contents
// - write file contents

Asset :: struct #all_or_none {
	path: string,
	size: i64,
	data: []u8,
}

read :: proc(path: string) -> Asset {
	f, open_err := os.open(path, {.Read})
	if open_err != nil {
		fmt.eprintln("error: open file failed:", open_err)
		os.exit(1)
	}
	defer os.close(f)

	path := strings.clone(os.name(f))

	size, size_err := os.file_size(f)
	if size_err != nil {
		fmt.eprintln("error: get file size failed:", size_err)
		os.exit(1)
	}

	data := make([]u8, size)

	n, read_err := os.read_full(f, data)
	if read_err != nil {
		delete(data)
		fmt.eprintln("error: file read failed:", read_err, "got", n, "of", size, "bytes")
		os.exit(1)
	}

	return Asset{path = path, size = size, data = data}
}
