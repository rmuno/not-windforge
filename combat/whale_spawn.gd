class_name WhaleSpawn
extends RefCounted

## The pod picker (Sprint 4, whale-variant spawning). The design jam
## (2026-08-20) produced five authored body plans, all suite-gated by
## `_check_whale_body_plan`; today the world only ever spawned
## `whale.ship`. This turns the sky's whales into a VARIED pod: a weighted
## pick over the five plans, so a few whales roaming read as different
## creatures, not clones.
##
## Weighting follows the ROADMAP (Phase 4): "three common, one semi-rare,
## one very rare". The reference blue and the bull/humpback are the
## everyday whales; the sleek is a semi-rare; the leviathan is the rare
## giant (its 1.6× mass makes its ram superlinearly harder — a per-variant
## charge-accel tune is a documented seam, kept rare so a one-in-a-pod
## leviathan cannot routinely one-shot a starter — see DECISIONS/BACKLOG).
##
## Cosmetic-only per-variant TINTS give the pod visible variety beyond
## silhouette (Ship.body_tint is documented cosmetic — never mass/collision/
## damage). The ghost-whale easter egg (a rare pale tint) still overrides
## these when its seed rolls (maps/world/easter_eggs.gd → the Pale Wanderer).
##
## Pure logic (a RefCounted, no tree, RNG passed in), so the whole pick is
## unit-testable without booting the world (see run_tests).

## One entry per authored body plan: its .ship path, spawn weight, and a
## cosmetic body tint. Weights need not sum to anything — pick_plan
## normalises against their total.
const PLANS := [
	{"path": "res://ships/whale.ship",           "weight": 10, "tint": Color(0.82, 0.86, 0.95)},  # reference blue — common
	{"path": "res://ships/whale_bull.ship",      "weight": 8,  "tint": Color(0.90, 0.84, 0.74)},  # tan bull — common
	{"path": "res://ships/whale_humpback.ship",  "weight": 8,  "tint": Color(0.78, 0.82, 0.80)},  # grey humpback — common
	{"path": "res://ships/whale_sleek.ship",     "weight": 4,  "tint": Color(0.74, 0.80, 0.90)},  # steel sleek — semi-rare
	{"path": "res://ships/whale_leviathan.ship", "weight": 1,  "tint": Color(0.86, 0.74, 0.78)},  # pale-red leviathan — very rare
]


## Weighted pick over PLANS, returning the chosen plan's .ship path. `rng`
## is passed in so the caller owns determinism (a fixed seed → a fixed pod,
## exactly like the world seed picks a fixed island field).
static func pick_plan(rng: RandomNumberGenerator) -> String:
	var total := 0
	for p in PLANS:
		total += int(p["weight"])
	var roll := rng.randi_range(0, total - 1)
	var acc := 0
	for p in PLANS:
		acc += int(p["weight"])
		if roll < acc:
			return String(p["path"])
	return String(PLANS[0]["path"])  # unreachable; a total>0 guard for safety


## The cosmetic tint for a body plan (white if the path is unknown). The
## world multiplies this over the whale's block colours, unless the ghost
## roll overrides it.
static func tint_for(path: String) -> Color:
	for p in PLANS:
		if String(p["path"]) == path:
			return p["tint"]
	return Color.WHITE
