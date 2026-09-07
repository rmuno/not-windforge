class_name SealBands
extends Node2D

## THE LADDER, painted (DESIGN_DESCENT §11 / §7 — "some quick visible aggressive
## wind-looking thing").
##
## Two columns of rectangular wind loops run the height of the Dive's sky: wind
## on the perimeter, a carrying calm inside, the whole stack translating. This
## draws them, and NOTHING else: every value comes from `world.ladder_bands()` as
## plain Rects, unit direction vectors and bools, per the standing
## world-decides/layer-paints rule. It never touches a Ship, the run model or the
## terrain.
##
## Behind the world (`z_index` below terrain and hulls) on purpose: an island
## crossing a wall then occludes the streaks by simply being opaque, which is
## ruling 4's "the wind goes around it" for free and with no terrain scan — and
## since ruling 8 the FORCE agrees with the picture (a pocket closed left and
## right is out of the wind).

var world: Node2D

## Behind terrain and every hull, above the lava core (-50) and the backdrop
## layer (-1 is a whole CanvasLayer, further back still).
const Z := -20

## The wash on a WALL, deliberately opposite `DeepFog.HAZE` (0.52, 0.40, 0.16) so
## the deepest walls stay legible inside the ember murk.
const WASH := Color(0.62, 0.72, 0.85, 0.16)
const STREAK := Color(0.86, 0.93, 1.0)
const LIP := Color(0.78, 0.88, 1.0, 0.8)
## The CALM interior: a whisper, not a wash. It is still moving — it carries you
## — so it gets streaks of its own at a fraction of the wall's alpha, which is
## the only thing on screen that says "this rectangle is going somewhere".
const CALM := Color(0.62, 0.72, 0.85, 0.04)

## Streaks per visible piece. A wall is thin and wants density; the calm is
## enormous and wants almost nothing, so it gets a quarter as many.
const STREAKS := 22

var _t := 0.0


func _ready() -> void:
	z_index = Z


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()  # erasing is a redraw too (godot-quirks)


func _draw() -> void:
	if world == null or not world.has_method("ladder_bands"):
		return
	for row_v in (world.call("ladder_bands") as Array):
		var row := row_v as Dictionary
		var r := row.get("rect", Rect2()) as Rect2
		if r.size.y <= 0.0 or r.size.x <= 0.0:
			continue
		var dir := row.get("dir", Vector2.ZERO) as Vector2
		if not bool(row.get("band", true)):
			_draw_flow(r, dir, CALM, int(float(STREAKS) * 0.25), 0.10)
			continue
		draw_rect(r, WASH)
		_draw_flow(r, dir, Color(STREAK, 1.0), STREAKS, 0.7)
		# THE LIPS. Safe air and a wall is what the whole ruling turns on, so the
		# boundary is drawn exactly rather than left as a gradient to guess at —
		# on the two LONG sides, whichever way this piece runs.
		var lw := maxf(minf(r.size.x, r.size.y) * 0.02, 2.0)
		if r.size.y >= r.size.x:
			draw_line(r.position, Vector2(r.position.x, r.end.y), LIP, lw)
			draw_line(Vector2(r.end.x, r.position.y), r.end, LIP, lw)
		else:
			draw_line(r.position, Vector2(r.end.x, r.position.y), LIP, lw)
			draw_line(Vector2(r.position.x, r.end.y), r.end, LIP, lw)


## Streaks scrolling ALONG `dir` inside `r` — the aggressive part, and the part
## that says which way this piece will throw you. Deterministic phase per index
## so they scroll rather than shimmer.
func _draw_flow(r: Rect2, dir: Vector2, tint: Color, count: int,
		alpha: float) -> void:
	if count <= 0 or dir == Vector2.ZERO:
		return
	var vertical := absf(dir.y) > absf(dir.x)
	# How far a streak travels (along the flow) and how wide the piece is across
	# it — the two axes swap with the piece's orientation and nothing else does.
	var run: float = r.size.y if vertical else r.size.x
	var across: float = r.size.x if vertical else r.size.y
	var seed_i := int(absf(r.position.x) + absf(r.position.y)) % 997
	var forward := (dir.x + dir.y) > 0.0
	for i in count:
		var f := float((i * 37 + seed_i) % 1000) / 1000.0
		var len_px := run * (0.10 + 0.10 * fposmod(f * 7.3, 1.0))
		var phase := fposmod(_t * 0.55 + f * 3.7, 1.0) * (run + len_px)
		var travel: float = phase if forward else (run + len_px) - phase
		var a0 := maxf(travel - len_px, 0.0)
		var a1 := minf(travel, run)
		if a1 <= a0:
			continue
		var b := f * across
		var alpha_i := alpha * (0.5 + 0.5 * fposmod(f * 11.1, 1.0))
		var w := maxf(across * 0.004, 1.0) * 2.0
		if vertical:
			draw_line(Vector2(r.position.x + b, r.position.y + a0),
				Vector2(r.position.x + b, r.position.y + a1),
				Color(tint, alpha_i), w)
		else:
			draw_line(Vector2(r.position.x + a0, r.position.y + b),
				Vector2(r.position.x + a1, r.position.y + b),
				Color(tint, alpha_i), w)
