package tests

import "core:fmt"
import "core:os"
import "core:testing"

import "src:chunks"
import "src:file"

TEST_INPUT_DIR :: "./build/tests/in"
TEST_OUTPUT_DIR :: "./build/tests/out"

// -----------------------------------------

Test_State :: struct {
	input_dir:  string,
	output_dir: string,
}

// -----------------------------------------

test_state_init :: proc(
	t: ^testing.T,
	name: string,
	allocator := context.allocator,
) -> Test_State {
	ensure_dir(t, TEST_INPUT_DIR)
	ensure_dir(t, TEST_OUTPUT_DIR)

	// Use the test name as the pattern so parallel tests with the same
	// RNG seed generate distinct temp directory names.

	temp_input_path, err := os.mkdir_temp(TEST_INPUT_DIR, name, allocator)
	testing.expect(t, err == nil, os.error_string(err))

	temp_output_path, err2 := os.mkdir_temp(TEST_OUTPUT_DIR, name, allocator)
	testing.expect(t, err2 == nil, os.error_string(err2))

	return Test_State {
		input_dir = temp_input_path,
		output_dir = temp_output_path,
	}
}

test_state_destroy :: proc(
	ts: ^Test_State,
	t: ^testing.T,
	allocator := context.allocator,
) {
	if os.exists(ts.input_dir) {
		err := os.remove_all(ts.input_dir)
		testing.expect(t, err == nil, os.error_string(err))
	}
	delete(ts.input_dir, allocator)

	if os.exists(ts.output_dir) {
		err := os.remove_all(ts.output_dir)
		testing.expect(t, err == nil, os.error_string(err))
	}
	delete(ts.output_dir, allocator)
}

// -----------------------------------------

ensure_dir :: proc(t: ^testing.T, dir: string) {
	err := os.make_directory_all(dir)
	testing.expect(t, err == nil || err == .Exist, os.error_string(err)) // TOCTOU safe
}

create_file :: proc(
	ts: ^Test_State,
	t: ^testing.T,
	path: string,
	content: string,
	allocator := context.allocator,
) {
	relpath, err := os.join_path({ts.input_dir, path}, allocator)
	testing.expect(t, err == nil, os.error_string(err))
	defer delete(relpath, allocator)

	dir := os.dir(relpath)
	err2 := os.make_directory_all(dir)
	testing.expect(t, err2 == nil || err2 == .Exist, os.error_string(err2)) // TOCTOU safe

	file, err3 := os.create(relpath)
	testing.expect(t, err3 == nil, os.error_string(err3))
	defer os.close(file)

	_, err4 := os.write(file, transmute([]u8)content)
	testing.expect(t, err4 == nil, os.error_string(err4))
}

delete_path :: proc(
	ts: ^Test_State,
	t: ^testing.T,
	path: string,
	allocator := context.allocator,
) {
	relpath, err := os.join_path({ts.input_dir, path}, allocator)
	defer delete(relpath, allocator)
	testing.expect(t, err == nil, os.error_string(err))

	if os.exists(relpath) {
		err2 := os.remove_all(relpath)
		testing.expect(t, err2 == nil, os.error_string(err2))
	}
}

pack :: proc(ts: ^Test_State, t: ^testing.T, size: u64) {
	wd, err := os.get_working_directory(context.allocator)
	testing.expect(t, err == nil, os.error_string(err))
	entries, err2 := file.list_dir_recursive_by_path(ts.input_dir, wd)
	testing.expect(t, err2 == nil, file.format_error(err2))

	w := chunks.writer_init(cast(u64)len(entries))
	defer chunks.writer_destroy(&w)

	if os.exists(ts.output_dir) {
		err3 := os.remove_all(ts.output_dir)
		testing.expect(t, err3 == nil, os.error_string(err3))
	}

	err4 := os.make_directory_all(ts.output_dir) // fails if dir exists
	testing.expect(t, err4 == nil, os.error_string(err4))

	output_file, err5 := os.open(ts.output_dir, {.Read})
	testing.expect(t, err5 == nil, os.error_string(err5))
	defer os.close(output_file)

	err6 := chunks.write_assets(&w, output_file, entries[:], size, 0)
	testing.expect(t, err6 == nil, chunks.format_error(err6))

	err7 := chunks.write_metadata(&w, output_file, entries[:], size, 0)
	testing.expect(t, err7 == nil, chunks.format_error(err7))
}

read :: proc(
	ts: ^Test_State,
	t: ^testing.T,
	path: string,
	allocator := context.allocator,
) -> string {
	relpath, err := os.join_path({ts.input_dir, path}, allocator)
	testing.expect(t, err == nil, os.error_string(err))
	defer delete(relpath, allocator)

	file, err2 := os.open(ts.output_dir)
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
