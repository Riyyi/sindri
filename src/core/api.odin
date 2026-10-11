package core

import "sindri:base"

// -----------------------------------------
// Types

Game_API :: struct {
	settings:      proc() -> base.Settings,
	init_once:     proc(),
	init:          proc(),
	update:        proc(dt: f32),
	render:        proc(),
	destroy:       proc(),
	should_close:  proc() -> bool,
	force_reload:  proc() -> bool,
	force_restart: proc() -> bool,
}
