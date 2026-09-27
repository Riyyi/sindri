$ErrorActionPreference = "Stop"

Set-Location $PSScriptRoot

$exe = Join-Path $PSScriptRoot "build.exe"
if (-not (Test-Path $exe)) {
	& odin build compile/build.odin -file ("-out:" + $exe)
}

& $exe @args

Set-Location -
