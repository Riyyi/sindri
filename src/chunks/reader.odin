package chunks

import "base:runtime"
import "core:os"

// -----------------------------------------

Reader :: struct {
	output:  ^os.File,
	header:  Header,
	indices: []Asset_Index,
}

Read_Error :: enum u8 {
	None             = 0,
	File_Not_A_Chunk = 1,
	Asset_Not_Exist  = 2,
	Unimplemented    = 127,
	Okay             = None,
}

// -----------------------------------------

read_error_strings := #sparse[Read_Error]string { 	// enumerated array
	.None             = "",
	.File_Not_A_Chunk = "file is not a chunk file",
	.Asset_Not_Exist  = "asset does not exist",
	.Unimplemented    = "feature is unimplemented",
}

// -----------------------------------------

reader_init :: proc(
	output: ^os.File,
	allocator := context.allocator,
) -> (
	r: Reader,
	err: Error,
) {
	r.output = output

	output_path := os.name(output)

	// Chunk path
	chunk_path := compute_chunk_path(output_path, 0, allocator) or_return
	defer delete(chunk_path, allocator)

	// Chunk open
	chunk_file := os.open(chunk_path, {.Read}) or_return
	defer os.close(chunk_file)

	// Chunk read
	read_header(&r, chunk_file, allocator) or_return
	read_asset_index(&r, chunk_file, allocator) or_return

	return r, nil
}

reader_destroy :: proc(r: ^Reader) {
	delete(r.indices)
}
