# Sindri

Game engine.

## Usage

<!-- TODO: --> TODO

## Compiling

### Dependencies

- `odin`
- `sh` a POSIX compatible shell

### Building

```sh
./build.sh
./build.sh debug
```

## Contributing

Make sure to enable git hooks:

```sh
git config core.hooksPath scripts
```

vendor
- wgpu
- glfw
- lua
- miniaudio
- microui (temp)
- box3d?
- build.sh -> build.odin

## Hot Reload

build.sh -> hot reload enabled, debug mode enabled
build_release.sh -> hot reload disabled, debug mode disabled
build_debug.sh -> hot reload disabled, debug mode enabled

hot reload builds engine as .exe, then game as dynamic lib.
skips building the engine if its already running (pgrep).

no hot reload does not use game.dll, instead it imports the game source
as a normal Odin package during build.
