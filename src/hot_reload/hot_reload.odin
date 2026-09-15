package hot_reload

import "core:c"
import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:time"

import "sindri:core"
import "sindri:input"

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
	lib:               dynlib.Library,
	memory:            proc() -> rawptr,
	memory_free:       proc(),
	memory_size:       proc() -> int,
	memory_set:        proc(mem: rawptr),
 settings:          proc() -> core.Settings,
	init_input:        proc(input.Key_State_Proc, input.Mouse_Button_State_Proc, input.Mouse_Position_Proc),
	init_once:         proc(),
	init:              proc(),
	update:            proc(_: f32),
	render:            proc(),
	destroy:           proc(),
	should_close:      proc() -> bool,
	force_reload:      proc() -> bool,
	force_restart:     proc() -> bool,
	modification_time: time.Time,
	api_version:       int, // iteration of the game lib
}

// -----------------------------------------

hot_reload_init :: proc() -> (hr: Hot_Reload, error: Error) {
	api: Game_API

	api_ok := load_game_lib(&api)
	if !api_ok {
		fmt.println("error: failed to load Game API")
		return {}, .Load_Game_Lib_Failed
	}

	hr.loaded_libs = make([dynamic]Game_API, 0, 0, context.allocator)
	append(&hr.loaded_libs, api)

	inject_input(&api)

	return hr, nil
}

// Store the engine's input implementations, to inject them into every
// game lib load. The dll has its own copies of the `input` package
// variables, which are nil until these are passed in.
register_input :: proc(
	hr: ^Hot_Reload,
	ks: input.Key_State_Proc,
	mbs: input.Mouse_Button_State_Proc,
	mp: input.Mouse_Position_Proc,
) {
	key_state_proc = ks
	mouse_button_state_proc = mbs
	mouse_position_proc = mp

	inject_input(active_lib(hr))
}

key_state_proc: input.Key_State_Proc
mouse_button_state_proc: input.Mouse_Button_State_Proc
mouse_position_proc: input.Mouse_Position_Proc

inject_input :: proc(api: ^Game_API) {
	if api.init_input != nil {
		api.init_input(key_state_proc, mouse_button_state_proc, mouse_position_proc)
	}
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
			"error: failed to copy {0} to {1}: {2:v}",
			GAME_LIB_PATH,
			to,
			copy_err,
		)
		return false
	}

	return true
}

// Load game lib symbols
load_game_lib :: proc(api: ^Game_API) -> bool {
	mod_time, mod_time_err := os.last_write_time_by_name(GAME_LIB_PATH)
	if mod_time_err != os.ERROR_NONE {
		fmt.printfln(
			"error: failed getting last write time of {0}, error code: {1}",
			GAME_LIB_PATH,
			mod_time_err,
		)
		return false
	}
	api.modification_time = mod_time

	lib_name := fmt.tprintf(
		GAME_LIB_DIR + "game_{0}" + LIB_EXT,
		api.api_version,
	)
	copy_lib(lib_name) or_return

	// Match the names of the fields in Game_API to symbols in the game DLL
	_, ok := dynlib.initialize_symbols(api, lib_name, "", "lib")
	if !ok {
		fmt.printfln(
			"error: failed initializing symbols: {0}",
			dynlib.last_error(),
		)
	} else {
		// Odin's shared libraries don't register a constructor, so the lib's
		// runtime init (@init procs like os.stdout setup) never runs on load.
		// Call it explicitly.
		//
		// Windows doesn't need this: its dynamic build exports DllMain, which
		// the OS calls on load and which runs _startup_runtime itself.
		when ODIN_OS != .Windows {
			Entry :: #type proc "c" () -> c.int
			entry_ptr, entry_ok := dynlib.symbol_address(
				api.lib,
				"_odin_entry_point",
			)
			if entry_ok do (transmute(Entry)entry_ptr)()
		}
	}

	return ok
}

// Unload game lib, used during full restarts
unload_game_lib :: proc(api: ^Game_API) {
	if api.lib != nil {
		if !dynlib.unload_library(api.lib) {
			fmt.eprintfln(
				"error: failed unloading lib: {0}",
				dynlib.last_error(),
			)
		}
	}

	if os.remove(
		   fmt.tprintf(GAME_LIB_DIR + "game_{0}" + LIB_EXT, api.api_version),
	   ) !=
	   nil {
		fmt.printfln(
			"error: failed to remove {0}game_{1}{2} copy",
			GAME_LIB_DIR,
			api.api_version,
			LIB_EXT,
		)
	}
}

reload_game_lib :: proc(hr: ^Hot_Reload) -> (lib: ^Game_API, err: Error) {
	api := active_lib(hr)
	force_reload := api.force_reload()
	force_restart := api.force_restart()
	reload := force_reload || force_restart

	lib_mod, lib_mod_err := os.last_write_time_by_name(GAME_LIB_PATH)
	// TODO: Handle error
	if lib_mod_err == os.ERROR_NONE && api.modification_time != lib_mod {
		reload = true
	}

	if !reload do return api, nil

	new_api: Game_API
	new_api.api_version = api.api_version + 1
	new_api_ok := load_game_lib(&new_api)
	if !new_api_ok {
		fmt.println("error: failed to load Game API")
		return nil, .Load_Game_Lib_Failed
	}

	force_restart = force_restart || api.memory_size() != new_api.memory_size()

	if !force_restart {
		// This does the normal hot reload

		// Note that we don't unload the old game APIs because that
		// would unload the lib. The lib can contain stored info
		// such as string literals. The old libs are only unloaded
		// on a full reset or on shutdown.
		memory := api.memory()
		new_api.memory_set(memory)
	} else {
		// This does a full reset. That's basically like opening and
		// closing the game, without having to restart the executable.
		//
		// You end up in here if the game requests a full reset OR
		// if the size of the game memory has changed. That would
		// probably lead to a crash anyways.

		api.memory_free()

		for &g in hr.loaded_libs {
			unload_game_lib(&g)
		}
		clear(&hr.loaded_libs)

		new_api.init()
	}

	append(&hr.loaded_libs, new_api)

	inject_input(active_lib(hr))

	return active_lib(hr), nil
}
