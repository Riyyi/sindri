package build

import "core:flags"
import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"

import "../vendor/brokkr"

when ODIN_OS == .Windows {
	LIB_EXT :: ".dll"
	OS_NAME :: "windows"
} else when ODIN_OS == .Darwin {
	LIB_EXT :: ".dylib"
	OS_NAME :: "macos"
} else {
	LIB_EXT :: ".so"
	OS_NAME :: "linux"
}

when ODIN_ARCH == .amd64 {
	ARCH_NAME :: "x86_64"
} else when ODIN_ARCH == .arm64 {
	ARCH_NAME :: "aarch64"
}

PROJECT_NAME :: "sindri"
BUILD_DIRECTORY :: "out/"

GAME_SRC_DIR :: "game/"

ENGINE_DIR :: "src/"
ENGINE_OUTPUT :: BUILD_DIRECTORY + PROJECT_NAME

BUILD_INPUT_FILES :: []string{"compile/build.odin"}

// -----------------------------------------
// Types

Options :: struct {
	debug:        bool `args:"optional"            usage:"Build project in debug-mode."`,
	release:      bool `args:"optional"            usage:"Build project in release-mode."`,
	run:          bool `args:"optional"            usage:"Run project."`,
	hot_reload:   bool `args:"optional"            usage:"Hot-reload project."`,
	wgpu_init:    bool `args:"optional"            usage:"Prepare wgpu-native."`,
	wgpu_version: string `args:"optional"          usage:"Override the wgpu release version to init."`,
	fmt:          bool `args:"optional"            usage:"Run odinfmt."`,
	pre_commit:   bool `args:"optional"            usage:"Run git pre-commit hook."`,
	overflow:     [dynamic]string `args:"manifold" usage:"Extra arguments passed through to the odin build calls."`,
}

// -----------------------------------------
// Main

main :: proc() {
	// Create logger
	context.logger = log.create_console_logger(
		.Warning,
		{.Level, .Terminal_Color},
		"build",
	)
	defer log.destroy_console_logger(context.logger)

	// Change working directory
	chdir_project_root()

	brokkr.auto_rebuild(..BUILD_INPUT_FILES)

	opts: Options
	flags.parse_or_exit(&opts, os.args, .Unix)

	if opts.debug do build_project(true, opts.overflow[:])
	if opts.release do build_project(false, opts.overflow[:])
	if opts.run do run_project(opts.overflow[:])
	if opts.hot_reload do hot_reload(!opts.release, opts.overflow[:])
	if opts.wgpu_init do wgpu_init(opts.wgpu_version)
	if opts.fmt do format_source()
	if opts.pre_commit do pre_commit()

	// Fallback to building project, if no option provided
	if len(os.args) - 1 == len(opts.overflow) {
		build_project(true, opts.overflow[:])
	}
}

// -----------------------------------------
// Build project

// Build the game library ('game/') and the engine ('src/')
build_project :: proc(debug: bool, extra_args: []string) {
	version := project_version()

	// Setup compiled wgpu binary
	wgpu_init()

	// ----------------------------------------
	// Engine compile

	// If the executable is already running, don't try to build and start it
	if engine_is_running() {
		fmt.println("Hot reloading...")
		return
	}

	build_engine(debug, version, extra_args)
}

// Shared builder between game/engine
build_common :: proc(
	dir: string,
	debug: bool,
	version: string,
	extra_args: []string,
) -> brokkr.Builder {
	b := brokkr.builder_make()
	brokkr.build(&b, dir)
	brokkr.append(&b, "-show-timings")
	brokkr.collection(&b, "game", ".")
	brokkr.collection(&b, PROJECT_NAME, "src")
	brokkr.collection(&b, "gram", "vendor/gram/src")
	brokkr.collection(&b, "wgpu", "vendor")
	brokkr.append(&b, "-microarch:native")
	brokkr.opt(&b, debug ? .Minimal : .Speed)
	brokkr.define(
		&b,
		"VERSION",
		debug ? fmt.tprintf("%v-debug", version) : version,
	)
	if debug {
		brokkr.debug(&b)
		brokkr.append(&b, "-use-separate-modules")
	}
	for arg in extra_args {
		brokkr.append(&b, arg)
	}
	return b
}

// Build the engine executable
build_engine :: proc(debug: bool, version: string, extra_args: []string) {
	b := build_common(ENGINE_DIR, debug, version, extra_args)
	defer brokkr.builder_destroy(&b)
	brokkr.out(&b, output_path(ENGINE_OUTPUT))
	if err := brokkr.execute(&b); err != nil {
		os.exit(1)
	}
}

