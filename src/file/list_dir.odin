package file

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"

// -----------------------------------------

FileEntry :: struct #all_or_none {
	relpath: string, // NOTE: owning string
	size:    i64,
}

// -----------------------------------------

// Returning `[dynamic]DirectoryEntry` and each relpath `string` inside it are owned by the caller.
list_dir_recursive :: proc(
	f: ^os.File,
	working_dir: string,
	allocator := context.allocator,
) -> [dynamic]FileEntry {
	path := os.name(f)
	return list_dir_recursive_by_path_impl(path, working_dir, allocator)
}

// Returning `[dynamic]DirectoryEntry` and each relpath `string` inside it are owned by the caller.
list_dir_recursive_by_path :: proc(
	path: string,
	working_dir: string,
	allocator := context.allocator,
) -> [dynamic]FileEntry {
	return list_dir_recursive_by_path_impl(path, working_dir, allocator)
}

// Frees every owning relpath string then the dynamic array itself.
delete_entries :: proc(entries: ^[dynamic]FileEntry) {
	for entry in entries {
		delete(entry.relpath, entries.allocator)
	}
	delete(entries^)
}

@(private)
list_dir_recursive_by_path_impl :: proc(
	path: string,
	working_dir: string,
	allocator: runtime.Allocator,
) -> [dynamic]FileEntry {
	if !os.is_dir(path) {
		fmt.eprintln("error: path is not a directory:", path)
		os.exit(1)
	}

	result := make([dynamic]FileEntry, allocator)

	queue := make([dynamic]string, 0, 1, allocator) // reserve 1 slot
	defer delete(queue) // dynamic array embeds allocator
	append(&queue, strings.clone(path))

	for len(queue) > 0 {
		list_dir_queue(&queue, &result, working_dir, allocator)
	}

	return result // owning [dynamic]
}

@(private)
list_dir_queue :: proc(
	queue: ^[dynamic]string,
	result: ^[dynamic]FileEntry,
	working_dir: string,
	allocator: runtime.Allocator,
) {
	assert(len(queue) > 0, "queue must not be empty")

	path := pop(queue)
	defer delete(path, queue^.allocator)

	f, open_err := os.open(path, {.Read})
	if open_err != nil {
		fmt.eprintln("error: open failed:", open_err)
		os.exit(1)
	}
	defer os.close(f)

	entries, read_err := os.read_all_directory(f, allocator)
	if read_err != nil {
		fmt.eprintln("error: read directory failed:", read_err)
		os.exit(1)
	}
	defer os.file_info_slice_delete(entries, allocator)

	// Reserve space for new entries, minor waste as directories are also counted.
	reserve(result, len(result) + len(entries))

	for entry in entries {
		#partial switch entry.type {
		case os.File_Type.Directory:
			append(queue, strings.clone(entry.fullpath, queue^.allocator))
		case os.File_Type.Regular:
			{
				relpath, was_allocation := strings.replace(
					entry.fullpath,
					working_dir,
					".",
					1,
					result^.allocator,
				)
				if !was_allocation {
					relpath = strings.clone(relpath, result^.allocator)
				}
				append(result, FileEntry{relpath = relpath, size = entry.size})
			}
		case: // skip other types
		}
	}
}
