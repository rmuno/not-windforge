extends SceneTree

## What a fire actually DOES to a real body (roadmap Phase 4: "a fight, not a
## verdict"). The two failure modes are opposite and both invisible in a unit
## test that only asks whether the rules hold:
##
##   * too weak — a fire fizzles in its own footprint and is never a threat,
##     which is what the first tuning did (a blubber cell died to its own burn
##     damage before it had time to light a neighbour);
##   * too strong — one spark takes a whole hull and the player never had a
##     move, which is the "verdict" the spec forbids.
##
## So this burns real bodies and reports the numbers that decide it: how much
## of the body is lost, how long the fire lives, and how many cells are alight
## at its worst — the last one being what the player is actually fighting.
##
##   godot --headless --path . --script tools/fire_probe.gd

const STEP := 0.2
const MAX_STEPS := 1200
const RUNS := 8


func _initialize() -> void:
	print("BURN_DPS %.0f   SPREAD/s %.2f   BURN_SECONDS %.0f   DOUSE %.2fs\n"
		% [Fire.BURN_DPS, Fire.SPREAD_PER_SECOND, Fire.BURN_SECONDS,
			Fire.DOUSE_SECONDS])
	print("%-22s %7s %8s %8s %9s %8s" % [
		"body", "cells", "lost", "lost %", "peak lit", "seconds"])
	await _burn("whale (blubber)", "res://ships/whale.ship", 1)
	await _burn("critter", "res://ships/critter.ship", 1)
	await _burn("starter (hull)", "res://ships/starter.ship", 8)
	await _burn("hulk (hull)", "res://ships/hulk.ship", 8)
	await _burn("nest_hive", "res://ships/nest_hive.ship", 1)
	await _burn("nest_den (shell)", "res://ships/nest_den.ship", 1)
	quit(0)


## Light one random burnable cell and let it run. Averaged over RUNS ignition
## points, because where a fire starts changes what it can reach.
func _burn(label: String, path: String, upscale: int) -> void:
	var cells := ShipLayout.load_cells(path)
	if upscale > 1:
		cells = ShipLayout.upscale_cells(cells, upscale)
	if cells.is_empty():
		print("%-22s  (no blueprint)" % label)
		return
	var lost_sum := 0.0
	var peak_sum := 0.0
	var life_sum := 0.0
	var size := 0
	for run in RUNS:
		var ship := Ship.new()
		for cell in cells:
			var type: int = cells[cell]
			ship.blocks[cell] = {"type": type, "hp": BlockDB.max_hp(type)}
		ship.gravity_scale = 0.0
		root.add_child(ship)
		ship.rebuild()
		size = ship.blocks.size()

		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + run
		var burnable: Array = []
		for cell in ship.blocks:
			if Fire.burns(int(ship.blocks[cell]["type"])):
				burnable.append(cell)
		if burnable.is_empty():
			print("%-22s %7d   nothing on it burns" % [label, size])
			ship.queue_free()
			await process_frame
			return
		var now := 10.0
		Fire.ignite(ship, burnable[rng.randi_range(0, burnable.size() - 1)], now)
		var peak := 0
		var steps := 0
		for i in MAX_STEPS:
			now += STEP
			steps += 1
			Fire.step(ship, STEP, now, rng)
			peak = maxi(peak, ship.burning.size())
			if ship.burning.is_empty():
				break
		lost_sum += float(size - ship.blocks.size())
		peak_sum += peak
		life_sum += steps * STEP
		ship.queue_free()
		await process_frame

	var lost := lost_sum / RUNS
	print("%-22s %7d %8.0f %7.1f%% %9.0f %8.1f" % [
		label, size, lost, 100.0 * lost / maxf(float(size), 1.0),
		peak_sum / RUNS, life_sum / RUNS])