run_project :: proc(extra_args: []string) {
	// Build project if it wasnt already
	if !os.exists(output_path(ENGINE_OUTPUT)) do build_project(true, {})

	cmd := []string{output_path(ENGINE_OUTPUT)}
	line := slice.concatenate(
		[][]string{cmd, extra_args},
		context.temp_allocator,
	)

	process, s_err := os.process_start(
		{
			command = line,
			stdin = os.stdin,
			stdout = os.stdout,
			stderr = os.stderr,
		},
	)
	if s_err != nil {
		die("failed to start project process: %v", os.error_string(s_err))
	}

	res, w_err := os.process_wait(process)
	if w_err != nil {
		die("failed to wait for project process: %v", os.error_string(w_err))
	}
	if !res.success {
		die("project process failed with exit code: %v", res.exit_code)
	}

	os.exit(res.exit_code)
}

hot_reload :: proc(debug: bool, extra_args: []string) {
	if engine_is_running() {
		process := output_path(PROJECT_NAME)
		when ODIN_OS == .Windows {
			// Ask process to shut down gracefully (equivalent to SIGTERM)
			_, ok, _ := exec([]string{"taskkill", "/IM", process + ".exe"})
			if !ok {
				die("hot reload: failed to terminate running %s", process)
			}
		} else {
			_, ok, _ := exec([]string{"pkill", "-TERM", "-x", process})
			if !ok {
				die(
					"hot reload: failed to send SIGTERM to running %s",
					process,
				)
			}
		}

		// Wait for process to terminate
		for engine_is_running() {
			time.sleep(time.Millisecond * 20)
		}
	}

	run_project(extra_args)
}

// -----------------------------------------
// wgpu setup

// Prepare wgpu for usage: download, unzip, copy vendor code
wgpu_init :: proc(version_override := "") {
	when ODIN_OS == .Windows {
		target_name :=
			"wgpu-" + OS_NAME + "-" + ARCH_NAME + "-msvc" + "-release"
	} else {
		target_name := "wgpu-" + OS_NAME + "-" + ARCH_NAME + "-release"
	}

	target := join_path({"vendor", "wgpu", "lib", target_name})

	// ----------------------------------------
	// wgpu version detection

	// Detect the wgpu-native version the bundled bindings expect
	odin_root, ok, _ := exec([]string{"odin", "root"})
	if !ok do os.exit(1)
	defer delete(odin_root)

	wgpu_version := version_override
	if len(wgpu_version) == 0 {
		v, found := bindings_version_from_file(
			join_path({odin_root, "vendor", "wgpu", "wgpu_native_types.odin"}),
		)
		if !found {
			die("wgpu setup: could not detect the wgpu-native version")
		}
		wgpu_version = fmt.tprintf("v%v", v)
	}

	// Detect the version of the vendored wgpu bindings
	current := ""
	if wgpu_types_path := join_path(
		{"vendor", "wgpu", "wgpu_native_types.odin"},
	); os.is_file(wgpu_types_path) {
		if ver, found := bindings_version_from_file(wgpu_types_path); found {
			current = fmt.tprintf("v%v", ver)
		}
	}

	// Check if the vendored wgpu is already up to date
	if current == wgpu_version && os.is_dir(target) {
		return
	}

	// ----------------------------------------
	// Copy vendor/wgpu

	// Remove any stale copy.
	os.remove_all("vendor/wgpu")

	// Copy wgpu from the odin installation.
	os.copy_directory_all(
		"vendor/wgpu",
		join_path({odin_root, "vendor", "wgpu"}),
	)
	chmod_recursively("vendor/wgpu")

	// Point imports at the copied vendor wgpu package.
	rewrite_imports("vendor/wgpu", `"vendor:wgpu"`, `"wgpu:wgpu"`)

	// ----------------------------------------
	// Download

	if !os.is_dir(target) {
		url := fmt.tprintf(
			"https://github.com/gfx-rs/wgpu-native/releases/download/%v/%v.zip",
			wgpu_version,
			target_name,
		)
		fmt.println("wgpu setup: downloading", url)

		tmp_dir, err := os.make_directory_temp(
			"",
			"out-tmp-*",
			context.temp_allocator,
		)
		if err != nil {
			die(
				"wgpu setup: failed to create a temporary directory: %v",
				os.error_string(err),
			)
		}
		defer os.remove_all(tmp_dir)
		zip_path := join_path({tmp_dir, "wgpu.zip"})

		when ODIN_OS == .Windows {
			if dl_err := brokkr.execute_command(
				[]string {
					"powershell",
					"-NoProfile",
					"-Command",
					fmt.tprintf(
						"$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri %q -OutFile %q",
						url,
						zip_path,
					),
				},
			); dl_err != nil {
				die("wgpu setup: failed to download wgpu-native release")
			}
		} else {
			if dl_err := brokkr.execute_command(
				[]string{"curl", "-fL", "--retry", "3", "-o", zip_path, url},
			); dl_err != nil {
				die("wgpu setup: failed to download wgpu-native release")
			}
		}

		when ODIN_OS == .Windows {
			// Uses the PowerShell cmdlet the same way scripts/wgpu-init.ps1 did.
			if ex_err := brokkr.execute_command(
				[]string {
					"powershell",
					"-NoProfile",
					"-Command",
					fmt.tprintf(
						"Expand-Archive -Force -Path %q -DestinationPath %q",
						zip_path,
						target,
					),
				},
			); ex_err != nil {
				die("wgpu setup: failed to extract wgpu-native release")
			}
		} else {
			// Matches scripts/wgpu-init.sh.
			if ex_err := brokkr.execute_command(
				[]string{"unzip", "-o", "-q", zip_path, "-d", target},
			); ex_err != nil {
				die("wgpu setup: failed to extract wgpu-native release")
			}
		}
	}
}

