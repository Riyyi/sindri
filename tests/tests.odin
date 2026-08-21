package tests

import "core:strings"
import "core:testing"

@(test)
single_asset_single_chunk_read_from_path :: proc(t: ^testing.T) {
	// Arrange

	ts := test_state_init(t, #procedure)
	defer test_state_destroy(&ts, t)

	delete_path(&ts, t, "")
	create_file(&ts, t, "single_tiny_file", "hello world!")
	pack(&ts, t, 750)
	delete_path(&ts, t, "")
	create_file(&ts, t, "single_tiny_file", "hello world from path!")

	// Act

	_, read := read(&ts, t, "single_tiny_file")

	// Assert

	testing.expect_value(t, read, "hello world from path!")
}

@(test)
single_asset_single_chunk_read_from_chunk :: proc(t: ^testing.T) {
	// Arrange

	ts := test_state_init(t, #procedure)
	defer test_state_destroy(&ts, t)

	delete_path(&ts, t, "")
	create_file(&ts, t, "single_tiny_file", "hello world!")
	pack(&ts, t, 750)
	delete_path(&ts, t, "")

	// Act

	_, read := read(&ts, t, "single_tiny_file")

	// Assert

	testing.expect_value(t, read, "hello world!")
}

@(test)
single_asset_multiple_chunks_read_from_chunk :: proc(t: ^testing.T) {
	// Arrange

	ts := test_state_init(t, #procedure)
	defer test_state_destroy(&ts, t)

	delete_path(&ts, t, "")
	content := strings.repeat("abcde", 400)
	defer delete(content)
	create_file(&ts, t, "multi_chunk_file", content)
	pack(&ts, t, 750)
	delete_path(&ts, t, "")

	// Act

	_, read := read(&ts, t, "multi_chunk_file")

	// Assert

	testing.expect_value(t, read, content)
}

// -----------------------------------------

@(test)
multiple_assets_single_chunk_read_from_path :: proc(t: ^testing.T) {
	// Arrange

	ts := test_state_init(t, #procedure)
	defer test_state_destroy(&ts, t)

	delete_path(&ts, t, "")
	create_file(&ts, t, "a", "hello a!")
	create_file(&ts, t, "b", "hello b!")
	create_file(&ts, t, "c", "hello c!")
	pack(&ts, t, 1750)
	delete_path(&ts, t, "")
	create_file(&ts, t, "a", "hello a from path!")
	create_file(&ts, t, "b", "hello b from path!")
	create_file(&ts, t, "c", "hello c from path!")

	// Act

	_, a := read(&ts, t, "a")
	_, b := read(&ts, t, "b")
	_, c := read(&ts, t, "c")

	// Assert

	testing.expect_value(t, a, "hello a from path!")
	testing.expect_value(t, b, "hello b from path!")
	testing.expect_value(t, c, "hello c from path!")
}

@(test)
multiple_assets_single_chunk_read_from_chunk :: proc(t: ^testing.T) {
	// Arrange

	ts := test_state_init(t, #procedure)
	defer test_state_destroy(&ts, t)

	delete_path(&ts, t, "")
	create_file(&ts, t, "a", "hello a!")
	create_file(&ts, t, "b", "hello b!")
	create_file(&ts, t, "c", "hello c!")
	pack(&ts, t, 1750)
	delete_path(&ts, t, "")

	// Act

	_, a := read(&ts, t, "a")
	_, b := read(&ts, t, "b")
	_, c := read(&ts, t, "c")

	// Assert

	testing.expect_value(t, a, "hello a!")
	testing.expect_value(t, b, "hello b!")
	testing.expect_value(t, c, "hello c!")
}

@(test)
multiple_assets_multiple_chunks_read_from_chunk :: proc(t: ^testing.T) {
	// Arrange

	ts := test_state_init(t, #procedure)
	defer test_state_destroy(&ts, t)

	delete_path(&ts, t, "")
	content_a := strings.repeat("a", 700)
	defer delete(content_a)
	content_b := strings.repeat("b", 700)
	defer delete(content_b)
	content_c := strings.repeat("c", 700)
	defer delete(content_c)
	create_file(&ts, t, "a", content_a)
	create_file(&ts, t, "b", content_b)
	create_file(&ts, t, "c", content_c)
	pack(&ts, t, 1750)
	delete_path(&ts, t, "")

	// Act

	_, a := read(&ts, t, "a")
	_, b := read(&ts, t, "b")
	_, c := read(&ts, t, "c")

	// Assert

	testing.expect_value(t, a, content_a)
	testing.expect_value(t, b, content_b)
	testing.expect_value(t, c, content_c)
}

// -----------------------------------------

@(test)
single_asset_single_chunk_nested_path_read_from_path :: proc(t: ^testing.T) {
	// Arrange

	ts := test_state_init(t, #procedure)
	defer test_state_destroy(&ts, t)

	delete_path(&ts, t, "")
	create_file(&ts, t, "subdir/nested_file", "hello nested!")
	pack(&ts, t, 750)
	delete_path(&ts, t, "")
	create_file(&ts, t, "subdir/nested_file", "hello nested from path!")

	// Act

	_, read := read(&ts, t, "subdir/nested_file")

	// Assert

	testing.expect_value(t, read, "hello nested from path!")
}

@(test)
single_asset_single_chunk_nested_path_read_from_chunk :: proc(t: ^testing.T) {
	// Arrange

	ts := test_state_init(t, #procedure)
	defer test_state_destroy(&ts, t)

	delete_path(&ts, t, "")
	create_file(&ts, t, "subdir/nested_file", "hello nested!")
	pack(&ts, t, 750)
	delete_path(&ts, t, "")

	// Act

	_, read := read(&ts, t, "subdir/nested_file")

	// Assert

	testing.expect_value(t, read, "hello nested!")
}

@(test)
single_asset_multiple_chunks_nested_path_read_from_chunk :: proc(
	t: ^testing.T,
) {
	// Arrange

	ts := test_state_init(t, #procedure)
	defer test_state_destroy(&ts, t)

	delete_path(&ts, t, "")
	content := strings.repeat("abcde", 50)
	defer delete(content)
	create_file(&ts, t, "subdir/nested_file", content)
	pack(&ts, t, 750)
	delete_path(&ts, t, "")

	// Act

	_, read := read(&ts, t, "subdir/nested_file")

	// Assert

	testing.expect_value(t, read, content)
}

// -----------------------------------------

@(test)
asset_in_path_not_in_chunk_read_matching_file :: proc(t: ^testing.T) {
	// Arrange

	ts := test_state_init(t, #procedure)
	defer test_state_destroy(&ts, t)

	delete_path(&ts, t, "")
	create_file(&ts, t, "chunk", "hello from chunk!")
	pack(&ts, t, 750)
	delete_path(&ts, t, "")
	create_file(&ts, t, "target", "hello from path!")

	// Act

	_, read := read(&ts, t, "target")

	// Assert

	testing.expect_value(t, read, "hello from path!")
}

@(test)
asset_in_chunk_not_in_path_read_matching_file :: proc(t: ^testing.T) {
	// Arrange

	ts := test_state_init(t, #procedure)
	defer test_state_destroy(&ts, t)

	delete_path(&ts, t, "")
	create_file(&ts, t, "target", "hello from chunk!")
	pack(&ts, t, 750)
	delete_path(&ts, t, "")

	// Act

	_, read := read(&ts, t, "target")

	// Assert

	testing.expect_value(t, read, "hello from chunk!")
}

@(test)
asset_in_chunk_and_in_path_read_matching_file :: proc(t: ^testing.T) {
	// Arrange

	ts := test_state_init(t, #procedure)
	defer test_state_destroy(&ts, t)

	delete_path(&ts, t, "")
	create_file(&ts, t, "target", "hello from chunk!")
	pack(&ts, t, 750)
	delete_path(&ts, t, "")
	create_file(&ts, t, "target", "hello from path!")

	// Act

	_, read := read(&ts, t, "target")

	// Assert

	testing.expect_value(t, read, "hello from path!")
}

@(test)
asset_in_path_not_in_chunk_read_non_matching_file :: proc(t: ^testing.T) {
	// Arrange

	ts := test_state_init(t, #procedure)
	defer test_state_destroy(&ts, t)

	pack(&ts, t, 750)
	delete_path(&ts, t, "")
	create_file(&ts, t, "target", "hello from path!")

	// Act

	exists, _ := read(&ts, t, "non_matching")

	// Assert

	testing.expect(t, !exists)
}

@(test)
asset_in_chunk_not_in_path_read_non_matching_file :: proc(t: ^testing.T) {
	// Arrange

	ts := test_state_init(t, #procedure)
	defer test_state_destroy(&ts, t)

	delete_path(&ts, t, "")
	create_file(&ts, t, "target", "hello from chunk!")
	pack(&ts, t, 750)
	delete_path(&ts, t, "")

	// Act

	exists, _ := read(&ts, t, "non_matching")

	// Assert

	testing.expect(t, !exists)
}

@(test)
asset_in_chunk_and_in_path_read_non_matching_file :: proc(t: ^testing.T) {
	// Arrange

	ts := test_state_init(t, #procedure)
	defer test_state_destroy(&ts, t)

	delete_path(&ts, t, "")
	create_file(&ts, t, "target", "hello from chunk!")
	pack(&ts, t, 750)
	delete_path(&ts, t, "")
	create_file(&ts, t, "target", "hello from path!")

	// Act

	exists, _ := read(&ts, t, "non_matching")

	// Assert

	testing.expect(t, !exists)
}
