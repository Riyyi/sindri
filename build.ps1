$ErrorActionPreference = "Stop"

$PROJECT = "sindri"
$COMMIT = git rev-parse --short HEAD
$VERSION = "dev-$(Get-Date -Format 'yyyy-MM-dd')-$COMMIT"

$OPTION = $args[0]
if ($args) { $args = $args[1..($args.Length - 1)] } else { $args = @() }

# ------------------------------------------
# Game compile

New-Item -ItemType Directory -Force -Path build | Out-Null

# Game.dll
odin build game/ -show-timings `
	-collection:sindri=src `
	-build-mode:dynamic `
	-out:build/game_tmp -microarch:native "-define:VERSION=$VERSION-debug" -debug @args

# Need to use a temp file on Windows because it first writes an empty file,
# which the engine will load before it is actually fully written.
if (-not (Test-Path "build/game_tmp.dll")) {
	Write-Error "error: build produced no game lib.dll"
	exit 1
}
Move-Item -Force "build/game_tmp.dll" "build/game.dll"

# ------------------------------------------
# Engine compile

# If the executable is already running, then don't try to build and start it.
$proc = Get-Process -Name $PROJECT -ErrorAction SilentlyContinue
if ($proc) {
	Write-Output "Hot reloading..."
	exit 0
}

if ($OPTION -eq "debug") {
	odin build src/ -show-timings `
		-collection:sindri=src `
		-collection:gram=vendor/gram/src `
		-collection:wgpu=vendor `
		-out:build/$PROJECT -microarch:native -use-separate-modules "-define:VERSION=$VERSION-debug" -debug @args
	exit 0
}

odin build src/ -show-timings `
	-collection:sindri=src `
	-collection:gram=vendor/gram/src `
	-collection:wgpu=vendor `
	-out:build/$PROJECT -microarch:native -o:speed "-define:VERSION=$VERSION" @args
