/*
 * Copyright (C) 2026 Riyyi
 *
 * SPDX-License-Identifier: MIT
 */

package sindri

import "core:fmt"
import "core:time"

import "game:game"
import "sindri:base"
import "sindri:core"
import "sindri:platform"

VERSION :: #config(VERSION, "dev")

// -----------------------------------------
// Variables

arena: base.Arena

// -----------------------------------------
// Public functions

main :: proc() {
	fmt.println("hello world!", VERSION)

	arena = base.arena_init_static()
	defer base.arena_destroy(&arena)
	allocator := base.arena_allocator(&arena)

	// Hot reload development functionality
	base.hot_reload_init(VERSION, allocator)
	defer base.hot_reload_destroy()

	// Load game API & settings
	api := game.api()
	defer api.destroy()
	settings := api.settings()

	// Event systems
	base.event_bus_init(allocator)
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
	platform.instance_init(settings, allocator)
	defer platform.instance_destroy()

	// Assets
	assets := core.assets_init(allocator)
	defer core.assets_destroy(&assets)

	// Large Array of Things
	things := new(core.Things, allocator)
	defer free(things, allocator)

	// Register engine API
	engine_api := core.Engine_API {
		assets = &assets,
		things = things,
	}
	api.register_api(&engine_api)

	// Register memory regions
	base.register_region("assets", cast(rawptr)&assets, size_of(core.Assets))
	base.register_region("things", things, size_of(core.Things))
	api.register_memory()

	// Read memory snapshot
	fresh, err := base.read_snapshot()
	fmt.assertf(err == nil, "[main] failed to read snapshot", err)
	assets.allocator = allocator

	// Init
	if fresh {
		api.init_once()
	}
	else {
		core.asset_reload_after_hot_reload(&assets, "assets")
	}
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

		// loop through Things, if model -> render
		// register the Things inside game.odin

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
