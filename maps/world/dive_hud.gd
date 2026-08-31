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
	# THE CARD DRAFT (Q-L): when a choice is on offer, a picker over everything —
	# it is the one moment the run asks you to stop and choose.
	if not (d.get("draft", []) as Array).is_empty():
		_draw_draft(d)


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
	# HULL INTEGRITY (v0.111.0): the one number that ends the run now. Ink while
	# whole, alarm under a third — the ship itself is also scorching (modulate),
	# so this is the number under the picture.
	var hull_frac := float(d.get("hull_frac", -1.0))
	if hull_frac >= 0.0:
		draw_string(font, Vector2(x - 52.0 * s, y + fs * 1.4),
			"hull %d%%" % int(round(hull_frac * 100.0)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			_ALARM if hull_frac < 0.34 else _INK)
	# The den's clock. Only shown when it is close enough to mean something —
	# a permanent countdown would be a nag, and the screen is meant to be calm.
	var into := float(d.get("surge_in", 99.0))
	if into <= 10.0:
		draw_string(font, Vector2(x - 52.0 * s, y + fs * 2.8),
			"they come: %.0f" % maxf(into, 0.0),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _ALARM)

	# THE CARD XP BAR + held count (Q-L), tucked under the coin/clock stack. The
	# bar fills toward the next draft; the count says how strong this run has got.
	var by := y + fs * 4.2
	var bw := 62.0 * s
	var bx := x - 52.0 * s
	var need := maxf(float(d.get("xp_need", 1)), 1.0)
	var frac := clampf(float(d.get("xp", 0)) / need, 0.0, 1.0)
	draw_rect(Rect2(Vector2(bx, by), Vector2(bw, 4.0 * s)), Color(0.18, 0.22, 0.28))
	draw_rect(Rect2(Vector2(bx, by), Vector2(bw * frac, 4.0 * s)), Color(0.55, 0.78, 0.95))
	var held := (d.get("cards", []) as Array).size()
	draw_string(font, Vector2(bx, by + fs * 1.3),
		"cards %d" % held, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _DIM)


## THE DRAFT PICKER — a choice of up to three cards, centred low so it does not
## cover the sky you are flying. Pick with 1 / 2 / 3 (world._try_pick_card).
func _draw_draft(d: Dictionary) -> void:
	var font := ThemeDB.fallback_font
	var s := _scale()
	var fs := 13 * s
	var hs := 15 * s
	var view := size
	var cards := d.get("draft", []) as Array
	var cw := 210.0 * s
	var gap := 12.0 * s
	var total := float(cards.size()) * cw + float(maxi(0, cards.size() - 1)) * gap
	var x0 := view.x * 0.5 - total * 0.5
	var top := view.y * 0.66
	var ch := 84.0 * s
	# A dim banner so the choice reads as a deliberate pause.
	draw_string(font, Vector2(view.x * 0.5 - 90.0 * s, top - 14.0 * s),
		"CHOOSE A CARD", HORIZONTAL_ALIGNMENT_LEFT, -1, hs, _INK)
	for i in cards.size():
		var card := cards[i] as Dictionary
		var cx := x0 + float(i) * (cw + gap)
		var box := Rect2(Vector2(cx, top), Vector2(cw, ch))
		draw_rect(box, Color(0.05, 0.07, 0.11, 0.92))
		draw_rect(box, Color(_DIM, 0.7), false, 1.0 * s)
		draw_string(font, Vector2(cx + 10.0 * s, top + fs * 1.4),
			"[%d]  %s" % [i + 1, String(card.get("name", ""))],
			HORIZONTAL_ALIGNMENT_LEFT, -1, hs, _COIN)
		# The description wraps inside the card width.
		draw_multiline_string(font, Vector2(cx + 10.0 * s, top + fs * 3.0),
			String(card.get("desc", "")), HORIZONTAL_ALIGNMENT_LEFT,
			cw - 20.0 * s, fs, -1, _INK)


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
		"went down    %d" % int(d.get("deaths", 0)),
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
