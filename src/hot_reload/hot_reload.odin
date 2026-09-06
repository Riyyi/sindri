package hot_reload

import "core:dynlib"
import "core:fmt"
import "core:os"

when ODIN_OS == .Windows {
	LIB_EXT :: ".dll"
} else when ODIN_OS == .Darwin {
	LIB_EXT :: ".dylib"
} else {
	LIB_EXT :: ".so"
}

GAME_LIB_DIR :: "build/"
GAME_LIB_PATH :: GAME_LIB_DIR + "game" + LIB_EXT

// -----------------------------------------

Hot_Reload :: struct {
	loaded_libs: [dynamic]Game_API,
}

Hot_Reload_Error :: enum u8 {
	None                 = 0,
	Load_Game_Lib_Failed = 1,
	Unimplemented        = 127,
	Okay                 = None,
}

Error :: union #shared_nil {
	Hot_Reload_Error,
}

Game_API :: struct {
	lib:          dynlib.Library,
	init:         proc(),
	update:       proc(),
	render:       proc(),
	destroy:      proc(),
	should_close: proc() -> bool,
	api_version:  int, // iteration of the game lib
}

// -----------------------------------------

hot_reload_init :: proc() -> (state: Hot_Reload, error: Error) {
	api: Game_API
	api.api_version = -1

	api_ok := load_game_lib(&api)
	if !api_ok {
		fmt.println("Failed to load Game API")
		return {}, .Load_Game_Lib_Failed
	}

	state.loaded_libs = make([dynamic]Game_API)
	append(&state.loaded_libs, api)

	return state, nil
}

hot_reload_destroy :: proc(state: ^Hot_Reload) {
	for &api in state.loaded_libs {
		unload_game_lib(&api)
	}

	delete(state.loaded_libs)
}

// -----------------------------------------

active_lib :: proc(hr: ^Hot_Reload) -> ^Game_API {
	return &hr.loaded_libs[len(hr.loaded_libs) - 1]
}

should_close :: proc(hr: ^Hot_Reload) -> bool {
	api := active_lib(hr)
	if api.lib == nil do return true
	return api.should_close()
}

copy_lib :: proc(to: string) -> bool {
	copy_err := os.copy_file(to, GAME_LIB_PATH)
	if copy_err != nil {
		fmt.printfln(
			"error: Failed to copy " + GAME_LIB_PATH + " to {0}: %v",
			to,
			copy_err,
		)
		return false
	}

	return true
}

// Load game lib symbols
load_game_lib :: proc(api: ^Game_API) -> bool {
	// Load next iteration
	api.api_version += 1

	lib_name := fmt.tprintf(
		GAME_LIB_DIR + "game_{0}" + LIB_EXT,
		api.api_version,
	)
	copy_lib(lib_name) or_return

	// Match the names of the fields in Game_API to symbols in the game DLL
	_, ok := dynlib.initialize_symbols(api, GAME_LIB_PATH, "", "lib")
	if !ok {
		fmt.printfln("Failed initializing symbols: {0}", dynlib.last_error())
	}

	return ok
}

// Unload game lib, used during full restarts
unload_game_lib :: proc(api: ^Game_API) {
	if api.lib != nil {
		if !dynlib.unload_library(api.lib) {
			fmt.eprintfln(
				"error: Failed unloading lib: {0}",
				dynlib.last_error(),
			)
		}
	}

	if os.remove(
		   fmt.tprintf(GAME_LIB_DIR + "game_{0}" + LIB_EXT, api.api_version),
	   ) !=
	   nil {
		fmt.printfln(
			"error: Failed to remove {0}game_{1}" + LIB_EXT + " copy",
			GAME_LIB_DIR,
			api.api_version,
		)
	}
}
