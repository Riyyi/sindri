package sindri

import "core:fmt"
import "core:strings"
import "vendor:glfw"

import "wgpu:wgpu"
import "wgpu:wgpu/glfwglue"

import "sindri:core"
import "sindri:event"

// -----------------------------------------
// Types

OS :: struct {
	window: glfw.WindowHandle,
}

// -----------------------------------------
// Constructor / destructor

os_init :: proc(settings: core.Settings) {
	if !glfw.Init() {
		panic("[glfw] init failure")
	}

	// Set window properties
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API) // do not create OpenGL context
	glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)

	// Create GLFW window
	state.os.window = glfw.CreateWindow(
		i32(settings.width),
		i32(settings.height),
		strings.unsafe_string_to_cstring(settings.title),
		nil,
		nil,
	)

	glfw.SetErrorCallback(error_callback)
	glfw.SetWindowCloseCallback(state.os.window, window_close_callback)
	// NOTE: SetFramebufferSize over SetWindowSize, to handle different DPIs
	glfw.SetFramebufferSizeCallback(state.os.window, size_callback)
	glfw.SetKeyCallback(state.os.window, key_callback)
	glfw.SetMouseButtonCallback(state.os.window, mouse_button_callback)
	glfw.SetCursorPosCallback(state.os.window, cursor_pos_callback)
	glfw.SetScrollCallback(state.os.window, scroll_callback)
	glfw.SetJoystickCallback(joystick_callback)

	// TODO: Figure out proper vsync, found 3 spots so far
	// - glfw.SwapInterval(0) this is only for OpenGL it seems?
	// - glfw.SetWindowMonitor(refresh)
	// - wgpu presentMode = .Fifo
}

os_destroy :: proc() {
	glfw.DestroyWindow(state.os.window)
	glfw.Terminate()
}

// -----------------------------------------
// Public functions

os_set_monitor :: proc(settings: core.Settings) {
	monitor := glfw.GetPrimaryMonitor()
	x_pos: i32
	y_pos: i32
	width := i32(settings.width)
	height := i32(settings.height)
	target_monitor: glfw.MonitorHandle

	mode := glfw.GetVideoMode(monitor)

	switch settings.mode {
		case .Fullscreen:
			target_monitor = monitor
		case .Borderless:
			// FIXME: On macOS, borderless also fills the notch area

			// Monitor origin on the virtual desktop
			x_pos, y_pos = glfw.GetMonitorPos(monitor)

			width = mode.width
			height = mode.height

			glfw.SetWindowAttrib(
				state.os.window,
				glfw.DECORATED,
				i32(glfw.FALSE),
			)
		case .Windowed:
			// Put window in the center of the monitor
			x_pos = (mode.width - width) / 2
			y_pos = (mode.height - height) / 2

			glfw.SetWindowAttrib(
				state.os.window,
				glfw.DECORATED,
				i32(glfw.TRUE),
			)
	}

	refresh := settings.vsync ? mode.refresh_rate : i32(settings.refresh)
	if refresh == 0 do refresh = glfw.DONT_CARE

	glfw.SetWindowMonitor(
		state.os.window,
		target_monitor,
		x_pos,
		y_pos,
		width,
		height,
		refresh,
	)
}

os_set_callback_proc :: proc(window: rawptr) {
	glfw.SetWindowUserPointer(state.os.window, window)
}

os_should_close :: proc() -> bool {
	return bool(glfw.WindowShouldClose(state.os.window))
}

os_set_should_close :: proc(val: bool) {
	glfw.SetWindowShouldClose(state.os.window, b32(val))
}

os_poll_events :: proc() {
	glfw.PollEvents()
}

os_get_framebuffer_size :: proc() -> (width, height: u32) {
	iw, ih := glfw.GetFramebufferSize(state.os.window)
	return u32(iw), u32(ih)
}

os_get_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
	return glfwglue.GetSurface(instance, state.os.window)
}

// -----------------------------------------
// Private functions

// Error callback
@(private = "file")
error_callback :: proc "c" (error: i32, description: cstring) {
	context = state.ctx
	fmt.eprintfln("error: GLFW {}: {}", error, description)
} // GLFWerrorfun

// Window close callback
@(private = "file")
window_close_callback :: proc "c" (window: glfw.WindowHandle) {
	context = state.ctx
	event.on_event(event.Window_Close_Event{})
} // GLFWwindowclosefun

// Window resize callback
@(private = "file")
size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	resize()
} // GLFWframebuffersizefun

// Keyboard callback
@(private = "file")
key_callback :: proc "c" (
	window: glfw.WindowHandle,
	key, scancode, action, mods: i32,
) {
	context = state.ctx
	if action == glfw.PRESS {
		event.on_event(event.Key_Press_Event{key = key, mods = mods})
	}
	if action == glfw.RELEASE {
		event.on_event(event.Key_Release_Event{key = key, mods = mods})
	}
	if action == glfw.REPEAT {
		event.on_event(event.Key_Repeat_Event{key = key, mods = mods})
	}

} // GLFWkeyfun

// Mouse button callback
@(private = "file")
mouse_button_callback :: proc "c" (
	window: glfw.WindowHandle,
	button, action, mods: i32,
) {
	context = state.ctx
	if action == glfw.PRESS {
		event.on_event(event.Mouse_Button_Press_Event{button = button})
	}
	if action == glfw.RELEASE {
		event.on_event(event.Mouse_Button_Release_Event{button = button})
	}
} // GLFWmousebuttonfun

// Mouse position callback
@(private = "file")
cursor_pos_callback :: proc "c" (
	window: glfw.WindowHandle,
	x_pos, y_pos: f64,
) {
	context = state.ctx
	event.on_event(
		event.Mouse_Position_Event{x_pos = f32(x_pos), y_pos = f32(y_pos)},
	)
} // GLFWcursorposfun

// Mouse scroll callback
@(private = "file")
scroll_callback :: proc "c" (
	window: glfw.WindowHandle,
	x_offset, y_offset: f64,
) {
	context = state.ctx
	event.on_event(
		event.Mouse_Scroll_Event {
			x_offset = f32(x_offset),
			y_offset = f32(y_offset),
		},
	)
} // GLFWscrollfun

// Joystick connected / disconnected callback
@(private = "file")
joystick_callback :: proc "c" (id, connected: i32) {
	context = state.ctx
	if connected == glfw.CONNECTED {
		event.on_event(event.Joystick_Connect_Event{id = id})
	} else {
		event.on_event(event.Joystick_Disconnect_Event{id = id})
	}
} // GLFWjoystickfun

// References:
// - https://www.glfw.org/docs/latest/group__init.html
// - https://www.glfw.org/docs/latest/group__window.html
// - https://www.glfw.org/docs/latest/group__input.html
