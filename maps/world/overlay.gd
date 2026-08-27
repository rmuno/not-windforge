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
	_draw_balloon_ghost()
	_draw_interact_prompt()
	_draw_damage_numbers()
	_draw_pickups()
	_draw_fires()
	_draw_engineering()


## The ENGINEERING OVERLAY (F). Two focused modes, never both at once (owner
## 2026-08-27): FLIGHT paints the handling picture — centre of mass, the
## lift-to-weight gauge, and the thrust authority on each axis; SYSTEMS paints
## the power grid — engines that FEED it green, props/turrets that DRAW it amber,
## with a supply-vs-demand bar that reddens into brownout. Every value comes from
## world.engineering_overlay() (the ship's own derived numbers); this only paints.
## The spatial markers are drawn in the SHIP's frame so a posed hull cannot slide
## them off its own grid.
func _draw_engineering() -> void:
	var d: Variant = world.call("engineering_overlay")
	if d == null:
		return
	var data := d as Dictionary
	var xform := data["xform"] as Transform2D
	var bounds := data["bounds"] as Rect2
	var com := data["com"] as Vector2
	var s := maxf(float(data["scale"]), 1.0)
	var cell: float = Ship.CELL * s
	var font := ThemeDB.fallback_font

	draw_set_transform_matrix(xform)
	if int(data["mode"]) == 1:
		_eng_flight(com, bounds, data, cell, font, s)
	else:
		_eng_systems(com, bounds, data, cell, font, s)

	# The CoM marker is common to both modes — the one point every airship
	# builder wants to see. A ringed dot with a crosshair, drawn last so it sits
	# on top of the bars and machine tints.
	var mk := cell * 0.55
	draw_circle(com, mk, Color(0.15, 0.95, 1.0, 0.9))
	draw_circle(com, mk, Color(0.02, 0.10, 0.14, 0.9), false, maxf(1.5, 1.5 * s))
	draw_line(com - Vector2(mk * 2.0, 0.0), com + Vector2(mk * 2.0, 0.0),
		Color(0.15, 0.95, 1.0, 0.7), maxf(1.0, 1.0 * s))
	draw_line(com - Vector2(0.0, mk * 2.0), com + Vector2(0.0, mk * 2.0),
		Color(0.15, 0.95, 1.0, 0.7), maxf(1.0, 1.0 * s))

	# Mode label above the hull, in the ship frame (the player's own ship flies
	# upright, so it reads level). Small and cornered — an instrument, not a sign.
	var fs := int(clampf(11.0 * s, 11.0, 200.0))
	draw_string(font, Vector2(bounds.position.x, bounds.position.y - cell * 0.6),
		"ENGINEERING · %s" % data["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(0.75, 0.95, 1.0, 0.95))
	draw_set_transform_matrix(Transform2D.IDENTITY)


## FLIGHT: lift-to-weight gauge at the CoM (green climbs, red sinks) and the
## thrust authority as a double-headed arrow on each axis (how hard the ship can
## push itself left/right and up/down — the maneuver picture).
func _eng_flight(com: Vector2, bounds: Rect2, data: Dictionary, cell: float,
		font: Font, s: float) -> void:
	# Thrust authority: the stronger axis fills a reference length, the other is
	# proportional — so the arrows READ as "which way can I push harder", which
	# is the buildable question. Symmetric (props push both ways on their axis).
	var ht := float(data["hthrust"])
	var vt := float(data["vthrust"])
	var maxt := maxf(ht, maxf(vt, 1.0))
	var ref := maxf(bounds.size.x, bounds.size.y) * 0.45
	var col := Color(1.0, 0.85, 0.30, 0.9)
	if ht > 0.0:
		var hlen := ht / maxt * ref
		_eng_arrow(com, com + Vector2(hlen, 0.0), col, s)
		_eng_arrow(com, com - Vector2(hlen, 0.0), col, s)
	if vt > 0.0:
		var vlen := vt / maxt * ref
		_eng_arrow(com, com + Vector2(0.0, vlen), col, s)
		_eng_arrow(com, com - Vector2(0.0, vlen), col, s)

	# Lift-to-weight gauge: a vertical bar rising green when the ship is buoyant
	# (ratio >= 1, it climbs) or falling red when it is heavy (it sinks). Height
	# is the deviation from balance, capped, so "just barely floats" reads small.
	var r := float(data["lift_ratio"])
	var dev := clampf(absf(r - 1.0), 0.0, 1.0)
	var h := (cell * 0.5 + dev * cell * 3.0)
	var w := cell * 0.7
	var x := com.x + bounds.size.x * 0.5 + cell * 1.2
	var up := r >= 1.0
	var bar := Color(0.30, 0.95, 0.45, 0.85) if up else Color(1.0, 0.42, 0.38, 0.85)
	var top := com.y - h if up else com.y
	draw_rect(Rect2(x - w * 0.5, top, w, h), bar)
	draw_line(Vector2(x - w, com.y), Vector2(x + w, com.y),
		Color(0.9, 0.9, 0.95, 0.8), maxf(1.0, 1.0 * s))  # the balance line
	var fs := int(clampf(11.0 * s, 11.0, 200.0))
	draw_string(font, Vector2(x + w, com.y + fs * 0.35),
		"L/W %.2f" % r, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		Color(bar, 1.0))


## SYSTEMS: the power grid. Each machine lights up by role — engines green
## (they FEED), props/turrets amber (they DRAW) — over a supply-vs-demand bar
## that reddens into brownout, so an under-engined build reads at a glance.
func _eng_systems(com: Vector2, bounds: Rect2, data: Dictionary, cell: float,
		font: Font, s: float) -> void:
	for m in (data["machines"] as Array):
		var rect := m["rect"] as Rect2
		var feed := int(m["role"]) > 0
		var tint := Color(0.30, 0.95, 0.45, 0.35) if feed else Color(1.0, 0.72, 0.25, 0.35)
		var edge := Color(0.30, 0.95, 0.45, 0.95) if feed else Color(1.0, 0.72, 0.25, 0.95)
		draw_rect(rect, tint)
		draw_rect(rect, edge, false, maxf(1.5, 1.5 * s))

	# Supply-vs-demand bar above the ship. ratio 1.0 = fully fed (green); below
	# that is brownout (amber into red) — the wiki's "underpowered flies slow".
	var ratio := float(data["power_ratio"])
	var supply := float(data["power_supply"])
	var draw_w := float(data["power_draw"])
	var bw := maxf(bounds.size.x, cell * 6.0)
	var bh := cell * 0.9
	var bx := com.x - bw * 0.5
	var by := bounds.position.y - cell * 2.4
	draw_rect(Rect2(bx, by, bw, bh), Color(0.08, 0.10, 0.13, 0.85))
	var fill := Color(0.30, 0.95, 0.45, 0.9)
	if ratio < 0.999:
		fill = Color(1.0, 0.72, 0.25, 0.9) if ratio > 0.5 else Color(1.0, 0.40, 0.35, 0.9)
	draw_rect(Rect2(bx, by, bw * ratio, bh), fill)
	draw_rect(Rect2(bx, by, bw, bh), Color(0.6, 0.7, 0.8, 0.8), false, maxf(1.0, 1.0 * s))
	var fs := int(clampf(11.0 * s, 11.0, 200.0))
	var txt := "PWR %d / %d" % [roundi(supply), roundi(draw_w)]
	if ratio < 0.999:
		txt += "   BROWNOUT %d%%" % roundi(ratio * 100.0)
	draw_string(font, Vector2(bx, by - fs * 0.3), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(fill, 1.0))


## A double-headed-friendly single arrow (line + filled head) for the thrust
## vectors, sized so the head stays proportional at any world scale.
func _eng_arrow(from: Vector2, to: Vector2, col: Color, s: float) -> void:
	draw_line(from, to, col, maxf(1.5, 1.8 * s))
	var dir := (to - from)
	if dir.length() < 0.001:
		return
	dir = dir.normalized()
	var head := maxf(6.0, 6.0 * s)
	var perp := Vector2(-dir.y, dir.x) * head * 0.6
	draw_colored_polygon(PackedVector2Array([
		to, to - dir * head + perp, to - dir * head - perp]), col)


## FIRE. A burning cell is a grid block-state, not a node and not a particle,
## so this is the only thing that shows one. Two stacked triangles per cell —
## a hot core inside a bigger flame — flickering on a per-cell phase so a wall
## of fire does not pulse in unison. Drawn on the overlay (above every hull)
## rather than in the ship skin on purpose: the skin repaints per TILE, and
## making a flicker a repaint would put a five-times-a-second churn storm
## through the exact path v0.55.x spent a session making cheap.
func _draw_fires() -> void:
	if not world.has_method("burning_points"):
		return
	var pts: Array = world.call("burning_points")
	if pts.is_empty():
		return
	var t := float(Time.get_ticks_msec()) * 0.001
	var cell: float = Ship.CELL * maxf(float(world.get("world_scale")), 1.0)
	for p in pts:
		var at: Vector2 = p
		# Per-cell phase from the position, so neighbours flicker out of step.
		var phase := t * 7.0 + at.x * 0.013 + at.y * 0.017
		var h := cell * (0.85 + 0.30 * sin(phase))
		var w := cell * 0.62
		draw_colored_polygon(PackedVector2Array([
			at + Vector2(0.0, -h), at + Vector2(w * 0.5, cell * 0.45),
			at + Vector2(-w * 0.5, cell * 0.45)]), Color(0.95, 0.45, 0.12, 0.75))
		draw_colored_polygon(PackedVector2Array([
			at + Vector2(0.0, -h * 0.55), at + Vector2(w * 0.24, cell * 0.42),
			at + Vector2(-w * 0.24, cell * 0.42)]), Color(1.0, 0.86, 0.35, 0.85))


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
		# The bulb: a warm helium red, a soft rim, and a highlight so it reads
		# round. DAMAGE DARKENS it — a balloon is ONE placeable (a hit anywhere
		# hurts all of it), so a bag you have been shooting reads as nearly gone.
		var health := float(s.get("health", 1.0))
		draw_circle(center, radius,
			Color(0.86, 0.40, 0.38).lerp(Color(0.34, 0.16, 0.16), 1.0 - health))
		draw_circle(center, radius, Color(1.0, 0.7, 0.7, 0.6), false, maxf(1.0, 1.5 * u))
		draw_circle(center + Vector2(-radius * 0.32, -radius * 0.32),
			radius * 0.32, Color(1.0, 1.0, 1.0, 0.35))


## The balloon BUILD GHOST: where the selected size would tether if you pressed
## U. Drawn in the same shape as the real thing (cables + bulb) but hollow and
## tinted — GREEN when the attach would succeed, RED when it would be refused
## (out of reach, or none of that size in the pack). All of that is decided in
## the world's balloon_ghost_to_draw(); this only paints.
func _draw_balloon_ghost() -> void:
	var g: Variant = world.call("balloon_ghost_to_draw")
	if g == null:
		return
	var spec := g as Dictionary
	var anchor := spec["anchor"] as Vector2
	var center := spec["center"] as Vector2
	var radius := float(spec["radius"])
	var cables := int(spec["cables"])
	var u := float(spec["unit"])
	var tint := Color(0.45, 0.95, 0.55) if bool(spec["ok"]) else Color(0.95, 0.35, 0.35)
	var bottom := center + Vector2(0.0, radius)
	for c in cables:
		var spread := 0.0
		if cables > 1:
			spread = (float(c) / float(cables - 1) - 0.5) * 2.0
		draw_line(bottom, anchor + Vector2(spread * Ship.CELL * u, 0.0),
			Color(tint, 0.45), maxf(1.0, 1.2 * u))
	draw_circle(center, radius, Color(tint, 0.16))
	draw_circle(center, radius, Color(tint, 0.85), false, maxf(2.0, 2.0 * u))


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
