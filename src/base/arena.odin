/*
 * Copyright (C) 2026 Riyyi
 *
 * SPDX-License-Identifier: MIT
 */

package base

import "base:runtime"
import "core:fmt"
import "core:mem"
import vmem "core:mem/virtual"
import "core:os"
import "core:path/filepath"
import "core:time"

ARENA_LOG_FILE :: "arena_log.json"

// -----------------------------------------
// Types

Arena :: struct {
	arena: vmem.Arena,
}

Arena_Log_Entry_Kind :: enum u8 {
	Push,
	Pop,
	Clear,
}

// -----------------------------------------
// Variables

@(private = "file")
arena_log: ^os.File

@(private = "file")
arena_log_count: uint

// -----------------------------------------
// Constructor/destructor

arena_init_buffer :: proc(buffer: []u8) -> Arena {
	arena_create_log()

	arena: vmem.Arena
	err := vmem.arena_init_buffer(&arena, buffer)
	fmt.ensuref(err == nil, "[arena] failed to init arena")
	return {arena = arena}
}

arena_init_growing :: proc(
	reserved: uint = vmem.DEFAULT_ARENA_GROWING_MINIMUM_BLOCK_SIZE,
) -> Arena {
	arena_create_log()

	arena: vmem.Arena
	err := vmem.arena_init_growing(&arena, reserved)
	fmt.ensuref(err == nil, "[arena] failed to init arena")
	return {arena = arena}
}

arena_init_static :: proc(
	reserved: uint = vmem.DEFAULT_ARENA_STATIC_RESERVE_SIZE,
	commit_size: uint = vmem.DEFAULT_ARENA_STATIC_COMMIT_SIZE,
) -> Arena {
	arena_create_log()

	arena: vmem.Arena
	err := vmem.arena_init_static(&arena, reserved, commit_size)
	fmt.ensuref(err == nil, "[arena] failt to init arena")
	return {arena = arena}
}

arena_destroy :: proc(arena: ^Arena) {
	arena_destroy_log()

	assert(arena != nil)
	vmem.arena_destroy(&arena.arena)
}

// -----------------------------------------
// Public functions

// Allocates memory from the provided arena.
arena_alloc :: proc(
	arena: ^Arena,
	size: uint,
	alignment: uint,
	loc := #caller_location,
) -> (
	data: []u8,
	err: runtime.Allocator_Error,
) {
	arena_write_log(arena, arena_log, .Push, cast(u64)size, loc)
	data = vmem.arena_alloc(&arena.arena, size, alignment, loc) or_return
	return data, nil
}

// Create an `Allocator` from the provided `Arena`
arena_allocator :: proc(arena: ^Arena) -> mem.Allocator {
	return mem.Allocator{arena_allocator_proc, arena}
}

// The allocator procedure used by an `Allocator` produced by `arena_allocator`
arena_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	data: []byte,
	err: vmem.Allocator_Error,
) {
	arena := cast(^Arena)allocator_data

	switch mode {
		case .Alloc, .Alloc_Non_Zeroed:
			arena_write_log(arena, arena_log, .Push, cast(u64)size, loc)
		case .Free:
		// Not implemented in arena
		case .Free_All:
			arena_write_log(
				arena,
				arena_log,
				.Clear,
				cast(u64)arena.arena.total_used,
				loc,
			)
		case .Resize, .Resize_Non_Zeroed:
			switch {
				case old_memory == nil:
					arena_write_log(
						arena,
						arena_log,
						.Push,
						cast(u64)size,
						loc,
					)
				case size == old_size:
				// No-op
				case size == 0:
				// Not implemented in arena
				case size > old_size:
					arena_write_log(
						arena,
						arena_log,
						.Push,
						cast(u64)(size - old_size),
						loc,
					)
				case size < old_size:
					arena_write_log(
						arena,
						arena_log,
						.Pop,
						cast(u64)(old_size - size),
						loc,
					)
			}

		case .Query_Features:
		// No state change
		case .Query_Info:
		// Not implemented in arena
	}

	return vmem.arena_allocator_proc(
		&arena.arena,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		loc,
	)
}

// Deallocates all but the first memory block of the arena and resets the allocator's usage to 0.
arena_free_all :: proc(arena: ^Arena, loc := #caller_location) {
	arena_write_log(
		arena,
		arena_log,
		.Clear,
		cast(u64)arena.arena.total_used,
		loc,
	)
	vmem.arena_free_all(&arena.arena, loc)
}

// Resets the memory of a Static or Buffer arena to a specific `position` (offset) and zeroes the previously used memory.
arena_static_reset_to :: proc(
	arena: ^Arena,
	pos: uint,
	loc := #caller_location,
) -> bool {
	arena_write_log(
		arena,
		arena_log,
		.Pop,
		cast(u64)(arena.arena.total_used - pos),
		loc,
	)
	result := vmem.arena_static_reset_to(&arena.arena, pos, loc)
	return result
}

@(private = "file")
arena_write_log :: proc(
	arena: ^Arena,
	file: ^os.File,
	kind: Arena_Log_Entry_Kind,
	size: u64,
	loc := #caller_location,
) {
	if arena_log == nil do return

	time := time.now()
	pos := cast(u64)arena.arena.total_used

	if arena_log_count > 0 {
		os.write_string(file, ",\n")
	}
	arena_log_count += 1

	os.write_string(
		file,
		fmt.tprintf(
			"  {{" +
			"\"id\": \"%p\", " +
			"\"kind\": \"%v\", " +
			"\"time\": \"%v\", " +
			"\"loc\": \"%v %v\", " +
			"\"pos\": %d, " +
			"\"size\": %d" +
			"}}",
			arena,
			kind,
			time,
			loc,
			loc.procedure,
			pos,
			size,
		),
	)
}

// -----------------------------------------
// Private functions

@(private = "file")
arena_create_log :: proc() {
	if arena_log != nil do return

	out, exec_err := os.get_executable_directory(context.temp_allocator)
	if exec_err != nil {
		fmt.eprintf("[arena] failed to get exec path")
		return
	}

	arena_log_file_path, join_err := filepath.join(
		{out, ARENA_LOG_FILE},
		context.temp_allocator,
	)
	if join_err != .None {
		fmt.eprintln("[arena] failed to construct log path")
		return
	}

	file, create_err := os.create(arena_log_file_path)
	if create_err != nil {
		fmt.eprintf("[arena] failed to create log file")
		return
	}

	os.write_string(file, fmt.tprintln("["))

	arena_log = file
}

@(private = "file")
arena_destroy_log :: proc() {
	if arena_log == nil do return

	os.write_string(arena_log, fmt.tprintln("\n]"))
	os.close(arena_log)
	arena_log = nil
}
