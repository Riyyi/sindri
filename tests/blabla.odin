package tests

import "core:os"
import "core:testing"

import "src:file"

@(test)
single_tiny_file :: proc(t: ^testing.T) {
	// Arrange

	create_file(t, "single_tiny_file", "hello world!")

	// Act

	wd, err := os.get_working_directory(context.allocator)
	entries, err2 := file.list_dir_recursive_by_path(TEST_DIR, wd)
	pack(t, 750)
	delete_path(t, "")
	read := read(t, "single_tiny_file")

	// Assert

	testing.expect_value(t, read, "hello world!")
}
