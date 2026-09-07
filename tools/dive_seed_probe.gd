extends SceneTree

## WHAT A FRESH SEED COSTS. Boots the DIVE'S OWN SCENE at 8× — the one the title
## opens for a run — and opens several runs back to back, timing what each one
## pays to throw the previous run's ring away and generate a new one.
##
##   godot --headless --path . --script tools/dive_seed_probe.gd
##
## The number that matters is the SECOND row onward: the first run of a boot
## inherits the sky `_ready` just rolled for it (`DiveRun.next_seed`), so it
## re-seeds nothing and prints 0.0 ms. Every run after it — a retry off the
## ledger, F2's "Start a dive" — wipes the resident grid, re-primes it and
## generates one burst around the launch deck, and that is a HITCH the player
## feels the instant they press dive. If it ever climbs past a frame or two the
## answer is a smaller burst, not a quieter probe.
##
## It also proves the feature end to end, which no unit check can: the seeds
## differ, the ground differs, and a PINNED seed reproduces both.
##
## This is a PROBE, not a test — it prints, it does not assert. The assertions
## live in `tests/scale_startup_test.gd` (the ring re-seeds) and
## `tests/world_startup_test.gd` (the run is scoped to the run).
##
## Names no `class_name` as a type on purpose: doing that inside a `--script`
## file compiles that script before the autoloads exist (CODEMAP §4).

## How many runs to open. Four is enough to see the first-run zero and three real
## re-seeds, and cheap on the owner's play machine.
const RUNS := 4

var world: Node


func _initialize() -> void:
	# Never write through the owner's real profile (every world boot can).
	Profile.path = "user://profile_probe.json"
	var packed: PackedScene = load("res://maps/dive/dive.tscn")
	if packed == null:
		print("!! could not load res://maps/dive/dive.tscn")
		return quit()
	world = packed.instantiate()
	root.add_child(world)
	for i in 60:
		await process_frame
	print("\n=== A FRESH SEED PER RUN — what re-generating the ring costs (8x) ===")
	print("boot: world_seed %d, subdiv %d, %d live chunks"
		% [int(world.get("world_seed")), int(world.get("terrain").subdiv),
			int(world.get("terrain").live_chunk_count())])

	var seeds: Array = []
	var signatures: Array = []
	for run_index in RUNS:
		if run_index > 0:
			# The wall clock around the WHOLE verb, not just the terrain: what the
			# player feels at "dive" is begin_dive, deck and all.
			var t0 := Time.get_ticks_usec()
			world.call("begin_dive")
			var whole := float(Time.get_ticks_usec() - t0) / 1000.0
			await _frames(4)
			var st: Dictionary = world.call("dive_status")
			seeds.append(int(st["seed"]))
			signatures.append(_terrain_signature())
			print("run %d: seed %-11d  re-seed %6.1f ms   begin_dive %6.1f ms   %d solid cells, %d live chunks"
				% [run_index + 1, int(st["seed"]), float(st["regen_ms"]), whole,
					int(world.get("terrain").total_solid_cells()),
					int(world.get("terrain").live_chunk_count())])
		else:
			await _frames(4)
			var st0: Dictionary = world.call("dive_status")
			seeds.append(int(st0["seed"]))
			signatures.append(_terrain_signature())
			print("run 1: seed %-11d  re-seed %6.1f ms   (the boot's own sky — nothing to redo)"
				% [int(st0["seed"]), float(st0["regen_ms"])])

	# --- Did anything actually change? --------------------------------------
	var distinct_seeds := {}
	var distinct_ground := {}
	for s in seeds:
		distinct_seeds[s] = true
	for g in signatures:
		distinct_ground[g] = true
	print("\n%d runs: %d distinct seeds, %d distinct skies"
		% [RUNS, distinct_seeds.size(), distinct_ground.size()])

	# --- ...and does a pin bring one back? ----------------------------------
	var want := int(seeds[1]) if seeds.size() > 1 else int(seeds[0])
	world.call("pin_dive_seed", want)
	world.call("begin_dive")
	await _frames(4)
	var again: Dictionary = world.call("dive_status")
	var was: int = int(signatures[1 if seeds.size() > 1 else 0])
	var same_ground: bool = _terrain_signature() == was
	print("pinned %d -> ran %d   same ground: %s"
		% [want, int(again["seed"]), str(same_ground)])

	# --- WHAT THE RE-SEED ACTUALLY ADDED ------------------------------------
	# `begin_dive` was never free: it tears the last run down, raises the launch
	# deck, moors every candidate and cuts two rungs. Pinning the seed the world
	# is ALREADY on skips the re-seed and nothing else, so this row is the same
	# verb without the new work — the rows above minus this one is the bill.
	world.call("pin_dive_seed", int(world.get("world_seed")))
	var t1 := Time.get_ticks_usec()
	world.call("begin_dive")
	var baseline := float(Time.get_ticks_usec() - t1) / 1000.0
	await _frames(4)
	print("begin_dive with the sky it is already on: %6.1f ms   (the re-seed is the difference)"
		% baseline)

	# ...and that the pin is SPENT: the run after a pinned one is fresh again.
	world.call("begin_dive")
	await _frames(4)
	var after: Dictionary = world.call("dive_status")
	print("the run after a pinned one: seed %d (pin spent: %s)"
		% [int(after["seed"]), str(int(after["seed"]) != want)])
	quit()


## A fingerprint of the ground this run generated: WHICH chunks hold data and how
## much of it is solid. Sampling cells around the deck was the obvious idea and
## the wrong one — depth 1 sits in the ring's updraft column, which the generator
## deliberately keeps CLEAR, so every seed fingerprinted as identical empty sky.
## The chunk set is the honest answer: it is exactly what the seed decided to put
## where, and it is what a pinned seed has to reproduce.
func _terrain_signature() -> int:
	var terrain = world.get("terrain")
	if terrain == null:
		return 0
	var coords: Array = terrain.chunk_coords()
	var packed := PackedInt64Array()
	for c in coords:
		packed.append(int((c as Vector2i).y) * 1000000 + int((c as Vector2i).x))
	packed.sort()
	return hash([packed, int(terrain.total_solid_cells())])


func _frames(n: int) -> void:
	for i in n:
		await world.get_tree().physics_frame
