package sindri

import "core:fmt"
import "core:time"

import "game:game"
import "sindri:base"
import "sindri:core"
import "sindri:platform"

VERSION :: #config(VERSION, "dev")

// -----------------------------------------

main :: proc() {
	fmt.println("hello world!", VERSION)

	// Hot reload development functionality
	base.hot_reload_init(VERSION)
	defer base.hot_reload_destroy()

	// Load game API & settings
	api := game.api()
	defer api.destroy()
	settings := api.settings()

	// Event system
	base.event_bus_init()
	defer base.event_bus_destroy()

	base.event_subscribe(base.Key_Press_Event, test)

	// Listen for OS signals (SIGINT, SIGTERM)
	platform.signals_init()
	defer platform.signals_destroy()

	// Initialize Window
	platform.os_init(settings)
	platform.os_set_monitor(settings)
	defer platform.os_destroy()

	// Initialize GPU resources
	platform.instance_init(settings)
	defer platform.instance_destroy()
	load_test_model()

	api.init_once()

	base.read_snapshot()

	api.init()

	dt: f64
	gt: f64
	st: f64

	for !api.should_close() &&
	    !platform.os_should_close() &&
	    !base.should_close {

		start := time.tick_now()

		platform.os_poll_events()
		base.drain_event_queue()
		api.update(cast(f32)dt)
		base.write_snapshot()

		platform.frame()
		api.render()

		dt = time.duration_seconds(time.tick_since(start))
		gt += dt
		st += dt

		if st > 5 {
			st -= 5
			base.set_write_full_snapshot()
		}

		if api.force_reload() do base.force_reload()
		if api.force_restart() do base.force_restart()
	}
}

test :: proc(e: ^base.Key_Press_Event, _: rawptr) -> bool {
	fmt.println("main: @@@@@@@@@@@", e)
	return true
}

// Load model from disk and upload it
load_test_model :: proc() {
	vertices, indices, model_ok := core.load_obj_model("assets/suzanne.obj")
	if !model_ok do fmt.panicf("[main] could not load model")
	defer delete(vertices)
	defer delete(indices)

	platform.fill_buffers_with_model(vertices, indices)
}
