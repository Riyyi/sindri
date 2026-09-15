$ErrorActionPreference = "Stop"

$VENDOR_DIR = Join-Path $PSScriptRoot "..\vendor" | Resolve-Path

# ------------------------------------------
# Platform detection (target dir name, only used for the up-to-date check)

# Windows PowerShell 5.1 doesn't define $IsWindows/$IsMacOS/$IsLinux
if (-not (Test-Path variable:IsWindows)) { $IsWindows = $env:OS -eq "Windows_NT" }
if (-not (Test-Path variable:IsMacOS)) { $IsMacOS = $false }
if (-not (Test-Path variable:IsLinux)) { $IsLinux = $false }

if ($IsWindows) {
	$os = "windows"
	$extra = "-msvc"
} elseif ($IsMacOS) {
	$os = "macos"
	$extra = ""
} elseif ($IsLinux) {
	$os = "linux"
	$extra = ""
} else {
	Write-Error "wgpu setup: unsupported OS"
	exit 1
}

$procArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
$arch = if ($procArch -eq [System.Runtime.InteropServices.Architecture]::Arm64) { "aarch64" } else { "x86_64" }

$odinRoot = (odin root).Trim()
$name = "wgpu-$os-$arch$extra-release"
$target = Join-Path $VENDOR_DIR "wgpu\lib\$name"

# ------------------------------------------
# WGPU version detection

if ($args.Count -gt 0 -and $args[0]) {
	$WGPU_VERSION = $args[0]
} else {
	$odinTypes = Join-Path $odinRoot "vendor\wgpu\wgpu_native_types.odin"
	$typesContent = Get-Content $odinTypes -Raw
	if ($typesContent -match 'BINDINGS_VERSION_STRING :: "([^"]*)"') {
		$WGPU_VERSION = "v" + $Matches[1]
	}
}

if (-not $WGPU_VERSION -or $WGPU_VERSION -eq "v") {
	Write-Error "wgpu setup: could not detect the wgpu-native version"
	exit 1
}

# Detect the version of the vendored wgpu bindings
$currentTypes = Join-Path $VENDOR_DIR "wgpu\wgpu_native_types.odin"
$current = $null
if (Test-Path $currentTypes) {
	$cur = Get-Content $currentTypes -Raw
	if ($cur -match 'BINDINGS_VERSION_STRING :: "([^"]*)"') {
		$current = "v" + $Matches[1]
	}
}

# Check if the vendored wgpu is already up to date
if ($current -eq $WGPU_VERSION -and (Test-Path $target)) {
	exit 0
}

# ------------------------------------------
# Copy vendor/wgpu

# Remove any stale copy
if (Test-Path (Join-Path $VENDOR_DIR "wgpu")) {
	Remove-Item -Recurse -Force (Join-Path $VENDOR_DIR "wgpu")
}

# Copy wgpu
$wgpuPath = Join-Path $odinRoot "vendor\wgpu"
Copy-Item -Recurse $wgpuPath $VENDOR_DIR

# Point imports at the copied vendor wgpu package
Get-ChildItem -Path (Join-Path $VENDOR_DIR "wgpu") -Recurse -Filter *.odin | ForEach-Object {
	(Get-Content $_.FullName -Raw) -replace '"vendor:wgpu"', '"wgpu:wgpu"' | Set-Content $_.FullName -NoNewline
}
