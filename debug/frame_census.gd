class_name FrameCensus
extends RefCounted

## What the RENDERED frame is made of — the render-side twin of PhysicsCensus,
## counted in one place so the F2 readout and the F3 log can never disagree.
##
## Why it exists (owner capture, 2026-08-26). The second 3-FPS capture closed
## one door and opened another. Its PHY lines read `pairs=4 active=13
## islands=1 shapes=45 worst=20`, which is a physics world with essentially
## NOTHING in it — the broadphase had four overlapping AABBs — while `phys`
## read 33-50 ms and the game ran at 4 FPS. Godot runs up to 8 catch-up
## physics steps per rendered frame, so 33-50 ms of `phys` is ~4-6 ms per
## step: real, but nowhere near a 250 ms frame on its own. Roughly 200 ms of
## every frame was going somewhere NEITHER monitor in that log could see.
##
## `draws=583` was the only render number recorded, and draw CALLS are the
## batched total — they say nothing about how much geometry was batched into
## them. These are the numbers that do.
##
## Reading them:
##   * `regions` is the standing cost of the drawn skins: a retained canvas
##     item re-submits its whole command list EVERY visible frame, so a body
##     parked in view bills its region count whether or not it repaints. It
##     fragments exactly like the collider did — the greedy merge breaks its
##     runs at every damage-shade boundary, so a shot-up hull draws far more
##     rects than an intact one of the same size.
##   * `onscreen` / `on_regions` narrow that to what the camera can actually
##     see, which is the difference between "the sky is expensive" and "the
##     thing you are fighting is expensive" — the owner's repro is a creature
##     pressed against the hull, filling the view.
##   * `prims` / `objects` are the engine's own totals for the frame, and
##     `items` counts the canvas items the skins hold (tiles + glyph layers).
##   * `ticks` is physics steps per rendered frame: 1 is healthy, 8 is the
##     catch-up ceiling and means the frame is losing the race.


static func of_world(world: Node) -> Dictionary:
	var out := {
		"fps": int(Performance.get_monitor(Performance.TIME_FPS)),
		"draws": int(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objects": int(Performance.get_monitor(
			Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"prims": int(Performance.get_monitor(
			Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
			/ 1048576.0,
		"items": 0,        ## canvas items across every ship's skin
		"regions": 0,      ## drawn rects those items re-submit each frame
		"worst": 0,        ## the worst single body's region count
		"worst_cells": 0,
		"onscreen": 0,     ## bodies whose bounds meet the camera's view
		"on_regions": 0,   ## and the regions THEY re-submit
		"terrain_regions": 0,
	}
	if world == null or not is_instance_valid(world):
		return out

	var view := view_rect(world)
	var fleet: Variant = world.get("fleet")
	if fleet != null and is_instance_valid(fleet):
		for s in (fleet.call("ships") as Array):
			var ship := s as Ship
			if ship == null or not is_instance_valid(ship):
				continue
			var r: int = ship.skin_regions()
			out["items"] = int(out["items"]) + ship.skin_tile_count()
			out["regions"] = int(out["regions"]) + r
			if r > int(out["worst"]):
				out["worst"] = r
				out["worst_cells"] = ship.blocks.size()
			if view.size.x > 0.0 and view.intersects(body_rect(ship)):
				out["onscreen"] = int(out["onscreen"]) + 1
				out["on_regions"] = int(out["on_regions"]) + r

	var terrain: Variant = world.get("terrain")
	if terrain != null and is_instance_valid(terrain):
		for c in (terrain as Node).get_children():
			if c is TerrainChunk:
				out["terrain_regions"] = int(out["terrain_regions"]) \
					+ (c as TerrainChunk).draw_region_count()
	return out


## The camera's view in world space, or an empty rect when there is no camera
## (headless tests, a dedicated server). Zoom is the live one — the wheel and
## the pilot pull-back both widen what the renderer is asked for.
static func view_rect(world: Node) -> Rect2:
	if world == null or not is_instance_valid(world):
		return Rect2()
	var cam: Variant = world.get("camera")
	if cam == null or not is_instance_valid(cam):
		return Rect2()
	var camera := cam as Camera2D
	var zoom := camera.zoom
	if zoom.x <= 0.0 or zoom.y <= 0.0:
		return Rect2()
	var half: Vector2 = camera.get_viewport_rect().size * 0.5 / zoom
	return Rect2(camera.get_screen_center_position() - half, half * 2.0)


## A body's world-space bounds, from the cell bounds it already keeps.
static func body_rect(ship: Ship) -> Rect2:
	var b: Rect2 = ship.solid_bounds
	if b.size == Vector2.ZERO:
		return Rect2(ship.global_position, Vector2.ONE)
	var size: Vector2 = b.size * ship.scale_unit
	return Rect2(ship.global_position - size * 0.5, size)


## One line, for the F3 log's RND. Same numbers the F2 tab shows.
static func line(world: Node, ticks := 0) -> String:
	var c := of_world(world)
	return ("fps=%d ticks=%d draws=%d objects=%d prims=%d vram=%.1fMB "
		+ "items=%d regions=%d worst=%d(%d cells) onscreen=%d on_regions=%d "
		+ "terrainregions=%d") % [
		c["fps"], ticks, c["draws"], c["objects"], c["prims"], c["vram_mb"],
		c["items"], c["regions"], c["worst"], c["worst_cells"],
		c["onscreen"], c["on_regions"], c["terrain_regions"]]
