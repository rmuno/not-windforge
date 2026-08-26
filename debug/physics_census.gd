class_name PhysicsCensus
extends RefCounted

## What the PHYSICS step is made of, counted in one place so the live F2
## readout and the F3 log can never disagree.
##
## Why it exists (owner 3-FPS capture, 2026-08-25). The whale_diag SUM lines
## read `proc=2.1-6.3 ms  phys=30-87 ms  draws=95  ships=11`, with `contacts`
## zero in 93% of rows. So: script was ~2 ms, render was 95 draw calls, and
## the frame was the PHYSICS step -- and once a physics frame overruns its
## 16.67 ms budget Godot runs CATCH-UP steps, up to 8 per rendered frame.
## 8 x 37 ms = 296 ms, which is the 3-4 FPS that was observed. The arithmetic
## closes exactly; nothing is unaccounted for.
##
## What could not be answered from that capture is WHY the step was
## expensive, because neither the readout nor the log recorded a single
## physics-side number. These are those numbers: what the server itself
## reports (pairs, active bodies, islands) plus the shape census that feeds
## them, and the resident terrain, which is the biggest thing a session
## accumulates that a fresh world does not have.
##
## Reading them: `pairs` is the broadphase's work -- every pair of shapes
## whose AABBs overlap is narrow-phased EVERY step, contact or not, so pairs
## can be huge while `contacts` stays 0. `active` is bodies the solver is
## still integrating; Ship sets `can_sleep = false`, so every ship counts
## forever, near or far. `worst` names the body carrying the most shapes -- a
## carcass or vessel on the exact per-cell collider, versus a living creature
## on its single coarse box.


static func of_world(world: Node) -> Dictionary:
	var out := {
		"pairs": int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)),
		"active": int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)),
		"islands": int(Performance.get_monitor(Performance.PHYSICS_2D_ISLAND_COUNT)),
		"shapes": 0,       ## collision shapes across every ship
		"worst": 0,        ## the worst single body's shape count
		"worst_cells": 0,  ## and how many blocks that body has
		"coarse": 0,       ## living creatures on the single-box collider
		"chunks": 0,       ## promoted terrain chunks (each a StaticBody2D)
		"chunk_shapes": 0,
	}
	if world == null or not is_instance_valid(world):
		return out

	var fleet: Variant = world.get("fleet")
	if fleet != null and is_instance_valid(fleet):
		for s in (fleet.call("ships") as Array):
			var ship := s as Ship
			if ship == null or not is_instance_valid(ship):
				continue
			var n := 0
			for c in ship.get_children():
				if c is CollisionShape2D:
					n += 1
			out["shapes"] = int(out["shapes"]) + n
			if n > int(out["worst"]):
				out["worst"] = n
				out["worst_cells"] = ship.blocks.size()
			if ship.shared_health_max > 0.0 and ship.shared_health > 0.0:
				out["coarse"] = int(out["coarse"]) + 1

	var terrain: Variant = world.get("terrain")
	if terrain != null and is_instance_valid(terrain):
		for c in (terrain as Node).get_children():
			if c is TerrainChunk:
				out["chunks"] = int(out["chunks"]) + 1
				out["chunk_shapes"] = int(out["chunk_shapes"]) \
					+ (c as TerrainChunk).draw_region_count()
	return out


## One line, for the F3 log's SUM. Same numbers the F2 tab shows.
static func line(world: Node) -> String:
	var c := of_world(world)
	return ("pairs=%d active=%d islands=%d shapes=%d worst=%d(%d cells) "
		+ "coarse=%d chunks=%d chunkshapes=%d") % [
		c["pairs"], c["active"], c["islands"], c["shapes"],
		c["worst"], c["worst_cells"], c["coarse"], c["chunks"], c["chunk_shapes"]]
