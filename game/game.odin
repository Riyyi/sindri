package game

import "core:time"
import "core:fmt"

import "sindri:base"
import "sindri:core"

// -----------------------------------------

Game_Memory :: struct {
	should_close: bool,
}

g: ^Game_Memory

// -----------------------------------------

@(export)
memory :: proc() -> rawptr {
	return g
}

@(export)
memory_free :: proc() {
	free(g)
}

@(export)
memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
memory_set :: proc(mem: rawptr) {
	g = (^Game_Memory)(mem)

	// Here you can also set your own global variables. A good idea is to make
	// your global variables into pointers that point to something inside `g`.
}

@(export)
settings :: proc() -> base.Settings {
	return base.Settings {
		width = 960,
		height = 540,
		title = "WGPU Native Triangle",
		mode = base.WindowMode.Windowed,
		refresh = 60,
		vsync = true,
	}
}

@(export)
init_once :: proc() {
	fmt.println("init once")
}

@(export)
init :: proc() {
	fmt.println("hello from .dll!")

	g = new(Game_Memory)
	memory_set(g)
}

@(export)
update :: proc(dt: f32) {
	fmt.println("dt:", dt)

	if core.key_state(.Key_Escape) == .Press {
		g.should_close = true
	}
}

@(export)
destroy :: proc() {
	fmt.println("bye")
}

start := time.tick_now()

@(export)
should_close :: proc() -> bool {
	elapsed := time.tick_since(start)
	seconds := time.duration_seconds(elapsed)
	if seconds > 4 do return true

	return g.should_close
}

@(export)
force_reload :: proc() -> bool {
	return core.key_state(.Key_F5) == .Press
}

@(export)
force_restart :: proc() -> bool {
	return core.key_state(.Key_F6) == .Press
}
