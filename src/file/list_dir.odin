package file

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"

// -----------------------------------------

File_Entry :: struct #all_or_none {
	relpath: string, // NOTE: owning string
	size:    i64,
}

// -----------------------------------------

// Returning `[dynamic]File_Entry` and each relpath `string` inside it are owned by the caller.
list_dir_recursive :: proc(
	f: ^os.File,
	working_dir: string,
	allocator := context.allocator,
) -> (
	entries: [dynamic]File_Entry,
	err: Error,
) {
	path := os.name(f)
	result := list_dir_recursive_by_path_impl(
		path,
		working_dir,
		allocator,
	) or_return
	return result, nil
}

// Returning `[dynamic]File_Entry` and each relpath `string` inside it are owned by the caller.
list_dir_recursive_by_path :: proc(
	path: string,
	working_dir: string,
	allocator := context.allocator,
) -> (
	entries: [dynamic]File_Entry,
	err: Error,
) {
	result := list_dir_recursive_by_path_impl(
		path,
		working_dir,
		allocator,
	) or_return
	return result, nil
}

// Frees every owning relpath string then the dynamic array itself.
delete_entries :: proc(entries: ^[dynamic]File_Entry) {
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
) -> (
	[dynamic]File_Entry,
	Error,
) {
	if !os.is_dir(path) {
		fmt.eprintln("path:", path)
		return {}, .Not_A_Directory
	}

	result := make([dynamic]File_Entry, allocator)

	queue := make([dynamic]string, 0, 1, allocator) // reserve 1 slot
	defer delete(queue) // dynamic array embeds allocator
	append(&queue, strings.clone(path))

	for len(queue) > 0 {
		list_dir_queue(&queue, &result, working_dir, allocator)
	}

	return result, nil // owning [dynamic]
}

@(private)
list_dir_queue :: proc(
	queue: ^[dynamic]string,
	result: ^[dynamic]File_Entry,
	working_dir: string,
	allocator: runtime.Allocator,
) -> Error {
	assert(len(queue) > 0, "queue must not be empty")

	path := pop(queue)
	defer delete(path, queue^.allocator)

	f := os.open(path, {.Read}) or_return
	defer os.close(f)

	entries := os.read_all_directory(f, allocator) or_return
	defer os.file_info_slice_delete(entries, allocator)

	// Reserve space for new entries, minor waste as directories are also counted.
	reserve(result, len(result) + len(entries))

	for entry in entries {
		#partial switch entry.type {
			case os.File_Type.Directory:
				append(queue, strings.clone(entry.fullpath, queue^.allocator))
			case os.File_Type.Regular:
				{
					relpath_dirty, was_allocation := strings.replace(
						entry.fullpath,
						working_dir,
						".",
						1,
						result^.allocator,
					)
					// Remove unneeded references to the current or parent directory (./).
					relpath := os.clean_path(
						relpath_dirty,
						result^.allocator,
					) or_return
					append(
						result,
						File_Entry{relpath = relpath, size = entry.size},
					)
					if was_allocation {
						delete(relpath_dirty, result^.allocator)
					}
				}
			case: // skip other types
		}
	}

	return nil
}
