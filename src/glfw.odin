package sindri

import "core:strings"
import "vendor:glfw"

import "wgpu:wgpu"
import "wgpu:wgpu/glfwglue"

import "sindri:core"

// -----------------------------------------

OS :: struct {
	window: glfw.WindowHandle,
}

// -----------------------------------------

os_init :: proc(settings: core.Settings) {
	if !glfw.Init() {
		panic("[glfw] init failure")
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	state.os.window = glfw.CreateWindow(
		i32(settings.width),
		i32(settings.height),
		strings.unsafe_string_to_cstring(settings.title),
		nil,
		nil,
	)

	glfw.SetFramebufferSizeCallback(state.os.window, size_callback)
}

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

os_should_close :: proc() -> bool {
	return bool(glfw.WindowShouldClose(state.os.window))
}

os_set_should_close :: proc(val: bool) {
	glfw.SetWindowShouldClose(state.os.window, b32(val))
}

os_poll_events :: proc() {
	glfw.PollEvents()
}

os_destroy :: proc() {
	glfw.DestroyWindow(state.os.window)
	glfw.Terminate()
}

os_get_framebuffer_size :: proc() -> (width, height: u32) {
	iw, ih := glfw.GetFramebufferSize(state.os.window)
	return u32(iw), u32(ih)
}

os_get_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
	return glfwglue.GetSurface(instance, state.os.window)
}

@(private = "file")
size_callback :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	resize()
}
