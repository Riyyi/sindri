package platform

import "base:intrinsics"
import "core:c/libc"
import "core:fmt"

// -----------------------------------------
// Variables

// Read with atomic_load, safe across threads / interrupt contexts
quit_signal_received: bool

// -----------------------------------------
// Public functions

// Register signal handlers
signals_init :: proc() {
	// SIGINT = Interrupt, typically Ctrl+C
	if libc.signal(libc.SIGINT, signal_handler) ==
	   cast(proc "c" (_: i32))libc.SIG_ERR {
		fmt.eprintln("error: failed to register SIGINT handler")
	}

	// SIGTERM = Normal termination
	if libc.signal(libc.SIGTERM, signal_handler) ==
	   cast(proc "c" (_: i32))libc.SIG_ERR {
		fmt.eprintln("error: failed to register SIGTERM handler")
	}
}

// Restore default signal handlers
signals_destroy :: proc() {
	libc.signal(libc.SIGINT, cast(proc "c" (_: i32))libc.SIG_DFL)
	libc.signal(libc.SIGTERM, cast(proc "c" (_: i32))libc.SIG_DFL)
}

@(private = "file")
signal_handler :: proc "c" (sig: i32) {
	switch sig {
		case libc.SIGINT:
			fallthrough
		case libc.SIGTERM:
			intrinsics.atomic_store(&quit_signal_received, true)
		case:
			context = state.ctx
			panic("[signal] unhandled signal type")
	}
}
