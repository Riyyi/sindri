package file

import "core:fmt"
import "core:os"
import "core:strings"

// -----------------------------------------

DirectoryEntry :: struct #all_or_none {
	relpath: string,
	size:    i64,
}

// -----------------------------------------

list_dir_by_path :: proc(path: string) -> [dynamic]DirectoryEntry {
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

	result := [dynamic]DirectoryEntry{}
	list_dir_impl(f, &result)
	return result
}

list_dir :: proc(f: ^os.File) -> [dynamic]DirectoryEntry {
	path := os.name(f)
	if !os.is_dir(path) {
		fmt.eprintln("error: path is not a directory:", path)
		os.exit(1)
	}

	result := [dynamic]DirectoryEntry{}
	list_dir_impl(f, &result)
	return result
}

@(private)
list_dir_impl :: proc(f: ^os.File, builder: ^[dynamic]DirectoryEntry) {
	entries, read_err := os.read_all_directory(f, context.allocator)
	if read_err != nil {
		fmt.eprintln("error: read directory failed:", read_err)
		os.exit(1)
	}
	defer delete(entries)

	// Reserve space for new entries
	reserve(builder, cap(builder) + len(entries))

	working_dir, wd_err := os.get_working_directory(context.allocator)
	if wd_err != nil {
		fmt.eprintln("error: get working directory failed:", wd_err)
		os.exit(1)
	}
	defer delete(working_dir)

	for entry, i in entries {

		if entry.type == os.File_Type.Regular {
			relpath, rel_err := strings.replace(
				entry.fullpath,
				working_dir,
				".",
				1,
				context.allocator,
			)
			append(
				builder,
				DirectoryEntry{relpath = relpath, size = entry.size},
			)
		}

		if entry.type == os.File_Type.Directory {
			dir, dir_err := os.open(entry.fullpath, {.Read})
			if dir_err != nil {
				fmt.eprintln("error: open directory failed:", dir_err)
				os.exit(1)
			}
			defer os.close(dir)
			list_dir_impl(dir, builder) // recurse into directory
		}
	}
}
