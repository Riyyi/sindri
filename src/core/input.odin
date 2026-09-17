package core

import "sindri:base"
import "sindri:platform"

// -----------------------------------------
// Public functions

// Returns the state of the keyboard key
key_state :: proc(key: base.Key) -> base.Action {
	return platform.os_key_state(key)
}

// Returns the state of the mouse button
mouse_button_state :: proc(button: base.Mouse_Button) -> base.Action {
	return platform.os_mouse_button_state(button)
}

// Returns the position of the mouse cursor
mouse_position :: proc() -> (x_pos: f32, y_pos: f32) {
	return platform.os_mouse_position()
}

// -----------------------------------------
// Private functions