// Extracts the wgpu-native version from BINDINGS_VERSION_STRING
bindings_version_from_file :: proc(
	path: string,
) -> (
	version: string,
	found: bool,
) {
	if !os.is_file(path) do return

	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil do return

	s := string(data)
	id := strings.index(s, "BINDINGS_VERSION_STRING")
	if id == -1 do return

	quote_start := strings.index(s[id:], `"`)
	if quote_start == -1 do return
	quote_start += id

	quote_end := strings.index(s[quote_start + 1:], `"`)
	if quote_end == -1 do return
	quote_end += quote_start + 1

	version = s[quote_start + 1:quote_end]
	found = len(version) != 0
	return
}

// 'chmod -R +w' equivalent: makes everything under 'path' writable,
// keeping every other permission bit
chmod_recursively :: proc(path: string) {
	when ODIN_OS == .Windows {
		return
	} else {
		info, err := os.stat(path, context.temp_allocator)
		if err != nil {
			die(
				"wgpu setup: failed to stat %q: %v",
				path,
				os.error_string(err),
			)
		}

		// Add writable (+w)
		if err := os.change_mode(path, info.mode + os.Permissions_Write_All);
		   err != nil {
			die("wgpu setup: chmod %q failed: %v", path, os.error_string(err))
		}

		// Recurse into directories
		if info.type == .Directory {
			entries, read_err := os.read_directory_by_path(
				path,
				-1,
				context.temp_allocator,
			)
			if read_err != nil {
				die(
					"wgpu setup: failed to read %q: %v",
					path,
					os.error_string(read_err),
				)
			}
			for entry in entries {
				if entry.name == "." || entry.name == ".." do continue
				chmod_recursively(join_path({path, entry.name}))
			}
		}
	}
}

// Replaces 'old_import' with 'new_import' in every '.odin' file under 'path'
rewrite_imports :: proc(path: string, old_import, new_import: string) {
	info, err := os.stat(path, context.temp_allocator)
	if err != nil {
		die("wgpu setup: failed to stat %q: %v", path, os.error_string(err))
	}

	// Recurse into directories
	if info.type == .Directory {
		entries, read_err := os.read_directory_by_path(
			path,
			-1,
			context.temp_allocator,
		)
		if read_err != nil {
			die(
				"wgpu setup: failed to read %q: %v",
				path,
				os.error_string(read_err),
			)
		}
		for entry in entries {
			if entry.name == "." || entry.name == ".." do continue
			rewrite_imports(
				join_path({path, entry.name}),
				old_import,
				new_import,
			)
		}
		return
	}

	if info.type != .Regular || !strings.ends_with(info.name, ".odin") do return

	data, read_err := os.read_entire_file(path, context.temp_allocator)
	if read_err != nil {
		die(
			"wgpu setup: failed to read %q: %v",
			path,
			os.error_string(read_err),
		)
	}

	replacement, was_allocation := strings.replace_all(
		string(data),
		old_import,
		new_import,
		context.temp_allocator,
	)
	if was_allocation {
		if write_err := os.write_entire_file(path, replacement);
		   write_err != nil {
			die(
				"wgpu setup: failed to write %q: %v",
				path,
				os.error_string(write_err),
			)
		}
	}
}

