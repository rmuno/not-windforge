class_name EdgeMarkers
extends Control

## EDGE POI MARKERS — the "something is over there" arrows the Source had, and
## the one piece of situational awareness this game was missing between the calm
## HUD and the Tab map (owner 2026-08-29).
##
## The problem it solves: the world is 6144×4608 cells and the camera at 8× sees
## a few thousand px of it, so a whale one screen to port, the ship you just
## jumped off, and the port you were flying to are all simply INVISIBLE until
## they happen to cross the frame. The map (Tab) answers "where is everything",
## which is a different, slower question than "what is just off my screen right
## now" — and the map is a mode, so asking costs you the controls.
##
## THE SHAPE, per the owner: a TRIANGLE at the screen edge that points at the
## thing, with an ICON DRAWN UPRIGHT inside it. The triangle rotates to carry the
## bearing; the icon never does, because a whale glyph lying on its side is not a
## whale glyph. One icon per kind of thing, so the marker says WHAT as well as
## WHERE — a screen of identical arrows is a screen of noise.
##
## Rendering ONLY. Every decision — which things are near enough, what kind each
## is, what colour it wears — is made in the world (`edge_marker_targets`), the
## same split HudLayer and WorldOverlay use, so nothing in here can touch a Ship.
## The one piece of real logic that lives here is the screen geometry, and it is
## a STATIC PURE FUNCTION (`place`) precisely so the suite can assert on it: a
## clamp buried in a draw call is a clamp no test can see.

var world: Node2D

## Every kind this layer can draw. The world's targets are asserted against this
## list by the suite, so a new POI kind that nobody taught an icon fails loudly
## instead of shipping as a blank triangle.
const KINDS := ["whale", "kraken", "basilisk", "critter", "enemy", "ship",
	"dock", "site", "boss"]

## Screen-edge inset (px at scale 1) the markers ride. Big enough that a marker
## never straddles the frame, small enough that it reads as "at the edge".
const MARGIN := 30.0

## Triangle radius (px at scale 1) — tip distance from the marker's anchor.
const RADIUS := 21.0

## The icon is a dark silhouette on the kind's colour, so it reads at a glance
## against any sky. (Painting the icon in the kind's colour and the triangle
## hollow was the first cut; at 30 px the outline won and the icon vanished.)
const INK := Color(0.05, 0.07, 0.09, 0.95)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()  # erasing is a redraw too (godot-quirks)


## Screen-space chrome, so the size must NOT track world_scale — the same rule
## HudLayer states at length (the 8× HUD ran off the screen once already).
func _scale() -> float:
	var vh := get_viewport_rect().size.y
	return clampf(vh / 900.0, 1.0, 3.0)


## Where a marker for `target` (screen px) sits, and which way it points.
## PURE — no node state, no drawing — so the suite can assert the clamp.
##
## Returns {"on_screen": bool, "pos": Vector2, "dir": Vector2}. `on_screen` means
## the thing is comfortably inside the frame and needs NO marker: you can see it,
## and an arrow pointing at something you are looking at is clutter (the clean-UI
## standing order). Otherwise the anchor is where the ray from the screen centre
## to the target crosses the inset rectangle, so the marker sits on the edge in
## the true bearing rather than in a corner bucket.
static func place(target: Vector2, view: Vector2, margin: float) -> Dictionary:
	var centre := view * 0.5
	var half := Vector2(maxf(centre.x - margin, 1.0), maxf(centre.y - margin, 1.0))
	var d := target - centre
	if d.length_squared() < 0.0001:
		return {"on_screen": true, "pos": centre, "dir": Vector2.RIGHT}
	if absf(d.x) <= half.x and absf(d.y) <= half.y:
		return {"on_screen": true, "pos": target, "dir": d.normalized()}
	# Scale the ray until it touches the nearer of the two inset limits.
	var k: float = minf(half.x / maxf(absf(d.x), 0.0001),
		half.y / maxf(absf(d.y), 0.0001))
	return {"on_screen": false, "pos": centre + d * k, "dir": d.normalized()}


