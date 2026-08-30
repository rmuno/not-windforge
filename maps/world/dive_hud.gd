class_name DiveHud
extends Control

## THE DIVE's read-out and its ledger (owner arc Q-G, 2026-08-30).
##
## Two things, and only when a run is live:
##   * a small DEPTH GAUGE on the right edge — the eight rungs of the ladder,
##     where you are on it, and how far down you have been. The run's whole
##     tension is vertical, so the gauge is vertical and sits where you are
##     already looking when you point the nose down.
##   * the coins you are CARRYING (unbanked — they burn with the ship), and the
##     seconds until this depth's den comes for you.
## When the run ends it draws THE LEDGER over everything: what you reached, what
## you banked or lost, and the line you will try to beat next time. On a lost run
## the world behind it is your body falling, which is the point (owner: "do you
## just fall until you die and that's that? 'you traversed X vertical distance'").
##
## Paints only. Every value comes from `world.dive_status()` as plain data, per
## the standing world-decides/layer-paints rule — nothing here reaches a Ship or
## a DiveRun.

var world: Node2D

const _INK := Color(0.88, 0.92, 1.0)
const _DIM := Color(0.55, 0.62, 0.74)
const _COIN := Color(0.95, 0.83, 0.42)
const _ALARM := Color(0.95, 0.45, 0.38)


## Screen-space chrome: sized off the viewport, never off world_scale (the 8×
## HUD ran off the screen once — see HudLayer._scale).
func _scale() -> int:
	var vh := get_viewport_rect().size.y
	return clampi(int(round(vh / 900.0)), 1, 3)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()  # erasing is a redraw too (godot-quirks)


func _draw() -> void:
	if world == null or not world.has_method("dive_status"):
		return
	var st: Variant = world.call("dive_status")
	if st == null:
		return  # no run: the Dive HUD does not exist outside the Dive
	var d := st as Dictionary
	if String(d.get("outcome", "")) != "":
		_draw_ledger(d)
		return
	_draw_gauge(d)


## The depth gauge: the ladder as eight rungs down the right edge, the current
## rung filled, the deepest rung marked. Plus the carried coins and the surge
## clock, stacked beneath it.
func _draw_gauge(d: Dictionary) -> void:
	var font := ThemeDB.fallback_font
	var s := _scale()
	var fs := 12 * s
	var view := size
	var rungs := int(d.get("depths", 8))
	var here := int(d.get("depth", 1))
	var deepest := int(d.get("deepest", 1))
	var w := 10.0 * s
	var gap := 4.0 * s
	var h := 14.0 * s
	var x := view.x - 22.0 * s - w
	var y0 := view.y * 0.5 - (float(rungs) * (h + gap)) * 0.5

	draw_string(font, Vector2(x - 52.0 * s, y0 - 8.0 * s), "THE DIVE",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _DIM)
	for i in rungs:
		var d_i := i + 1
		var r := Rect2(Vector2(x, y0 + float(i) * (h + gap)), Vector2(w, h))
		# The rung's own colour is the depth's character: safe up top, hot at
		# the floor. The same red the deep already speaks elsewhere.
		var t := float(i) / float(maxi(1, rungs - 1))
		var base := Color(0.20, 0.30, 0.34).lerp(Color(0.42, 0.14, 0.13), t)
		draw_rect(r, base)
		if d_i <= deepest:
			draw_rect(r, Color(base.lerp(_ALARM, 0.35), 0.9), false, 1.0 * s)
		if d_i == here:
			draw_rect(r.grow(2.0 * s), _INK, false, 2.0 * s)
	# The floor is a place, not a number.
	draw_string(font, Vector2(x - 52.0 * s, y0 + float(rungs) * (h + gap) + fs),
		String(d.get("depth_label", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _INK)

	# Carried coins — unbanked, and the word matters: this is what burns.
	var y := y0 + float(rungs) * (h + gap) + fs * 2.6
	draw_string(font, Vector2(x - 52.0 * s, y), "carrying %d" % int(d.get("pot", 0)),
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _COIN)
	# NO HULL YET. On the launch deck the run has no ship to lose, and the one
	# thing worth saying is what the deck is for.
	if bool(d.get("shipless", false)):
		draw_string(font, Vector2(x - 52.0 * s, y + fs * 1.4), "no ship",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _ALARM)
		return
	# The den's clock. Only shown when it is close enough to mean something —
	# a permanent countdown would be a nag, and the screen is meant to be calm.
	var into := float(d.get("surge_in", 99.0))
	if into <= 10.0:
		draw_string(font, Vector2(x - 52.0 * s, y + fs * 1.4),
			"they come: %.0f" % maxf(into, 0.0),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _ALARM)


## THE LEDGER — the run-over screen. A centred plate over whatever the world is
## doing behind it (on a lost run, that is your body falling).
func _draw_ledger(d: Dictionary) -> void:
	var font := ThemeDB.fallback_font
	var s := _scale()
	var fs := 15 * s
	var view := size
	var lines: Array[String] = [
		String(d.get("headline", "")),
		"",
		"reached      %s" % String(d.get("deepest_label", "")),
		"kills        %d" % int(d.get("kills", 0)),
		"attacks      %d" % int(d.get("surges", 0)),
		"time         %s" % _mmss(float(d.get("elapsed", 0.0))),
		"banked       %d coins" % int(d.get("banked", 0)),
		"",
		"(any key)",
	]
	var wide := 0.0
	for l in lines:
		wide = maxf(wide, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var pad := 18.0 * s
	var box := Rect2(
		Vector2(view.x * 0.5 - wide * 0.5 - pad, view.y * 0.32 - pad),
		Vector2(wide + pad * 2.0, float(lines.size()) * fs * 1.45 + pad * 2.0))
	draw_rect(box, Color(0.04, 0.05, 0.08, 0.88))
	draw_rect(box, Color(_DIM, 0.5), false, 1.0 * s)
	var y := box.position.y + pad + fs
	for i in lines.size():
		var col := _INK if i == 0 else _DIM
		if String(lines[i]).begins_with("banked"):
			col = _COIN
		draw_string(font, Vector2(box.position.x + pad, y), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		y += fs * 1.45


static func _mmss(sec: float) -> String:
	var t := maxi(0, int(sec))
	return "%d:%02d" % [t / 60, t % 60]
