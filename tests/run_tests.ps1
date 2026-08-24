# Headless test runner. Exits 0 on pass, 1 on failure.
#   powershell -File tests\run_tests.ps1

$ErrorActionPreference = "Stop"

$godot = "D:\software\godot-4.6.0\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe"
if (-not (Test-Path $godot)) {
    Write-Error "Godot not found at $godot - update the path in this script."
    exit 2
}

$project = Split-Path -Parent $PSScriptRoot

& $godot --headless --path $project --script "res://tests/run_tests.gd"
exit $LASTEXITCODE
