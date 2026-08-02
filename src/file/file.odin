package file

import "core:fmt"
import "core:os"
import "core:strings"

// TODO:
// - list files in directory
//   - get relative path
// - read file contents
// - write file contents

// -----------------------------------------

Asset :: struct #all_or_none {
	relpath: string,
	size: i64,
	data: []u8,
}

DirectoryEntry :: struct #all_or_none {
	relpath: string,
	size: i64,
}

// -----------------------------------------

list_dir_by_path :: proc(path: string) -> []DirectoryEntry {
	if !os.is_dir(path) {
		fmt.eprintln("error: path is not a directory:", path)
		os.exit(1)
	}

	f, open_err := os.open(path, {.Read})
	if open_err != nil {
		fmt.eprintln("error: open failed:", open_err)
		os.exit(1)
	}
	defer os.close(f)

	return list_dir_impl(f)
}

list_dir :: proc(f: ^os.File) -> []DirectoryEntry {
	path := os.name(f)
	if !os.is_dir(path) {
		fmt.eprintln("error: path is not a directory:", path)
		os.exit(1)
	}

	return list_dir_impl(f)
}

@(private)
list_dir_impl :: proc(f: ^os.File) -> []DirectoryEntry {
	entries, read_err := os.read_all_directory(f, context.allocator)
	if read_err != nil {
		fmt.eprintln("error: read directory failed:", read_err)
		os.exit(1)
	}
	defer delete(entries)

	working_dir, wd_err := os.get_working_directory(context.allocator)
	if wd_err != nil {
		fmt.eprintln("error: get working directory failed:", wd_err)
		os.exit(1)
	}
	defer delete(working_dir)

	result := make([]DirectoryEntry, len(entries))
	for entry, i in entries {
		relpath, rel_err := strings.replace(
			entry.fullpath,
			working_dir,
			".",
			1,
			context.allocator,
		)
		result[i] = DirectoryEntry{relpath = relpath, size = entry.size}
	}

	return result
}

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
