class_name LavaCore
extends Node2D

## The earth's core (owner 2026-08-23): the bottom slice of the world is a molten
## lava sea. Fly a ship into it and "you can just say goodbye" — contact is
## instant death, no crush, no mining. This node RENDERS the glowing core (a
## world-space band behind the ships); the world owns the lethal check and drives
## it against the SAME geometry via the static predicates below (one source of
## truth for "is this in the core").

## How much of the world height, from the floor up, is molten core. Lowered
## 0.10→0.06 (owner 2026-08-23: "the lava seems to be a layer or two too high") so
## the sea hugs the very floor (just above the LAVA band, Airspace.LAVA_TOP 0.05).
const DEFAULT_TOP_FRAC := 0.06

var world_rect := Rect2()
var scale_unit := 1.0
var top_frac := DEFAULT_TOP_FRAC
var _t := 0.0


func _ready() -> void:
	# Behind the ships and terrain (siblings at z 0) — the core is backdrop, the
	# hulls sinking into it read on top.
	z_as_relative = false
	z_index = -50


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()   # animated glow; erasing is a redraw too (godot-quirks)


## The world-space y of the lava SURFACE (top of the core). Anything at or below
## this y is in the molten core. Pure, so the lethal check and the render agree.
static func surface_y_for(rect: Rect2, frac: float) -> float:
	return rect.end.y - frac * rect.size.y


## Is world-space point `y` inside the lethal core? Inert when no world is mapped.
static func is_in_core(rect: Rect2, frac: float, y: float) -> bool:
	return rect.size.y > 0.0 and y >= surface_y_for(rect, frac)


func surface_y() -> float:
	return surface_y_for(world_rect, top_frac)


func _draw() -> void:
	if world_rect.size.y <= 0.0:
		return
	var top := surface_y()
	var left := world_rect.position.x
	var w := world_rect.size.x
	# Extend below the world floor so there is no visible bottom edge to the sea.
	var bottom := world_rect.end.y + world_rect.size.y * 0.06
	var u := scale_unit

	# The molten body: a deep base with a hotter glow toward the surface.
	draw_rect(Rect2(left, top, w, bottom - top), Color(0.34, 0.07, 0.03))
	draw_rect(Rect2(left, top, w, (bottom - top) * 0.55), Color(0.80, 0.26, 0.05, 0.45))
	# The molten SURFACE line, pulsing so the sea reads as alive.
	var pulse := 0.55 + 0.45 * (0.5 + 0.5 * sin(_t * 2.2))
	draw_rect(Rect2(left, top, w, 7.0 * u), Color(1.0, 0.68, 0.18, pulse))

	# A few rising embers (the Core-of-Cordeus look). Deterministic columns, each
	# cycling upward from the surface and fading — a dozen cheap dots, not a system.
	for i in 14:
		var fx := float((i * 7 + 3) % 100) / 100.0
		var ex := left + fx * w
		var phase := fposmod(_t * 0.35 + float(i) * 0.137, 1.0)
		var ey := top - phase * 90.0 * u
		var a := (1.0 - phase) * 0.7
		draw_circle(Vector2(ex, ey), maxf(1.5, 2.2 * u), Color(1.0, 0.55, 0.15, a))