func _draw() -> void:
	if world == null or not world.has_method("edge_marker_targets"):
		return
	var targets: Array = world.call("edge_marker_targets")
	if targets.is_empty():
		return
	var xf := get_viewport().get_canvas_transform()
	var view := size
	var s := _scale()
	var margin := MARGIN * s
	for t in targets:
		var m := t as Dictionary
		var spot := place(xf * (m["pos"] as Vector2), view, margin)
		if bool(spot["on_screen"]):
			continue
		var col := m["color"] as Color
		# Nearer reads brighter: the alpha IS the distance cue, so no marker
		# needs a number beside it.
		col.a = lerpf(0.42, 1.0, clampf(float(m.get("near", 1.0)), 0.0, 1.0))
		_draw_marker(spot["pos"] as Vector2, spot["dir"] as Vector2,
			String(m["kind"]), col, s)


## One marker: the bearing triangle, then the upright icon at its middle.
func _draw_marker(at: Vector2, dir: Vector2, kind: String, col: Color,
		s: float) -> void:
	var r := RADIUS * s
	var perp := Vector2(-dir.y, dir.x)
	var tip := at + dir * r
	var b1 := at - dir * (r * 0.62) + perp * (r * 0.98)
	var b2 := at - dir * (r * 0.62) - perp * (r * 0.98)
	draw_colored_polygon(PackedVector2Array([tip, b1, b2]), col)
	draw_polyline(PackedVector2Array([tip, b1, b2, tip]),
		Color(0.02, 0.03, 0.05, col.a * 0.8), maxf(1.0, 1.4 * s))
	# The icon sits at the triangle's own centroid, drawn UPRIGHT — the triangle
	# carries the direction so the glyph never has to.
	var ink := Color(INK.r, INK.g, INK.b, INK.a * col.a)
	_draw_icon(kind, (tip + b1 + b2) / 3.0, r * 0.34, ink)


## The icon set. Code-drawn like everything else here (no art dependencies until
## the feel is locked) and deliberately blunt: at ~14 px a silhouette either
## reads instantly or it is decoration.
func _draw_icon(kind: String, at: Vector2, r: float, col: Color) -> void:
	match kind:
		"whale":
			_icon_whale(at, r, col)
		"kraken":
			_icon_squid(at, r, col)
		"basilisk":
			_icon_flame(at, r, col)
		"critter":
			_icon_critter(at, r, col)
		"enemy":
			_icon_warning(at, r, col)
		"ship":
			_icon_blimp(at, r, col)
		"dock":
			_icon_anchor(at, r, col)
		"site":
			_icon_diamond(at, r, col)
		"boss":
			_icon_crown(at, r, col)


## A whale: a blunt-nosed body with a raised tail fluke behind it.
func _icon_whale(at: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(r * 1.15, -r * 0.10),
		at + Vector2(r * 0.55, -r * 0.62),
		at + Vector2(-r * 0.35, -r * 0.55),
		at + Vector2(-r * 0.85, 0.0),
		at + Vector2(-r * 0.30, r * 0.55),
		at + Vector2(r * 0.60, r * 0.45)]), col)
	# The fluke — the one silhouette cue that says "whale" and not "fish".
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(-r * 0.60, 0.0),
		at + Vector2(-r * 1.30, -r * 0.95),
		at + Vector2(-r * 1.30, r * 0.95)]), col)


## A squid: a pointed mantle above, tentacles trailing below.
func _icon_squid(at: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(0.0, -r * 1.25),
		at + Vector2(r * 0.62, r * 0.05),
		at + Vector2(-r * 0.62, r * 0.05)]), col)
	var w := maxf(1.0, r * 0.26)
	for i in 3:
		var x := at.x + (float(i) - 1.0) * r * 0.48
		draw_line(Vector2(x, at.y + r * 0.05), Vector2(x, at.y + r * 1.15), col, w)


