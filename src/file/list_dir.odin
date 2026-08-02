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

list_dir_recursive :: proc(f: ^os.File) -> [dynamic]DirectoryEntry {
	path := os.name(f)
	return list_dir_recursive_by_path_impl(path)
}

list_dir_recursive_by_path :: proc(path: string) -> [dynamic]DirectoryEntry {
	return list_dir_recursive_by_path_impl(path)
}

@(private)
list_dir_recursive_by_path_impl :: proc(
	path: string,
) -> [dynamic]DirectoryEntry {
	if !os.is_dir(path) {
		fmt.eprintln("error: path is not a directory:", path)
		os.exit(1)
	}

	result := [dynamic]DirectoryEntry{}

	queue := [dynamic]string{}
	append(&queue, path)

	for len(queue) > 0 {
		list_dir_queue(&queue, &result)
	}

	shrink(&result, len(result)) // shrink to fit
	return result
}

@(private)
list_dir_queue :: proc(
	queue: ^[dynamic]string,
	result: ^[dynamic]DirectoryEntry,
) {
	assert(len(queue) > 0, "queue must not be empty")

	path := pop(queue)

	f, open_err := os.open(path, {.Read})
	if open_err != nil {
		fmt.eprintln("error: open failed:", open_err)
		os.exit(1)
	}
	defer os.close(f)

	entries, read_err := os.read_all_directory(f, context.allocator)
	if read_err != nil {
		fmt.eprintln("error: read directory failed:", read_err)
		os.exit(1)
	}
	defer delete(entries)

	// Reserve space for new entries
	reserve(result, cap(result) + len(entries))

	working_dir, wd_err := os.get_working_directory(context.allocator)
	if wd_err != nil {
		fmt.eprintln("error: get working directory failed:", wd_err)
		os.exit(1)
	}
	defer delete(working_dir)

	for entry, i in entries {

		if entry.type == os.File_Type.Directory {
			append(queue, entry.fullpath)
		}

		if entry.type == os.File_Type.Regular {
			relpath, rel_err := strings.replace(
				entry.fullpath,
				working_dir,
				".",
				1,
				context.allocator,
			)
			append(
				result,
				DirectoryEntry{relpath = relpath, size = entry.size},
			)
		}
	}
}
