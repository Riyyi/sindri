package game

import "core:time"
import "core:fmt"

@(export)
hello :: proc() {
	fmt.println("hello from .dll!")
}

start := time.tick_now()

@(export)
should_close :: proc() -> bool {
	elapsed := time.tick_since(start)
	seconds := time.duration_seconds(elapsed)
	if seconds > 4 do return true

	return false
}
