package chunks

import "base:runtime"
import "core:io"
import "core:mem"
import "core:os"

// -----------------------------------------

@(private)
read_header :: proc(
	r: ^Reader,
	chunk: ^os.File,
	allocator: runtime.Allocator,
) -> (
	err: Error,
) {
	chunk1_stream := os.to_stream(chunk)

	header_bytes := mem.ptr_to_bytes(&r.header)
	io.read_at(chunk1_stream, header_bytes, 0) or_return

	if r.header.magic_string != MAGIC_STRING || r.header.version != 1 {
		return .File_Not_A_Chunk
	}

	if r.header.compression != 0 {
		return Read_Error.Unimplemented
	}

	return nil
}

@(private)
read_asset_index :: proc(
	r: ^Reader,
	chunk: ^os.File,
	allocator := context.allocator,
) -> (
	err: Error,
) {
	chunk1_stream := os.to_stream(chunk)

	indices := make(
		[]Asset_Index,
		r.header.number_of_assets,
		allocator,
	) or_return
	index_bytes := mem.slice_to_bytes(indices)
	io.read_at(chunk1_stream, index_bytes, size_of(Header)) or_return

	r.indices = indices

	return nil
}
