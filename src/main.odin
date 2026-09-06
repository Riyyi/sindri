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
	settings := api.settings()

	// Initialize Window
	os_init(settings)
	os_set_monitor(settings)
	defer os_destroy()

	// Initialize GPU resources
	instance_init()
	defer instance_destroy()

	api.init_once()
	api.init()

	gt: f64 = 0
	dt: f32

	for !os_should_close() && !hot_reload.should_close(&hr) {
		start := time.tick_now()

		os_poll_events()
		api.update(dt)

		frame(dt)

		dt = f32(time.duration_seconds(time.tick_since(start)))
		gt += f64(dt)

		// Hot reload
		api, err = hot_reload.reload_game_lib(&hr)
		if err != nil do break
	}

	api.destroy()
}
