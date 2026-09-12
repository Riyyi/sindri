package input

// -----------------------------------------
// Public functions

// Returns the state of the keyboard key
//   implementation in platform package, to prevent cyclic dependency
key_state: proc(key: Key) -> Action

// Returns the state of the mouse button
//   implementation in platform package, to prevent cyclic dependency
mouse_button_state: proc(button: Mouse_Button) -> Action

// -----------------------------------------
// Private functions