## A basilisk: a flame — the same language the burning-cell overlay speaks, and
## the reason the creature exists.
func _icon_flame(at: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(0.0, -r * 1.3),
		at + Vector2(r * 0.85, r * 0.9),
		at + Vector2(-r * 0.85, r * 0.9)]), col)
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(0.0, -r * 0.15),
		at + Vector2(r * 0.42, r * 1.15),
		at + Vector2(-r * 0.42, r * 1.15)]), Color(col, col.a * 0.55))


## A critter: a small fish, so wildlife-you-can-eat never reads as a threat.
func _icon_critter(at: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(r * 1.05, 0.0),
		at + Vector2(r * 0.10, -r * 0.62),
		at + Vector2(-r * 0.45, 0.0),
		at + Vector2(r * 0.10, r * 0.62)]), col)
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(-r * 0.40, 0.0),
		at + Vector2(-r * 1.05, -r * 0.62),
		at + Vector2(-r * 1.05, r * 0.62)]), col)


## An enemy ship: a warning bang. Not a ship silhouette on purpose — what the
## player needs off-screen is "someone is shooting at you", not a hull census.
func _icon_warning(at: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(-r * 0.26, -r * 1.15),
		at + Vector2(r * 0.26, -r * 1.15),
		at + Vector2(r * 0.16, r * 0.28),
		at + Vector2(-r * 0.16, r * 0.28)]), col)
	draw_circle(at + Vector2(0.0, r * 0.92), r * 0.27, col)


## Your own ship: a blimp — envelope, fin, gondola. The Source's own green.
func _icon_blimp(at: Vector2, r: float, col: Color) -> void:
	var hull := PackedVector2Array()
	for i in 14:
		var a := TAU * float(i) / 14.0
		hull.append(at + Vector2(cos(a) * r * 1.15, sin(a) * r * 0.62))
	draw_colored_polygon(hull, col)
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(-r * 0.85, -r * 0.20),
		at + Vector2(-r * 1.45, -r * 0.95),
		at + Vector2(-r * 1.45, r * 0.35)]), col)      # tail fin
	draw_rect(Rect2(at + Vector2(-r * 0.34, r * 0.52), Vector2(r * 0.68, r * 0.46)), col)


## The dock master: an anchor. Ring, shank, stock, and the two flukes.
func _icon_anchor(at: Vector2, r: float, col: Color) -> void:
	var w := maxf(1.0, r * 0.28)
	draw_circle(at + Vector2(0.0, -r * 0.95), r * 0.34, Color(col, 0.0))
	draw_arc(at + Vector2(0.0, -r * 0.92), r * 0.34, 0.0, TAU, 12, col, w)
	draw_line(at + Vector2(0.0, -r * 0.62), at + Vector2(0.0, r * 1.05), col, w)
	draw_line(at + Vector2(-r * 0.78, -r * 0.30), at + Vector2(r * 0.78, -r * 0.30), col, w)
	draw_polyline(PackedVector2Array([
		at + Vector2(-r * 0.95, r * 0.34),
		at + Vector2(-r * 0.72, r * 0.92),
		at + Vector2(0.0, r * 1.15),
		at + Vector2(r * 0.72, r * 0.92),
		at + Vector2(r * 0.95, r * 0.34)]), col, w)


## A place (a spawn site): the hollow diamond the world map already uses, so the
## edge marker and the map speak the same word for the same thing.
func _icon_diamond(at: Vector2, r: float, col: Color) -> void:
	draw_polyline(PackedVector2Array([
		at + Vector2(0.0, -r * 1.1), at + Vector2(r * 1.1, 0.0),
		at + Vector2(0.0, r * 1.1), at + Vector2(-r * 1.1, 0.0),
		at + Vector2(0.0, -r * 1.1)]), col, maxf(1.0, r * 0.3))


## The boss: a crown. The only thing in the sky that gets one.
func _icon_crown(at: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(-r * 1.1, r * 0.85),
		at + Vector2(-r * 1.1, -r * 0.85),
		at + Vector2(-r * 0.55, -r * 0.10),
		at + Vector2(0.0, -r * 1.15),
		at + Vector2(r * 0.55, -r * 0.10),
		at + Vector2(r * 1.1, -r * 0.85),
		at + Vector2(r * 1.1, r * 0.85)]), col)
