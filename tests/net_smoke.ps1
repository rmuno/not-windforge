# Two-process multiplayer integration test.
# Starts a headless server, runs a headless client against it, and carries the
# client's exit code. Exits 0 on pass, 1 on failure.
#   powershell -File tests\net_smoke.ps1

$ErrorActionPreference = "Stop"

$godot = "D:\software\godot-4.6.0\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe"
if (-not (Test-Path $godot)) {
    Write-Error "Godot not found at $godot - update the path in this script."
    exit 2
}

$project = Split-Path -Parent $PSScriptRoot
$serverLog = Join-Path $env:TEMP "not-windforge-net-server.log"

Write-Output "--- starting server ---"
$server = Start-Process -FilePath $godot -PassThru -NoNewWindow -RedirectStandardOutput $serverLog `
    -ArgumentList @("--headless", "--path", $project, "--script", "res://tests/net_smoke.gd", "--", "--server")

# Give ENet a moment to bind the port before the client dials in.
Start-Sleep -Seconds 3

Write-Output "--- running client ---"
& $godot --headless --path $project --script "res://tests/net_smoke.gd" -- --client
$code = $LASTEXITCODE

if (-not $server.HasExited) {
    Stop-Process -Id $server.Id -Force
}

Write-Output ""
Write-Output "--- server log ---"
if (Test-Path $serverLog) {
    Get-Content $serverLog | Select-Object -Last 20
}

Write-Output ""
if ($code -eq 0) { Write-Output "NET SMOKE: PASS" } else { Write-Output "NET SMOKE: FAIL ($code)" }
exit $code