// -----------------------------------------
// Formatting

// Run `odinfmt -w` on source directory
format_source :: proc() {
	for dir in ([]string{GAME_SRC_DIR, ENGINE_DIR}) {
		err := brokkr.execute_command([]string{"odinfmt", "-w", dir})
		if err != nil do os.exit(1)
	}
}

// -----------------------------------------
// Git pre-commit hook

pre_commit :: proc() {
	err := brokkr.execute_command(
		[]string{"git", "stash", "push", "--keep-index", "--quiet"},
	)
	if err != nil do os.exit(1)

	format_source()

	err = brokkr.execute_command([]string{"git", "diff", "--quiet"})
	if err != nil {
		log.error("formatting changed staged files; commit aborted")
		_ = brokkr.execute_command([]string{"git", "checkout", "--", "."})
		_ = brokkr.execute_command([]string{"git", "stash", "pop", "--quiet"})
		os.exit(1)
	}

	err = brokkr.execute_command([]string{"git", "stash", "pop", "--quiet"})
	if err != nil do os.exit(1)
}

// -----------------------------------------
// Helpers

// Log an error and exit(1)
die :: proc(fmt_str: string, args: ..any, loc := #caller_location) -> ! {
	log.errorf(fmt_str, ..args, location = loc)
	os.exit(1)
}

// Change working directory to project root
chdir_project_root :: proc() {
	// Get full path
	binary_path, abs_err := filepath.abs(os.args[0])
	if abs_err != nil {
		die(
			"failed to get absolute binary path %q: %v",
			os.args[0],
			os.error_string(abs_err),
		)
	}

	// Set working directory to project root
	project_root_dir := filepath.dir(binary_path)
	if err := os.set_working_directory(project_root_dir); err != nil {
		die(
			"failed to change working directory to %q: %v",
			project_root_dir,
			os.error_string(err),
		)
	}

	// Set program argument to the full path of the binary
	os.args[0] = binary_path
}

// Check if engine (executable named `Project_Name`) is already running
engine_is_running :: proc() -> bool {
	when ODIN_OS == .Windows {
		out, ok := exec(
			[]string {
				"tasklist",
				"/FI",
				("IMAGENAME eq " + PROJECT_NAME + ".exe"),
				"/NH",
			},
		)
		if !ok do return false
		return strings.contains(string(out), PROJECT_NAME + ".exe")
	} else {
		_, ok, code := exec([]string{"pgrep", "-x", PROJECT_NAME}, false)
		if !ok do return false
		return code == 0
	}
}

// Runs a command. Use this over brokkr.execute_command when you need to
// capture the contents of stdout, or the return code
exec :: proc(
	cmd: []string,
	print_error := true,
) -> (
	out: string,
	ok: bool,
	code: int,
) {
	state, stdout, stderr, err := os.process_exec(
		{command = cmd},
		context.temp_allocator,
	)
	defer delete(stdout, context.temp_allocator)
	defer delete(stderr, context.temp_allocator)

	if err != nil {
		log.errorf("exec failed %v: %v", cmd, os.error_string(err))
		return "", false, 1
	}
	if state.exit_code != 0 {
		if print_error {
			log.errorf("exec failed %v: %s", cmd, stderr)
		}
		return "", false, state.exit_code
	}

	str, a_err := strings.clone_from_bytes(stdout)
	if a_err != nil {
		return "", false, 1
	}
	return strings.trim_space(str), true, 0
}

// Joins segments into a full path, ex: {"a", "b", "c"} -> a/b/c
join_path :: proc(elems: []string) -> string {
	joined, err := filepath.join(elems, context.temp_allocator)
	if err != nil {
		die("failed to join path %v: %v", elems, os.error_string(err))
	}
	return joined
}

output_path :: proc(binary_path: string) -> string {
	when ODIN_OS == .Windows {
		return binary_path + ".exe"
	}
	return binary_path
}

// Get project version, example: `dev-2026-09-23-a4084b3`
project_version :: proc() -> string {
	commit, ok, _ := exec([]string{"git", "rev-parse", "--short", "HEAD"})
	if !ok do os.exit(1)
	defer delete(commit)

	buf: [time.MIN_YYYY_DATE_LEN]u8
	date := time.to_string_yyyy_mm_dd(time.now(), buf[:])
	return fmt.tprintf("dev-%v-%v", date, commit)
}
