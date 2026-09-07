class_name CombatScore
extends RefCounted

## THE COMBAT SCORECARD'S ARITHMETIC (Q-O), on its own so it can be TESTED.
##
## `tools/dive_probe.gd` prints hit rates, uptimes and time-to-kill off tallies
## it collects during a run. A probe is not a test — it measures and never
## asserts — so every one of those numbers used to be un-checkable: a divide by
## the wrong denominator, or an interval union that double-counts an overlap,
## would print a plausible percentage and steer a design decision. The four
## Q-O candidates are ranked off these figures, so the figures themselves get a
## test (`tests/run_tests.gd` → the combat scorecard's arithmetic).
##
## Pure and dependency-free ON PURPOSE: no autoloads, no other class_names, no
## engine state. That is what lets the probe `preload()` it inside a `--script`
## file without dragging a compile of the autoload graph in behind it
## (CODEMAP §4), and what lets the suite call it with plain numbers.
##
## Every function answers with 0.0 for an empty denominator rather than NAN or
## INF: a run where nobody fired must print "0%", not "nan%".


## A percentage of a whole. 0.0 when the whole is empty or negative — "nothing
## was fired" is not "an undefined hit rate", and a probe line reading `nan%`
## has cost more than one session's confidence.
static func pct(part: float, whole: float) -> float:
	if whole <= 0.0:
		return 0.0
	return 100.0 * part / whole


## Shells that LANDED, as a percentage of shells FIRED. Landed can never exceed
## fired — if it does the tallies are broken, and clamping would hide that, so
## the raw ratio is returned and the caller's numbers speak for themselves.
static func hit_pct(landed: int, fired: int) -> float:
	return pct(float(landed), float(fired))


## Seconds held as a percentage of seconds it COULD have held — the kraken grab
## line. Uptime is the honest version of "grabs per minute": a hunter that never
## got within reach cannot be blamed for not grabbing, and one that was in reach
## for the whole descent and grabbed for two seconds of it is a different
## problem from one that never arrived.
static func uptime_pct(held: float, in_reach: float) -> float:
	return pct(held, in_reach)


## Frames × the fixed step, as seconds. The probe counts frames because that is
## what a per-frame tally can honestly count; every printed figure goes through
## here so the conversion lives in one place.
static func frames_to_secs(frames: int, step: float) -> float:
	return float(maxi(frames, 0)) * step


## Total length of the UNION of `spans` — an array of two-element [start, end]
## arrays. Overlapping engagements are merged, so "seconds in contact" is wall
## time and not the sum of every hostile's own clock: three pickets on you at
## once for ten seconds is ten seconds of fighting, not thirty.
##
## Backwards or zero-length spans contribute nothing. Input is not mutated.
static func span_union(spans: Array) -> float:
	var live: Array = []
	for s in spans:
		var a: Array = s
		if a.size() < 2:
			continue
		var lo := float(a[0])
		var hi := float(a[1])
		if hi > lo:
			live.append([lo, hi])
	if live.is_empty():
		return 0.0
	live.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	var total := 0.0
	var cur_lo := float(live[0][0])
	var cur_hi := float(live[0][1])
	for i in range(1, live.size()):
		var lo := float(live[i][0])
		var hi := float(live[i][1])
		if lo > cur_hi:
			total += cur_hi - cur_lo
			cur_lo = lo
			cur_hi = hi
		else:
			cur_hi = maxf(cur_hi, hi)
	return total + cur_hi - cur_lo


## Mean of a list of floats; 0.0 for an empty list (no kills means no
## time-to-kill, not a division by zero).
static func mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sum := 0.0
	for v in values:
		sum += float(v)
	return sum / float(values.size())


## TIME TO KILL: from the first shell of OURS that landed on a body to the
## moment it died. -1.0 when the body was never hit by us (it died to terrain,
## to another hostile, or it was never engaged) or when the clock runs
## backwards — a kill we cannot attribute must not be averaged in as a fast one.
static func ttk(first_hit_t: float, died_t: float) -> float:
	if first_hit_t < 0.0 or died_t < first_hit_t:
		return -1.0
	return died_t - first_hit_t


## A rate per minute, from a count and a duration in seconds. 0.0 for a run of
## no length.
static func per_minute(count: int, secs: float) -> float:
	if secs <= 0.0:
		return 0.0
	return float(count) * 60.0 / secs


## An average per unit, with an empty denominator reading 0.0 — "damage taken
## per picket met" in a run that met none is zero, not the whole run's damage.
static func per_each(total: float, n: int) -> float:
	if n <= 0:
		return 0.0
	return total / float(n)
