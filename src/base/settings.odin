/*
 * Copyright (C) 2026 Riyyi
 *
 * SPDX-License-Identifier: MIT
 */

package base

// -----------------------------------------
// Types

Settings :: struct {
	// Window
	width:             u16,
	height:            u16,
	title:             string,
	mode:              WindowMode,
	refresh:           u16, // 0 = unlimited
	vsync:             bool,
	fov:               f32,
	// Input
	mouse_sensitivity: f32,
	mouse_captured:    bool,
	// TODO:
	// windowed resizable y/n
	// exit key (ex: escape)
}

WindowMode :: enum u8 {
	Windowed   = 0,
	Borderless = 1,
	Fullscreen = 2,
}

// -----------------------------------------
// Public functions

settings :: proc() -> Settings {
	return {
		// Window
		width             = 960,
		height            = 540,
		title             = "WGPU Native",
		mode              = WindowMode.Windowed,
		refresh           = 60,
		vsync             = true,
		fov               = 60,
		// Input
		mouse_sensitivity = 0.005,
		mouse_captured    = false,
	}
}
