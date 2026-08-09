package chunks

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:mem"
import "core:os"
import "core:strings"

// -----------------------------------------

Reader :: struct {}

Read_Error :: enum u8 {
	None             = 0,
	File_Not_A_Chunk = 1,
	File_Not_Exist   = 2,
	Unimplemented    = 127,
	Okay             = None,
}

// -----------------------------------------

read_header :: proc(
	chunk1: ^os.File,
	allocator := context.allocator,
) -> (
	Header,
	Error,
) {
	return read_header_impl(chunk1, allocator)
}

read_header_by_path :: proc(
	chunk1: string,
	allocator := context.allocator,
) -> (
	header: Header,
	err: Error,
) {
	chunk1_file := os.open(chunk1, {.Read}) or_return
	defer os.close(chunk1_file)

	return read_header_impl(chunk1_file, allocator)
}

@(private)
read_header_impl :: proc(
	chunk1: ^os.File,
	allocator: runtime.Allocator,
) -> (
	header: Header,
	err: Error,
) {
	chunk1_stream := os.to_stream(chunk1)

	header_bytes := mem.ptr_to_bytes(&header)
	io.read_at(chunk1_stream, header_bytes, 0) or_return

	if header.magic_string != MAGIC_STRING || header.version != 1 {
		return {}, .File_Not_A_Chunk
	}

	if header.compression != 0 {
		return {}, .Unimplemented
	}

	return header, nil
}

// Returning `[]Asset_Index` is owned by the caller.
read_asset_index :: proc(
	chunk1: ^os.File,
	header: Header,
	allocator := context.allocator,
) -> (
	indices: []Asset_Index,
	err: Error,
) {
	chunk1_stream := os.to_stream(chunk1)

	indices = make([]Asset_Index, header.number_of_assets, allocator) or_return
	index_bytes := mem.slice_to_bytes(indices)
	io.read_at(chunk1_stream, index_bytes, size_of(Header)) or_return

	return indices, nil
}

file_exists :: proc(
	header: Header,
	indices: []Asset_Index,
	path: string,
) -> (
	bool,
	u32,
) {
	for i in 0 ..< header.number_of_assets {
		str := string(indices[i].relpath[:])
		relpath := strings.trim_right_null(str)
		if path == relpath do return true, i
	}

	return false, 0
}

// Returning `[]u8` is owned by the caller.
read_file :: proc(
	header: Header,
	indices: []Asset_Index,
	output: ^os.File,
	path: string,
	allocator := context.allocator,
) -> (
	bytes: []u8,
	err: Error,
) {

	// Check filesystem first, so chunks can be overriden
	if os.exists(path) {
		// Open file
		fmt.println("searching:", path)
		file := os.open(path, {.Read}) or_return
		defer os.close(file)

		// Read
		file_size := os.file_size(file) or_return
		bytes = make([]u8, file_size, allocator)
		os.read(file, bytes) or_return

		return bytes, nil
	}

	// Check chunk
	if found, i := file_exists(header, indices, path); found {
		output_path := os.name(output)
		entry := indices[i]

		// Find correct chunk
		chunk_index := entry.offset / header.size_per_chunk

		// Find offset within this chunk
		chunk_offset := entry.offset % header.size_per_chunk

		bytes = make([]u8, entry.size, allocator)
		n_left: u64
		n_read: u64

		for entry.size > n_read {
			// Chunk path
			chunk_path := compute_chunk_path(
				output_path,
				cast(int)chunk_index,
				allocator,
			)
			defer delete(chunk_path, allocator)

			// Open chunk
			file := os.open(chunk_path, {.Read}) or_return
			defer os.close(file)

			// Calculate how much of the current chunk should be read
			if entry.size > n_read + header.size_per_chunk - chunk_offset {
				n_left = header.size_per_chunk - chunk_offset
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

	return nil, .File_Not_Exist
}
