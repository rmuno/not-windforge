class_name SealBands
extends Node2D

## THE DESCENT SEAL, painted (DESIGN_DESCENT.md §7 — "some quick visible
## aggressive wind-looking thing").
##
## A band of lethal rising air sits under each depth of a Dive run, live until
## that depth's whole standing garrison is dead. This draws it, and NOTHING else:
## every value comes from `world.seal_bands()` as plain Rects, bools and ints,
## per the standing world-decides/layer-paints rule. It never touches a Ship, the
## run model or the terrain.
##
## Behind the world (`z_index` below terrain and hulls) on purpose: an island
## crossing a band then occludes the streaks by simply being opaque, which is
## ruling 4's "the wind goes around it" for free and with no terrain scan. The
## measured shadow (slice 6) will make that true of the FORCE as well; today it
## is true of the picture.

var world: Node2D

## Behind terrain and every hull, above the lava core (-50) and the backdrop
## layer (-1 is a whole CanvasLayer, further back still).
const Z := -20

## The wash, deliberately opposite `DeepFog.HAZE` (0.52, 0.40, 0.16) so the two
## deepest seals stay legible inside the ember murk.
const WASH := Color(0.62, 0.72, 0.85, 0.16)
const STREAK := Color(0.86, 0.93, 1.0)
const LIP := Color(0.78, 0.88, 1.0, 0.8)
const DEAD := Color(0.45, 0.52, 0.62, 0.30)

## Streaks per visible band. Enough to read as violent, few enough that six
## bands on screen at max zoom is still a hundred and fifty lines.
const STREAKS := 26

var _t := 0.0


func _ready() -> void:
	z_index = Z


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()  # erasing is a redraw too (godot-quirks)


func _draw() -> void:
	if world == null or not world.has_method("seal_bands"):
		return
	for row_v in (world.call("seal_bands") as Array):
		var row := row_v as Dictionary
		var r := row.get("rect", Rect2()) as Rect2
		if r.size.y <= 0.0 or r.size.x <= 0.0:
			continue
		if not bool(row.get("live", false)):
			# CLEARED. The band's death has to be visible from a screen away,
			# because it is the reward for the fight: everything goes, and one
			# faint line is left along the centre saying a door used to be here.
			draw_line(Vector2(r.position.x, r.get_center().y),
				Vector2(r.end.x, r.get_center().y), DEAD, maxf(r.size.y * 0.01, 2.0))
			continue
		draw_rect(r, WASH)
		# THE STREAKS — the aggressive part. Deterministic phase per index so they
		# scroll rather than shimmer, and scrolling UP because that is which way
		# the air is going and which way it will throw you.
		var seed_i := int(row.get("depth", 2)) * 97
		for i in STREAKS:
			var f := float((i * 37 + seed_i) % 1000) / 1000.0
			var x := r.position.x + f * r.size.x
			var phase := fposmod(_t * 0.55 + f * 3.7, 1.0)
			var len_px := r.size.y * (0.18 + 0.14 * fposmod(f * 7.3, 1.0))
			var y := r.end.y - phase * (r.size.y + len_px)
			var a := 0.35 + 0.35 * fposmod(f * 11.1, 1.0)
			draw_line(Vector2(x, maxf(y, r.position.y)),
				Vector2(x, minf(y + len_px, r.end.y)),
				Color(STREAK, a), maxf(r.size.y * 0.0012, 1.0) * 3.0)
		# THE LIPS. The safe/unsafe line is what the whole ruling turns on, so the
		# boundaries are drawn exactly rather than left as a gradient to guess at.
		var lw := maxf(r.size.y * 0.004, 2.0)
		draw_line(r.position, Vector2(r.end.x, r.position.y), LIP, lw)
		draw_line(Vector2(r.position.x, r.end.y), r.end, LIP, lw)
