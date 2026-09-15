package input

// -----------------------------------------
// Proc types, used to pass implementations across binary boundaries
// (e.g. into the hot-reloaded game dll)

Key_State_Proc :: proc(key: Key) -> Action
Mouse_Button_State_Proc :: proc(button: Mouse_Button) -> Action
Mouse_Position_Proc :: proc() -> (x_pos: f32, y_pos: f32)

// -----------------------------------------
// Public functions

// Returns the state of the keyboard key
//   implementation in platform package, to prevent cyclic dependency
key_state: proc(key: Key) -> Action

// Returns the state of the mouse button
//   implementation in platform package, to prevent cyclic dependency
mouse_button_state: proc(button: Mouse_Button) -> Action

// Returns the position of the mouse cursor
//   implementation in platform package, to prevent cyclic dependency
mouse_position: proc() -> (x_pos: f32, y_pos: f32)

// -----------------------------------------
// Private functions
