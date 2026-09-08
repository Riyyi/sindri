package event

import "core:fmt"
// -----------------------------------------

// event category, bitfield (?)

Event :: union {
	Window_Close_Event,
	Window_Resize_Event,
	Joystick_Connect_Event,
	Joystick_Disconnect_Event,
	Key_Press_Event,
	Key_Release_Event,
	Key_Repeat_Event,
	Mouse_Button_Press_Event,
	Mouse_Button_Release_Event,
	Mouse_Position_Event,
	Mouse_Scroll_Event,
}

Window_Close_Event :: struct {
	handled: bool,
}

Window_Resize_Event :: struct {
	handled: bool,
	width:   i32,
	height:  i32,
}

Joystick_Connect_Event :: struct {
	handled: bool,
	id:      i32,
}

Joystick_Disconnect_Event :: struct {
	handled: bool,
	id:      i32,
}

Key_Press_Event :: struct {
	handled: bool,
	key:     i32,
	mods:    i32,
}

Key_Release_Event :: struct {
	handled: bool,
	key:     i32,
	mods:    i32,
}

Key_Repeat_Event :: struct {
	handled: bool,
	key:     i32,
	mods:    i32,
}

Mouse_Button_Press_Event :: struct {
	handled: bool,
	button:  i32,
	mods:    i32,
}

Mouse_Button_Release_Event :: struct {
	handled: bool,
	button:  i32,
	mods:    i32,
}

Mouse_Position_Event :: struct {
	handled: bool,
	x_pos:   f32,
	y_pos:   f32,
}

Mouse_Scroll_Event :: struct {
	handled:  bool,
	x_offset: f32,
	y_offset: f32,
}

// -----------------------------------------

// Dispatcher(Event) -> forwards to the right function
on_event :: proc(event: Event) {
	fmt.println("toby!")

	#partial switch e in event {
		case Window_Close_Event:
			fmt.println("Close")
		case Window_Resize_Event:
			fmt.println("Resize:", e.width, e.height)

		case Key_Press_Event:
			fmt.println("Key press", e.key, e.mods)
		case Key_Release_Event:
			fmt.println("Key release", e.key, e.mods)
		case Key_Repeat_Event:
			fmt.println("Key repeat", e.key, e.mods)

		case Mouse_Button_Press_Event:
			fmt.println("Mouse press", e.button, e.mods)
		case Mouse_Button_Release_Event:
			fmt.println("Mouse release", e.button, e.mods)
		case Mouse_Position_Event:
			fmt.printfln("Mouse pos: {}x{}", e.x_pos, e.y_pos)

		case Joystick_Connect_Event:
			fmt.println("Joy con:", e.id)
		case Joystick_Disconnect_Event:
			fmt.println("Joy dis:", e.id)
	}
}
