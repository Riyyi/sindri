package sindri

import "core:fmt"
import "core:time"

import "sindri:hot_reload"

VERSION :: #config(VERSION, "dev")

// -----------------------------------------

main :: proc() {
	fmt.println("hello world!")

	// Hot reload development functionality
	hr, err := hot_reload.hot_reload_init()
	defer hot_reload.hot_reload_destroy(&hr)

	api := hot_reload.active_lib(&hr)
	api.init()

	// Initialize Window
	os_init()
	defer os_destroy()

	// Initialize GPU resources
	instance_init()
	defer instance_destroy()

	gt: f32

	for !os_should_close() && !hot_reload.should_close(&hr) {
		start := time.tick_now()

		os_poll_events()
		frame(gt)

		gt = f32(time.duration_seconds(time.tick_since(start)))
	}
}
