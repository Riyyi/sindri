package chunks

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"

// -----------------------------------------

file_exists :: proc(
	r: ^Reader,
	path: string,
	allocator := context.allocator,
) -> (
	found: bool,
	index: u32,
	error: Error,
) {
	clean_path := os.clean_path(path, allocator) or_return
	for i in 0 ..< r.header.number_of_assets {
		str := string(r.indices[i].relpath[:])
		relpath := strings.trim_right_null(str)
		if clean_path == relpath do return true, i, nil
	}

	return false, 0, nil
}

// Returning `[]u8` is owned by the caller.
read_file :: proc(
	r: ^Reader,
	path: string,
	allocator := context.allocator,
) -> (
	bytes: []u8,
	err: Error,
) {
	clean_path := os.clean_path(path, allocator) or_return

	// Check filesystem first, so chunks can be overriden
	if os.exists(clean_path) {
		// Open file
		file := os.open(clean_path, {.Read}) or_return
		defer os.close(file)

		// Read
		file_size := os.file_size(file) or_return
		bytes = make([]u8, file_size, allocator)
		os.read(file, bytes) or_return

		return bytes, nil
	}

	// Check chunk
	if found, i := file_exists(r, clean_path) or_return; found {
		output_path := os.name(r.output)
		entry := r.indices[i]

		// Find correct chunk
		chunk_index := entry.offset / r.header.size_per_chunk

		// Find offset within this chunk
		chunk_offset := entry.offset % r.header.size_per_chunk

		bytes = make([]u8, entry.size, allocator)
		n_left: u64
		n_read: u64

		for entry.size > n_read {
			// Chunk path
			chunk_path := compute_chunk_path(
				output_path,
				cast(int)chunk_index,
				allocator,
			) or_return
			defer delete(chunk_path, allocator)

			// Open chunk
			file := os.open(chunk_path, {.Read}) or_return
			defer os.close(file)

			// Calculate how much of the current chunk should be read
			if entry.size > n_read + r.header.size_per_chunk - chunk_offset {
				n_left = r.header.size_per_chunk - chunk_offset
			} else {
				n_left = entry.size - n_read
			}

			// Read
			n_read += cast(u64)os.read_at(
				file,
				bytes[n_read:n_read + n_left],
				cast(i64)chunk_offset,
			) or_return

			// Overflow to next chunk
			chunk_index += 1
			chunk_offset = 0
		}

		return bytes, nil
	}

	fmt.eprintln("asset: ", clean_path)
	return nil, .Asset_Not_Exist
}
