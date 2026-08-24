class_name WorldOverlay
extends Node2D

## World-space text and markers that must render ABOVE every ship.
##
## A Node2D's own drawing always sits BENEATH its children, and ships are
## children of the world — so anything the world itself draws (terrain,
## correctly behind) can never float in front of a hull. This node exists
## purely to own a canvas item with a sky-high z_index for prompts.

var world: Node2D


func _ready() -> void:
	z_as_relative = false
	z_index = 4000


func _process(_delta: float) -> void:
	queue_redraw()  # erasing is a redraw too (godot-quirks)


func _draw() -> void:
	if world == null:
		return
	_draw_build_ghost()
	_draw_mine_target()
	_draw_place_target()
	_draw_balloons()
	_draw_interact_prompt()
	_draw_damage_numbers()
	_draw_pickups()


## The block that Q WOULD place, where it would land — green when the
## placement is legal, red when it would be refused. Purely a picture:
## every decision behind it was made in the world's build_ghost(), which
## hands over plain values precisely so nothing here can touch a ship.
func _draw_build_ghost() -> void:
	var ghost: Variant = world.call("build_ghost")
	if ghost == null:
		return
	var g := ghost as Array
	var xform := g[0] as Transform2D
	var rect := g[1] as Rect2
	var base := g[2] as Color
	var tint := g[3] as Color

	# Drawn in the SHIP's frame: the cell rect is in ship-local px, and a
	# ship can be posed off level (whales pitch), so a world-space rect
	# would slide off the grid it is claiming to sit on.
	draw_set_transform_matrix(xform)
	var body := base.lerp(tint, 0.55)
	body.a = 0.40
	draw_rect(rect, body)
	draw_rect(rect, Color(tint, 0.95), false, 2.0)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## The terrain cell the mine action is aimed at: an outlined highlight while Z
## is held, filling up as the cut progresses. Green in reach, red out of reach —
## so "you can't reach that" is legible before you wonder why nothing happens.
## All the state lives in the world's mine_target(); this only paints it.
func _draw_mine_target() -> void:
	var target: Variant = world.call("mine_target")
	if target == null:
		return
	var t := target as Array
	var rect := t[0] as Rect2
	var progress := float(t[1])
	var in_reach := bool(t[2])
	var edge := Color(0.45, 1.0, 0.55) if in_reach else Color(1.0, 0.45, 0.42)
	# A faint fill that grows from the bottom as the cell is cut — the tactile
	# "almost through" read. No fill at all when out of reach.
	if in_reach and progress > 0.0:
		var fill := rect
		fill.position.y += rect.size.y * (1.0 - progress)
		fill.size.y *= progress
		draw_rect(fill, Color(edge, 0.30))
	var s: float = float(world.get("world_scale"))
	draw_rect(rect, Color(edge, 0.95), false, maxf(2.0, 2.0 * s))


## The terrain cell the place action is aimed at while V is held — the mirror of
## the mine highlight. Green when the placement is legal (in reach, empty,
## stocked), red when it would be refused, with a faint fill so it reads as
## "block will land here". All the decision lives in the world's place_target().
func _draw_place_target() -> void:
	var target: Variant = world.call("place_target")
	if target == null:
		return
	var t := target as Array
	var rect := t[0] as Rect2
	var legal := bool(t[1])
	var edge := Color(0.45, 1.0, 0.55) if legal else Color(1.0, 0.45, 0.42)
	if legal:
		draw_rect(rect, Color(edge, 0.22))
	var s: float = float(world.get("world_scale"))
	draw_rect(rect, Color(edge, 0.95), false, maxf(2.0, 2.0 * s))


