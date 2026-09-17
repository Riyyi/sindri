package sindri

import "core:fmt"
import "core:time"

import "sindri:base"
import "sindri:platform"

VERSION :: #config(VERSION, "dev")

// -----------------------------------------

main :: proc() {
	fmt.println("hello world!")

	// Hot reload development functionality
	hr, err := base.hot_reload_init()
	defer base.hot_reload_destroy(&hr)

	api := base.active_lib(&hr)
	settings := api.settings()

	// Initialize Window
	platform.os_init(settings)
	platform.os_set_monitor(settings)
	defer platform.os_destroy()

	// Initialize GPU resources
	platform.instance_init(settings)
	defer platform.instance_destroy()

	api.init_once()
	api.init()

	gt: f64 = 0
	dt: f32

	for !platform.os_should_close() && !base.should_close(&hr) {
		start := time.tick_now()

		platform.os_poll_events()
		api.update(dt)

		platform.frame(dt)

		dt = f32(time.duration_seconds(time.tick_since(start)))
		gt += f64(dt)

		// Hot reload
		api, err = base.reload_game_lib(&hr)
		if err != nil do break
	}

	api.destroy()
}
