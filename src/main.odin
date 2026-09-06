package sindri

import "core:dynlib"
import "core:fmt"
import "core:time"

VERSION :: #config(VERSION, "dev")

// -----------------------------------------

instance_ready: bool

Game_API :: struct {
	__handle:     dynlib.Library,
	hello:        proc(),
	should_close: proc() -> bool,
}

main :: proc() {
	fmt.println("hello world!")

	api: Game_API
	load_game_api(&api)
	api.hello()

	// Initialize window
	os_init()

	// Initialize GPU resources
	instance_init()

	gt: f32

	for !os_should_close() && !api.should_close() {
		start := time.tick_now()

		os_poll_events()
		frame(gt)

		gt = f32(time.duration_seconds(time.tick_since(start)))
	}

	// Cleanup GPU resources
	instance_destroy()

	// Cleanup window
	os_destroy()
}

load_game_api :: proc(api: ^Game_API) {
	// Match the names of the fields in Game_API to symbols in the game DLL
	_, ok := dynlib.initialize_symbols(api, "build/game.dylib")
	if !ok {
		fmt.printfln("Failed initializing symbols: {0}", dynlib.last_error())
	}
}
