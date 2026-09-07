class_name TickPerf
extends RefCounted

## WHO SPENT THE PHYSICS TICK — per-BODY attribution, not per-system.
##
## `world._step_systems` already answers "which of the world's systems" (the F3
## SYS line, `take_system_ms`). What it cannot see is everything else inside the
## step: the solver, and every node's own `_physics_process` /
## `_integrate_forces`. On the owner's 2026-09-07 floor capture that remainder
## was ~96% of the tick — `SYS total=6.7 ms` against a step that was costing tens
## of milliseconds — so the SYS line was measuring the wrong 4%.
##
## This is the other half: a stopwatch each participating callback bills itself
## into, keyed by a label the caller chooses (a body's creature kind + cell
## count, "shots", "player"). Then
##
##     solver = wall time per tick - SYS total - everything booked here
##
## which is an attribution that ADDS UP, which is the only kind worth having.
##
## COST WHEN OFF: one static bool read per callback. `on` is false in play and
## nothing but a probe or a timing check ever sets it — deliberately NOT wired to
## the F3 recording, because the F3 capture is the owner's and a probe must never
## overwrite it (the same rule `world.sys_timing_forced` follows).
##
## Godot's own per-node profiler is editor-only, so this is the headless
## equivalent; `Time.get_ticks_usec()` is the same clock `_step_systems` uses, so
## the two halves are comparable without conversion.

## The stopwatch. Off in play.
static var on := false

## label -> microseconds accumulated since the last reset.
static var usec := {}
## label -> how many callbacks were billed, so a per-call cost is derivable
## (600 shots at 3 us and one whale at 1.8 ms are very different problems).
static var calls := {}


static func reset() -> void:
	usec.clear()
	calls.clear()


## Bill `t0` (a `Time.get_ticks_usec()` stamp taken before the work) to `label`.
static func bill(label: String, t0: int) -> void:
	var dt := Time.get_ticks_usec() - t0
	usec[label] = int(usec.get(label, 0)) + dt
	calls[label] = int(calls.get(label, 0)) + 1


## Everything booked, in milliseconds per tick, given how many ticks were
## sampled. Returns [[label, ms, calls_per_tick], ...] sorted by cost.
static func rows(ticks: int) -> Array:
	var n := maxi(ticks, 1)
	var out: Array = []
	for k in usec:
		out.append([k, float(usec[k]) * 0.001 / float(n),
			float(calls.get(k, 0)) / float(n)])
	out.sort_custom(func(a, b) -> bool: return float(a[1]) > float(b[1]))
	return out


## The total booked, in ms per tick.
static func total_ms(ticks: int) -> float:
	var sum := 0
	for k in usec:
		sum += int(usec[k])
	return float(sum) * 0.001 / float(maxi(ticks, 1))
