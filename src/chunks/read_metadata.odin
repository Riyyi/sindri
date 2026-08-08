package chunks

import "base:runtime"
import "core:io"
import "core:mem"
import "core:os"

// -----------------------------------------

Reader :: struct {}

Read_Error :: enum u8 {
	None             = 0,
	File_Not_A_Chunk = 1,
	Unimplemented    = 127,
	Okay             = None,
}

// -----------------------------------------

// read header
// file_exists() func
// read_file() -> check chunks -> check fs -> fail

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