## Tethered helium balloons above the ships/corpses they lift (carcass-as-airship).
## World space, above the hulls. All the geometry (anchor, swaying centre, radius,
## cable count) is computed in the world's balloons_to_draw(); this only paints —
## cables from the balloon down to points spanning the anchor cell, then the bulb.
func _draw_balloons() -> void:
	var specs: Variant = world.call("balloons_to_draw")
	if specs == null:
		return
	for s in (specs as Array):
		var anchor := s["anchor"] as Vector2
		var center := s["center"] as Vector2
		var radius := float(s["radius"])
		var cables := int(s["cables"])
		var u := float(s["unit"])
		var bottom := center + Vector2(0.0, radius)
		var cable_col := Color(0.80, 0.76, 0.64, 0.85)
		for c in cables:
			var spread := 0.0
			if cables > 1:
				spread = (float(c) / float(cables - 1) - 0.5) * 2.0
			var foot := anchor + Vector2(spread * Ship.CELL * u, 0.0)
			draw_line(bottom, foot, cable_col, maxf(1.0, 1.4 * u))
		# The bulb: a warm helium red, a soft rim, and a highlight so it reads round.
		draw_circle(center, radius, Color(0.86, 0.40, 0.38))
		draw_circle(center, radius, Color(1.0, 0.7, 0.7, 0.6), false, maxf(1.0, 1.5 * u))
		draw_circle(center + Vector2(-radius * 0.32, -radius * 0.32),
			radius * 0.32, Color(1.0, 1.0, 1.0, 0.35))


func _draw_interact_prompt() -> void:
	# Floating prompt over the helm. The control panel being *findable* is
	# the difference between a pilotable ship and a raft of confusing
	# squares. World-space text shrinks with the zoomed-out camera, so it
	# scales with the world. All validity checks live in the world's
	# interact_prompt() — raw references here crashed on freed instances.
	var prompt: Variant = world.call("interact_prompt")
	if prompt == null:
		return
	var pos := (prompt as Array)[0] as Vector2
	var text := (prompt as Array)[1] as String
	var s: float = float(world.get("world_scale"))
	var bob := sin(Time.get_ticks_msec() / 250.0) * 2.0 * s
	draw_string(ThemeDB.fallback_font,
		pos + Vector2(-46.0 * s, -18.0 * s + bob),
		text, HORIZONTAL_ALIGNMENT_CENTER, int(96 * s),
		int(12 * s), Color(1.0, 0.95, 0.75))


## Floating collision-damage numbers, in WORLD space at each impact point. They
## rise and fade over their life; the value is the coalesced total for that
## source. Font scales with world_scale so it stays legible at 8× (like the
## helm prompt above). All the coalescing/expiry lives in DamageNumbers — this
## only paints active().
func _draw_damage_numbers() -> void:
	var mgr := world.get("_damage_numbers") as DamageNumbers
	if mgr == null:
		return
	var font := ThemeDB.fallback_font
	for n in mgr.active():
		var t: float = clampf(float(n["age"]) / DamageNumbers.LIFETIME, 0.0, 1.0)
		var s: float = float(n["scale"])
		var rise := DamageNumbers.RISE_CELLS * Ship.CELL * s * t
		var pos: Vector2 = (n["pos"] as Vector2) + Vector2(0.0, -rise)
		# Fade out over the life; a touch of grow early so a fresh hit "pops".
		var col := Color(1.0, 0.82, 0.35, 1.0 - t)
		var fs := int(clampf(11.0 * s, 11.0, 220.0))
		draw_string(font, pos - Vector2(0.0, fs * 0.5),
			"%d" % roundi(float(n["total"])),
			HORIZONTAL_ALIGNMENT_CENTER, -1, fs, col)


## Floating "+1 Stone" pickup numbers at each mined cell, rising and fading.
## Greenish (a gain, distinct from the amber collision numbers above). Same
## float idiom; all the lifetime logic lives in PickupFloats.
func _draw_pickups() -> void:
	var mgr := world.get("_pickups") as PickupFloats
	if mgr == null:
		return
	var font := ThemeDB.fallback_font
	for f in mgr.active():
		var t: float = clampf(float(f["age"]) / PickupFloats.LIFETIME, 0.0, 1.0)
		var s: float = float(f["scale"])
		var rise := PickupFloats.RISE_CELLS * Ship.CELL * s * t
		var pos: Vector2 = (f["pos"] as Vector2) + Vector2(0.0, -rise)
		var col := Color(0.62, 1.0, 0.55, 1.0 - t)
		var fs := int(clampf(11.0 * s, 11.0, 220.0))
		draw_string(font, pos - Vector2(0.0, fs * 0.5),
			f["text"] as String, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, col)
