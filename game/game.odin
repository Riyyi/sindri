package game

import "core:fmt"
import "core:time"

import "sindri:base"
import "sindri:core"

// -----------------------------------------
// Types

Game_Memory :: struct {
	should_close: bool,
}

Test_Memory :: struct {
	asd: int,
	qwe: int,
}

// -----------------------------------------
// Variables

g: Game_Memory
t: Test_Memory

game_api := core.Game_API {
	settings      = settings,
	init_once     = init_once,
	init          = init,
	update        = update,
	render        = render,
	destroy       = destroy,
	should_close  = should_close,
	force_reload  = force_reload,
	force_restart = force_restart,
}

// -----------------------------------------
// Public functions

api :: proc() -> ^core.Game_API {
	return &game_api
}

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

init_once :: proc() {
	fmt.println("init once")

	base.register_region("game_memory", &g, size_of(Game_Memory))
	base.register_region("test_memory", &t, size_of(Test_Memory))
}

init :: proc() {
	fmt.println("hello from .dll!")

	g.should_close = false
}

update :: proc(dt: f32) {
	fmt.println("dt:", dt)

	if core.key_state(.Key_Escape) == .Press {
		g.should_close = true
	}

	if core.key_state(.Key_F5) == .Press do t.asd = 555
	if core.key_state(.Key_F6) == .Press do t.asd = 666
}

render :: proc() {  }

destroy :: proc() {
	fmt.println("bye")

	fmt.println(t.asd, t.qwe)
}

start := time.tick_now()

should_close :: proc() -> bool {
	elapsed := time.tick_since(start)
	seconds := time.duration_seconds(elapsed)
	if seconds > 4 do return true

	return g.should_close
}

force_reload :: proc() -> bool {
	return core.key_state(.Key_F5) == .Press
}

force_restart :: proc() -> bool {
	return core.key_state(.Key_F6) == .Press
}
