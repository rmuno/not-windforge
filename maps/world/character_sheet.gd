class_name CharacterSheet
extends Control

## The toggled character sheet (Sprint 5, the progression layer). Hidden by
## default and opened with K — NOT always-on, honouring the decluttered-screen
## direction (owner 2026-08-22: the last slice removed the wall of always-on
## chrome; this must not put one back). It doubles as the SHOP: while it is open
## and you are standing by a trainer, it shows the costs and the salvage value,
## and the number keys buy levels / sell salvage.
##
## Pure presentation, the same split HudLayer/MapView use: every decision — levels,
## perks, costs, whether a trainer is in reach — is made in the world
## (`character_sheet_model`); this only paints it, so nothing here can touch a
## Player, a Stats or a Wallet directly.

var world: Node2D

## SCREEN-space UI, so its size must NOT track world_scale — at the shipped 8×
## that drew the whole sheet 8× oversize and off the screen (owner 2026-08-23:
## "the character sheet is just far too large"). A comfortable fixed size, nudged
## up only on hi-dpi displays, exactly like HudLayer.
func _scale() -> int:
	var vh := get_viewport_rect().size.y
	return clampi(int(round(vh / 900.0)), 1, 3)


func _ready() -> void:
	# Centre-anchored, hidden until K. Ignore the mouse — the game reads the raw
	# cursor and the sheet is keyboard-driven.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func toggle() -> void:
	visible = not visible


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()  # live: money, reach and costs change while it is open


func _draw() -> void:
	if world == null or not visible:
		return
	var model: Variant = world.call("character_sheet_model")
	if model == null:
		return
	var m := model as Dictionary
	var font := ThemeDB.fallback_font
	var s := _scale()
	var fs := 14 * s
	var small := 12 * s
	var line := fs + 6 * s

	# A calm, centred panel sized to the content.
	var stock: Array = m.get("outpost_stock", [])
	var stats: Array = m.get("stats", [])
	if not stock.is_empty():
		return _draw_outpost(m, stock)
	var rows := 3 + stats.size() * 7 + 3   # title/money + per-stat header+5 perks+gap + footer
	var w := 360.0 * s
	var h := float(rows) * (small + 3 * s) + 40.0 * s
	var origin := Vector2((size.x - w) * 0.5, (size.y - h) * 0.5)

	draw_rect(Rect2(origin, Vector2(w, h)), Color(0.05, 0.07, 0.10, 0.94))
	draw_rect(Rect2(origin, Vector2(w, h)), Color(0.35, 0.42, 0.52, 0.9), false, 1.0)

	var x := origin.x + 16.0 * s
	var y := origin.y + 24.0 * s

	draw_string(font, Vector2(x, y), "CHARACTER   (K to close)",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.90, 0.94, 1.0))
	y += line
	draw_string(font, Vector2(x, y), "Money:  $%d" % int(m.get("money", 0)),
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.86, 0.45))
	y += line + 4.0 * s

	var key := 1
	for st in stats:
		var stat := st as Dictionary
		var cost := int(stat.get("next_cost", -1))
		var cost_text := "MAX" if cost < 0 else "[%d] train  $%d" % [key, cost]
		draw_string(font, Vector2(x, y), "%s   L%d/%d   %s" % [
			stat.get("name", "?"), int(stat.get("level", 1)),
			int(stat.get("max", 5)), cost_text],
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.82, 0.90, 0.98))
		y += small + 4 * s
		for perk in stat.get("perks", []) as Array:
			var p := perk as Dictionary
			var unlocked := bool(p.get("unlocked", false))
			var col := Color(0.55, 0.82, 0.55) if unlocked else Color(0.45, 0.47, 0.52)
			var mark := "+" if unlocked else "-"
			draw_string(font, Vector2(x + 12.0 * s, y),
				"%s %s" % [mark, p.get("name", "")],
				HORIZONTAL_ALIGNMENT_LEFT, -1, small, col)
			y += small + 3 * s
		y += 4.0 * s
		key += 1

	# Footer: the shop line if a trainer is in reach, else the where-to hint.
	y += 6.0 * s
	if bool(m.get("near_trainer", false)):
		draw_string(font, Vector2(x, y),
			"[0] sell salvage  (+$%d)" % int(m.get("salvage_value", 0)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, small, Color(0.95, 0.90, 0.60))
	else:
		draw_string(font, Vector2(x, y),
			"Stand by a trainer to train or sell salvage.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, small, Color(0.62, 0.66, 0.72))


## THE OUTPOST'S COUNTER — the same panel, the same digits, a different trade
## (owner 2026-08-30: "a few natural safe zones along the way … in-run upgrades
## which are temporary but MUCH cheaper than anything permanent").
##
## It replaces the stat sheet entirely while you stand at a quartermaster: the
## two can never be in reach at once, and a run has no use for the permanent
## ladder — what it needs is the line at the top, which says that everything
## here is bought with coins you have not taken home yet.
func _draw_outpost(m: Dictionary, stock: Array) -> void:
	var font := ThemeDB.fallback_font
	var s := _scale()
	var fs := 14 * s
	var small := 12 * s
	var line := fs + 6 * s
	var w := 420.0 * s
	var h := float(stock.size() + 5) * line + 30.0 * s
	var origin := Vector2((size.x - w) * 0.5, (size.y - h) * 0.5)
	draw_rect(Rect2(origin, Vector2(w, h)), Color(0.06, 0.06, 0.05, 0.95))
	draw_rect(Rect2(origin, Vector2(w, h)), Color(0.55, 0.46, 0.32, 0.9), false, 1.0)

	var x := origin.x + 16.0 * s
	var y := origin.y + 26.0 * s
	draw_string(font, Vector2(x, y), "THE OUTPOST   (K to close)",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.94, 0.88, 0.74))
	y += line
	draw_string(font, Vector2(x, y), "Carrying:  %d coins  (unbanked)"
		% int(m.get("pot", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(0.95, 0.86, 0.45))
	y += line + 4.0 * s
	for row in stock:
		var r := row as Dictionary
		var afford := bool(r.get("afford", false))
		var col := Color(0.86, 0.90, 0.96) if afford else Color(0.48, 0.46, 0.44)
		draw_string(font, Vector2(x, y), "[%d]  %-46s %4d" % [
			int(r.get("key", 0)), String(r.get("label", "")), int(r.get("cost", 0))],
			HORIZONTAL_ALIGNMENT_LEFT, -1, small, col)
		y += line
	y += 6.0 * s
	draw_string(font, Vector2(x, y),
		"Every coin spent here is a coin you do not carry home.",
		HORIZONTAL_ALIGNMENT_LEFT, -1, small, Color(0.62, 0.60, 0.56))
