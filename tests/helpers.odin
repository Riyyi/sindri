package tests

import "core:os"
import "core:testing"

import "src:chunks"
import "src:file"

TEST_DIR :: "./build/tests"
TEST_OUTPUT_DIR :: "./build/out"

// -----------------------------------------

create_file :: proc(
	t: ^testing.T,
	path: string,
	content: string,
	allocator := context.allocator,
) {
	relpath, err := os.join_path({TEST_DIR, path}, allocator)
	testing.expect(t, err == nil, os.error_string(err))
	defer delete(relpath, allocator)

	dir := os.dir(relpath)
	if !os.exists(dir) {
		err2 := os.make_directory_all(dir)
		testing.expect(t, err2 == nil, os.error_string(err2))
	}

	file, err3 := os.create(relpath)
	testing.expect(t, err3 == nil, os.error_string(err3))
	defer os.close(file)

	_, err4 := os.write(file, transmute([]u8)content)
	testing.expect(t, err4 == nil, os.error_string(err4))
}

delete_path :: proc(
	t: ^testing.T,
	path: string,
	allocator := context.allocator,
) {
	relpath, err := os.join_path({TEST_DIR, path}, allocator)
	defer delete(relpath, allocator)
	testing.expect(t, err == nil, os.error_string(err))

	err2 := os.remove_all(relpath)
	testing.expect(t, err2 == nil, os.error_string(err2))
}

pack :: proc(t: ^testing.T, size: u64) {
	wd, err := os.get_working_directory(context.allocator)
	testing.expect(t, err == nil, os.error_string(err))
	entries, err2 := file.list_dir_recursive_by_path(TEST_DIR, wd)
	testing.expect(t, err2 == nil, file.format_error(err2))

	w := chunks.writer_init(cast(u64)len(entries))
	defer chunks.writer_destroy(&w)

	if os.exists(TEST_OUTPUT_DIR) {
		err3 := os.remove_all(TEST_OUTPUT_DIR)
		testing.expect(t, err3 == nil, os.error_string(err3))
	}

	err4 := os.make_directory_all(TEST_OUTPUT_DIR) // fails if dir exists
	testing.expect(t, err4 == nil, os.error_string(err4))

	output_file, err5 := os.open(TEST_OUTPUT_DIR, {.Read})
	testing.expect(t, err5 == nil, os.error_string(err5))
	defer os.close(output_file)

	err6 := chunks.write_assets(&w, output_file, entries[:], size, 0)
	testing.expect(t, err6 == nil, chunks.format_error(err6))

	err7 := chunks.write_metadata(&w, output_file, entries[:], size, 0)
	testing.expect(t, err7 == nil, chunks.format_error(err7))
}

read :: proc(
	t: ^testing.T,
	path: string,
	allocator := context.allocator,
) -> string {
	relpath, err := os.join_path({TEST_DIR, path}, allocator)
	testing.expect(t, err == nil, os.error_string(err))
	defer delete(relpath, allocator)

	file, err2 := os.open(TEST_OUTPUT_DIR)
	testing.expect(t, err2 == nil, os.error_string(err2))
	defer os.close(file)

	r, err3 := chunks.reader_init(file)
	testing.expect(t, err3 == nil, chunks.format_error(err3))
	defer chunks.reader_destroy(&r)

	exists, i, err4 := chunks.file_exists(&r, relpath)
	testing.expect(t, exists)
	testing.expect(t, err4 == nil, chunks.format_error(err4))

	bytes, err5 := chunks.read_file(&r, relpath)
	testing.expect(t, err5 == nil, chunks.format_error(err5))

	return string(bytes)
}
