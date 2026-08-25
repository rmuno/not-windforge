# Runs every suite. Exits 0 only if all pass.
#   powershell -File tests/run_all.ps1          (full - the pre-merge certifier)
#   powershell -File tests/run_all.ps1 -Quick   (unit suite + version gate only)
#
# GENTLE ON THE PLAY MACHINE (owner standing order 2026-08-25, after a crash
# during parallel load): this runner and every Godot it spawns drop to
# BelowNormal priority, so the owner session always wins the CPU.
# Iterate with -Quick; run the FULL suite exactly once, to certify a merge.

param([switch]$Quick)

# Child processes inherit the priority class, so one line covers every Godot
# (and the net_smoke child shell) launched below.
try { (Get-Process -Id $PID).PriorityClass = "BelowNormal" } catch {}

$godot = "D:\software\godot-4.6.0\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe"
if (-not (Test-Path $godot)) {
    Write-Error "Godot not found at $godot - update the path in this script."
    exit 2
}

$project = Split-Path -Parent $PSScriptRoot
$failed = @()

# Cold-start check. The global class cache is what makes `class_name` types
# resolve; if it is stale or missing, every script referencing Fleet/Ship/
# BlockDB/NetUtil fails to compile and the game will not launch. An editor that
# was already open when a new class_name file was added will not have rescanned.
#
# So: wipe the cache, rebuild it, and prove the game still compiles from
# scratch. This also leaves the cache correct on disk, which means F5 works
# immediately after running the tests.
Write-Output "=== cold-start compile ==="
$cache = Join-Path $project ".godot\global_script_class_cache.cfg"
if (Test-Path $cache) { Remove-Item $cache -Force }

& $godot --headless --path $project --import | Out-Null
if ($LASTEXITCODE -ne 0) { $failed += "import" }

# --quit-after boots the real main scene; a compile failure surfaces here.
$boot = & $godot --headless --path $project --quit-after 30 2>&1
if ($LASTEXITCODE -ne 0 -or ($boot | Select-String "SCRIPT ERROR|Compilation failed|Parse Error")) {
    Write-Output "  main scene failed to compile:"
    $boot | Select-String "SCRIPT ERROR|Parse Error|Compilation failed" | Select-Object -First 8
    $failed += "cold-start compile"
} else {
    Write-Output "  main scene compiles and boots"
}

Write-Output "=== unit + physics ==="
& $godot --headless --path $project --script "res://tests/run_tests.gd" | Select-String "checks,|^PASS|^FAIL"
if ($LASTEXITCODE -ne 0) { $failed += "run_tests" }

if ($Quick) {
    Write-Output "=== quick mode: startup/pilot/net suites skipped (full run certifies the merge) ==="
}
if (-not $Quick) {
Write-Output "=== 8x default startup ==="
& $godot --headless --path $project --script "res://tests/scale_startup_test.gd" | Select-String "SCALE STARTUP|FAIL"
if ($LASTEXITCODE -ne 0) { $failed += "8x_startup" }

Write-Output "=== legacy 1x startup ==="
& $godot --headless --path $project --script "res://tests/world_startup_test.gd" | Select-String "WORLD STARTUP|FAIL"
if ($LASTEXITCODE -ne 0) { $failed += "legacy_1x_startup" }

Write-Output "=== pilot 1x (legacy scene, input-driven flight) ==="
& $godot --headless --path $project --script "res://tests/pilot_test.gd" | Select-String "PILOT|FAIL"
if ($LASTEXITCODE -ne 0) { $failed += "pilot_1x" }

# The same walkthrough on the SHIPPED scene. Until this existed, no test had
# ever walked the native-8x starter: the 8-cell doorways (exact player fit),
# the deck seams and the hatch drops had zero on-foot coverage. Lines tagged
# KNOWN-FAIL are real defects the suite reports without reddening - see the
# block comment in pilot_test.gd.
Write-Output "=== pilot 8x (walks the shipped ship) ==="
& $godot --headless --path $project --script "res://tests/pilot_test.gd" -- --scale 8 | Select-String "PILOT|FAIL"
if ($LASTEXITCODE -ne 0) { $failed += "pilot_8x" }

Write-Output "=== multiplayer (two processes) ==="
& powershell -File (Join-Path $PSScriptRoot "net_smoke.ps1") | Select-String "NET SMOKE|FAIL"
if ($LASTEXITCODE -ne 0) { $failed += "net_smoke" }
}

# SAFETY NET: no test Godot may outlive the runner (a hung headless process is
# invisible load on the play machine). CONSOLE-exe only -- the owner editor
# is the GUI exe and must never be touched.
Get-Process "Godot_v4.6-stable_win64_console" -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue

# WEB RENDERER GUARD (owner 2026-08-25): editor re-saves of project.godot have
# twice DROPPED the [rendering] section, and without the gl_compatibility web
# override every Pages deploy black-screens. Always on, -Quick included.
Write-Output "=== web renderer guard ==="
$projRaw = Get-Content (Join-Path $project "project.godot") -Raw
if ($projRaw -notmatch 'rendering_method\.web="gl_compatibility"') {
    Write-Output "  project.godot LOST the [rendering] web override - restore renderer/rendering_method.web='gl_compatibility' or the web build black-screens"
    $failed += "web_renderer_guard"
} else {
    Write-Output "  gl_compatibility web override present"
}

# Version gate (owner 2026-08-20): anything merged to main MUST carry a new
# x.y.z in project.godot's config/version. Enforced here because run_all is
# the mandatory pre-merge step (AGENTS.md workflow) and there is no remote
# to hang a push hook on. Skipped on main itself so the owner's local play
# never trips it.
Write-Output "=== version gate ==="
$branch = (& git -C $project rev-parse --abbrev-ref HEAD 2>$null)
if ($branch -and $branch -ne "main") {
    $verRe = 'config/version="([^"]+)"'
    $cur = ([regex]::Match((Get-Content (Join-Path $project "project.godot") -Raw), $verRe)).Groups[1].Value
    $mainProj = (& git -C $project show main:project.godot 2>$null) -join "`n"
    $old = ([regex]::Match($mainProj, $verRe)).Groups[1].Value
    & git -C $project diff main --quiet -- . 2>$null
    $hasChanges = ($LASTEXITCODE -ne 0)
    if ($cur -notmatch '^\d+\.\d+\.\d+$') {
        Write-Output "  config/version '$cur' is not x.y.z"
        $failed += "version_gate"
    } elseif ($hasChanges -and $cur -eq $old) {
        Write-Output "  changes vs main but config/version is still $cur - bump it"
        $failed += "version_gate"
    } else {
        Write-Output "  version $cur ok (main has '$old')"
    }
} else {
    Write-Output "  on main - gate not applicable"
}

Write-Output ""
if ($failed.Count -eq 0) {
    Write-Output "ALL SUITES PASS"
    exit 0
}
Write-Output ("FAILED: " + ($failed -join ", "))
exit 1
