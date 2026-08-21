package tests

import "core:testing"

@(test)
single_tiny_file_read_from_chunk :: proc(t: ^testing.T) {
	// Arrange

	ts := test_state_init(t, #procedure)
	defer test_state_destroy(&ts, t)

	delete_path(&ts, t, "")
	create_file(&ts, t, "single_tiny_file", "hello world!")
	pack(&ts, t, 750)
	delete_path(&ts, t, "")

	// Act

	read := read(&ts, t, "single_tiny_file")

	// Assert

	testing.expect_value(t, read, "hello world!")
}

@(test)
single_file_single_chunk_read_from_path :: proc(t: ^testing.T) {
	// Arrange

	ts := test_state_init(t, #procedure)
	defer test_state_destroy(&ts, t)

	delete_path(&ts, t, "")
	create_file(&ts, t, "single_tiny_file", "hello world!")
	pack(&ts, t, 750)
	delete_path(&ts, t, "")
	create_file(&ts, t, "single_tiny_file", "hello world from path!")

	// Act

	read := read(&ts, t, "single_tiny_file")

	// Assert

	testing.expect_value(t, read, "hello world from path!")
}

@(test)
multiple_files_single_chunk_read_from_chunk :: proc(t: ^testing.T) {
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

	a := read(&ts, t, "a")
	b := read(&ts, t, "b")
	c := read(&ts, t, "c")

	// Assert

	testing.expect_value(t, a, "hello a!")
	testing.expect_value(t, b, "hello b!")
	testing.expect_value(t, c, "hello c!")
}

@(test)
multiple_files_single_chunk_read_from_path :: proc(t: ^testing.T) {
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

	a := read(&ts, t, "a")
	b := read(&ts, t, "b")
	c := read(&ts, t, "c")

	// Assert

	testing.expect_value(t, a, "hello a from path!")
	testing.expect_value(t, b, "hello b from path!")
	testing.expect_value(t, c, "hello c from path!")
}

// @(test)
// blabla :: proc(t: ^testing.T) {
// 	// Arrange
//
// 	// Act
//
// 	// Assert
// }

// TODO:
// v multiple files (path and chunk find)
// - nested file    (path and chunk find)
// - not found in path
// - not found in path + chunk
