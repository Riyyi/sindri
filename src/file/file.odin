package file

import "core:fmt"
import "core:os"

// TODO:
// - list files in directory
//   - get relative path
// - read file contents
// - write file contents

Asset :: struct {
	path: string,
	size: i64,
	data: []u8,
}

read :: proc(f: ^os.File) -> Asset {
	path := os.name(f)

	size, err := os.file_size(f)
	if err != nil {
		fmt.eprintln("error: failed to get file size:", err)
		os.exit(1)
	}

	data := make([]u8, size)

	n, read_err := os.read_full(f, data)
	if read_err != nil {
		fmt.eprintln("read failed:", read_err, "got", n, "of", size, "bytes")
		os.exit(1)
	}

	return Asset{path = path, size = size, data = data}
}
