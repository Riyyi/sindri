# Sindri

Game engine.

## Usage

<!-- TODO: --> TODO

## Compiling

### Dependencies

- `git`
- `odin`
- `unzip` on macOS or Linux

### Building

```sh
./build.sh              # debug game and engine (default)
./build.sh -debug       # debug game and engine
./build.sh -release     # build game and engine
./build.sh -run         # run game
./build.sh -fmt         # format sources
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
- build.sh -> bootstrap shim for `compile/build.odin`

## Hot Reload

build.sh -> hot reload enabled, debug mode enabled
build_release.sh -> hot reload disabled, debug mode disabled
build_debug.sh -> hot reload disabled, debug mode enabled

hot reload builds engine as .exe, then game as dynamic lib.
skips building the engine if its already running (pgrep).

no hot reload does not use game.dll, instead it imports the game source
as a normal Odin package during build.
