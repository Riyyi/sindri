/*
 * Copyright (C) 2026 Riyyi
 *
 * SPDX-License-Identifier: MIT
 */

package core

// -----------------------------------------
// Types

// API for when the Game talks to the Engine.
Engine_API :: struct {
	assets: ^Assets,
	things: ^Things,
}

// API for when the Engine talks to the Game.
Game_API :: struct {
	register_api:    proc(api: ^Engine_API),
	register_memory: proc(),
	init_once:       proc(),
	init:            proc(),
	update:          proc(dt: f32),
	render:          proc(),
	destroy:         proc(),
	should_close:    proc() -> bool,
	force_reload:    proc() -> bool,
	force_restart:   proc() -> bool,
}
