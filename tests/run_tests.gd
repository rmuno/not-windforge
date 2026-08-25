extends SceneTree

## Headless test suite. Run with:
##   godot --headless --path <project> --script res://tests/run_tests.gd
## or just: tests/run_tests.ps1
##
## Exits 0 on pass, 1 on failure, so it can gate a commit.
##
## Covers both pure grid logic (mass, merge, severing) and real physics
## integration (does the ship actually climb, does the upright rule actually
## hold), because the physics is where the feel lives and unit-testing
## only the grid would miss every interesting failure.

var _checks := 0
var _failures := 0
var _current := ""


func _initialize() -> void:
	print("\n=== not-windforge test suite ===\n")

	await _test_mass_and_centre_of_mass()
	await _test_greedy_merge()
	await _test_placement_adjacency()
	await _test_damage_destroys_block()
	await _test_air_density()
	await _test_lift_ratio_and_ceiling()
	await _test_severing_keeps_core()
	await _test_severed_piece_inherits_velocity()
	await _test_empty_ship_frees_itself()
	await _test_ship_climbs()
	await _test_damage_cannot_strand_the_ship_airborne()
	await _test_hover_assist()
	await _test_heavy_ship_sinks()
	await _test_doors()
	await _test_doors_open_and_close()
	await _test_projectiles_are_ballistic()
	await _test_bullets_carry_far()
	await _test_shots_are_culled_past_their_range()
	await _test_shots_inherit_the_shooters_velocity()
	await _test_shots_survive_firing_along_the_motion()
	await _test_solid_bounds_track_the_grid()
	await _test_guns_aim_at_what_they_can_reach()
	await _test_blubber_is_buoyant_structure()
	await _test_prop_wash_bends_slow_shots_more()
	await _test_props_alone_hold_altitude()
	await _test_balloons_lift_and_detach()
	await _test_balloons_are_one_destructible_placeable()
	await _test_whale_is_a_whale()
	await _test_whale_is_one_unit_until_dead()
	await _test_shots_snap_to_the_nearest_block_on_a_creature()
	await _test_living_creature_gets_a_coarse_collider()
	await _test_living_whale_rests_on_terrain_with_coarse_collider()
	await _test_creature_skin_faces_its_motion()
	await _test_whale_pose_tilt_follows_its_facing()
	await _test_ram_immunity()
	await _test_ship_ram_bites_at_scale()
	await _test_living_creature_soaks_crashes()
	await _test_a_chase_never_kills_the_whale()
	await _test_whale_diagnostic_captures_the_sandwich()
	await _test_whale_diag_buffers_and_flushes_periodically()
	await _test_combat_rebuilds_coalesce_per_frame()
	await _test_whale_ai_neutral_until_provoked()
	await _test_provoked_whale_rams_its_attacker()
	await _test_provoked_whale_never_endlessly_charges_down()
	await _test_provoked_whale_align_still_rams_when_reachable()
	await _test_whale_spawn_picks_varied_plans()
	await _test_tamed_and_ridden_whale()
	await _test_shell_armor_soaks_ram_damage()
	await _test_ride_mine_front_cells_lead_the_travel()
	await _test_taming_bar_scales_with_creature_tier()
	await _test_enemy_flees_when_outmatched()
	await _test_layout_comments_never_eat_hull_rows()
	await _test_scaffold_wreck_still_collides()
	await _test_hulk_is_a_real_ship()
	await _test_platforms()
	await _test_power_grid()
	await _test_props_are_inert_without_engines()
	await _test_blueprint_and_repair()
	await _test_blueprint_survives_severing()
	await _test_rope_wraps_and_respects_walls()
	await _test_walking_on_a_moving_deck()
	await _test_pendulum_swings_freely()
	await _test_ramming_plows_through()
	await _test_gasbags_shrug_off_soft_collisions()
	await _test_damage_numbers_coalesce_per_source()
	await _test_combat_damage_floats_a_number()
	await _test_restitution_transfers_more_momentum()
	await _test_ridden_whale_treads_water()
	await _test_kraken_is_a_kraken()
	await _test_kraken_ai_grabs_hovers_and_rams()
	await _test_kraken_cavity_loot_spills_once_on_breach()
	await _test_carcass_loot_state_survives_the_wire_and_the_save()
	await _test_kraken_mouth_bites_the_player_on_foot()
	await _test_kraken_spawn_keeps_out_of_deep_rock()
	await _test_single_player_is_not_online()
	await _test_remote_ships_are_eased_not_snapped()
	await _test_serialization_roundtrip()
	await _test_from_data_reconstruction()
	await _test_payload_round_trip_survives_hosting()
	await _test_walls_ride_the_payload()
	await _test_ships_stay_upright_always()
	await _test_sky_bands_and_winds()
	await _test_sky_moves_ships()
	await _test_hover_rides_the_wind()
	await _test_blueprint_upscaling()
	await _test_upscaled_props_keep_their_axis()
	await _test_scale_unit_preserves_feel()
	await _test_components_die_as_a_whole()
	await _test_shots_respect_factions()
	await _test_crash_bite_scales_with_the_world()
	await _test_walls_hold_the_ship_together()
	await _test_turret_arcs_derive_from_mounting()
	await _test_helm_is_the_seat_of_control()
	await _test_blueprint_follows_construction()
	await _test_build_preview_predicts_the_placement()
	await _test_terrain_far_chunk_is_inert()
	await _test_terrain_promotes_and_demotes_with_hysteresis()
	await _test_terrain_dig_removes_cell_and_shrinks_collider()
	await _test_terrain_edits_batch_into_one_rebuild_per_frame()
	await _test_terrain_edit_replication_applies_and_diffs()
	await _test_body_rests_on_promoted_terrain()
	await _test_terrain_promote_demote_leaks_no_nodes()
	await _test_terrain_promotion_is_amortized()
	await _test_island_gen_is_deterministic()
	await _test_island_gen_is_banded_and_columns_clear()
	await _test_island_gen_islands_are_coherent()
	await _test_island_gen_is_data_only_and_sparse()
	await _test_lazy_generation_matches_eager_and_clips()
	await _test_fill_row_matches_set_cell()
	await _test_streaming_is_tiered_and_skips_still_frames()
	await _test_subdiv_world_is_the_same_world_finer()
	await _test_inventory_add_remove_count()
	await _test_mining_seam_digs_and_credits()
	await _test_pickup_floats_rise_and_expire()
	await _test_item_id_scheme_keeps_kinds_distinct()
	await _test_terrain_placement_writes_consumes_and_digs_back()
	await _test_whale_carcass_harvest_yields_products()
	await _test_crafting_consumes_inputs_and_yields_output()
	await _test_craft_all_makes_the_whole_stack_in_one_action()
	await _test_balloons_are_crafted_items()
	await _test_machine_bundles_geometry()
	await _test_redraws_and_rebuilds_are_batched()
	await _test_hud_cues_show_only_usable_actions()
	await _test_fog_of_war_reveals_by_distance()
	await _test_map_view_toggles_visibility()
	await _test_wind_map_helper_reads_the_circulation()
	await _test_hazards_gate_on_band()
	await _test_meteors_are_broad_and_world_anchored()
	await _test_hazard_fireball_damages_and_cannot_tunnel()
	await _test_lava_erupts_and_arcs()
	await _test_lava_core_is_the_bottom_slice()
	await _test_deep_fog_thickens_with_depth()
	await _test_easter_eggs_are_present_but_hidden()
	await _test_tunables_get_set_reset_and_clamp()
	await _test_a_system_reads_the_tunable()
	await _test_whale_ai_reads_the_ram_tunable()
	await _test_debug_window_toggles_and_switches_tabs()
	await _test_stats_default_raise_and_cap()
	await _test_stat_perks_change_effects()
	await _test_double_jump_gated_by_grace()
	await _test_hostile_shot_hits_player_friendly_does_not()
	await _test_hazard_fireball_burns_the_player()
	await _test_grit_matters_and_regen_heals()
	await _test_deep_air_suffocates_the_unprotected()
	await _test_life_support_gates_the_deep()
	await _test_life_support_recipe_crafts()
	await _test_firing_speed_is_upgradable_and_tunable()
	await _test_salvage_economy_values_and_selling()
	await _test_training_costs_deducts_and_refuses()
	await _test_save_terrain_diffs_round_trip()
	await _test_save_ships_and_player_round_trip()
	await _test_save_metadata_readable_without_full_load()
	await _test_save_load_fails_gracefully()
	await _test_web_key_aliases()

	print("\n=== %d checks, %d failed ===" % [_checks, _failures])
	if _failures == 0:
		print("PASS\n")
		quit(0)
	else:
		print("FAIL\n")
		quit(1)


# --- Assertions -----------------------------------------------------------

func _t(name: String) -> void:
	_current = name
	print("• %s" % name)


func _check(condition: bool, detail: String) -> void:
	_checks += 1
	if condition:
		print("    ok   %s" % detail)
	else:
		_failures += 1
		print("    FAIL %s   [%s]" % [detail, _current])


func _check_approx(actual: float, expected: float, eps: float, detail: String) -> void:
	_check(absf(actual - expected) <= eps,
		"%s  (expected ~%.3f, got %.3f)" % [detail, expected, actual])


# --- Helpers --------------------------------------------------------------

## Build a ship from {Vector2i: BlockDB.Type} and add it to the tree so _ready
## runs. `floating` kills gravity and lift for tests that only care about grid
## logic and must not drift while awaiting frames.
func _make_ship(cells: Dictionary, floating := true) -> Ship:
	var s := Ship.new()
	for cell in cells:
		var type: int = cells[cell]
		s.blocks[cell] = {"type": type, "hp": BlockDB.max_hp(type)}
	if floating:
		s.gravity_scale = 0.0
	root.add_child(s)
	# _ready() is not guaranteed to have run yet when nodes are added from
	# _initialize(), so derive explicitly rather than racing it.
	s.rebuild()
	return s


## The 1×-granularity starter these behavioural tests are written against.
## Since the native-8× re-author (2026-08-20) the game's real file is
## ships/starter.ship at 8× cell granularity; the frozen 1× fixture keeps
## these cell-level guarantees checkable (and the legacy scene loads the
## same fixture). The REAL file is gated by the native-8× contract test
## and the 8× startup suite.
func _starter_ship() -> Dictionary:
	return ShipLayout.load_cells("res://tests/fixtures/starter_1x.ship")


func _shape_count(s: Ship) -> int:
	var n := 0
	for child in s.get_children():
		if child is CollisionShape2D:
			n += 1
	return n


## Every collision shape the ship owns, as a sorted local-space signature.
## The Q10 pin compares this across a facing flip: after the owner's
## 2026-08-21 reversal the collider MIRRORS with the skin, so an asymmetric
## body's signature must CHANGE on flip and return on the flip back.
func _collider_signature(s: Ship) -> Array:
	var out: Array[String] = []
	for child in s.get_children():
		if child is CollisionShape2D:
			var cs := child as CollisionShape2D
			var size: Vector2 = (cs.shape as RectangleShape2D).size
			out.append("%.3f,%.3f,%.3f,%.3f"
				% [cs.position.x, cs.position.y, size.x, size.y])
	out.sort()
	return out


## The collision shape whose centre pokes furthest "up" in body space — in the
## skin test that is the fin column (the greedy merge folds the lone fin into a
## 1×2 with the spine cell above it), the asymmetric marker. Returned as a
## GLOBAL position, so it carries the body's live pose rotation and reads where
## the physical fin actually sits.
func _topmost_shape_global(s: Ship) -> Vector2:
	var best: CollisionShape2D = null
	for child in s.get_children():
		if child is CollisionShape2D:
			var cs := child as CollisionShape2D
			if best == null or cs.position.y < best.position.y:
				best = cs
	return best.global_position if best != null else Vector2(1e12, 1e12)


func _step(frames: int) -> void:
	for i in frames:
		await physics_frame


# --- Grid logic -----------------------------------------------------------

func _test_mass_and_centre_of_mass() -> void:
	_t("mass and centre of mass derive from blocks")
	# Two hulls (10 each) at x=0 and x=2 cells; centre of mass sits between them.
	var s := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(2, 0): BlockDB.Type.HULL,
	})
	_check_approx(s.mass, 20.0, 0.01, "mass is the sum of block masses")
	_check_approx(s.center_of_mass.x, 1.0 * Ship.CELL, 0.01, "com.x midway between blocks")
	_check_approx(s.center_of_mass.y, 0.0, 0.01, "com.y level")

	# A ballast block (26) should drag the centre of mass toward itself.
	s.set_block(Vector2i(2, 0), BlockDB.Type.BALLAST)
	_check(s.center_of_mass.x > 1.0 * Ship.CELL, "ballast pulls com toward the heavy side")
	s.queue_free()
	await process_frame


func _test_greedy_merge() -> void:
	_t("greedy rectangle merge collapses adjacent blocks")
	var solid := {}
	for x in 3:
		for y in 2:
			solid[Vector2i(x, y)] = BlockDB.Type.HULL
	var rect_ship := _make_ship(solid)
	_check(_shape_count(rect_ship) == 1, "a solid 3x2 slab becomes exactly 1 collider")
	rect_ship.queue_free()

	var l_ship := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.HULL,
		Vector2i(0, 1): BlockDB.Type.HULL,
	})
	_check(_shape_count(l_ship) == 2, "an L shape becomes 2 colliders")
	l_ship.queue_free()

	var big := {}
	for x in 20:
		for y in 10:
			big[Vector2i(x, y)] = BlockDB.Type.HULL
	var big_ship := _make_ship(big)
	_check(_shape_count(big_ship) == 1,
		"a 200-block hull is 1 collider, not 200 (perf invariant)")
	big_ship.queue_free()
	await process_frame


func _test_placement_adjacency() -> void:
	_t("blocks may only be placed adjacent to existing blocks")
	var s := _make_ship({Vector2i(0, 0): BlockDB.Type.HULL})
	_check(s.can_place_at(Vector2i(1, 0)), "adjacent cell is placeable")
	_check(not s.can_place_at(Vector2i(0, 0)), "occupied cell is not placeable")
	_check(not s.can_place_at(Vector2i(5, 5)), "floating disconnected cell is refused")
	s.queue_free()
	await process_frame


func _test_damage_destroys_block() -> void:
	_t("damage reduces hp and destroys at zero")
	var s := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HELM,
		Vector2i(1, 0): BlockDB.Type.HULL,
	})
	s.damage_cell(Vector2i(1, 0), 30.0)
	_check_approx(s.blocks[Vector2i(1, 0)]["hp"], 70.0, 0.01, "partial damage leaves the block")
	s.damage_cell(Vector2i(1, 0), 70.0)
	_check(not s.has_block(Vector2i(1, 0)), "block destroyed at 0 hp")
	_check_approx(s.mass, 8.0, 0.01, "mass drops when a block is destroyed")
	s.queue_free()
	await process_frame


func _test_air_density() -> void:
	_t("air thins with altitude")
	var s := _make_ship({Vector2i(0, 0): BlockDB.Type.HULL})
	_check_approx(s.air_density_at(Ship.SEA_LEVEL_Y), 1.0, 0.001, "full density at sea level")
	_check_approx(s.air_density_at(Ship.CEILING_Y), Ship.MIN_AIR_DENSITY, 0.001,
		"floor density at the ceiling")
	var mid := s.air_density_at(Ship.CEILING_Y * 0.5)
	_check(mid > Ship.MIN_AIR_DENSITY and mid < 1.0, "density falls monotonically between")
	s.queue_free()
	await process_frame


func _test_lift_ratio_and_ceiling() -> void:
	_t("lift ratio and ceiling estimate")
	var s := _make_ship(_starter_ship())
	var ratio := s.lift_ratio()
	# Capacity comfortably above weight: with buoyancy clamped at neutral,
	# surplus is pure margin (altitude reach, damage tolerance), never climb.
	_check(ratio > 0.95 and ratio < 1.4,
		"starter has capacity margin over its weight (ratio %.2f)" % ratio)

	var ceiling := s.ceiling_estimate()
	_check(ceiling <= Ship.SEA_LEVEL_Y and ceiling > Ship.CEILING_Y,
		"ceiling lands between sea level and max altitude (%.0f)" % -ceiling)
	s.queue_free()

	var brick := _make_ship({Vector2i(0, 0): BlockDB.Type.BALLAST})
	_check_approx(brick.lift_ratio(), 0.0, 0.001, "a ship with no gasbags has no lift")
	_check_approx(brick.ceiling_estimate(), Ship.SEA_LEVEL_Y, 0.001,
		"a ship with no lift has no ceiling above sea level")
	brick.queue_free()
	await process_frame


# (The inertia-under-torque test retired with rotation itself: under the
# upright rule — lock_rotation, owner 2026-08-20 — no ship rotates at all,
# so rotational inertia is unobservable. See _test_ships_stay_upright_always.)


# --- Severing -------------------------------------------------------------

func _test_severing_keeps_core() -> void:
	_t("severing splits the grid and keeps the core island")
	# Barbell: helm — joint — two-block tail.
	var s := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HELM,
		Vector2i(1, 0): BlockDB.Type.HULL,
		Vector2i(2, 0): BlockDB.Type.HULL,
		Vector2i(3, 0): BlockDB.Type.HULL,
	})

	var pieces: Array = []
	s.severed.connect(func(piece: Ship) -> void: pieces.append(piece))

	s.remove_block(Vector2i(1, 0))  # cut the joint

	_check(pieces.size() == 1, "exactly one piece severed off")
	_check(s.blocks.size() == 1, "the helm island stays with the original ship")
	_check(s.has_block(Vector2i(0, 0)), "the retained island is the one holding the helm")
	if pieces.size() == 1:
		_check(pieces[0].blocks.size() == 2, "the severed piece carries the other 2 blocks")
		_check(pieces[0].has_block(Vector2i(2, 0)) and pieces[0].has_block(Vector2i(3, 0)),
			"severed piece holds the correct cells")
		_check(not pieces[0].assist_enabled, "wreckage does not fly itself")

	await process_frame
	s.queue_free()
	for p in pieces:
		if is_instance_valid(p):
			p.queue_free()
	await process_frame


func _test_severed_piece_inherits_velocity() -> void:
	_t("severed wreckage inherits velocity — and stays upright, like all ships")
	var s := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HELM,
		Vector2i(1, 0): BlockDB.Type.HULL,
		Vector2i(2, 0): BlockDB.Type.HULL,
	}, false)
	s.gravity_scale = 0.0
	s.linear_velocity = Vector2(120.0, -40.0)
	await _step(1)

	var pieces: Array = []
	s.severed.connect(func(piece: Ship) -> void: pieces.append(piece))
	s.remove_block(Vector2i(1, 0))

	_check(pieces.size() == 1, "piece severed")
	if pieces.size() == 1:
		var v: Vector2 = pieces[0].linear_velocity
		_check(v.is_equal_approx(s.linear_velocity),
			"piece carries the parent's velocity (%.0f, %.0f)" % [v.x, v.y])
		# The upright rule covers wreckage too: no spin exists to inherit.
		_check_approx(pieces[0].angular_velocity, 0.0, 0.001,
			"wreckage does not tumble — ships are always upright")

	await process_frame
	s.queue_free()
	for p in pieces:
		if is_instance_valid(p):
			p.queue_free()
	await process_frame


func _test_empty_ship_frees_itself() -> void:
	_t("a ship with no blocks left destroys itself")
	var s := _make_ship({Vector2i(0, 0): BlockDB.Type.HULL})
	var died := [false]
	s.destroyed.connect(func() -> void: died[0] = true)
	s.remove_block(Vector2i(0, 0))
	_check(died[0], "destroyed signal fired")
	await process_frame
	_check(not is_instance_valid(s), "node was freed")


# --- Doors ------------------------------------------------------------------

## A door is structure without collision: it has mass and hp, holds the ship
## together for severing purposes, but produces no collider — so characters
## walk through it. (The pilot test proves the walk-through on the real ship.)
func _test_doors() -> void:
	_t("doors are structural openings")
	var s := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.DOOR,
		Vector2i(2, 0): BlockDB.Type.HULL,
	})
	_check(_shape_count(s) == 2,
		"the door contributes no collider — hull, gap, hull (%d shapes)" % _shape_count(s))
	_check_approx(s.mass, 25.0, 0.01, "but it does have mass")
	_check(s._connected_islands().size() == 1,
		"and it holds the ship together — no severing through a doorway")

	# The owner's founding example for the wall model: a destroyed door
	# leaves the doorway unusable but the ship WHOLE — the wall behind it
	# holds. Only removing the wall (deconstruction) lets the piece go.
	var pieces: Array = []
	s.severed.connect(func(p: Ship) -> void: pieces.append(p))
	s.damage_cell(Vector2i(1, 0), 999.0)
	_check(pieces.is_empty(), "destroying the door does NOT sever — its wall holds")
	s.remove_block(Vector2i(1, 0))
	_check(pieces.size() == 1, "removing the doorway's wall lets the piece go")

	await process_frame
	s.queue_free()
	for p in pieces:
		if is_instance_valid(p):
			p.queue_free()
	await process_frame


func _test_doors_open_and_close() -> void:
	_t("doors open and close as a whole component")
	var s := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.DOOR,
		Vector2i(1, 1): BlockDB.Type.DOOR,
		Vector2i(2, 0): BlockDB.Type.HULL,
	})
	s.position = Vector2(-800, 0)
	await _step(2)

	# A bullet's-eye view: the same ray Shot casts (hull + shield layers),
	# straight down the door column. Open passes, closed stops.
	var space := s.get_world_2d().direct_space_state
	var ray := PhysicsRayQueryParameters2D.create(
		s.to_global(Vector2(Ship.CELL, -600.0)),
		s.to_global(Vector2(Ship.CELL, 600.0)), 1 | 8)
	_check(space.intersect_ray(ray).is_empty(),
		"an open doorway lets shots straight through")

	s.damage_cell(Vector2i(1, 0), 10.0)  # scuff it, to prove hp survives
	_check(s.toggle_door(Vector2i(1, 1)), "the door toggles from either cell")
	_check(s.blocks[Vector2i(1, 0)]["type"] == BlockDB.Type.DOOR_CLOSED
		and s.blocks[Vector2i(1, 1)]["type"] == BlockDB.Type.DOOR_CLOSED,
		"both cells of the doorway close together — one component, one door")
	_check_approx(s.blocks[Vector2i(1, 0)]["hp"], 50.0, 0.01,
		"closing carries the door's damage along")
	await _step(2)
	_check(not space.intersect_ray(ray).is_empty(),
		"a closed door STOPS shots — shoot-through only when open")

	# Use, not construction: the blueprint still holds the authored door.
	_check(s.blueprint_map().get(Vector2i(1, 0), -1) == BlockDB.Type.DOOR,
		"open/close never touches the blueprint")

	_check(s.toggle_door(Vector2i(1, 0)), "and it opens again")
	await _step(2)
	_check(space.intersect_ray(ray).is_empty(),
		"reopened, the doorway passes shots once more")

	s.queue_free()
	await process_frame


func _test_projectiles_are_ballistic() -> void:
	_t("projectiles are physical: they arc, and their momentum shoves")
	# Owner 2026-08-20: "all projectiles should be driven by physics —
	# mass, force, direction". A shot is a dense slug: muzzle velocity is
	# impulse/mass, gravity bends the flight, and the mass × velocity it
	# arrives with shoves the ship that stops it.
	var s := Shot.new()
	s.mass = 2.0
	s.fire(Vector2(600.0, 0.0))  # J = m·v → v = 300
	_check(s.velocity.is_equal_approx(Vector2(300.0, 0.0)),
		"muzzle velocity is impulse over mass (%.0f px/s)" % s.velocity.x)

	s.position = Vector2(-2000.0, -400.0)
	s.gravity = 980.0 * Shot.GRAVITY_FACTOR
	s.life = 10.0
	s.faction = 1
	root.add_child(s)
	var y0 := s.position.y
	await _step(30)  # half a second of flight
	_check(is_instance_valid(s) and s.position.y > y0 + 5.0,
		"the flight arcs under gravity (dropped %.0f px)" % (s.position.y - y0))
	_check(is_instance_valid(s) and s.velocity.y > 0.0,
		"and the velocity vector bends with it")
	if is_instance_valid(s):
		s.queue_free()

	# Momentum transfer: park a target in a slug's path and let it thud in.
	var target := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(0, 1): BlockDB.Type.HULL,
	})
	target.position = Vector2(2400.0, 0.0)
	await _step(2)  # let the collider register with the space

	var slug := Shot.new()
	slug.mass = 5.0
	slug.fire(Vector2(2000.0, 0.0) * slug.mass)  # 2000 px/s, heavy
	slug.gravity = 0.0  # point-blank: isolate the shove from the arc
	slug.faction = 1
	slug.position = target.position + Vector2(-120.0, 8.0)
	root.add_child(slug)
	await _step(5)
	_check(not is_instance_valid(slug), "the hull stopped the slug")
	_check(target.linear_velocity.x > 0.0,
		"and absorbed its momentum — the impact shoves (%.1f px/s)"
			% target.linear_velocity.x)

	target.queue_free()
	await process_frame


## Owner 2026-08-21: "bullets should all be able to travel about 10x their
## current distance... perhaps up the time limit to 30 or 60 seconds."
## Range here is purely time-based (nothing caps distance — terrain, hulls
## and the arc are the only stoppers), so this pins the lifetime that IS
## the reach. The default is the range for EVERY shooter now — the old
## per-shooter life multiplier is gone (world.gd).
func _test_bullets_carry_far() -> void:
	_t("every bullet lives long enough to carry ~10x the old distance")
	_check(Shot.new().life >= 30.0,
		"the base shell life is the owner's 30 s+ range (%.0f s)" % Shot.new().life)

	# A level shot in empty sky (no gravity, no geometry) is still flying
	# well past the old 14 s enemy ceiling — the reach the owner asked for.
	var s := Shot.new()
	s.gravity = 0.0
	s.faction = 1
	s.velocity = Vector2(3000.0, 0.0)
	s.position = Vector2(0.0, -30000.0)
	root.add_child(s)
	await _step(15 * 60)  # 15 s of stepped flight
	_check(is_instance_valid(s),
		"still airborne after 15 s (old enemy shells died at 14 s, players at 1.4 s)")
	_check(is_instance_valid(s) and s.position.x > 40000.0,
		"and has carried far downrange (%.0f px)"
			% (s.position.x if is_instance_valid(s) else 0.0))
	if is_instance_valid(s):
		s.queue_free()
	await process_frame


## The distance twin of the range pin: a shot is freed once its PATH LENGTH
## passes `max_travel`, well before its 30 s life — this is what keeps a
## missed-fire swarm from accumulating and dragging the frame rate down
## (each live shot costs a raycast + a per-ship prop-wash sweep every frame).
## The cull is OPT-IN (INF by default), so a bare shot — and the range pin —
## still fly the full felt range; only the spawner caps in-game shots.
func _test_shots_are_culled_past_their_range() -> void:
	_t("a shot past its max_travel is freed early — the swarm cannot pile up")

	# Capped: 500 px of range at 1200 px/s → ~0.42 s, a tiny fraction of 30 s.
	var capped := Shot.new()
	capped.gravity = 0.0
	capped.faction = 1
	capped.life = 30.0
	capped.max_travel = 500.0
	capped.velocity = Vector2(1200.0, 0.0)
	capped.position = Vector2(0.0, -30000.0)  # empty sky, no geometry to hit
	root.add_child(capped)
	await _step(6)  # ~120 px in: still short of the cap
	_check(is_instance_valid(capped), "it is still flying inside its range")
	await _step(30)  # now well past 500 px
	_check(not is_instance_valid(capped),
		"and is freed once it out-flies max_travel — long before the 30 s life")

	# Uncapped control: the SAME flight without a cap keeps going past 500 px,
	# so the felt range the owner asked for is untouched (this is the range
	# pin's guarantee, restated at the cull boundary).
	var uncapped := Shot.new()
	uncapped.gravity = 0.0
	uncapped.faction = 1
	uncapped.life = 30.0
	uncapped.velocity = Vector2(1200.0, 0.0)
	uncapped.position = Vector2(0.0, -31000.0)
	root.add_child(uncapped)
	await _step(36)
	_check(is_instance_valid(uncapped) and uncapped.position.x > 500.0,
		"a bare shot (max_travel INF) flies straight past that distance (%.0f px)"
			% (uncapped.position.x if is_instance_valid(uncapped) else -1.0))
	if is_instance_valid(uncapped):
		uncapped.queue_free()

	# The swarm stays bounded: fire a cloud of capped shots, run them past the
	# cap, and the live-Shot population drains to nothing — no 30 s backlog.
	var swarm: Array = []
	for i in 40:
		var sh := Shot.new()
		sh.gravity = 0.0
		sh.faction = 1
		sh.life = 30.0
		sh.max_travel = 500.0
		sh.velocity = Vector2(1400.0, 0.0)
		sh.position = Vector2(-4000.0 + i * 30.0, -33000.0)
		root.add_child(sh)
		swarm.append(sh)
	await _step(40)  # ~930 px of travel — every one is past its 500 px cap
	var alive := 0
	for sh in swarm:
		if is_instance_valid(sh):
			alive += 1
			sh.queue_free()
	_check(alive == 0,
		"all %d swarm shots freed themselves past range — the swarm is bounded (%d left)"
			% [swarm.size(), alive])
	await process_frame


func _test_shots_inherit_the_shooters_velocity() -> void:
	_t("a shot leaves the muzzle carrying its shooter's velocity")
	# Owner 2026-08-21: "if you're moving in the direction the ship is
	# shooting, the projectile collides with the turret immediately." The
	# muzzle velocity was world-absolute, so a ship faster than its own
	# shells simply overran them. v = J/m + v_platform now.
	var still := Shot.new()
	still.mass = 2.0
	still.fire(Vector2(600.0, 0.0))  # J = m·v → v = 300, as before
	_check(still.velocity.is_equal_approx(Vector2(300.0, 0.0)),
		"a stationary platform reproduces the old numbers exactly (%.0f px/s)"
			% still.velocity.x)

	var platform := Vector2(250.0, -40.0)
	var moving := Shot.new()
	moving.mass = 2.0
	moving.fire(Vector2(600.0, 0.0), platform)
	_check(moving.velocity.is_equal_approx(Vector2(550.0, -40.0)),
		"from a moving platform it is muzzle PLUS platform (%s)" % moving.velocity)
	# The whole point of the fix, stated as the invariant it protects: the
	# shell always leaves the barrel at muzzle speed RELATIVE TO THE BARREL,
	# so however fast the ship goes it can never catch its own shot.
	_check((moving.velocity - platform).is_equal_approx(still.velocity),
		"so relative to its own gun the shell always leaves at J/m")

	still.free()
	moving.free()
	await process_frame


func _test_shots_survive_firing_along_the_motion() -> void:
	_t("a shell fired the way the ship moves is not eaten by its own gun")
	# Owner 2026-08-21, SECOND report: bullets still deleted at the gun.
	# The surviving mechanism is the ENEMY fire path: _enemy_fire spawns
	# from _physics_process, where poses are one integrate old — by the
	# shot's first ray the gun has moved on, and a gun moving WITH the
	# shot has overtaken its stale muzzle point, so the first ray strikes
	# the turret's rear face from OUTSIDE (hit_from_inside only protects
	# a start inside the shape). Shot.fire() rides the spawn point one
	# physics frame forward. This test recreates the stale epoch exactly:
	# capture the muzzle, let one integrate advance the hull, then spawn
	# at the captured point — with the real collider geometry (the turret
	# hangs on a non-colliding strut, so its collider is a small separate
	# shape the hull overtakes in a single tick).
	var s := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(0, 1): BlockDB.Type.STRUT,
		Vector2i(0, 2): BlockDB.Type.TURRET,
	})
	s.position = Vector2(-4600, -1200)
	s.gravity_scale = 0.0
	s.linear_damp = 0.0
	s.linear_velocity = Vector2(1200.0, 0.0)  # > one turret-cell per tick
	await _step(2)  # collider registered, ship under way

	# The stale epoch: muzzle captured HERE, ship integrates once more
	# before the shot exists — exactly what a _physics_process spawner sees.
	var stale_muzzle: Vector2 = s.to_global(s.local_pos_of(Vector2i(0, 2)))
	await _step(1)

	var shot := Shot.new()
	shot.mass = 5.0
	shot.gravity = 0.0
	shot.faction = s.faction
	shot.life = 10.0
	shot.position = stale_muzzle
	shot.fire(Vector2(700.0, 0.0) * shot.mass, s.linear_velocity)
	root.add_child(shot)

	await _step(20)
	_check(is_instance_valid(shot),
		"the shell is still flying 20 ticks after leaving a fast gun")
	if is_instance_valid(shot):
		var lead := shot.position.x - s.to_global(s.local_pos_of(Vector2i(0, 2))).x
		_check(lead > 100.0,
			"and it pulled ahead of the gun that fired it (%.0f px clear)" % lead)
		shot.queue_free()
	s.queue_free()
	await process_frame


func _test_solid_bounds_track_the_grid() -> void:
	_t("solid_bounds is a live-grid cache")
	var s := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.HULL,
		Vector2i(2, 0): BlockDB.Type.HULL,
		Vector2i(2, 1): BlockDB.Type.STRUT,  # pass-through: not in the bounds
	})
	s.position = Vector2(-3200, 0)
	_check(s.solid_bounds.is_equal_approx(Rect2(-8, -8, 48, 16)),
		"bounds cover the solid cells only (%s)" % s.solid_bounds)
	s.damage_cell(Vector2i(2, 0), 999.0)
	_check(s.solid_bounds.is_equal_approx(Rect2(-8, -8, 32, 16)),
		"destroying a block shrinks the cache the same frame (%s)" % s.solid_bounds)
	s.queue_free()
	await process_frame


func _test_guns_aim_at_what_they_can_reach() -> void:
	_t("gunners aim at whatever part of the target their arc can reach")
	# The owner's screenshot: a belly gun facing DOWN, a target ship at
	# roughly the same altitude. The target's ORIGIN sits above the gun's
	# horizon, but its lower hull hangs below it — the gun must fire at
	# that, not sulk.
	var target := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(0, 1): BlockDB.Type.HULL,
		Vector2i(0, 2): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.HULL,
		Vector2i(1, 1): BlockDB.Type.HULL,
		Vector2i(1, 2): BlockDB.Type.HULL,
	})
	target.position = Vector2(3600, -20)  # centre above the muzzle's y=0
	await process_frame

	var muzzle := Vector2(3400, 0.0)
	var aim: Variant = ShipAI.arc_aim_point(muzzle, Vector2.DOWN, target)
	_check(aim != null, "a level ship is still engageable")
	if aim != null:
		var p := aim as Vector2
		_check(p.y > muzzle.y, "the chosen point lies below the horizon (y=%.0f)" % p.y)
		var rect := Rect2(target.to_global(target.solid_bounds.position),
			target.solid_bounds.size)
		_check(rect.grow(0.5).has_point(p), "and on the target's hull")

	# A target ENTIRELY above the horizon genuinely cannot be reached —
	# that is what the flying AI's repositioning is for.
	target.position = Vector2(3600, -400)
	_check(ShipAI.arc_aim_point(muzzle, Vector2.DOWN, target) == null,
		"a target fully above a down-gun's horizon is out of reach")

	target.queue_free()
	await process_frame


func _test_blubber_is_buoyant_structure() -> void:
	_t("blubber is buoyant structure — armored lift")
	# The original's whale-product block (owner survey 2026-08-20):
	# "naturally buoyant" AND a solid building material — unlike the
	# gasbag, which is dedicated fragile lift.
	var s := _make_ship({
		Vector2i(0, 0): BlockDB.Type.BLUBBER,
		Vector2i(1, 0): BlockDB.Type.BLUBBER,
	})
	s.position = Vector2(-4000, 0)
	_check(_shape_count(s) == 1, "solid: it joins the hull collider")
	_check(s.lift_ratio() > 1.0,
		"a pure blubber hull floats itself (%.2f)" % s.lift_ratio())
	s.damage_cell(Vector2i(0, 0), 10.0)
	_check(s.blocks[Vector2i(1, 0)]["hp"] == BlockDB.max_hp(BlockDB.Type.BLUBBER),
		"damage stays per-cell — raw structure, not a balloon component")
	s.queue_free()
	await process_frame


func _test_prop_wash_bends_slow_shots_more() -> void:
	_t("prop wash bends slow shells hard and fast rounds barely")
	# Owner survey (2026-08-20): the original's props push projectiles —
	# heavy slow artillery visibly more than machine-gun rounds. Emergent
	# from dwell time in the jet: same force, longer exposure.
	var s := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.ENGINE,
		Vector2i(0, 1): BlockDB.Type.PROPELLER,  # hung below → vertical
	})
	s.position = Vector2(2600, -900)
	s.freeze = true  # hold the test rig still; wash only reads state
	s.thrust_input = Vector2(0, 1)  # climbing: air blasts DOWN below
	await _step(2)

	var slow := await _wash_deflection(s, 260.0)
	var fast := await _wash_deflection(s, 1300.0)
	_check(slow > 100.0,
		"a slow shell is bent hard by the jet (%.0f px/s down)" % slow)
	_check(fast > 5.0 and fast < slow * 0.5,
		"a fast round barely notices the same jet (%.0f px/s)" % fast)

	s.thrust_input = Vector2.ZERO
	var idle := await _wash_deflection(s, 260.0)
	_check(absf(idle) < 1.0,
		"an idle prop blows nothing (%.1f px/s)" % idle)

	s.queue_free()
	await process_frame


## Fly one horizontal shot under the ship's lift prop and report the
## vertical velocity it picked up crossing the jet.
func _wash_deflection(s: Ship, speed: float) -> float:
	var sh := Shot.new()
	sh.gravity = 0.0
	sh.faction = 1
	sh.life = 8.0
	sh.velocity = Vector2(speed, 0.0)
	sh.position = s.to_global(Vector2(-200.0, 80.0))
	root.add_child(sh)
	var exit_x: float = s.to_global(Vector2(200.0, 0.0)).x
	for i in 300:
		await physics_frame
		if not is_instance_valid(sh) or sh.position.x > exit_x:
			break
	var dvy := sh.velocity.y if is_instance_valid(sh) else 0.0
	if is_instance_valid(sh):
		sh.queue_free()
	await process_frame
	return dvy


func _test_props_alone_hold_altitude() -> void:
	_t("buoyancy is optional: strong props alone maintain height")
	# Owner observation (2026-08-20, from the original): a ship with no
	# gas at all floats if its propellers are strong enough. Our altitude
	# hold has always been thrust-based and power-hungry — this pins the
	# zero-buoyancy case: engines and lift props, not one gasbag aboard.
	var s := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.ENGINE,
		Vector2i(2, 0): BlockDB.Type.ENGINE,
		Vector2i(3, 0): BlockDB.Type.HULL,
		Vector2i(4, 0): BlockDB.Type.HULL,
		Vector2i(0, 1): BlockDB.Type.PROPELLER,
		Vector2i(2, 1): BlockDB.Type.PROPELLER,
		Vector2i(4, 1): BlockDB.Type.PROPELLER,
	}, false)
	s.position = Vector2(1400, -300)
	_check(s.lift_ratio() == 0.0, "not one gasbag aboard")
	await _step(30)
	var y := s.position.y
	await _step(120)
	_check(absf(s.position.y - y) < 14.0,
		"the props alone hold it aloft (drifted %.1f px in 2s)" % (s.position.y - y))
	_check(s._hover_engaged, "the altitude hold is doing real prop work")
	s.queue_free()
	await process_frame


## Carcass-as-airship (owner 2026-08-23): a body with no lift of its own flies once
## you bolt on tethered helium balloons. The balloon's lift folds into the body's
## total (Ship.rebuild); a balloon whose anchor cell is gone detaches; and balloons
## ride the payload so a built airship persists.
func _test_balloons_lift_and_detach() -> void:
	_t("tethered balloons add lift (carcass-as-airship), detach with their cell, ride the payload")
	var cells := {}
	for x in 4:
		for y in 2:
			cells[Vector2i(x, y)] = BlockDB.Type.HULL   # dead weight: no lift of its own
	var s := _make_ship(cells, false)
	_check(s.lift_ratio() < 1.0, "the bare hull sinks (ratio %.2f)" % s.lift_ratio())
	var base_lift := s._total_lift
	s.attach_balloon(Vector2i(0, 0), Ship.BalloonSize.LARGE)
	s.attach_balloon(Vector2i(3, 0), Ship.BalloonSize.LARGE)
	_check(is_equal_approx(s.balloon_lift_total(), Ship.BALLOON_LIFT[Ship.BalloonSize.LARGE] * 2.0),
		"two large balloons add their lift (%.0f)" % s.balloon_lift_total())
	_check(s._total_lift > base_lift and s.lift_ratio() >= 1.0,
		"with balloons the dead weight now floats (ratio %.2f)" % s.lift_ratio())
	# Lose the anchor cell (mined / severed / shot away) → that balloon detaches.
	s.blocks.erase(Vector2i(0, 0))
	s.rebuild()
	_check(s.balloons.size() == 1
			and is_equal_approx(s.balloon_lift_total(), Ship.BALLOON_LIFT[Ship.BalloonSize.LARGE]),
		"a balloon whose anchor cell is gone detaches (%d left)" % s.balloons.size())
	# Balloons ride the spawn payload (a built airship persists).
	var clone := Ship.from_data(s.to_payload())
	root.add_child(clone)
	clone.rebuild()
	_check(clone.balloons.size() == 1, "balloons ride the payload (%d)" % clone.balloons.size())
	s.queue_free()
	clone.queue_free()
	await process_frame


## THE SOURCE MODEL (owner 2026-08-24): balloons are RIGID PREBUILT PLACEABLES —
## three fixed sizes with SET tether counts (1 / 2 / 3), and NOT independently
## destructible: "when the balloon is damaged or destroyed, the entire placeable
## has the same effect — no need to destroy EVERY block, just hit it from
## anywhere". One pool per balloon; a hit anywhere on the bulb hurts all of it;
## at zero the WHOLE thing pops and takes its lift with it.
func _test_balloons_are_one_destructible_placeable() -> void:
	_t("a balloon is ONE placeable: 3 prebuilt sizes, fixed tethers, pops whole")
	_check(Ship.BALLOON_LIFT.size() == 3 and Ship.BALLOON_CABLES.size() == 3
			and Ship.BALLOON_HP.size() == 3 and Ship.BALLOON_RADIUS_CELLS.size() == 3,
		"three prebuilt balloon sizes, fully specified")
	_check(Ship.BALLOON_CABLES == [1, 2, 3],
		"tether counts are fixed per size: smallest 1, largest 3 (%s)"
			% str(Ship.BALLOON_CABLES))
	_check(Ship.BALLOON_LIFT[0] < Ship.BALLOON_LIFT[2]
			and Ship.BALLOON_HP[0] < Ship.BALLOON_HP[2],
		"a bigger bag lifts more and takes more to burst")

	var b := _make_ship({Vector2i(0, 0): BlockDB.Type.HULL, Vector2i(1, 0): BlockDB.Type.HULL})
	b.position = Vector2(-64000, 0)
	_check(b.attach_balloon(Vector2i(0, 0), Ship.BalloonSize.MEDIUM),
		"a MEDIUM balloon (the new middle size) attaches")
	var blift := b.balloon_lift_total()
	_check(is_equal_approx(blift, Ship.BALLOON_LIFT[Ship.BalloonSize.MEDIUM]),
		"and contributes its size's lift (%.0f)" % blift)

	# A HIT ANYWHERE ON THE BULB counts: the edge is as good as the centre,
	# because the whole placeable is one target.
	var centre := b.balloon_center(0)
	var rad: float = Ship.BALLOON_RADIUS_CELLS[Ship.BalloonSize.MEDIUM] * Ship.CELL * b.scale_unit
	_check(b.balloon_at_global(centre) == 0, "the bulb centre hits the balloon")
	_check(b.balloon_at_global(centre + Vector2(rad * 0.9, 0.0)) == 0,
		"so does its EDGE — any part of the placeable is the whole placeable")
	_check(b.balloon_at_global(centre + Vector2(rad * 3.0, 0.0)) == -1,
		"a miss well clear of the bulb hits nothing")

	# PARTIAL damage does NOT shrink it: still one whole balloon, still lifting
	# exactly the same, just closer to bursting.
	var popped := b.damage_balloon(0, Ship.BALLOON_HP[Ship.BalloonSize.MEDIUM] * 0.5)
	_check(not popped and b.balloons.size() == 1,
		"half its hp gone: still ONE whole balloon, no partial bag")
	_check(is_equal_approx(b.balloon_lift_total(), blift),
		"and its lift is undiminished until it bursts (%.0f)" % b.balloon_lift_total())

	# The rest of the pool POPS the whole thing, and the lift vanishes with it.
	var saw_pop := [false]
	b.balloon_popped.connect(func(_at: Vector2, _size: int) -> void: saw_pop[0] = true)
	popped = b.damage_balloon(0, Ship.BALLOON_HP[Ship.BalloonSize.MEDIUM])
	_check(popped and b.balloons.is_empty(),
		"the finishing hit pops the ENTIRE placeable at once")
	_check(saw_pop[0], "and announces it (balloon_popped)")
	_check(is_equal_approx(b.balloon_lift_total(), 0.0),
		"its lift is gone the same frame — a shot balloon drops what it held")

	# Battle damage RIDES the payload: a half-shot balloon reloads half-shot.
	_check(b.attach_balloon(Vector2i(1, 0), Ship.BalloonSize.LARGE), "a large balloon attaches")
	b.damage_balloon(0, Ship.BALLOON_HP[Ship.BalloonSize.LARGE] * 0.5)
	var hurt: float = float(b.balloons[0]["hp"])
	var clone2 := Ship.from_data(b.to_payload())
	root.add_child(clone2)
	_check(clone2.balloons.size() == 1
			and absf(float(clone2.balloons[0]["hp"]) - hurt) < 0.02,
		"a damaged balloon round-trips its hp (%.1f)" % hurt)
	# BACKWARD-COMPAT: the pre-hp payload packed THREE ints per balloon; such a
	# save must still load its airship (healed to full), not lose it.
	var old_style := Ship._decode_balloons(
		PackedInt32Array([1, 0, Ship.BalloonSize.SMALL]))
	_check(old_style.size() == 1
			and is_equal_approx(float(old_style[0]["hp"]), Ship.BALLOON_HP[Ship.BalloonSize.SMALL]),
		"a legacy 3-int balloon payload still loads, healed to full")

	b.queue_free()
	clone2.queue_free()
	await process_frame


func _test_whale_is_a_whale() -> void:
	# The whole pod (design jam 2026-08-20): the reference plus the four
	# owner-adopted variants, each gated on the same surveyed body plan.
	for path in ["res://ships/whale.ship", "res://ships/whale_bull.ship",
			"res://ships/whale_sleek.ship", "res://ships/whale_humpback.ship",
			"res://ships/whale_leviathan.ship"]:
		await _check_whale_body_plan(path)


func _check_whale_body_plan(path: String) -> void:
	var whale_name := path.get_file().get_basename()
	_t("%s: one connected, mostly-blubber, floating beast" % whale_name)
	var cells := ShipLayout.load_cells(path)
	var s := _make_ship(cells)
	s.position = Vector2(-5200, 0)
	_check(s._connected_islands().size() == 1, "one connected body")
	var blubber := 0
	for cell in cells:
		if cells[cell] == BlockDB.Type.BLUBBER:
			blubber += 1
	var frac := float(blubber) / cells.size()
	_check(frac > 0.5 and frac < 0.85,
		"largely blubber, as surveyed (%.0f%%)" % (frac * 100.0))
	_check(s.lift_ratio() > 1.0,
		"and it floats on its own fat (%.2f)" % s.lift_ratio())

	# The FLESH holds it together (the wall model, owner: Windforge's
	# background tiles): every cell spawns with a combat-indestructible
	# wall, so shooting a channel clean through the whale must never
	# split it — one anchored unit until deliberately MINED apart.
	var pieces: Array = []
	s.severed.connect(func(p: Ship) -> void: pieces.append(p))
	# Cut the DENSEST column so the test survives owner redesigns of the
	# body plan — whatever the shape, a full vertical cut must not sever.
	var columns := {}
	for cell in s.blocks:
		columns[cell.x] = columns.get(cell.x, 0) + 1
	var cut_x: int = 0
	var best_n := 0
	for x in columns:
		if columns[x] > best_n:
			best_n = columns[x]
			cut_x = x
	for cell in s.blocks.keys():
		if cell.x == cut_x and s.blocks.has(cell):
			s.damage_cell(cell, 9999.0, false)
	s.rebuild()
	_check(pieces.is_empty() and s._connected_islands().size() == 1,
		"a channel shot clean through does not sever — the flesh walls hold")
	s.queue_free()
	for p in pieces:
		if is_instance_valid(p):
			p.queue_free()
	await process_frame


func _test_whale_is_one_unit_until_dead() -> void:
	_t("a living whale is ONE unit; only a carcass breaks block by block")
	# Owner: no tiny squares popping off a live whale — damage drains the
	# shared pool, the body stays whole, and death flips it to ordinary
	# breakable blocks for corpse-mining.
	var s := _make_ship(ShipLayout.load_cells("res://ships/whale.ship"))
	s.position = Vector2(-9600, 0)
	s.shared_health = 100.0
	s.shared_health_max = 100.0
	var cell: Vector2i = s.blocks.keys()[0]
	var n0 := s.blocks.size()
	s.damage_cell(cell, 60.0)
	_check(s.blocks.size() == n0 and is_equal_approx(s.shared_health, 40.0),
		"damage drains the WHALE, not a block (pool %.0f)" % s.shared_health)
	s.damage_cell(cell, 60.0)
	_check(s.shared_health == 0.0 and s.blocks.size() == n0,
		"the pool empties with the body still whole")
	s.damage_cell(cell, 9999.0)
	_check(s.blocks.size() < n0, "dead, the carcass breaks block by block")
	s.queue_free()
	await process_frame


## Owner 2026-08-24: "whales seem completely immune to damage while charging."
## ROOT CAUSE: a LIVING creature collides as one coarse AABB box (the physics-cliff
## fix), but its cells are SPARSE inside — a shot into an empty corner mapped to an
## AIR cell, damaged nothing, and was consumed anyway (visibly "eaten", read as
## immune). Ram immunity is, and always was, a BLOCKS-only crush thing — it never
## touched gunfire. Fix: shots snap the hit to the nearest real block, so a visible
## hit always bites. (A vessel's exact collider already lands on a solid cell.)
func _test_shots_snap_to_the_nearest_block_on_a_creature() -> void:
	_t("a shot into a living creature's coarse-AABB margin snaps to a real block (the 'immune whale' fix)")
	var s := _make_ship(ShipLayout.load_cells("res://ships/whale.ship"))
	s.position = Vector2(-12000, 0)
	s.shared_health = 1000.0
	s.shared_health_max = 1000.0
	# An empty cell right beside the body — the margin the single-AABB collider
	# still covers, where a shot used to land on nothing.
	var solid: Vector2i = s.blocks.keys()[0]
	var air := Vector2i.ZERO
	var found := false
	for off in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0),
			Vector2i(-1, -1), Vector2i(1, -1)]:
		if not s.blocks.has(solid + off):
			air = solid + off
			found = true
			break
	_check(found, "found an empty cell beside the body")
	var air_pt := s.to_global(s.local_pos_of(air))
	_check(not s.blocks.has(s.cell_at_global(air_pt)),
		"the raw hit cell is AIR — the old path damaged nothing here (the 'immune' bug)")
	var snapped := s.nearest_solid_cell(air_pt)
	_check(s.blocks.has(snapped), "nearest_solid_cell snaps the hit onto a real block")
	_check(s.nearest_solid_cell(s.to_global(s.local_pos_of(solid))) == solid,
		"a hit already on a block returns that block (no-op for a vessel's exact collider)")
	# End to end: the snapped hit DRAINS the shared pool — the whale bleeds now.
	var pool := s.shared_health
	s.damage_cell(snapped, 50.0)
	_check(s.shared_health < pool,
		"the snapped shot drains the pool — no longer immune (%.0f -> %.0f)" % [pool, s.shared_health])
	# Break-the-fix: the raw air cell still deals nothing, proving the snap is what bites.
	var pool2 := s.shared_health
	s.damage_cell(air, 50.0)
	_check(is_equal_approx(s.shared_health, pool2),
		"an air-cell hit still deals nothing (the snap is what makes the hit land)")
	s.queue_free()
	await process_frame


## The whale-sandwich FPS fix (session 5). A LIVING creature is one flexing body
## (no cell breaks, damage pools), so it does not need a cell-accurate collider —
## and the cost of the sandwich is the number of overlapping shape PAIRS the
## solver churns, so a coarse few-shape collider is the fix. Measured headless
## (a living whale between a ram and a wall): ~7 precise shapes → ~181 ms/frame
## TIME_PHYSICS_PROCESS; ~4 coarse shapes → ~34 ms (a ~5-6× cut). A carcass and
## every vessel keep the EXACT per-cell grid (mining needs it; vessels are
## untouched). mass / CoM / lift derive from the grid, never the collider, so
## coarse is contact-only.
func _test_living_creature_gets_a_coarse_collider() -> void:
	_t("a living creature gets a COARSE collider; carcasses and vessels stay exact")
	var cells := ShipLayout.upscale_cells(
		ShipLayout.load_cells("res://ships/whale.ship"), 8)

	# The reference precise coverage: build the SAME body as a CARCASS (pool
	# empty). A carcass takes the exact per-cell greedy merge — so its covered
	# cells equal the solid grid EXACTLY, and its shape count is the precise one.
	var carcass := _make_ship(cells)
	carcass.position = Vector2(-30000, 0)
	carcass.scale_unit = 8.0
	carcass.shared_health_max = 15000.0
	carcass.shared_health = 0.0  # dead: a carcass, precise
	carcass.rebuild()
	var precise_shapes := _shape_count(carcass)
	_check(_covered_cells(carcass) == _solid_cells(carcass),
		"a carcass covers the solid grid EXACTLY (%d cells, %d shapes)"
			% [_solid_cells(carcass).size(), precise_shapes])

	# The LIVING whale: coarse. Fewer shapes than the precise merge, and its
	# coverage is a clean OVER-approximation — a superset of the solid grid
	# (never a live cell left uncovered) that stays inside the body's AABB (never
	# reaching off into open air past the whale).
	var whale := _make_ship(cells)
	whale.position = Vector2(-30000, -6000)
	whale.scale_unit = 8.0
	whale.shared_health_max = 15000.0
	whale.shared_health = 15000.0  # alive
	whale.rebuild()
	var coarse_shapes := _shape_count(whale)
	_check(coarse_shapes < precise_shapes,
		"the living whale has FEWER collision shapes than the precise merge (%d < %d)"
			% [coarse_shapes, precise_shapes])
	var covered := _covered_cells(whale)
	var solid := _solid_cells(whale)
	var covers_all := true
	for c in solid:
		if not covered.has(c):
			covers_all = false
			break
	_check(covers_all, "coarse still covers every solid cell (no gap to fall through)")
	var b: Rect2 = whale.solid_bounds
	var lo := Vector2i(roundi(b.position.x / Ship.CELL), roundi(b.position.y / Ship.CELL))
	var hi := Vector2i(roundi((b.position.x + b.size.x) / Ship.CELL) - 1,
		roundi((b.position.y + b.size.y) / Ship.CELL) - 1)
	var within := true
	for c in covered:
		if c.x < lo.x or c.x > hi.x or c.y < lo.y or c.y > hi.y:
			within = false
			break
	_check(within, "and the coarse collider stays inside the body's footprint (no overreach)")

	# --- The living→carcass transition swaps coarse→precise ------------------
	# Draining the pool to 0 must flip the collider to the exact grid the moment
	# the whale dies, so a corpse mines and crushes cell by cell.
	whale.shared_health = 50.0
	whale.rebuild()  # still alive, still coarse
	_check(_shape_count(whale) == coarse_shapes, "still coarse just before death")
	whale.damage_cell(whale.blocks.keys()[0], 60.0)  # empties the pool → transition
	_check(whale.shared_health == 0.0, "the killing blow emptied the pool")
	_check(_shape_count(whale) == precise_shapes
			and _covered_cells(whale) == _solid_cells(whale),
		"on death the collider swapped coarse→precise, covering the exact grid (%d shapes)"
			% _shape_count(whale))

	# --- Vessels are never coarsened (regression) ----------------------------
	# The same body as a VESSEL (no shared pool) keeps the exact per-cell merge:
	# the coarse path is creatures-only and must not touch ship-vs-ship at all.
	var vessel := _make_ship(cells)
	vessel.position = Vector2(-30000, -12000)
	vessel.scale_unit = 8.0
	vessel.rebuild()
	_check(_shape_count(vessel) == precise_shapes
			and _covered_cells(vessel) == _solid_cells(vessel),
		"a vessel of the same shape is precise, exactly the solid grid (%d shapes)"
			% _shape_count(vessel))

	# --- Break-the-fix guard -------------------------------------------------
	# Force the LIVING whale onto the precise grid: the "fewer shapes" property
	# must VANISH — proving the coarse path is what buys it, not some accident of
	# the body plan. If this ever equals the coarse count, the fix is dead.
	var forced := _make_ship(cells)
	forced.position = Vector2(-30000, -18000)
	forced.scale_unit = 8.0
	forced.shared_health_max = 15000.0
	forced.shared_health = 15000.0
	forced.force_precise_collider = true
	forced.rebuild()
	_check(_shape_count(forced) == precise_shapes and _shape_count(forced) > coarse_shapes,
		"forced precise, a LIVING whale is back to the many-shape merge (%d, not %d)"
			% [_shape_count(forced), coarse_shapes])

	carcass.queue_free()
	whale.queue_free()
	vessel.queue_free()
	forced.queue_free()
	await process_frame


## The coarse collider is an OVER-approximation, so a living whale must still
## rest on terrain — never fall through the gap a downsample might have opened.
func _test_living_whale_rests_on_terrain_with_coarse_collider() -> void:
	_t("a living whale with a coarse collider still lands on terrain, no fall-through")
	var cells := ShipLayout.upscale_cells(
		ShipLayout.load_cells("res://ships/whale.ship"), 8)
	var whale := _make_ship(cells, false)  # gravity ON: it must be held up
	whale.scale_unit = 8.0
	whale.gravity_scale = 1.0
	whale.shared_health_max = 15000.0
	whale.shared_health = 15000.0
	whale.position = Vector2(40000, -2000)
	whale.rebuild()
	_check(_shape_count(whale) < 7, "the whale is on its coarse collider (%d shapes)"
		% _shape_count(whale))

	# A big static floor just below the whale's underside.
	var floor_top := whale.position.y + whale.solid_bounds.size.y * 0.5 + 200
	var wall := StaticBody2D.new()
	var wshape := RectangleShape2D.new()
	wshape.size = Vector2(whale.solid_bounds.size.x + 4000, 800)
	var wcs := CollisionShape2D.new()
	wcs.shape = wshape
	wall.position = Vector2(whale.position.x, floor_top + 400)
	wall.add_child(wcs)
	root.add_child(wall)

	for i in 240:
		await physics_frame
	# It should have fallen a little and STOPPED on the floor — not sailed on
	# through it. Its underside rests at floor_top, so the body sits above it.
	var underside := whale.position.y + whale.solid_bounds.size.y * 0.5
	_check(underside <= floor_top + 40.0 and whale.position.y < floor_top,
		"the whale rests on the floor, not through it (underside=%.0f, floor=%.0f)"
			% [underside, floor_top])
	_check(absf(whale.linear_velocity.y) < 120.0,
		"and it is at rest, not still tunnelling (vy=%.0f)" % whale.linear_velocity.y)

	whale.queue_free()
	wall.queue_free()
	await process_frame


func _test_creature_skin_faces_its_motion() -> void:
	_t("Q10 (reversed): a creature's skin faces its motion — the collider MIRRORS with it")
	# An ASYMMETRIC body, deliberately: a four-cell spine along +x with a
	# single fin on the -x end. Every physical claim below leans on that
	# asymmetry — after the owner's 2026-08-21 reversal a facing flip carries
	# the fin's COLLISION over to the mirrored side, so the drawn head and the
	# physical body occupy the same reflected shape (the owner accepts the
	# rider-dump risk the source's real mirror carries).
	var fin := Vector2i(0, -1)
	var fin_mirrored := Vector2i(3, -1)  # the fin's reflection about the footprint centre
	var beast := _make_ship({
		Vector2i(0, 0): BlockDB.Type.BLUBBER,
		Vector2i(1, 0): BlockDB.Type.BLUBBER,
		Vector2i(2, 0): BlockDB.Type.BLUBBER,
		Vector2i(3, 0): BlockDB.Type.BLUBBER,
		fin: BlockDB.Type.BLUBBER,
	})
	# Parked far from every other test ship, and at x≈0 so the position-delta
	# facing signal is read at full float precision.
	beast.position = Vector2(0.0, -20000.0)
	beast.faction = 2
	beast.shared_health = 100.0
	beast.shared_health_max = 100.0
	await _step(2)
	_check(beast.visual_facing == 1, "it starts in the authored form (head +x)")

	# --- Photograph the physical body in the authored form -------------------
	var keys_before: Array = beast.blocks.keys()
	keys_before.sort()
	var bounds_before: Rect2 = beast.solid_bounds
	var shapes_before := _collider_signature(beast)
	var space := beast.get_world_2d().direct_space_state
	var fin_ray := PhysicsRayQueryParameters2D.create(
		beast.to_global(beast.local_pos_of(fin) + Vector2(0.0, -Ship.CELL * 1.5)),
		beast.to_global(beast.local_pos_of(fin)), 1)
	var ghost_ray := PhysicsRayQueryParameters2D.create(
		beast.to_global(beast.local_pos_of(fin_mirrored) + Vector2(0.0, -Ship.CELL * 1.5)),
		beast.to_global(beast.local_pos_of(fin_mirrored)), 1)
	_check(not space.intersect_ray(fin_ray).is_empty(),
		"authored: a probe into the fin's cell finds solid body")
	_check(space.intersect_ray(ghost_ray).is_empty(),
		"authored: the mirrored side is empty")

	# --- Swim left: the SKIN turns AND the collider mirrors with it ----------
	beast.linear_velocity = Vector2(-400.0, 0.0)
	await _step(12)
	_check(beast.visual_facing == -1, "swimming left, the drawn body flips to face left")

	beast.linear_velocity = Vector2.ZERO
	await _step(2)

	# The authored GRID never moves — mass, walls and severing all derive from
	# it; only the DERIVED collider geometry and the drawing reflect.
	var keys_after: Array = beast.blocks.keys()
	keys_after.sort()
	_check(keys_after == keys_before, "flipped: every authored block cell is where it was")
	_check(beast.solid_bounds == bounds_before,
		"flipped: solid_bounds is untouched (%s)" % beast.solid_bounds)
	# ...but the COLLIDER now occupies the mirrored shape (the reversal).
	_check(_collider_signature(beast) != shapes_before,
		"flipped: the collision geometry mirrored — its signature changed")
	fin_ray = PhysicsRayQueryParameters2D.create(
		beast.to_global(beast.local_pos_of(fin) + Vector2(0.0, -Ship.CELL * 1.5)),
		beast.to_global(beast.local_pos_of(fin)), 1)
	ghost_ray = PhysicsRayQueryParameters2D.create(
		beast.to_global(beast.local_pos_of(fin_mirrored) + Vector2(0.0, -Ship.CELL * 1.5)),
		beast.to_global(beast.local_pos_of(fin_mirrored)), 1)
	_check(space.intersect_ray(fin_ray).is_empty(),
		"flipped: the fin's OLD cell is now empty — its collision followed the drawn head")
	_check(not space.intersect_ray(ghost_ray).is_empty(),
		"flipped: and the physics probe now HITS the fin on the mirrored (-x) side")

	# --- Drawn pitch and collider pitch AGREE (the whole point of the reversal)
	# WhaleAI's tilt sign for a left-facing DIVE is NEGATIVE (vy>0 × facing -1);
	# with the body reflected about x that tips the drawn head DOWN into the
	# dive. The mirrored collider is pitched by the SAME node rotation, so it
	# agrees: the drawn head sits BELOW the collider's tail-side fin shape.
	beast.set_pose_tilt(-Ship.POSE_MAX)
	await _step(40)  # ease the real node rotation toward the target
	var head_world := beast.to_global(beast._mirror_point(beast.local_pos_of(Vector2i(3, 0))))
	var fin_shape_world := _topmost_shape_global(beast)
	_check(beast.rotation < -0.1,
		"the pose is a real negative node rotation for a left-facing dive (%.2f rad)"
			% beast.rotation)
	_check(head_world.y > fin_shape_world.y,
		"the drawn head pitches BELOW the collider's fin — collider pitch agrees with the skin")
	beast.set_pose_tilt(0.0)
	await _step(30)

	# --- Swim right again, then hold through a drift -------------------------
	beast.linear_velocity = Vector2(400.0, 0.0)
	await _step(12)
	_check(beast.visual_facing == 1, "swimming right again, it faces right again")
	_check(_collider_signature(beast) == shapes_before,
		"and the collider UNMIRRORS back to the authored signature")

	# Hysteresis: a body barely drifting the other way must NOT flicker.
	beast.linear_velocity = Vector2(-Ship.FACING_FLIP_SPEED * 0.5, 0.0)
	await _step(30)
	_check(beast.visual_facing == 1,
		"a drift under the flip threshold (%.0f px/s) holds the last facing"
			% Ship.FACING_FLIP_SPEED)

	# --- A carcass freezes its facing forever --------------------------------
	beast.linear_velocity = Vector2(-400.0, 0.0)
	await _step(12)
	_check(beast.visual_facing == -1, "alive, a hard swim left turns it")
	beast.shared_health = 0.0  # the pool empties: it is a corpse now
	beast.linear_velocity = Vector2(600.0, 0.0)
	await _step(20)
	_check(beast.visual_facing == -1,
		"dead, it drifts the other way without turning — a corpse does not face its drift")
	beast.queue_free()

	# --- Vessels are not creatures and never mirror --------------------------
	var vessel := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.HULL,
	})
	vessel.position = Vector2(0.0, -21000.0)
	vessel.linear_velocity = Vector2(-600.0, 0.0)
	await _step(20)
	_check(vessel.visual_facing == 1,
		"a plain ship flying left is drawn exactly as authored — hulls have no facing")
	vessel.queue_free()
	await process_frame


func _test_whale_pose_tilt_follows_its_facing() -> void:
	_t("the pose tilt reads into the motion BOTH ways (sign follows the skin flip)")
	# The mirror is draw-only but the pose tilt is a REAL eased node
	# rotation, so a mirrored body needs the opposite rotation sign for its
	# nose to read as pitched into the dive. Same vertical velocity, both
	# facings, opposite targets — that is the whole contract.
	var whale := _make_ship({
		Vector2i(0, 0): BlockDB.Type.BLUBBER,
		Vector2i(1, 0): BlockDB.Type.BLUBBER,
		Vector2i(2, 0): BlockDB.Type.BLUBBER,
	})
	whale.position = Vector2(0.0, -22000.0)
	whale.faction = 2
	whale.shared_health = 100.0
	whale.shared_health_max = 100.0
	var ai := WhaleAI.new()
	ai.whale = whale
	ai.home = whale.global_position

	# Diving hard. No physics step between the two ticks, so both read the
	# identical velocity and only the facing differs.
	whale.linear_velocity = Vector2(0.0, WhaleAI.TILT_AT_SPEED * 3.0)
	await _step(1)
	whale.visual_facing = 1
	ai.tick(1.0 / 60.0, null)
	var tilt_right: float = whale._pose_tilt
	whale.visual_facing = -1
	ai.tick(1.0 / 60.0, null)
	var tilt_left: float = whale._pose_tilt
	_check(tilt_right > 0.1, "facing right, a dive pitches the nose down (%.2f rad)" % tilt_right)
	_check(tilt_left < -0.1, "facing left, the SAME dive pitches it the other way (%.2f rad)"
		% tilt_left)
	_check_approx(tilt_left, -tilt_right, 0.001,
		"the two are exact mirrors — one formula, one facing multiplier")
	whale.queue_free()
	await process_frame


func _test_ram_immunity() -> void:
	_t("a charging creature's own ram costs it nothing; bystanders still crash")
	var wall := _make_ship({
		Vector2i(0, -2): BlockDB.Type.HULL, Vector2i(0, -1): BlockDB.Type.HULL,
		Vector2i(0, 0): BlockDB.Type.HULL, Vector2i(0, 1): BlockDB.Type.HULL,
		Vector2i(0, 2): BlockDB.Type.HULL,
	})
	wall.position = Vector2(-11000, 0)
	wall.freeze = true  # an immovable obstacle that takes no damage itself

	var rammer := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.HULL,
		Vector2i(2, 0): BlockDB.Type.HULL,
	})
	rammer.position = wall.position + Vector2(-300, 0)
	# What WhaleAI now sets for the WHOLE attack — the PUSH window and the
	# ballistic GLIDE that follows it (owner 2026-08-21). The old flat
	# charge set the same field; the boundaries below are unchanged.
	rammer.ram_immunity_dir = Vector2.RIGHT
	rammer.linear_velocity = Vector2(2000, 0)
	await _step(30)
	_check(is_instance_valid(rammer) and rammer.blocks.size() == 3,
		"head-on at ramming speed, the charger keeps every block")

	# Control: the same crash WITHOUT the charge immunity bites hard. This
	# is the "clumsy non-attack crash" boundary — roaming and aligning
	# whales carry no immunity, so their bumps still cost them.
	var faller := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.HULL,
		Vector2i(2, 0): BlockDB.Type.HULL,
	})
	faller.position = wall.position + Vector2(-300, 40)
	faller.linear_velocity = Vector2(2000, 0)
	await _step(30)
	_check(not is_instance_valid(faller) or faller.blocks.size() < 3,
		"the same crash without immunity crunches blocks")

	if is_instance_valid(rammer):
		rammer.queue_free()
	if is_instance_valid(faller):
		faller.queue_free()
	wall.queue_free()

	# Boundary: immunity is the CHARGER's alone. The victim pays the full
	# ram — it is the whole point of the attack, so pin it rather than
	# trusting that "skip the charger's impacts" only skips the charger's.
	var victim_cells := {}
	for x in 5:
		for y in 8:
			victim_cells[Vector2i(x, y - 4)] = BlockDB.Type.HULL
	var victim := _make_ship(victim_cells)
	victim.position = Vector2(-11000, 900)
	var victim_blocks := victim.blocks.size()
	var charger := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.HULL,
		Vector2i(2, 0): BlockDB.Type.HULL,
	})
	charger.position = victim.position + Vector2(-300, 0)
	charger.ram_immunity_dir = Vector2.RIGHT
	charger.linear_velocity = Vector2(2000, 0)
	await _step(30)
	_check(is_instance_valid(victim) and victim.blocks.size() < victim_blocks,
		"the VICTIM of an immune ram still takes the full crunch (%d of %d left)"
			% [victim.blocks.size() if is_instance_valid(victim) else 0,
				victim_blocks])
	_check(is_instance_valid(charger) and charger.blocks.size() == 3,
		"while the charger that hit it is still whole")
	if is_instance_valid(charger):
		charger.queue_free()
	if is_instance_valid(victim):
		victim.queue_free()

	# Boundary: BULLETS are unaffected by ram immunity (owner spec). It
	# filters CONTACTS; shots damage through the shot path, so a charging
	# whale is still shootable mid-shove.
	var shootable := _make_ship({
		Vector2i(0, 0): BlockDB.Type.BLUBBER,
		Vector2i(0, -1): BlockDB.Type.BLUBBER,
	})
	shootable.position = Vector2(-11000, 1600)
	shootable.faction = 2
	shootable.shared_health = 500.0
	shootable.shared_health_max = 500.0
	shootable.ram_immunity_dir = Vector2.RIGHT  # mid-attack, either phase
	await _step(2)
	var slug := Shot.new()
	slug.position = shootable.position + Vector2(-300, 0)
	slug.velocity = Vector2(2000, 0)
	slug.gravity = 0.0
	slug.faction = 0
	slug.damage = 40.0
	root.add_child(slug)
	await _step(20)
	_check(shootable.shared_health < 500.0,
		"bullets still hurt a charging whale (pool %.0f of 500)"
			% shootable.shared_health)
	if is_instance_valid(slug):
		slug.queue_free()
	shootable.queue_free()
	await process_frame


## Owner 2026-08-24: "they should target whatever tried to attack it — if I
## (player) am outside my ship and shoot a whale, the whale will go for the ship
## (???)". The provoked whale used to ram the CALLER-chosen nearest player-side
## ship, always. Now provoke() latches the attacker (stamped by Shot onto
## Ship.last_attacker_id → the world's damaged wiring) and the brain retaliates
## against THAT — a ship or the on-foot player alike; the caller's target is only
## the fallback for unattributed damage.
func _test_provoked_whale_rams_its_attacker() -> void:
	_t("a provoked whale retaliates against its ATTACKER, not the nearest ship")
	var whale := _make_ship(ShipLayout.load_cells("res://ships/whale.ship"))
	whale.faction = 2
	whale.position = Vector2(-16000, 0)
	# The decoy: a player-side ship parked LEVEL and to the RIGHT — exactly what
	# the old doctrine would charge (the fallback target the world still passes).
	var decoy := _make_ship({Vector2i(0, 0): BlockDB.Type.HULL})
	decoy.freeze = true
	decoy.position = whale.position + Vector2(900, 0)
	# The attacker: the on-foot "player" — a bare Node2D (all the brain may
	# assume about a retaliation target) standing level on the LEFT.
	var attacker := Node2D.new()
	root.add_child(attacker)
	attacker.global_position = whale.position + Vector2(-900, 0)
	await _step(2)

	var ai := WhaleAI.new()
	ai.whale = whale
	ai.home = whale.global_position

	# Shot from the left: the whale is told WHO hit it.
	ai.provoke(attacker)
	ai.tick(1.0 / 60.0, decoy)
	_check(ai.phase() == WhaleAI.Phase.PUSH,
		"level with its attacker, it commits to the shove at once")
	var d: float = ai._push_dir.x
	_check(d < 0.0,
		"and the shove aims at the ATTACKER (left, %.0f) — not the decoy ship (right)" % d)

	# The attacker latch survives an unattributed re-provoke (a terrain bump
	# must not make it forget who shot it)...
	ai.provoke()
	_check(ai._attacker() == attacker, "an unattributed re-provoke keeps the attacker latched")
	# ...and clears when the attacker is gone: freed mid-anger, the brain falls
	# back to the caller's nearest-ship target instead of chasing a ghost.
	attacker.queue_free()
	await process_frame
	_check(ai._attacker() == null, "a freed attacker is forgotten (no dangling ram target)")
	ai._end_attack()
	ai.tick(1.0 / 60.0, decoy)
	_check(ai.phase() == WhaleAI.Phase.PUSH and ai._push_dir.x > 0.0,
		"with the attacker gone it falls back to the fallback ship (break-the-fix: the old doctrine)")

	# Taming forgives: the latch is wiped with the anger.
	ai.provoke(decoy)
	ai.tame()
	_check(ai._attacker() == null, "taming clears the grudge along with the anger")

	whale.queue_free()
	decoy.queue_free()
	await process_frame


func _test_whale_ai_neutral_until_provoked() -> void:
	_t("whale AI: neutral roamer, rams when hurt, drifts as carcass")
	var whale := _make_ship(ShipLayout.load_cells("res://ships/whale.ship"))
	whale.faction = 2
	whale.position = Vector2(-6400, 0)
	var target := _make_ship({Vector2i(0, 0): BlockDB.Type.HULL})
	# Frozen: the test teleports the target between phases, and an ACTIVE
	# RigidBody2D's transform belongs to the physics server — a mid-test
	# `position =` set can be overridden by the server's next sync (seen:
	# the align phase read the stale, level offset and charged flat).
	target.freeze = true
	target.position = whale.position + Vector2(1200, 0)
	await _step(2)

	var ai := WhaleAI.new()
	ai.whale = whale
	ai.home = whale.global_position

	# Neutral: a target nearby is not a provocation.
	for i in 60:
		ai.tick(1.0 / 60.0, target)
		await physics_frame
	_check(whale.linear_velocity.x < 20.0,
		"unprovoked, it ignores the ship beside it (vx=%.1f)" % whale.linear_velocity.x)
	_check(whale.ram_immunity_dir == Vector2.ZERO,
		"and a roaming whale carries no ram immunity")

	# Hurt it, and it attacks — BROADSIDE (owner, from the original):
	# a target far above gets an alignment climb, not a diagonal lunge.
	ai.provoke()
	target.position = whale.position + Vector2(900.0, -800.0)
	for i in 60:
		ai.tick(1.0 / 60.0, target)
		await physics_frame
	_check(whale.linear_velocity.y < -20.0,
		"provoked from above, it first climbs to ALIGN (vy=%.1f)"
			% whale.linear_velocity.y)
	_check(absf(whale.linear_velocity.x) < absf(whale.linear_velocity.y),
		"the approach is mostly vertical, not a diagonal ram")
	_check(whale.ram_immunity_dir == Vector2.ZERO,
		"aligning is manoeuvring, not attacking — no immunity yet")

	# Level with its prey, the attack is a blunt SHOVE (owner 2026-08-21:
	# "a blunt PUSH, as opposed to a constant locomotive"): one heavy
	# horizontal force for PUSH_SECONDS, then nothing at all.
	#
	# REPLACES the old flat-charge assertion `vx > 200` ("aligned, it rams
	# flat and HARD"), which pinned a CONSTANT CHARGE_ACCEL that no longer
	# exists. Its intent — the ram must stay scary — survives below as the
	# PUSH_PEAK_FLOOR check, whose floor is 3.5× the old one because the
	# shove now buys in one second what the locomotive took seconds to
	# wind up to.
	whale.linear_velocity = Vector2.ZERO
	# Parked far enough away that the shove cannot actually reach it: this
	# stretch is about the push/glide SHAPE, and a mid-test crunch would
	# resolve the attack early.
	target.position = whale.position + Vector2(9000.0, 0.0)
	# One frame past the window: PUSH_SECONDS / delta lands exactly on the
	# boundary, and float accumulation can leave it a hair short.
	for i in int(WhaleAI.PUSH_SECONDS * 60.0) + 1:
		ai.tick(1.0 / 60.0, target)
		await physics_frame
	var peak := whale.linear_velocity.x
	_check(peak > WhaleAI.PUSH_PEAK_FLOOR,
		"the %.1fs shove alone reaches ram speed (vx=%.0f, floor %.0f)"
			% [WhaleAI.PUSH_SECONDS, peak, WhaleAI.PUSH_PEAK_FLOOR])
	_check(absf(whale.linear_velocity.y) < 8.0,
		"and the shove is sideways-only (vy=%.1f)" % whale.linear_velocity.y)
	_check(ai.phase() == WhaleAI.Phase.GLIDE,
		"the push window closes into a ballistic glide")
	_check(whale.ram_immunity_dir.x > 0.0,
		"immunity rides the glide too — the crunch usually lands there")

	# THE LOCOMOTIVE IS GONE. Another second of ticks adds no speed: pure
	# drag (linear_damp 0.4) leaves e^-0.4 = 67% of the peak, and any
	# self-propulsion at all would show up as more than that.
	for i in 60:
		ai.tick(1.0 / 60.0, target)
		await physics_frame
	_check(whale.linear_velocity.x < peak * 0.75,
		"past the window it propels itself NOT AT ALL — it coasts, drag bites (%.0f → %.0f px/s)"
			% [peak, whale.linear_velocity.x])
	_check(whale.ram_immunity_dir.x > 0.0,
		"and it is still riding the same attack")

	# Crunch: the impact kills the speed, so the attack resolves — and,
	# still angry, it lines up and shoves AGAIN. PUSH … glide … crunch …
	# re-align … PUSH.
	whale.linear_velocity = Vector2.ZERO
	ai.tick(1.0 / 60.0, target)
	await physics_frame
	_check(ai.phase() == WhaleAI.Phase.NONE,
		"a crunch that kills the speed resolves the attack")
	for i in 30:
		ai.tick(1.0 / 60.0, target)
		await physics_frame
	_check(ai.phase() == WhaleAI.Phase.PUSH and whale.linear_velocity.x > 50.0,
		"and while the anger lasts it shoves again (vx=%.0f)"
			% whale.linear_velocity.x)

	# A shove that hits NOTHING still has to end, or a miss sails off the
	# map wearing its ram immunity. Let this one run to its own timeout.
	var resolve_frames := 0
	while ai.phase() != WhaleAI.Phase.NONE and resolve_frames < 600:
		ai.tick(1.0 / 60.0, target)
		await physics_frame
		resolve_frames += 1
	_check(resolve_frames < 600,
		"a shove that connects with nothing times out anyway (%.1fs)"
			% (resolve_frames / 60.0))

	# It pitches into its motion — POSE, not physics (owner-approved,
	# ~30° like the source): still provoked with prey far below, the
	# dive tips the nose down while the solver lock holds. With the attack
	# resolved this is the ALIGN phase again, so the immunity is off.
	whale.linear_velocity = Vector2.ZERO
	target.position = whale.position + Vector2(900.0, 800.0)
	for i in 90:
		ai.tick(1.0 / 60.0, target)
		await physics_frame
	_check(whale.rotation > 0.1 and whale.rotation <= Ship.POSE_MAX + 0.01,
		"diving, the nose pitches down within the source's range (%.2f rad)"
			% whale.rotation)
	_check(whale.lock_rotation and absf(whale.angular_velocity) < 0.001,
		"the pose is kinematic — the solver still cannot spin it")
	_check(whale.ram_immunity_dir == Vector2.ZERO,
		"and manoeuvring between shoves carries no immunity")

	# A ship that INHERITS a tilt (severed chunk of a pitched whale)
	# eases back to level on its own: the pose target defaults to zero.
	var chunk := _make_ship({Vector2i(0, 0): BlockDB.Type.BLUBBER})
	chunk.position = Vector2(-8000, 0)
	chunk.rotation = 0.4
	await _step(90)
	_check(absf(chunk.rotation) < 0.02,
		"an inherited tilt settles flat by itself (%.3f rad)" % chunk.rotation)
	chunk.queue_free()

	# Kill the whale UNIT (the shared pool) and it stops swimming.
	whale.shared_health = 50.0
	whale.shared_health_max = 50.0
	whale.damage_cell(whale.blocks.keys()[0], 60.0)
	_check(whale.shared_health == 0.0, "the whale unit is dead")
	whale.linear_velocity = Vector2.ZERO
	for i in 30:
		ai.tick(1.0 / 60.0, target)
		await physics_frame
	_check(whale.linear_velocity.length() < 1.0,
		"a carcass swims nowhere (v=%.1f)" % whale.linear_velocity.length())

	whale.queue_free()
	target.queue_free()
	await process_frame


func _test_provoked_whale_never_endlessly_charges_down() -> void:
	_t("a provoked whale converts a stuck vertical drive into a broadside — it does not charge down forever")
	# The owner's 2026-08-22 bug: provoked, the whale "charges toward whatever
	# attacked it but won't stop charging vertically — it'll endlessly push
	# one down." Root cause (whale_ai.gd tick): the align drove mostly-
	# vertically toward the target's altitude every tick, and when the target
	# itself was in the way (whale directly above it) it could never get level,
	# so it never transitioned to the sideways PUSH — it drove down forever.

	# --- Scenario 1: BLOCKED from the prey → the align TIMEOUT saves it. ----
	# The whale drives down toward its attacker, but a frozen mass in the way
	# pins it short: it can neither get level nor touch the prey. On the old
	# code that is the endless vertical charge. The align timeout must convert
	# it to a broadside regardless. THIS is the check that fails on the old
	# code and after reverting the timeout (break-the-fix).
	var whale := _make_ship({
		Vector2i(-1, 0): BlockDB.Type.BLUBBER,
		Vector2i(0, 0): BlockDB.Type.BLUBBER,
		Vector2i(1, 0): BlockDB.Type.BLUBBER,
	})
	whale.faction = 2
	whale.position = Vector2(0.0, -1000.0)
	whale.shared_health = 100.0
	whale.shared_health_max = 100.0
	# A frozen plate just below the whale: it can rest ON this but never sink
	# through it to reach the prey below.
	var blocker := _make_ship({
		Vector2i(-2, 0): BlockDB.Type.HULL, Vector2i(-1, 0): BlockDB.Type.HULL,
		Vector2i(0, 0): BlockDB.Type.HULL, Vector2i(1, 0): BlockDB.Type.HULL,
		Vector2i(2, 0): BlockDB.Type.HULL,
	})
	blocker.freeze = true
	blocker.position = Vector2(0.0, -800.0)
	# The attacker, frozen far below the blocker — the altitude the whale is
	# forever trying (and failing) to reach. Never touched.
	var prey := _make_ship({Vector2i(0, 0): BlockDB.Type.HULL})
	prey.freeze = true
	prey.position = Vector2(0.0, 600.0)
	await _step(2)

	var ai := WhaleAI.new()
	ai.whale = whale
	ai.home = whale.global_position

	# Drive it for 1.5 s — LESS than ALIGN_MAX_SECONDS. It should still be
	# aligning (neither level nor touching the prey), where the old code
	# stayed forever.
	for i in 90:
		ai.provoke()  # stay angry for the whole run
		ai.tick(1.0 / 60.0, prey)
		await physics_frame
	var to_prey_y: float = absf(prey.global_position.y - whale.global_position.y)
	_check(ai.phase() == WhaleAI.Phase.NONE,
		"below the align timeout it is still aligning (phase NONE)")
	_check(to_prey_y > WhaleAI.ALIGN_BAND,
		"and it never got level with the prey (%.0f px off, band %.0f)"
			% [to_prey_y, WhaleAI.ALIGN_BAND])
	_check(not whale.get_colliding_bodies().has(prey),
		"nor did it ever touch the prey — only the timeout can end this align")

	# Past ALIGN_MAX_SECONDS it MUST have committed to the broadside instead
	# of charging down forever.
	for i in 90:  # on to ~3 s total
		ai.provoke()
		ai.tick(1.0 / 60.0, prey)
		await physics_frame
	_check(ai.phase() != WhaleAI.Phase.NONE,
		"past the %.1fs align timeout it commits to a broadside, not an endless dive"
			% WhaleAI.ALIGN_MAX_SECONDS)
	_check(absf(whale.linear_velocity.x) > 50.0
			and absf(whale.linear_velocity.x) > absf(whale.linear_velocity.y),
		"and the committed ram is sideways, not a downward drive (vx=%.0f, vy=%.0f)"
			% [whale.linear_velocity.x, whale.linear_velocity.y])
	whale.queue_free()
	blocker.queue_free()
	prey.queue_free()
	await _step(3)

	# --- Scenario 2: RIGHT ON the prey → contact commits at once. ----------
	# When the whale already TOUCHES the attacker but is still off the
	# broadside band, it is close enough to ram now; it must not idle away the
	# whole align timeout. A tall prey pillar whose reference point (cell 0,0,
	# where the AI measures the band) sits at its FOOT: the whale drives down
	# onto the far TOP of the pillar, so it makes contact while still hundreds
	# of px off the band — the only thing that can end this align early is the
	# touch, never a "level".
	var whale2 := _make_ship({
		Vector2i(-1, 0): BlockDB.Type.BLUBBER,
		Vector2i(0, 0): BlockDB.Type.BLUBBER,
		Vector2i(1, 0): BlockDB.Type.BLUBBER,
	})
	whale2.faction = 2
	whale2.shared_health = 100.0
	whale2.shared_health_max = 100.0
	var tall := {}
	for y in 40:
		tall[Vector2i(0, -y)] = BlockDB.Type.HULL  # foot at cell (0,0), rising up
	var prey2 := _make_ship(tall)
	prey2.freeze = true
	prey2.position = Vector2(20000.0, 0.0)  # its foot; the top is ~624 px above
	whale2.position = prey2.position + Vector2(0.0, -700.0)  # above the far top
	await _step(2)

	var ai2 := WhaleAI.new()
	ai2.whale = whale2
	ai2.home = whale2.global_position

	# Classify the commit by the state on the tick it fires: a touch (off-band
	# but colliding) vs a level (in-band) vs the timeout backstop.
	var commit_kind := "none"
	var committed_frame := -1
	for i in 130:
		ai2.provoke()
		var to_y: float = absf(prey2.global_position.y - whale2.global_position.y)
		var touching: bool = whale2.get_colliding_bodies().has(prey2)
		var off_band: bool = to_y > WhaleAI.ALIGN_BAND
		var was_none: bool = ai2.phase() == WhaleAI.Phase.NONE
		ai2.tick(1.0 / 60.0, prey2)
		await physics_frame
		if was_none and ai2.phase() != WhaleAI.Phase.NONE and committed_frame < 0:
			committed_frame = i
			commit_kind = "band" if not off_band \
				else ("touch" if touching else "timeout")
	_check(commit_kind == "touch" and committed_frame < 120,
		"driven onto the prey, the TOUCH commits the ram before the timeout (%s at frame %d)"
			% [commit_kind, committed_frame])
	whale2.queue_free()
	prey2.queue_free()
	await _step(3)


func _test_provoked_whale_align_still_rams_when_reachable() -> void:
	_t("the align timeout leaves the normal broadside intact: reachable prey is aligned-then-rammed, in-band prey is rammed at once")
	# Regression guard for the align-timeout fix: a REACHABLE prey offset in
	# altitude must still climb-to-align and ram inside the timeout (open air,
	# nothing in the way), exactly as before.
	var whale := _make_ship({
		Vector2i(-1, 0): BlockDB.Type.BLUBBER,
		Vector2i(0, 0): BlockDB.Type.BLUBBER,
		Vector2i(1, 0): BlockDB.Type.BLUBBER,
	})
	whale.faction = 2
	whale.position = Vector2(0.0, 0.0)
	whale.shared_health = 100.0
	whale.shared_health_max = 100.0
	var prey := _make_ship({Vector2i(0, 0): BlockDB.Type.HULL})
	prey.freeze = true
	prey.position = Vector2(1500.0, -200.0)  # up and to the side, reachable
	await _step(2)

	var ai := WhaleAI.new()
	ai.whale = whale
	ai.home = whale.global_position
	ai.provoke()

	# It climbs (aligns) first — mostly vertical, no immunity yet.
	for i in 20:
		ai.tick(1.0 / 60.0, prey)
		await physics_frame
	_check(whale.linear_velocity.y < -20.0 and ai.phase() == WhaleAI.Phase.NONE,
		"reachable prey above: it climbs to align first (vy=%.0f)" % whale.linear_velocity.y)
	_check(whale.ram_immunity_dir == Vector2.ZERO, "aligning carries no immunity")

	# It reaches the band and rams WELL within the timeout — this is the
	# normal path, not the timeout backstop.
	var reached := -1
	for i in 90:  # 20+90 = 110 frames < 120 (the timeout)
		ai.tick(1.0 / 60.0, prey)
		if ai.phase() != WhaleAI.Phase.NONE and reached < 0:
			reached = i
		await physics_frame
	_check(reached >= 0,
		"and reaches the broadside inside the align timeout, as before (frame %d of 90)" % reached)
	whale.queue_free()
	prey.queue_free()
	await _step(3)

	# In-band prey: already level, so the very first tick rams — no delay.
	var whale2 := _make_ship({
		Vector2i(-1, 0): BlockDB.Type.BLUBBER,
		Vector2i(0, 0): BlockDB.Type.BLUBBER,
		Vector2i(1, 0): BlockDB.Type.BLUBBER,
	})
	whale2.faction = 2
	whale2.position = Vector2(10000.0, 0.0)
	whale2.shared_health = 100.0
	whale2.shared_health_max = 100.0
	var prey2 := _make_ship({Vector2i(0, 0): BlockDB.Type.HULL})
	prey2.freeze = true
	prey2.position = whale2.position + Vector2(3000.0, 0.0)  # level, off to the side
	await _step(2)
	var ai2 := WhaleAI.new()
	ai2.whale = whale2
	ai2.home = whale2.global_position
	ai2.provoke()
	ai2.tick(1.0 / 60.0, prey2)
	await physics_frame
	_check(ai2.phase() == WhaleAI.Phase.PUSH,
		"in-band prey is rammed immediately — no align delay")
	_check(whale2.ram_immunity_dir.x != 0.0,
		"and the shove carries ram immunity from the first frame")
	whale2.queue_free()
	prey2.queue_free()
	await _step(3)


## WHALE VARIETY (Sprint 4 whale-variant spawning). The spawner picks from the
## five authored body plans with weights, so a pod reads as different creatures;
## every plan it can return is a valid, gated whale, each with a variety tint,
## and the ghost-whale roll still fires on its seed.
func _test_whale_spawn_picks_varied_plans() -> void:
	_t("the whale spawner picks a VARIED pod — each a valid whale, ghost roll intact")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260822
	var seen := {}
	for i in 300:
		seen[WhaleSpawn.pick_plan(rng)] = true
	_check(seen.size() > 1,
		"the weighted pick covers more than one body plan across rolls (%d of %d)"
			% [seen.size(), WhaleSpawn.PLANS.size()])
	# Every plan the picker can return is a real, gated whale body — and carries
	# a distinct cosmetic tint so the pod's variety is visible beyond silhouette.
	for entry in WhaleSpawn.PLANS:
		var path: String = entry["path"]
		var short := path.get_file().get_basename()
		var cells := ShipLayout.load_cells(path)
		_check(not cells.is_empty(), "%s loads" % short)
		var s := _make_ship(cells)
		s.position = Vector2(-42000, 0)
		_check(s._connected_islands().size() == 1 and s.lift_ratio() > 1.0,
			"%s is one connected, floating body" % short)
		_check(WhaleSpawn.tint_for(path) != Color.WHITE, "%s has a variety tint" % short)
		s.queue_free()
	# The ghost easter egg is independent of the natural tint — its seed still rolls.
	_check(EasterEggs.is_ghost_whale(EasterEggs.GHOST_WHALE_RESIDUE),
		"the ghost-whale (Pale Wanderer) roll still fires on its seed")
	await _step(2)


## TAMING + RIDING (Sprint 5 payoff, WhaleAI side). A tamed whale ignores
## provocation and never rams; when mounted, the rider's steer vector drives the
## swim force directly (not the roam/ram AI); dismounting returns it to roam.
func _test_tamed_and_ridden_whale() -> void:
	_t("a tamed whale won't ram and obeys the rider's steer; dismount returns to roam")
	var whale := _make_ship(ShipLayout.load_cells("res://ships/whale.ship"))
	whale.faction = 2
	whale.position = Vector2(52000, 0)
	whale.shared_health = 100.0
	whale.shared_health_max = 100.0
	var target := _make_ship(_starter_ship())
	target.position = whale.position + Vector2(2500, 0)  # something it could ram
	var ai := WhaleAI.new()
	ai.whale = whale
	ai.home = whale.global_position

	# TAME: provocation is now ignored and no ram phase is ever built.
	ai.tame()
	ai.provoke()
	whale.linear_velocity = Vector2.ZERO
	for i in 40:
		ai.tick(1.0 / 60.0, target)
		await physics_frame
	_check(ai.tamed and ai.phase() == WhaleAI.Phase.NONE,
		"tamed: no ram phase even after being provoked")
	_check(whale.ram_immunity_dir == Vector2.ZERO, "a tamed whale carries no ram immunity")
	_check(absf(whale.global_position.x - ai.home.x) < 3000.0,
		"it roams near home instead of charging the ship (dx=%.0f)"
			% (whale.global_position.x - ai.home.x))

	# MOUNT + steer RIGHT: the swim force pushes it +x, not the roam target.
	ai.mount()
	whale.linear_velocity = Vector2.ZERO
	ai.steer = Vector2(1.0, 0.0)
	for i in 40:
		ai.tick(1.0 / 60.0, null)
		await physics_frame
	_check(ai.ridden and whale.linear_velocity.x > 100.0,
		"mounted + steer right: rider input drives it +x (vx=%.0f)" % whale.linear_velocity.x)

	# Steer UP: input drives it screen-up (−y), proving both axes obey the rider.
	whale.linear_velocity = Vector2.ZERO
	ai.steer = Vector2(0.0, -1.0)
	for i in 40:
		ai.tick(1.0 / 60.0, null)
		await physics_frame
	_check(whale.linear_velocity.y < -100.0,
		"steer up drives it up (vy=%.0f)" % whale.linear_velocity.y)

	# DISMOUNT: back to a calm allied roam — no more rider force.
	ai.dismount()
	_check(not ai.ridden and ai.steer == Vector2.ZERO, "dismount clears the ride")
	whale.linear_velocity = Vector2.ZERO
	whale.global_position = ai.home  # start at home so roam has nowhere to rush
	for i in 30:
		ai.tick(1.0 / 60.0, null)
		await physics_frame
	_check(ai.tamed and whale.linear_velocity.length() < 400.0,
		"a dismounted whale drifts home, it does not keep riding (v=%.0f)"
			% whale.linear_velocity.length())

	whale.queue_free()
	target.queue_free()
	await _step(3)


## Owner 2026-08-23: "whales sink automatically when being ridden... could their
## AI keep them level?" A ridden whale now TREADS WATER — when the rider is not
## driving vertically the AI cancels the unsupported weight and damps drift, so a
## whale tamed high in thin air holds its band instead of sinking. Contrasted with
## a free-falling twin so the hold is measured, not assumed.
func _test_ridden_whale_treads_water() -> void:
	_t("a ridden whale treads water instead of sinking out of thin air")
	var cells := {}
	for x in 6:
		cells[Vector2i(x, 0)] = BlockDB.Type.HULL  # heavy, no lift -> it WOULD sink
	var faller := _make_ship(cells, false)         # a free-falling control twin
	faller.position = Vector2(0, -6000)
	var whale := _make_ship(cells, false)
	whale.position = Vector2(3000, -6000)
	whale.shared_health = 100.0
	whale.shared_health_max = 100.0
	var ai := WhaleAI.new()
	ai.whale = whale
	ai.home = whale.global_position
	ai.tame()
	ai.mount()
	ai.steer = Vector2.ZERO  # rider coasting: the hold takes the vertical axis
	_check(whale.unsupported_weight() > 0.0,
		"the scenario is a genuine sink case (unsupported=%.0f)" % whale.unsupported_weight())
	var wy0 := whale.global_position.y
	var fy0 := faller.global_position.y
	for i in 90:
		ai.tick(1.0 / 60.0, null)
		await physics_frame
	var whale_drop := whale.global_position.y - wy0
	var faller_drop := faller.global_position.y - fy0
	_check(faller_drop > 200.0, "the control twin falls freely (%.0f px)" % faller_drop)
	_check(whale_drop < faller_drop * 0.4,
		"the ridden whale holds its altitude far better (%.0f vs %.0f px dropped)"
			% [whale_drop, faller_drop])
	whale.queue_free()
	faller.queue_free()
	await process_frame


## The kraken body-plan GATE (owner 2026-08-23, the design-jam rework): the two
## adopted krakens are SHELL casing SURROUNDING a MEAT interior, with only a LITTLE
## exposed meat as the weak spot. This pins the anatomy so a future edit can't
## quietly turn a kraken back into a meat-bodied blob or a floating whale.
##   * SHELL + MEAT only (no blubber — krakens carry none);
##   * one connected body;
##   * a small exposed-meat WEAK SPOT exists, but the shell is the majority of the
##     exterior skin (the casing hides the meat) — NOT a meat exterior;
##   * survives a full vertical cut (the wall model — combat can't sever, only
##     mining, exactly like whales);
##   * NO float requirement (krakens are held aloft by AI, not fat).
func _test_kraken_is_a_kraken() -> void:
	for path in ["res://ships/kraken_b.ship", "res://ships/kraken_c.ship"]:
		await _check_kraken_body_plan(path)


func _check_kraken_body_plan(path: String) -> void:
	var kname := path.get_file().get_basename()
	_t("%s: shell-cased, meat inside, a tiny exposed-meat weak spot, survives a cut" % kname)
	var cells := ShipLayout.load_cells(path)
	var s := _make_ship(cells)
	s.position = Vector2(-42000, 0)

	# Shell + meat only — no blubber, no vessel parts.
	var shell := 0
	var meat := 0
	var other := 0
	for cell in cells:
		match cells[cell]:
			BlockDB.Type.SHELL: shell += 1
			BlockDB.Type.MEAT: meat += 1
			_: other += 1
	_check(other == 0 and shell > 0 and meat > 0,
		"shell + meat only (shell %d, meat %d, other %d)" % [shell, meat, other])
	_check(s._connected_islands().size() == 1, "one connected body")

	# The WEAK SPOT: some meat is reachable from outside (the mouth / tentacle
	# roots), but the shell is the majority of the EXTERIOR skin — the casing hides
	# the bulk of the meat. Flood empty space from outside the body, then classify
	# each cell whose face touches that exterior air.
	var exterior := _exterior_air_cells(cells)
	var exposed_meat := 0
	var exposed_shell := 0
	for cell in cells:
		var on_surface := false
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if exterior.has(cell + d):
				on_surface = true
				break
		if not on_surface:
			continue
		if cells[cell] == BlockDB.Type.MEAT:
			exposed_meat += 1
		elif cells[cell] == BlockDB.Type.SHELL:
			exposed_shell += 1
	_check(exposed_meat > 0, "a meat weak spot IS exposed (%d tiles)" % exposed_meat)
	_check(exposed_shell > exposed_meat,
		"but the shell is the majority of the exterior skin (shell %d > meat %d exposed)"
			% [exposed_shell, exposed_meat])

	# Survives a full vertical cut — the flesh walls hold (combat never severs a
	# creature; only mining does). Cut the DENSEST column so the pin survives any
	# owner redesign of the silhouette.
	var pieces: Array = []
	s.severed.connect(func(p: Ship) -> void: pieces.append(p))
	var columns := {}
	for cell in s.blocks:
		columns[cell.x] = columns.get(cell.x, 0) + 1
	var cut_x: int = 0
	var best_n := 0
	for x in columns:
		if columns[x] > best_n:
			best_n = columns[x]
			cut_x = x
	for cell in s.blocks.keys():
		if cell.x == cut_x and s.blocks.has(cell):
			s.damage_cell(cell, 9999.0, false)
	s.rebuild()
	_check(pieces.is_empty() and s._connected_islands().size() == 1,
		"a channel cut clean through does not sever — the flesh walls hold")

	# NO float requirement: a kraken carries no lift and is held aloft by AI. Just
	# assert it isn't secretly floating on blubber (which would mean it wasn't
	# reworked to shell+meat).
	_check(s.lift_ratio() == 0.0, "carries no lift of its own (held aloft by AI)")

	s.queue_free()
	for p in pieces:
		if is_instance_valid(p):
			p.queue_free()
	await process_frame


## Empty cells that reach the OUTSIDE (flood from a border ring), so an enclosed
## loot cavity's air is excluded — used to find the true exterior skin.
func _exterior_air_cells(cells: Dictionary) -> Dictionary:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	lo -= Vector2i.ONE
	hi += Vector2i.ONE
	var seen := {}
	var stack: Array[Vector2i] = [lo]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		if seen.has(c) or cells.has(c):
			continue
		if c.x < lo.x or c.y < lo.y or c.x > hi.x or c.y > hi.y:
			continue
		seen[c] = true
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			stack.append(c + d)
	return seen


## The KrakenAI (owner build order item 1): the two-ended brain. It HUNTS on sight
## (aggressive, unlike the whale that waits to be hit), its MOUTH does continuous
## grab damage when it reaches the prey, and — via the WhaleAI hover exception (item
## 2) — a WILD lift-less kraken TREADS WATER instead of sinking.
func _test_kraken_ai_grabs_hovers_and_rams() -> void:
	_t("a kraken hunts on sight, its mouth grabs continuously, and it hovers (no lift)")
	var cells := ShipLayout.upscale_cells(ShipLayout.load_cells("res://ships/kraken_c.ship"), 8)
	var kraken := _make_ship(cells)
	kraken.scale_unit = 8.0
	kraken.gravity_scale = 8.0
	kraken.creature_kind = "kraken"
	kraken.shared_health = 12000.0
	kraken.shared_health_max = 12000.0
	kraken.position = Vector2(-70000, 0)

	var ai := KrakenAI.new()
	ai.whale = kraken
	ai.home = kraken.global_position

	# HOVER (item 2): a wild kraken carries no lift, so it WOULD sink — but the
	# hover exception holds it. Contrast with a free-falling hull twin.
	_check(kraken.unsupported_weight() > 0.0,
		"a kraken genuinely has no buoyancy (unsupported=%.0f)" % kraken.unsupported_weight())
	var faller := _make_ship(cells, false)
	faller.scale_unit = 8.0
	faller.gravity_scale = 8.0
	faller.position = kraken.position + Vector2(6000, 0)
	var ky0 := kraken.global_position.y
	var fy0 := faller.global_position.y
	for i in 90:
		ai.tick(1.0 / 60.0, null)  # no prey: it roams + hovers
		await physics_frame
	var kdrop := kraken.global_position.y - ky0
	var fdrop := faller.global_position.y - fy0
	_check(fdrop > 400.0, "the lift-less control twin falls freely (%.0f px)" % fdrop)
	_check(kdrop < fdrop * 0.4,
		"the wild kraken hovers, holding the deep (%.0f vs %.0f px dropped)" % [kdrop, fdrop])

	# --- THE HUNT MUST NOT FALL EITHER (owner 2026-08-25: "they just fall
	# endlessly when I spawn them"). A kraken restamps its own provocation
	# every tick, so a spawned one lives almost entirely in the ram loop —
	# whose PUSH and GLIDE phases used to apply no vertical support at all.
	# Fine for a buoyant whale (net gravity ~0 during the coast), free-fall
	# for a lift-less kraken; the unified swim bladder now spans every living
	# phase. Prey far to the SIDE and frozen, so the brain cycles
	# align→push→glide continuously while the altitude is watched.
	var lure := _make_ship(_starter_ship())
	lure.faction = 0
	lure.scale_unit = 8.0
	lure.position = kraken.global_position + Vector2(60000, 0)
	lure.freeze = true
	var hy0 := kraken.global_position.y
	for i in 180:
		ai.tick(1.0 / 60.0, lure)
		await physics_frame
	var hunt_drop := kraken.global_position.y - hy0
	_check(absf(hunt_drop) < 3000.0,
		"a HUNTING kraken holds its band through push and glide (drifted %.0f px; free fall would be ~35k)"
			% hunt_drop)
	lure.queue_free()

	# MOUTH GRAB + AGGRESSION: place a prey ship right at the kraken's mouth. The
	# kraken is never provoked by hand — it must hunt on sight and chew. Freeze both
	# so the ram physics doesn't drift the jaws off the prey mid-measure; the grab
	# is damage the brain applies, not a collision, so freezing does not mask it.
	kraken.freeze = true
	var mouth := ai._mouth_world()
	var prey := _make_ship(_starter_ship())
	prey.faction = 0
	prey.scale_unit = 8.0
	prey.position = mouth  # sitting in the jaws
	prey.freeze = true
	var prey_hp0 := 0.0
	for cell in prey.blocks:
		prey_hp0 += prey.blocks[cell]["hp"]
	var ever_grabbed := false
	for i in 30:
		ai.tick(1.0 / 60.0, prey)
		ever_grabbed = ever_grabbed or ai.grabbing
		await physics_frame
	var prey_hp1 := 0.0
	for cell in prey.blocks:
		prey_hp1 += prey.blocks[cell]["hp"]
	_check(ever_grabbed, "the mouth latched onto the prey at the jaws")
	_check(prey_hp1 < prey_hp0,
		"and it chews continuously without being provoked first (prey %.0f → %.0f hp)"
			% [prey_hp0, prey_hp1])
	_check(Time.get_ticks_msec() < ai._provoked_until,
		"a kraken hunts on sight — it keeps itself provoked while prey lives")

	# The mouth does NOT reach across the map: a far prey takes no grab damage.
	ai.grabbing = false
	var far := _make_ship(_starter_ship())
	far.faction = 0
	far.scale_unit = 8.0
	far.position = mouth + Vector2(40000, 0)
	var far_hp0 := 0.0
	for cell in far.blocks:
		far_hp0 += far.blocks[cell]["hp"]
	for i in 10:
		ai._mouth_grab(1.0 / 60.0, far)
		await physics_frame
	var far_hp1 := 0.0
	for cell in far.blocks:
		far_hp1 += far.blocks[cell]["hp"]
	_check(not ai.grabbing and is_equal_approx(far_hp0, far_hp1),
		"a prey out of the jaws is not grabbed (%.0f hp, untouched)" % far_hp1)

	kraken.queue_free()
	faller.queue_free()
	prey.queue_free()
	far.queue_free()
	await _step(3)


## The sealed LOOT CAVITY (owner follow-up 2026-08-24): both kraken plans wall a
## hollow pocket into the meat, and mining THROUGH into it on a CARCASS spills a
## fixed bundle. The gates that matter here: it is the BREACH that pays (not the
## kill, and not any old harvest), a LIVING kraken never pays, and the bundle
## comes out exactly once — the whale stomach-drop contract, for a bundle.
func _test_kraken_cavity_loot_spills_once_on_breach() -> void:
	_t("a breached kraken loot cavity spills its bundle once; a living one never does")
	# A 5×5 meat shell around ONE sealed air cell — the authored cavity in
	# miniature, with every wall cell harvestable flesh.
	var cells := {}
	for x in 5:
		for y in 5:
			if Vector2i(x, y) != Vector2i(2, 2):
				cells[Vector2i(x, y)] = BlockDB.Type.MEAT

	# --- A LIVING body: no cavity loot, ever --------------------------------
	var live := _make_ship(cells.duplicate())
	live.position = Vector2(-52000, 0)
	live.shared_health_max = 100.0
	live.shared_health = 100.0
	_check(live.cavity_cells().has(Vector2i(2, 2)),
		"the sealed pocket is found — interior air the outside flood never reaches")
	_check(live.cavity_cells().size() == 1,
		"and nothing outside the body is mistaken for it (%d cells)"
			% live.cavity_cells().size())
	_check(live.harvest_cell(Vector2i(2, 1)) == -1,
		"a LIVING body yields nothing to a harvest, cavity wall included")
	_check(not live.cavity_breached() and live.take_cavity_loot().is_empty(),
		"so a living kraken never drops its cavity bundle")
	live.queue_free()

	# --- A CARCASS: the BREACH is what pays ---------------------------------
	var corpse := _make_ship(cells.duplicate())
	corpse.position = Vector2(-52000, -6000)
	corpse.shared_health_max = 100.0
	corpse.shared_health = 0.0  # dead → a carcass
	_check(corpse.take_cavity_loot().is_empty(),
		"an intact carcass pays nothing — killing it is not cracking it open")
	_check(corpse.harvest_cell(Vector2i(0, 0)) == ItemDB.Product.MEAT,
		"harvesting an OUTER wall cell yields its flesh product as usual")
	_check(not corpse.cavity_breached() and corpse.take_cavity_loot().is_empty(),
		"but that cell is nowhere near the pocket — still no bundle")

	_check(corpse.harvest_cell(Vector2i(2, 1)) == ItemDB.Product.MEAT,
		"the cell ON the cavity wall harvests to flesh too")
	_check(corpse.cavity_breached(), "and THAT one breaches the pocket")
	var bundle := corpse.take_cavity_loot()
	var got := {}
	for entry in bundle:
		got[int(entry[0])] = int(entry[1])
	_check(bundle.size() == 2 and got.size() == 2,
		"the breach spills a two-entry bundle (%d)" % bundle.size())
	_check(got.get(TerrainDB.Type.AETHERITE, 0) == 12,
		"12 aetherite — the deep band's own prize, buried in the beast")
	_check(got.get(TerrainDB.Type.STONE, 0) == 3, "and the 3 stone it was packed in")
	for id in got:
		_check(ItemDB.is_terrain(int(id)),
			"%s is an existing terrain-range item id, not an invented type"
				% ItemDB.name_of(int(id)))
	_check(corpse.take_cavity_loot().is_empty(),
		"and only once — the cavity is emptied, exactly like the stomach")
	corpse.queue_free()

	# --- The AUTHORED plans really carry one --------------------------------
	# Break-the-fix insurance for the SHIP FILES: re-author a kraken without its
	# walled pocket and this fails, instead of the drop quietly never happening.
	for path in ["res://ships/kraken_b.ship", "res://ships/kraken_c.ship"]:
		var body := _make_ship(ShipLayout.load_cells(path))
		body.position = Vector2(-52000, -12000)
		_check(not body.cavity_cells().is_empty(),
			"%s walls in a sealed loot cavity (%d cells)"
				% [path.get_file(), body.cavity_cells().size()])
		body.queue_free()
	await _step(3)


## The one-shot carcass loot flags PERSIST (2026-08-25 bugfix). They used to live
## only in RAM, so a looted corpse that went through the spawner again — a save/
## load, a host migration, a client joining — came back pristine and paid its
## stomach drop and cavity bundle a SECOND time (an item duplication bug: park a
## looted carcass, save, reload, crack it again). Now they ride `to_payload` as a
## packed int and the save dict alongside it. Checked BOTH ways round, because a
## flag stuck ON is the same bug in reverse: an honest corpse nobody can loot.
func _test_carcass_loot_state_survives_the_wire_and_the_save() -> void:
	_t("a looted carcass stays looted through the payload and the save")
	# The 5x5 meat shell around one sealed cell again — a kraken in miniature.
	var cells := {}
	for x in 5:
		for y in 5:
			if Vector2i(x, y) != Vector2i(2, 2):
				cells[Vector2i(x, y)] = BlockDB.Type.MEAT

	# --- An EMPTIED corpse stays emptied ------------------------------------
	var looted := _make_ship(cells.duplicate())
	looted.position = Vector2(-53000, 0)
	looted.shared_health_max = 100.0
	looted.shared_health = 0.0
	_check(looted.take_stomach_loot() == ItemDB.Product.STOMACH_LOOT,
		"the source corpse gives up its stomach drop")
	looted.harvest_cell(Vector2i(2, 1))
	_check(looted.cavity_breached() and not looted.take_cavity_loot().is_empty(),
		"and its cracked cavity gives up the bundle")

	var reloaded := Ship.from_data(looted.to_payload())
	root.add_child(reloaded)
	_check(reloaded.is_carcass(), "the reloaded body is still a carcass")
	_check(reloaded.take_stomach_loot() == -1,
		"the reloaded corpse has NO stomach drop left (it was already taken)")
	_check(reloaded.cavity_breached(),
		"the breach travels — the pocket is still cracked open after the trip")
	_check(reloaded.take_cavity_loot().is_empty(),
		"and no second cavity bundle — the duplication bug is closed")

	# --- BREAK-THE-FIX: an UNTOUCHED corpse still pays, once -----------------
	# If the flags came back stuck on (or the encode wrote a constant), this half
	# fails: a fresh carcass would be unlootable.
	var fresh := _make_ship(cells.duplicate())
	fresh.position = Vector2(-53000, -6000)
	fresh.shared_health_max = 100.0
	fresh.shared_health = 0.0
	var fresh_clone := Ship.from_data(fresh.to_payload())
	root.add_child(fresh_clone)
	_check(fresh_clone.take_stomach_loot() == ItemDB.Product.STOMACH_LOOT,
		"a never-looted carcass still spills its stomach after the round trip")
	_check(not fresh_clone.cavity_breached(),
		"and its pocket is still sealed (no phantom breach)")
	fresh_clone.harvest_cell(Vector2i(2, 1))
	_check(fresh_clone.cavity_breached() and fresh_clone.take_cavity_loot().size() == 2,
		"cracking the reloaded body pays the bundle exactly as the original would")

	# --- A BREACHED but UNLOOTED pocket keeps its debt -----------------------
	# The middle state: combat cracked the shell open, nobody harvested yet.
	var cracked := _make_ship(cells.duplicate())
	cracked.position = Vector2(-53000, -12000)
	cracked.shared_health_max = 100.0
	cracked.shared_health = 0.0
	cracked.harvest_cell(Vector2i(2, 1))
	_check(cracked.cavity_breached(), "the source pocket is open but unpaid")
	var cracked_clone := Ship.from_data(cracked.to_payload())
	root.add_child(cracked_clone)
	_check(cracked_clone.cavity_breached() and cracked_clone.take_cavity_loot().size() == 2,
		"the reloaded body owes the bundle, and pays it")
	_check(cracked_clone.take_cavity_loot().is_empty(), "then never again")

	# --- Through the SAVE FILE, the same ------------------------------------
	var sd := SaveGame.encode_ship(looted)
	var save_fleet := Fleet.new()
	root.add_child(save_fleet)
	await process_frame
	var from_save: Ship = SaveGame.spawn_ship_from_encoded(save_fleet, sd)
	_check(from_save != null and from_save.take_stomach_loot() == -1,
		"a corpse loaded from a SAVE remembers its stomach was emptied")
	_check(from_save.take_cavity_loot().is_empty(),
		"and its cavity too — save/load cannot duplicate the bundle")

	# A LEGACY save dict (written before the flags were persisted) has no key at
	# all: it must load as a pristine corpse, not crash and not read as looted.
	var legacy := sd.duplicate(true)
	legacy.erase("carcass_state")
	var from_legacy: Ship = SaveGame.spawn_ship_from_encoded(save_fleet, legacy)
	_check(from_legacy != null
			and from_legacy.take_stomach_loot() == ItemDB.Product.STOMACH_LOOT,
		"a legacy save with no carcass_state key loads as an unlooted corpse")

	looted.queue_free()
	reloaded.queue_free()
	fresh.queue_free()
	fresh_clone.queue_free()
	cracked.queue_free()
	cracked_clone.queue_free()
	save_fleet.queue_free()
	await _step(3)


## The mouth chews PEOPLE (owner follow-up 2026-08-24): stand on foot in the jaws
## and the kraken eats YOU at the same DPS a hull cell takes. Also pins the two
## new F2 levers — the grab knobs are read live now, not baked in.
func _test_kraken_mouth_bites_the_player_on_foot() -> void:
	_t("the kraken mouth chews the on-foot player, and its grab knobs are levers")
	# Parity first: the levers ship the constants they replaced, so the feel of a
	# default game is byte-identical to before they existed.
	_check_approx(Tunables.get_num("kraken_grab_dps"), KrakenAI.GRAB_DPS, 0.001,
		"kraken_grab_dps default = KrakenAI.GRAB_DPS")
	_check_approx(Tunables.get_num("kraken_grab_reach"), KrakenAI.GRAB_REACH, 0.001,
		"kraken_grab_reach default = KrakenAI.GRAB_REACH")

	var cells := ShipLayout.upscale_cells(
		ShipLayout.load_cells("res://ships/kraken_c.ship"), 8)
	var kraken := _make_ship(cells)
	kraken.scale_unit = 8.0
	kraken.creature_kind = "kraken"
	kraken.shared_health = 12000.0
	kraken.shared_health_max = 12000.0
	kraken.position = Vector2(-120000, 0)
	kraken.freeze = true  # the bite is damage the brain applies, not a collision

	var ai := KrakenAI.new()
	ai.whale = kraken
	ai.home = kraken.global_position
	# A pace INSIDE the jaws — deliberately not exactly ON the mouth point, so a
	# zeroed reach lever is a real gate below rather than a 0-distance tie.
	var jaws := ai._mouth_world() + Vector2(0.0, 200.0)

	var p := Player.new()
	p.GRAVITY = 0.0
	root.add_child(p)
	await _step(2)

	# No prey_player handed in (the world's "they are piloting / nobody here"
	# case): the mouth must not reach for anything, and must not crash.
	ai.prey_player = null
	var solo: float = await _bite_drain(ai, p, jaws, 10)
	_check(solo == 0.0 and not ai.grabbing_player,
		"with no on-foot player handed in, nothing is bitten")

	ai.prey_player = p
	var drain: float = await _bite_drain(ai, p, jaws, 10)
	_check(ai.grabbing_player, "the mouth latches onto a person standing in the jaws")
	_check(drain > 0.0, "and chews them — %.1f hp gone in 10 ticks" % drain)

	# Out of the jaws: the same person a body-length away is not bitten.
	var away := jaws + Vector2(40000, 0)
	var far_drain: float = await _bite_drain(ai, p, away, 10)
	_check(far_drain == 0.0 and not ai.grabbing_player,
		"a person out of the jaws takes nothing")

	# THE DPS LEVER: four times the knob, four times the chewing (break-the-fix —
	# reading KrakenAI.GRAB_DPS again here would leave the drain unchanged).
	Tunables.set_value("kraken_grab_dps", KrakenAI.GRAB_DPS * 4.0)
	var hard: float = await _bite_drain(ai, p, jaws, 10)
	_check(hard > drain * 3.0,
		"the DPS lever drives the bite (%.1f hp vs %.1f at default)" % [hard, drain])
	Tunables.reset("kraken_grab_dps")

	# THE REACH LEVER: zero it and the very same jaws-deep person is out of range.
	Tunables.set_value("kraken_grab_reach", 0.0)
	var no_reach: float = await _bite_drain(ai, p, jaws, 10)
	_check(no_reach == 0.0 and not ai.grabbing_player,
		"the reach lever gates the bite — zeroed, even the jaws cannot reach")
	Tunables.reset("kraken_grab_reach")

	# TAMED, IT STILL BITES (owner 2026-08-24: krakens "always do damage if you
	# touch their mouth parts" — the tamer included). Taming ends the HUNT, not
	# the jaws: a person in the mouth of your own kraken is chewed all the same.
	ai.tamed = true
	var tame_drain: float = await _bite_drain(ai, p, jaws, 10)
	_check(tame_drain > 0.0 and ai.grabbing_player,
		"a TAMED kraken's mouth still chews a person in the jaws (%.1f hp)" % tame_drain)
	ai.tamed = false

	# A CARCASS does not bite: an emptied pool stops the mouth with the swim.
	kraken.shared_health = 0.0
	var dead_drain: float = await _bite_drain(ai, p, jaws, 10)
	_check(dead_drain == 0.0 and not ai.grabbing_player,
		"a kraken CARCASS chews nobody — a dead mouth is just meat")

	Tunables.reset_all()
	p.queue_free()
	kraken.queue_free()
	await _step(3)


## Run the kraken brain for `ticks` with the player pinned at `spot`, and return
## how much health the mouth took. The pin is deliberate: the bite is the AI's
## own damage, so holding the body still isolates it from walk/collision drift.
func _bite_drain(ai: KrakenAI, p: Player, spot: Vector2, ticks: int) -> float:
	p.health = p.max_health
	p.velocity = Vector2.ZERO
	ai.grabbing_player = false
	var latched := false
	for i in ticks:
		p.global_position = spot
		ai.tick(1.0 / 60.0, null)
		latched = latched or ai.grabbing_player
		await physics_frame
	ai.grabbing_player = latched
	return p.max_health - p.health


## DEEP-SPAWN KEEP-OUT (owner follow-up 2026-08-24): krakens spawn in the deep,
## which is where the island field is thickest, so the computed point could put a
## 12,000-hp body inside rock. The probe+scatter is pure, so it is checked here
## without booting the world.
func _test_kraken_spawn_keeps_out_of_deep_rock() -> void:
	_t("a kraken spawn buried in a deep island scatters clear; a clear one never moves")
	var t := _make_terrain()  # scale 1: plain 16px cells
	t.fill_rect(Rect2i(0, 0, 40, 40), TerrainDB.Type.OBSIDIAN)  # a deep island slab

	var cells := {}
	for x in 4:
		for y in 3:
			cells[Vector2i(x, y)] = BlockDB.Type.MEAT
	var foot := WhaleSpawn.footprint_of(cells)
	_check(foot.size == Vector2(4, 3) * Ship.CELL,
		"the probe measures the whole 4x3 FOOTPRINT, not a point (%s)" % foot.size)

	var buried := Vector2(10, 10) * Ship.CELL  # well inside the slab
	_check(WhaleSpawn.footprint_blocked(t, buried, foot),
		"the probe sees a body embedded in rock")
	var moved := WhaleSpawn.clear_spawn_pos(t, buried, foot, 1.0)
	_check(moved != buried, "so the spawn scatters off the island")
	_check(not WhaleSpawn.footprint_blocked(t, moved, foot),
		"and lands somewhere genuinely clear")
	_check(WhaleSpawn.clear_spawn_pos(t, buried, foot, 1.0) == moved,
		"deterministically — no RNG, so a seed still reproduces its world")

	var open_air := Vector2(0.0, -8000.0)
	_check(not WhaleSpawn.footprint_blocked(t, open_air, foot), "open air is not blocked")
	_check(WhaleSpawn.clear_spawn_pos(t, open_air, foot, 1.0) == open_air,
		"and a clear spawn is left exactly where it was — no gratuitous drift")

	# BREAK THE FIX: with nothing to probe against (the keep-out disabled), the
	# very same buried spawn comes straight back — the probe is what moves it.
	_check(WhaleSpawn.clear_spawn_pos(null, buried, foot, 1.0) == buried,
		"without the probe the kraken spawns inside the island, exactly as it used to")

	t.queue_free()
	await _step(2)


## RAM-MINING damage model (owner 2026-08-23, reverses the v0.36.0 no-suicide
## immunity): a ridden whale RAMS terrain and TAKES damage now — but the struck
## nose's ARMOR (BlockDB.collision_resist) divides the bruise, so a FLESH (blubber)
## whale pays in full while a SHELL-armored one barely feels it. This is what lets
## a shell-nosed kraken chew through terrain without dying, without a blanket flag.
func _test_shell_armor_soaks_ram_damage() -> void:
	_t("a ridden whale takes ram damage now; SHELL armor soaks most of it")

	var wall := StaticBody2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(400, 6000)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	wall.position = Vector2(30000, -20000)
	wall.add_child(cs)
	root.add_child(wall)

	var ram := func(mat: int) -> float:
		var blob := {}
		for x in 5:
			for y in 8:
				blob[Vector2i(x, y - 4)] = mat
		var big: Dictionary = ShipLayout.upscale_cells(blob, 8)
		var w := _make_ship(big)
		w.scale_unit = 8.0
		w.gravity_scale = 0.0
		w.linear_damp = 0.0
		w.assist_enabled = false
		w.position = wall.position + Vector2(-2000, 0)
		w.shared_health_max = 15000.0
		w.shared_health = 15000.0
		w.ridden_mining = true  # a drilling mount — no longer immune
		w.linear_velocity = Vector2(4000.0, 0.0)
		await _step(40)
		var lost := 15000.0 - (w.shared_health if is_instance_valid(w) else 0.0)
		if is_instance_valid(w):
			w.queue_free()
		await process_frame
		return lost

	# (a) FLESH nose: a ridden whale rammed into terrain now TAKES the bruise
	# (the blanket ride immunity is gone — owner: whales take damage when ramming).
	var flesh_lost: float = await ram.call(BlockDB.Type.BLUBBER)
	_check(flesh_lost > 0.0,
		"a ridden FLESH whale now TAKES ram damage (%.0f lost) — immunity reversed" % flesh_lost)

	# (b) SHELL nose: the SAME ram, but armor (resist 20) soaks nearly all of it —
	# durability is earned by the shell, not granted by a flag.
	var shell_lost: float = await ram.call(BlockDB.Type.SHELL)
	_check(shell_lost < flesh_lost * 0.5,
		"SHELL armor soaks the ram: %.0f lost vs the flesh whale's %.0f" % [shell_lost, flesh_lost])

	wall.queue_free()
	await process_frame


## RIDDEN-WHALE MINING — the front-cell probe (pure geometry, RideMining). The
## swath is the cells at the whale's LEADING edge along its travel, `depth` layers
## deep and as wide as the whale (+ breadth padding). Zero travel → no front.
func _test_ride_mine_front_cells_lead_the_travel() -> void:
	_t("ride-mining probes the leading edge along travel, across the whale's width")
	var center := Vector2(1000.0, 500.0)
	var half := Vector2(320.0, 128.0)  # a whale-ish half-extent in px
	var cpx := 64.0
	# Drive +x: every probed cell is at or ahead of the leading edge, none behind.
	var cells := RideMining.front_cells(center, half, Vector2(1.0, 0.0), cpx, 2, 1)
	_check(not cells.is_empty(), "there are cells at the front (%d)" % cells.size())
	var edge_cell_x := floori((center.x + half.x) / cpx)
	var all_ahead := true
	for c in cells:
		if c.x < edge_cell_x:
			all_ahead = false
	_check(all_ahead, "every probed cell is at or ahead of the +x leading edge")
	# depth 2 → exactly two cell-layers deep (two distinct x columns).
	var xs := {}
	for c in cells:
		xs[c.x] = true
	_check(xs.size() == 2, "depth 2 digs exactly two layers deep (%d)" % xs.size())
	# Breadth: half-height 128 px / 64 = 2 cells, + 1 pad each side → 5 rows.
	var ys := {}
	for c in cells:
		ys[c.y] = true
	var expected_rows := 2 * (int(ceil(half.y / cpx)) + 1) + 1
	_check(ys.size() == expected_rows,
		"the swath spans the whale height + padding (%d rows, want %d)" % [ys.size(), expected_rows])
	# No travel, no mining front.
	_check(RideMining.front_cells(center, half, Vector2.ZERO, cpx, 2, 1).is_empty(),
		"a still creature has no mining front")


## The taming Wisdom bar SCALES with the creature tier (small→whale progression,
## WIKI). Beast Whisperer (LORE 3) tames tier-1 small beasts; the whale tier (2)
## needs Master Trader (LORE 5). Pure Stats logic; the world's per-creature gate
## is taming_level() >= creature.tame_level (world.try_tame, tested end-to-end in
## the startup suite).
func _test_taming_bar_scales_with_creature_tier() -> void:
	_t("the taming bar scales with creature tier: small beasts need less LORE than whales")
	var s := Stats.new()
	s.set_level(StatDB.Stat.LORE, StatDB.MIN_LEVEL)
	_check(s.taming_level() == 0, "level-1 LORE = taming tier 0")
	_check(not s.taming_enabled(), "and taming is disabled")
	# Beast Whisperer (LORE 3): tier 1 — enough for a critter (tame_level 1), not
	# for a whale (tame_level 2).
	s.set_level(StatDB.Stat.LORE, 3)
	_check(s.taming_level() == 1, "Beast Whisperer = taming tier 1")
	_check(s.taming_enabled(), "taming is enabled")
	_check(s.taming_level() >= 1 and s.taming_level() < 2,
		"tier 1 tames a small critter but not a whale")
	# Master Trader (LORE 5): tier 3 — the great whales AND the deep krakens
	# answer (owner 2026-08-24: krakens tame at the top bar, kraken.tame_level 3).
	s.set_level(StatDB.Stat.LORE, StatDB.MAX_LEVEL)
	_check(s.taming_level() == 3, "Master Trader = taming tier 3 (whales + krakens)")
	_check(s.taming_level() >= 2, "tier 3 tames a whale")
	_check(s.taming_level() >= 3, "and the top bar reaches a kraken (tame_level 3)")


## ENEMY FLEE (Sprint 4 smarter enemies). An outmatched bandit — guns gone, hull
## chewed low, or outnumbered — DISENGAGES and retreats; a healthy, armed, even
## fight still engages. (Break-the-fix: make _is_outmatched always false and the
## guns-gone / low-hull cases below fail.)
func _test_enemy_flees_when_outmatched() -> void:
	_t("an outmatched bandit flees; a healthy armed one still engages")
	# A small crewed gunship: a 3×3 hull with a helm and a turret.
	var cells := {}
	for x in 3:
		for y in 3:
			cells[Vector2i(x, y)] = BlockDB.Type.HULL
	cells[Vector2i(1, 1)] = BlockDB.Type.HELM
	cells[Vector2i(2, 0)] = BlockDB.Type.TURRET
	var ship := _make_ship(cells)
	ship.position = Vector2(-60000, 0)
	ship.capture_blueprint()
	var target := _make_ship(_starter_ship())
	target.position = ship.position + Vector2(2000, 0)  # a threat off to +x

	var ai := ShipAI.new()
	ai.ship = ship
	ai.home = ship.global_position

	# HEALTHY + ARMED: not outmatched — it engages.
	_check(ship.has_helm(), "the gunship has a helm to pilot from")
	_check(not ai._is_outmatched(false),
		"a whole, armed bandit is not outmatched — it fights")

	# OUTNUMBERED (the caller's headcount): a reason to run even while whole.
	_check(ai._is_outmatched(true), "reported outnumbered, it is outmatched")

	# GUNS GONE: shoot the turret away — nothing to answer with, so it runs.
	ship.remove_block(Vector2i(2, 0))
	ship.rebuild()
	_check(not ai._has_gun() and ai._is_outmatched(false),
		"guns gone: outmatched (no turret left to return fire)")
	# And it actually retreats — thrust points AWAY from the +x threat.
	ai.tick(1.0 / 60.0, target, 700.0)
	await physics_frame
	_check(ship.thrust_input.x < 0.0,
		"it flies away from the threat on +x (thrust.x=%.2f)" % ship.thrust_input.x)

	# LOW HULL (gun restored conceptually is moot — test hull path on a fresh ship).
	var cells2 := {}
	for x in 3:
		for y in 3:
			cells2[Vector2i(x, y)] = BlockDB.Type.HULL
	cells2[Vector2i(1, 1)] = BlockDB.Type.HELM
	cells2[Vector2i(2, 0)] = BlockDB.Type.TURRET
	var ship2 := _make_ship(cells2)
	ship2.position = Vector2(-64000, 0)
	ship2.capture_blueprint()
	var ai2 := ShipAI.new()
	ai2.ship = ship2
	ai2.home = ship2.global_position
	_check(not ai2._is_outmatched(false), "full hull: not outmatched")
	# Chew the hull below FLEE_HULL_FRACTION while keeping helm + turret connected.
	# COMBAT damage (not deconstruction) — so the BLUEPRINT stays 9 and the
	# surviving fraction really drops; the flesh-walls hold it together (no sever).
	for cell in [Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(0, 1), Vector2i(0, 0)]:
		ship2.damage_cell(cell, 9999.0, false)
	ship2.rebuild()
	_check(ai2._has_gun(),
		"the turret still stands (isolating the low-hull trigger from guns-gone)")
	_check(ai2._is_outmatched(false),
		"hull chewed below the flee fraction (%d of %d blocks): outmatched"
			% [ship2.blocks.size(), ship2.blueprint_map().size()])

	ship.queue_free()
	ship2.queue_free()
	target.queue_free()
	await _step(3)


func _test_layout_comments_never_eat_hull_rows() -> void:
	_t("blueprint comments never eat hull rows")
	# The hulk's `#E#H#` hull row was silently parsed as a COMMENT — the
	# enemy shipped as a blimp with no floor, no engine and no helm, and
	# the rows below collapsed upward. Comments are "# " or a bare "#".
	var cells := ShipLayout.parse("""# a real comment
#
origin 0 0
#E#H#
""")
	_check(cells.size() == 5,
		"a row starting with '#' is hull, not a comment (%d cells)" % cells.size())
	_check(cells.get(Vector2i(3, 0), -1) == BlockDB.Type.HELM,
		"the helm on that row survives parsing")
	_check(cells.get(Vector2i(1, 0), -1) == BlockDB.Type.ENGINE,
		"so does the engine")


func _test_scaffold_wreck_still_collides() -> void:
	_t("an all-scaffold wreck still lands on terrain")
	# Shot-down wrecks reduced to pure pass-through structure (struts, open
	# doors) had ZERO collision shapes and fell through the world floor
	# (owner report, session 3). The fallback gives such wrecks colliders
	# from whatever cells remain.
	var wreck := _make_ship({
		Vector2i(0, 0): BlockDB.Type.STRUT,
		Vector2i(0, 1): BlockDB.Type.STRUT,
	})
	wreck.position = Vector2(-1600, 0)
	_check(_shape_count(wreck) > 0,
		"struts-only wreckage keeps a collider (%d shapes)" % _shape_count(wreck))

	# The fallback must NOT leak into normal play: while any solid cell
	# stands, scaffolding stays pass-through.
	var mixed := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.STRUT,
	})
	mixed.position = Vector2(1600, 0)
	_check(_shape_count(mixed) == 1,
		"with a solid cell present, struts contribute no collider")

	wreck.queue_free()
	mixed.queue_free()
	await process_frame


func _test_hulk_is_a_real_ship() -> void:
	_t("the enemy hulk is a real vessel")
	var cells := ShipLayout.load_cells("res://ships/hulk.ship")
	var s := _make_ship(cells)
	s.position = Vector2(3200, 0)
	_check(s.has_helm(), "it has a control panel — a driveable ship, not a prop")
	_check(s.power_supply() > 0.0, "and an engine to feed its gun")
	_check(s.lift_ratio() > 1.0,
		"and enough gasbag to float (%.2f)" % s.lift_ratio())
	var has_turret := false
	var helm_floor := true
	for cell in cells:
		if cells[cell] == BlockDB.Type.TURRET:
			has_turret = true
		if cells[cell] == BlockDB.Type.HELM:
			# Multi-row helms (4×7 at 8×) stack on their own cells; only
			# the bottom row of the component needs a solid floor.
			var below: Vector2i = cell + Vector2i.DOWN
			if not (cells.has(below) and cells[below] == BlockDB.Type.HELM):
				helm_floor = helm_floor and cells.has(below) \
					and BlockDB.get_def(cells[below])["solid"]
	_check(has_turret, "it carries the slung gun")
	_check(helm_floor, "the driver's station stands on a solid floor")
	# Since the driver actually FLIES it (ShipAI), it needs authority on
	# both axes — and the power to use them with the gun idling.
	var has_hprop := false
	for cell in s.blocks:
		if s.blocks[cell]["type"] == BlockDB.Type.PROPELLER \
				and not s._vertical_props.has(cell):
			has_hprop = true
	_check(s._total_vthrust > 0.0, "lift props for the vertical axis")
	_check(has_hprop, "a pusher for the horizontal axis")
	var full_draw := 0.0
	for cell in s.blocks:
		full_draw += BlockDB.get_def(s.blocks[cell]["type"])["draw"]
	_check(s.power_supply() >= full_draw,
		"engines cover everything running at once (%.0f / %.0f)"
			% [s.power_supply(), full_draw])
	var doors := 0
	var all_closed := true
	for cell in cells:
		if cells[cell] == BlockDB.Type.DOOR or cells[cell] == BlockDB.Type.DOOR_CLOSED:
			doors += 1
			all_closed = all_closed and cells[cell] == BlockDB.Type.DOOR_CLOSED
	_check(doors >= 2, "the cabin has a way in (%d door cells)" % doors)
	_check(all_closed, "and its doors spawn CLOSED (owner 2026-08-20)")
	s.queue_free()
	await process_frame


func _test_platforms() -> void:
	_t("platforms are one-way strips on their own body")
	var s := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.PLATFORM,
	})
	_check(_shape_count(s) == 1, "the platform is not part of the hull collider")

	var body: Node = null
	for child in s.get_children():
		if child is AnimatableBody2D and String(child.name).begins_with("Platforms"):
			body = child
			break
	_check(body is AnimatableBody2D, "a Platforms child body exists")
	if body != null:
		var strips := body.get_children().filter(func(c: Node) -> bool: return c is CollisionShape2D)
		_check(strips.size() == 1, "one strip per platform cell")
		if strips.size() == 1:
			_check((strips[0] as CollisionShape2D).one_way_collision,
				"the strip is one-way — jump up through, stand on top")
		_check(body.get_collision_layer_value(3) and body.collision_mask == 0,
			"platform body is layer 3, collides back with nothing")

	_check_approx(s.mass, 13.0, 0.01, "platforms carry their mass")
	_check(s._connected_islands().size() == 1, "and hold the ship together structurally")
	s.queue_free()
	await process_frame


# --- Power grid -----------------------------------------------------------
#
# The original's component model (docs/WIKI_REFERENCE.md): engines produce
# power, propellers and turrets consume it, and when demand exceeds supply
# everything degrades proportionally — brownout, not blackout.

func _test_power_grid() -> void:
	_t("engines supply power; demand beyond supply browns out proportionally")
	var s := _make_ship(_starter_ship())
	_check_approx(s.power_supply(), 4500.0, 0.01, "three engines supply 4500")

	s.thrust_input = Vector2.ZERO
	_check_approx(s.active_draw(), 500.0, 0.01,
		"idle ship: only the two wing turrets idle-scan (2×250)")
	_check_approx(s._power_ratio(), 1.0, 0.001, "idle ship is at full power")

	s.thrust_input = Vector2(1.0, 1.0)
	_check_approx(s.active_draw(), 4100.0, 0.01,
		"pushers (1800) + lift props (1800) + turret scan (500) = 4100 at full burn")
	_check_approx(s._power_ratio(), 1.0, 0.001, "4500 supply covers 4100 — no brownout")

	# Bolt on two more turrets: +500 idle-scan tips demand over supply.
	s.set_block(Vector2i(0, 1), BlockDB.Type.TURRET)
	s.set_block(Vector2i(0, 2), BlockDB.Type.TURRET)
	_check_approx(s.active_draw(), 4600.0, 0.01, "turrets always draw — demand climbs to 4600")
	_check_approx(s._power_ratio(), 4500.0 / 4600.0, 0.001,
		"demand 4600 vs supply 4500 browns everything to ~98%")

	# Another engine restores full output: the "you need multiple engines" loop.
	s.set_block(Vector2i(0, 3), BlockDB.Type.ENGINE)
	_check_approx(s._power_ratio(), 1.0, 0.001, "another engine clears the brownout")

	# The grid is live, not blueprint-bookkeeping: destroy engines mid-flight
	# and supply drops the same physics frame — "oops" is the design.
	s.damage_cell(Vector2i(-3, 1), 999.0)
	s.damage_cell(Vector2i(2, 1), 999.0)
	s.damage_cell(Vector2i(3, 1), 999.0)
	_check_approx(s.power_supply(), 1500.0, 0.01,
		"three engines destroyed in flight: supply drops instantly")
	_check(s._power_ratio() < 1.0,
		"and everything powered browns out in realtime (ratio %.2f)" % s._power_ratio())

	s.queue_free()
	await process_frame


func _test_props_are_inert_without_engines() -> void:
	_t("propellers without an engine do nothing — engines are required to fly")
	var powerless := {
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.PROPELLER,
	}
	var powered := {
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.PROPELLER,
		Vector2i(0, -1): BlockDB.Type.ENGINE,
	}

	# Far apart — two ships spawned at the origin collide and shove each other,
	# which is a fine physics result and a ruined measurement.
	var dead := _make_ship(powerless, false)
	dead.gravity_scale = 0.0
	dead.position = Vector2(-2000, -5000)
	dead.thrust_input = Vector2(1.0, 0.0)
	var live := _make_ship(powered, false)
	live.gravity_scale = 0.0
	live.position = Vector2(2000, -5000)
	live.thrust_input = Vector2(1.0, 0.0)
	await _step(30)

	# Off-centre thrust also spins a helmless hull, so measure speed rather
	# than direction — the claim under test is "no engine, no push".
	_check(dead.linear_velocity.length() < 1.0,
		"no engine: propeller produces no thrust (%.2f px/s)" % dead.linear_velocity.length())
	_check(live.linear_velocity.length() > 50.0,
		"with an engine the same propeller pushes hard (%.0f px/s)" % live.linear_velocity.length())

	dead.queue_free()
	live.queue_free()
	await process_frame


# --- Blueprint and repair -------------------------------------------------

## The original's repair tool restored a ship to "its original form", implying
## a persisted blueprint. Grid-as-truth makes that a second serialised grid.
func _test_blueprint_and_repair() -> void:
	_t("repair restores a ship toward its blueprint")
	var s := _make_ship(_starter_ship())

	_check(s.blueprint.size() == s.blocks.size() * 4, "blueprint captured on spawn")
	_check_approx(s.blueprint_completion(), 1.0, 0.001, "an intact ship is 100% complete")

	# Damaged but present.
	s.damage_cell(Vector2i(-5, 0), 40.0)
	_check(s.blueprint_completion() < 1.0, "damage shows up as incompleteness")
	_check(s.repair_cell(Vector2i(-5, 0), 25.0), "repairing a damaged block does work")
	_check_approx(s.blocks[Vector2i(-5, 0)]["hp"], 85.0, 0.01, "hp healed by the repair amount")
	_check(s.repair_cell(Vector2i(-5, 0), 999.0), "over-repair still tops it up")
	_check_approx(s.blocks[Vector2i(-5, 0)]["hp"], 100.0, 0.01, "healing caps at max hp")
	_check(not s.repair_cell(Vector2i(-5, 0), 10.0),
		"repairing intact hull reports no work — a tool must not charge for it")

	# Destroyed outright — by COMBAT (damage), which leaves the blueprint
	# intact. remove_block is deconstruction now and shrinks it instead.
	s.damage_cell(Vector2i(1, 0), 999.0)
	_check(not s.has_block(Vector2i(1, 0)), "block destroyed")
	_check(s.repair_cell(Vector2i(1, 0), 30.0), "repair rebuilds a destroyed block")
	_check(s.has_block(Vector2i(1, 0)), "the block is back")
	_check(s.blocks[Vector2i(1, 0)]["type"] == BlockDB.Type.HULL,
		"rebuilt with the blueprint's block type, not a guess")
	_check_approx(s.blocks[Vector2i(1, 0)]["hp"], 30.0, 0.01, "rebuilt partially, not free")

	# Boundaries.
	_check(not s.repair_cell(Vector2i(40, 40), 50.0),
		"repair refuses cells outside the blueprint — that would be construction")
	s.blueprint = PackedInt32Array([80, 80, BlockDB.Type.HULL, 100])
	_check(not s.repair_cell(Vector2i(80, 80), 50.0),
		"repair refuses to rebuild a detached block with nothing to attach to")

	s.queue_free()
	await process_frame


func _test_blueprint_survives_severing() -> void:
	_t("wreckage becomes its own blueprint")
	# Severed pieces must not carry the parent's blueprint, or a repair tool
	# would let a broken-off tail regrow the entire ship it fell from.
	var s := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HELM,
		Vector2i(1, 0): BlockDB.Type.HULL,
		Vector2i(2, 0): BlockDB.Type.HULL,
	})
	var pieces: Array = []
	s.severed.connect(func(p: Ship) -> void: pieces.append(p))
	s.remove_block(Vector2i(1, 0))

	_check(pieces.size() == 1, "piece severed")
	if pieces.size() == 1:
		await process_frame  # _spawn_island adds the piece deferred; don't add it twice
		_check(pieces[0].blueprint.size() == 4,
			"wreckage's blueprint is only itself (%d blocks)" % (pieces[0].blueprint.size() / 4))
		_check(not pieces[0].repair_cell(Vector2i(1, 0), 50.0),
			"wreckage cannot regrow the ship it broke off")
		pieces[0].queue_free()

	s.queue_free()
	await process_frame


func _test_walking_on_a_moving_deck() -> void:
	_t("standing on a moving ship: glued; walking against it: you win")
	# Owner report: standing on a coasting ship slid the player deck-forward
	# at ~ship speed, and walking the opposite way could not counter it —
	# the platform carry was being applied twice (engine + walking code).
	var cells: Dictionary = _starter_ship()
	var s := _make_ship(cells, false)
	s.position = Vector2(0, -7000)
	s.linear_velocity = Vector2(220, 0)
	s.assist_enabled = true
	# Doors spawn closed (2026-08-20), and the walk below runs into the
	# mast doorway — open it: this test is about the platform carry.
	for cell in s.blocks:
		if cell.x < 0 and s.blocks[cell]["type"] == BlockDB.Type.DOOR_CLOSED:
			s.toggle_door(cell)
			break

	var p := Player.new()
	root.add_child(p)
	# Drop the player just above the open deck so they LAND on it (landing,
	# not teleport-on-top, is what populates the platform bookkeeping).
	p.global_position = s.to_global(Vector2(-40, -40))
	p.velocity = s.linear_velocity
	await _step(20)

	_check(p.is_on_floor(), "landed on the moving deck")
	var rel0: float = s.to_local(p.global_position).x
	await _step(45)
	var drift: float = s.to_local(p.global_position).x - rel0
	_check(absf(drift) < 12.0,
		"standing still stays glued to the deck (drifted %.1f px in 0.75s)" % drift)

	# Ship moves +x; walk left. The player must gain ground on the deck.
	rel0 = s.to_local(p.global_position).x
	Input.action_press("move_left")
	await _step(45)
	Input.action_release("move_left")
	var gained: float = rel0 - s.to_local(p.global_position).x
	_check(gained > 40.0,
		"walking against the ship's motion moves you across the deck (%.0f px)" % gained)

	# The hatch planks must hold weight on a MOVING ship. sync_to_physics=true
	# on the strip bodies broke exactly this in live play (pass-through both
	# directions) while near-stationary test ships masked it — never again.
	p.global_position = s.to_global(Vector2(-8, -40))
	p.velocity = s.linear_velocity
	var held := false
	for i in 40:
		await physics_frame
		if p.is_on_floor():
			held = true
			break
	_check(held, "the hatch planks hold weight on a moving ship")
	if held:
		var rel_y := s.to_local(p.global_position).y
		_check(rel_y < 0.0,
			"standing ON the plank, not fallen through the hull (rel_y=%.0f)" % rel_y)

	p.queue_free()
	s.queue_free()
	await process_frame


# --- Grapple rope ----------------------------------------------------------

## Owner spec: the rope bends like a rope. Pulling reels you to the bend and
## then past it, and it must never pull you through geometry.
func _test_rope_wraps_and_respects_walls() -> void:
	_t("the grapple rope bends at corners and cannot pull through walls")
	# A slab hangs in the air; the anchor is above-left of it; the player
	# hangs below-right, so the straight line to the anchor crosses the slab.
	var slab := StaticBody2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(190, 10)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	slab.position = Vector2(105, -145)
	cs.position = Vector2.ZERO
	slab.add_child(cs)
	root.add_child(slab)

	var p := Player.new()
	root.add_child(p)
	p.global_position = Vector2(100, 0)
	p._hook_state = Player.HookState.LATCHED
	p._anchor_ship = null
	p._pivots = [{"ship": null, "point": Vector2(0, -300)}]
	p._rope_len = 330.0

	await _step(15)
	_check(p._pivots.size() >= 2, "the rope bent around the slab (%d pivots)" % p._pivots.size())

	# Reel in, watching every frame: the player may be pulled to the bend,
	# around the slab's edge, and on toward the anchor — that is correct rope
	# behaviour ("to the bend and then past it") — but never through the slab.
	var y_before := p.global_position.y
	var breached := false
	Input.action_press("reel_in")
	for i in 90:
		await physics_frame
		var d := p.global_position - Vector2(105, -145)
		if absf(d.x) < 95.0 + 4.0 and absf(d.y) < 5.0 + 8.0:
			breached = true
	Input.action_release("reel_in")
	_check(p.global_position.y < y_before - 10.0,
		"reeling pulls the player up toward the bend (%.0f -> %.0f)"
			% [-y_before, -p.global_position.y])
	_check(not breached, "and at no frame was the player inside the slab")

	# Wherever the reel ended, a clear line means a straight rope again.
	p.global_position = Vector2(0, -250)
	p.velocity = Vector2.ZERO
	await _step(10)
	_check(p._pivots.size() == 1, "with a clear line the rope unwraps back to the hook")

	p.queue_free()
	slab.queue_free()
	await process_frame


func _test_pendulum_swings_freely() -> void:
	_t("a rope pendulum swings through vertical and keeps its energy")
	# Owner report: hanging from a ceiling hook, the swing stalled ~10 degrees
	# off vertical and inched down. Cause: the walking code's mid-air brake
	# (velocity.x -> 0 at AIR_ACCEL with no input) ate the horizontal motion
	# that IS the swing near the bottom. With no input held, airborne momentum
	# must be preserved.
	var p := Player.new()
	root.add_child(p)
	var anchor := Vector2(0, -9600)
	p.global_position = Vector2(95, -9471)  # ~36 degrees off vertical, at rest
	p._hook_state = Player.HookState.LATCHED
	p._anchor_ship = null
	p._pivots = [{"ship": null, "point": anchor}]
	p._rope_len = 160.0

	var crossed := false
	var far_side := 0.0
	for i in 150:
		await physics_frame
		if p.global_position.x < 0.0:
			crossed = true
		far_side = minf(far_side, p.global_position.x)

	_check(crossed, "the swing crosses the vertical instead of stalling short")
	_check(far_side < -40.0,
		"and carries through to the far side (reached x=%.0f from +95)" % far_side)

	# But not forever: attrition brings it to rest hanging near vertical
	# within ~8s (owner: "this isn't a spinning simulator").
	await _step(350)
	# Horizontal component only: the stretch-spring keeps a tiny (sub-2px)
	# vertical limit-cycle bob at 60Hz that is invisible in play; the owner's
	# complaint — and this assertion — is about the side-to-side pendulation.
	_check(absf(p.global_position.x) < 25.0 and absf(p.velocity.x) < 30.0,
		"attrition settles the pendulation to a hang (x=%.0f, vx=%.0f)"
			% [p.global_position.x, p.velocity.x])
	p.queue_free()
	await process_frame


# --- Ramming ----------------------------------------------------------------

## Owner spec: collision damage is momentum — the ship crunches through the
## contact block, keeps going slower, crunches the next, until the momentum is
## spent. And gentle contact costs nothing.
## The coverage the 1× ram tests could not give (owner 2026-08-21: "the
## ram works visually, it just does no damage"): at 8× the impact
## threshold carries unit³ (×512) while ship-on-ship contacts resolve
## SOFTLY across many solver steps — per-step killed momentum ducked the
## threshold every step and the whale's 4,600 px/s ram left the starter
## untouched. Vessel collisions now bite once per contact EPISODE, sized
## by closing speed × reduced mass. This test rams at REAL 8× masses.
func _test_ship_ram_bites_at_scale() -> void:
	_t("a vessel ram at 8x scale takes a real bite (episode momentum)")
	var blob := {}
	for x in 5:
		for y in 8:
			blob[Vector2i(x, y - 4)] = BlockDB.Type.HULL
	var big: Dictionary = ShipLayout.upscale_cells(blob, 8)

	var victim := _make_ship(big)
	victim.scale_unit = 8.0
	victim.gravity_scale = 0.0
	victim.linear_damp = 0.0
	victim.position = Vector2(-16000, -14000)
	var victim_before := victim.blocks.size()

	var rammer := _make_ship(big)
	rammer.scale_unit = 8.0
	rammer.gravity_scale = 0.0
	rammer.linear_damp = 0.0
	rammer.position = victim.position + Vector2(-1800, 0)
	rammer.ram_immunity_dir = Vector2.RIGHT  # a whale mid-attack
	rammer.linear_velocity = Vector2(4600.0, 0.0)
	await _step(40)

	var lost := victim_before - (victim.blocks.size() if is_instance_valid(victim) else 0)
	_check(is_instance_valid(victim) and lost >= 10,
		"the rammed hull loses a real bite of blocks (%d gone)" % lost)
	_check(is_instance_valid(rammer) and rammer.blocks.size() == big.size(),
		"the immune rammer pays nothing")

	# A gentle 8x docking must stay free: episode momentum sits under the
	# threshold at closing speeds a pilot would call parking.
	var docker := _make_ship(big)
	docker.scale_unit = 8.0
	docker.gravity_scale = 0.0
	docker.linear_damp = 0.0
	docker.position = victim.position + Vector2(-2600, 0)
	docker.linear_velocity = Vector2(300.0, 0.0)
	var docker_before := docker.blocks.size()
	var victim_after_ram := victim.blocks.size()
	await _step(60)
	_check(is_instance_valid(docker) and docker.blocks.size() == docker_before
			and is_instance_valid(victim) and victim.blocks.size() == victim_after_ram,
		"a gentle 8x docking costs neither hull a block")

	for n in [victim, rammer, docker]:
		if is_instance_valid(n):
			n.queue_free()
	await process_frame


## Owner report 2026-08-21: "the whale dies within moments of touching me or
## the ground" — with a 15,000 pool. The crush walks INWARD cell by cell, but
## on a living creature `damage_cell` banks everything in the shared pool and
## breaks nothing, so the walk never ran out of cells and billed the pool its
## full remaining budget at EVERY step (≈ available²/(2·hp) ≈ 800,000 for one
## hard ram). A living body now takes the crash once, damped by
## CREATURE_IMPACT_FACTOR; only a carcass crushes cell by cell like a vessel.
func _test_living_creature_soaks_crashes() -> void:
	_t("a living creature soaks crashes into its pool; a carcass crushes")
	var blob := {}
	for x in 5:
		for y in 8:
			blob[Vector2i(x, y - 4)] = BlockDB.Type.BLUBBER
	var big: Dictionary = ShipLayout.upscale_cells(blob, 8)

	# (a) Rammed by a vessel at real 8× ramming speed.
	var whale := _make_ship(big)
	whale.scale_unit = 8.0
	whale.gravity_scale = 0.0
	whale.linear_damp = 0.0
	whale.position = Vector2(16000, -14000)
	whale.shared_health_max = 15000.0
	whale.shared_health = 15000.0
	var whale_blocks := whale.blocks.size()

	var rammer := _make_ship(big)
	rammer.scale_unit = 8.0
	rammer.gravity_scale = 0.0
	rammer.linear_damp = 0.0
	rammer.position = whale.position + Vector2(-1800, 0)
	rammer.linear_velocity = Vector2(4600.0, 0.0)
	await _step(40)

	var hurt := 15000.0 - whale.shared_health
	_check(is_instance_valid(whale) and hurt > 0.0,
		"a vessel ram still bruises the creature (%.0f of 15000)" % hurt)
	_check(is_instance_valid(whale) and whale.shared_health > 0.8 * 15000.0,
		"but costs only a sliver of the pool (%.0f left)" % whale.shared_health)
	_check(is_instance_valid(whale) and whale.blocks.size() == whale_blocks,
		"and no block pops off the living body")
	rammer.queue_free()
	whale.queue_free()

	# (b) The same creature crashing into terrain.
	var wall := StaticBody2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(400, 6000)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	wall.position = Vector2(16000, -20000)
	wall.add_child(cs)
	root.add_child(wall)

	var flier := _make_ship(big)
	flier.scale_unit = 8.0
	flier.gravity_scale = 0.0
	flier.linear_damp = 0.0
	flier.assist_enabled = false
	flier.position = wall.position + Vector2(-2000, 0)
	flier.shared_health_max = 15000.0
	flier.shared_health = 15000.0
	var flier_blocks := flier.blocks.size()
	flier.linear_velocity = Vector2(4000.0, 0.0)
	await _step(40)

	var crash_hurt := 15000.0 - flier.shared_health
	_check(is_instance_valid(flier) and crash_hurt > 0.0
			and flier.shared_health > 0.8 * 15000.0,
		"a hard terrain crash costs a small fraction too (%.0f lost)" % crash_hurt)
	_check(is_instance_valid(flier) and flier.blocks.size() == flier_blocks,
		"the living body survives the crash whole")
	flier.queue_free()

	# (c) Boundary: once the pool is empty the carcass crushes like a vessel.
	var carcass := _make_ship(big)
	carcass.scale_unit = 8.0
	carcass.gravity_scale = 0.0
	carcass.linear_damp = 0.0
	carcass.assist_enabled = false
	carcass.position = wall.position + Vector2(-2000, 0)
	carcass.shared_health_max = 15000.0
	carcass.shared_health = 0.0  # dead
	var carcass_blocks := carcass.blocks.size()
	carcass.linear_velocity = Vector2(4000.0, 0.0)
	await _step(40)

	var crushed := carcass_blocks - (carcass.blocks.size() if is_instance_valid(carcass) else 0)
	_check(crushed > 0,
		"the same crash crushes a dead carcass block by block (%d gone)" % crushed)
	if is_instance_valid(carcass):
		carcass.queue_free()
	wall.queue_free()
	await process_frame


## Owner report 2026-08-21, AFTER v0.11.5: "the whale still seems to
## basically collide with things and just die... if it's chasing the player,
## it'll hit a world block and just poof."
##
## Instrumented before fixing. The measured profile (whale mass 37,184 at
## 8×, 15,000 pool):
##   * terrain does NOT bill per step. Killed momentum is measured against
##     the PREVIOUS step's post-solve velocity, so a body already stopped
##     cannot be billed again — every crash tested (7,000 px/s, 20,000
##     px/s, thin shelf, ground scrape, 10 s of driven grinding) resolved
##     in exactly ONE qualifying step.
##   * the killer was the IMMUNITY-CLEAR RACE. Impacts are recorded in
##     _integrate_forces (physics time) and billed in _process (idle time),
##     and WhaleAI._end_attack() clears `ram_immunity_dir` exactly when the
##     crunch kills the whale's speed — i.e. on the tick after the ram
##     lands. Any frame carrying two physics ticks slotted that clear
##     between record and bill, and the whale paid 1,024 hp for its own
##     terminal ram crunch: ~7% of the pool on EVERY ram that connects,
##     which over one angry chase is the "poof".
##   * magnitude was hot too: a clumsy full-speed terrain crash cost the
##     same 1,024 (6.8%).
## Fixes: the immunity verdict is stamped at RECORD time, terrain bills
## once per contact face per touch episode for living creatures, and
## CREATURE_TERRAIN_IMPACT_FACTOR (0.02) sets scenery crashes to ~2.7% of
## the pool each.
func _test_a_chase_never_kills_the_whale() -> void:
	_t("an angry chase bruises the whale; its own ram crunch is still free")
	var blob := {}
	for x in 5:
		for y in 8:
			blob[Vector2i(x, y - 4)] = BlockDB.Type.BLUBBER
	var big: Dictionary = ShipLayout.upscale_cells(blob, 8)

	var ground := StaticBody2D.new()
	for r in [Rect2(Vector2(-30000, 6000), Vector2(60000, 2000)),
			Rect2(Vector2(9000, 2000), Vector2(1200, 4000))]:
		var rect := r as Rect2
		var shape := RectangleShape2D.new()
		shape.size = rect.size
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.position = rect.position + rect.size * 0.5
		ground.add_child(cs)
	root.add_child(ground)
	await _step(2)

	# (a) THE RACE. A charging creature slams the wall, and — exactly as
	# WhaleAI does — the attack ends the moment the crunch kills the speed,
	# clearing the immunity before the idle frame bills the contact. The
	# ram it was immune to must not become the thing that kills it.
	var charger := _make_ship(big)
	charger.scale_unit = 8.0
	charger.gravity_scale = 0.0
	charger.assist_enabled = false
	charger.position = Vector2(3000, 3000)
	charger.shared_health_max = 15000.0
	charger.shared_health = 15000.0
	charger.ram_immunity_dir = Vector2.RIGHT
	charger.linear_velocity = Vector2(7000, 0)
	for i in 200:
		# WhaleAI's own rule, tick for tick (GLIDE_END_SPEED × scale_unit).
		charger.ram_immunity_dir = Vector2.ZERO \
			if charger.linear_velocity.length() < WhaleAI.GLIDE_END_SPEED * 8.0 \
			else Vector2.RIGHT
		await physics_frame
	_check(is_instance_valid(charger) and charger.shared_health >= 15000.0,
		"its own terminal ram crunch costs it NOTHING, even though the attack "
			+ "ended on impact (pool %.0f of 15000)" % charger.shared_health)
	charger.queue_free()
	await _step(3)

	# (b) A CLUMSY crash — no charge, no immunity — still costs something.
	# The owner-pinned spec: no blanket attack immunity for creatures.
	var clumsy := _make_ship(big)
	clumsy.scale_unit = 8.0
	clumsy.gravity_scale = 0.0
	clumsy.assist_enabled = false
	clumsy.position = Vector2(3000, 3000)
	clumsy.shared_health_max = 15000.0
	clumsy.shared_health = 15000.0
	clumsy.linear_velocity = Vector2(7000, 0)
	await _step(200)
	var clumsy_cost := 15000.0 - clumsy.shared_health
	_check(clumsy_cost > 0.0,
		"a clumsy non-charge crash still hurts (%.0f hp)" % clumsy_cost)
	_check(clumsy_cost < 0.06 * 15000.0,
		"but a single scenery clout is a bruise, not a wound (%.1f%% of the pool)"
			% (clumsy_cost / 150.0))
	clumsy.queue_free()
	await _step(3)

	# (c) GRIND: a creature held in sustained contact with one face is
	# billed ONCE for that touch, however many steps the contact lasts.
	var grinder := _make_ship(big)
	grinder.scale_unit = 8.0
	grinder.gravity_scale = 0.0
	grinder.assist_enabled = false
	grinder.position = Vector2(-20000, 6000 - 900)
	grinder.shared_health_max = 15000.0
	grinder.shared_health = 15000.0
	for i in 600:
		# Driven down and along: 10 s of scraping the same floor.
		grinder.apply_central_force(
			Vector2(1100.0 * 8.0, 400.0 * 8.0) * grinder.mass)
		await physics_frame
	var grind_cost := 15000.0 - grinder.shared_health
	_check(grind_cost <= clumsy_cost * 1.5,
		"10 s of grinding the same floor costs at most one crash (%.0f hp vs %.0f for one clout)"
			% [grind_cost, clumsy_cost])
	_check(is_instance_valid(grinder) and grinder.blocks.size() > 0,
		"and no block comes off the living body")
	grinder.queue_free()
	await _step(3)

	# (d) THE WHOLE CHASE, driven by the real WhaleAI: a permanently
	# provoked creature shoving at a target parked past a wall block, with
	# the ground underneath — 20 s of push/glide/crunch/re-align. The owner's
	# scenario end to end. It must come out bruised and ALIVE.
	var prey := _make_ship(big)
	prey.scale_unit = 8.0
	prey.gravity_scale = 0.0
	prey.assist_enabled = false
	prey.freeze = true
	prey.position = Vector2(14000, 5300)

	var whale := _make_ship(big)
	whale.scale_unit = 8.0
	whale.gravity_scale = 0.0
	whale.assist_enabled = false
	whale.faction = 2
	whale.position = Vector2(-6000, 0)
	whale.shared_health_max = 15000.0
	whale.shared_health = 15000.0
	var ai := WhaleAI.new()
	ai.whale = whale
	ai.home = whale.position
	for i in 1200:
		ai.provoke()  # stay angry for the whole chase
		ai.tick(1.0 / 60.0, prey)
		if not is_instance_valid(whale) or whale.shared_health <= 0.0:
			break
		await physics_frame
	var chase_left: float = whale.shared_health if is_instance_valid(whale) else 0.0
	_check(chase_left > 0.0, "20 s of angry chasing does not kill the whale")
	_check(chase_left > 0.7 * 15000.0,
		"and leaves it well above 70%% of its pool (%.0f of 15000)" % chase_left)
	_check(chase_left < 15000.0,
		"while a chase that crashes is not free either (%.0f hp of bruises)"
			% (15000.0 - chase_left))
	if is_instance_valid(whale):
		whale.queue_free()
	prey.queue_free()
	ground.queue_free()
	await process_frame


## The whale/collision diagnostic (maps/world/whale_diag.gd) — tests the TOOL
## and gives the owner the first data sample. Runs the owner's exact repro: a
## whale with a shared pool sandwiched between a moving ship and a StaticBody2D
## wall, for ~1-2 s of stepped frames, with recording ON. Then it flips the
## whale to a carcass and shoots it, so blocks die and the rebuild counter —
## the FPS suspect — is exercised too. Asserts the log captured (a) damage from
## more than one source, (b) a populated rebuild counter, and (c) a non-empty,
## parseable file. The captured rows are printed for the report.
func _test_whale_diagnostic_captures_the_sandwich() -> void:
	_t("the whale diagnostic captures a sandwich: sources, rebuilds, a log file")
	var blob := {}
	for x in 5:
		for y in 8:
			blob[Vector2i(x, y - 4)] = BlockDB.Type.BLUBBER
	var big: Dictionary = ShipLayout.upscale_cells(blob, 8)
	var dt := 1.0 / float(Engine.physics_ticks_per_second)

	# The whale, mid-arena, with a live shared pool.
	var whale := _make_ship(big)
	whale.scale_unit = 8.0
	whale.gravity_scale = 0.0
	whale.linear_damp = 0.0
	whale.faction = 2
	whale.position = Vector2(16000, -14000)
	whale.shared_health_max = 15000.0
	whale.shared_health = 15000.0

	# A StaticBody2D wall just to starboard — the terrain half of the sandwich.
	var wall := StaticBody2D.new()
	var wshape := RectangleShape2D.new()
	wshape.size = Vector2(400, 6000)
	var wcs := CollisionShape2D.new()
	wcs.shape = wshape
	wall.position = whale.position + Vector2(1100, 0)
	wall.add_child(wcs)
	root.add_child(wall)

	# A ship closing from port at ram speed — the vessel half. It shoves the
	# whale into the wall: two damage sources in one squeeze.
	var rammer := _make_ship(big)
	rammer.scale_unit = 8.0
	rammer.gravity_scale = 0.0
	rammer.linear_damp = 0.0
	rammer.position = whale.position + Vector2(-1800, 0)
	rammer.linear_velocity = Vector2(5000.0, 0.0)

	var diag := WhaleDiag.new()
	diag.start([whale])

	# Phase A — the living sandwich (~40 frames ≈ 0.66 s). Capture a row every
	# physics frame (as world._physics_process does), then let the idle frame
	# run so Ship._process bills the pending impacts.
	for i in 45:
		await physics_frame
		diag.capture_frame([whale], dt)
		await process_frame
		if not is_instance_valid(whale):
			break

	var living_left: float = whale.shared_health if is_instance_valid(whale) else -1.0

	# Phase B — the carcass. Kill the pool and keep squeezing while shooting it,
	# so blocks die and rebuild() fires: this is the grapple-and-shoot FPS
	# report, and it populates the rebuild counter the ROWs record.
	if is_instance_valid(whale):
		whale.shared_health = 0.0
		rammer.linear_velocity = Vector2(4000.0, 0.0)
		for i in 30:
			await physics_frame
			# A shot into a carcass kills the struck cell -> a full rebuild.
			if is_instance_valid(whale) and not whale.blocks.is_empty():
				var cell: Vector2i = whale.blocks.keys()[0]
				whale.net_damage_cell(cell, 1.0e6)
			diag.capture_frame([whale], dt)
			await process_frame
			if not is_instance_valid(whale):
				break

	diag.stop([whale])

	# (c) The log file exists, is non-empty, and parses.
	var text := ""
	var f := FileAccess.open(WhaleDiag.LOG_PATH, FileAccess.READ)
	if f != null:
		text = f.get_as_text()
		f.close()
	var lines := text.split("\n", false)
	_check(not text.is_empty() and lines.size() > 4,
		"the log file is written and non-empty (%d lines at %s)"
			% [lines.size(), diag.resolved_path()])

	# Parse ROW and EVT lines.
	var sources := {}
	var max_rebuilds := 0
	var row_count := 0
	var evt_count := 0
	var health_curve: Array[String] = []
	for line in lines:
		if line.begins_with("EVT"):
			evt_count += 1
			for tok in line.split(" ", false):
				if tok.begins_with("src="):
					sources[tok.substr(4)] = true
		elif line.begins_with("ROW"):
			row_count += 1
			for tok in line.split(" ", false):
				if tok.begins_with("rebuilds="):
					max_rebuilds = maxi(max_rebuilds, int(tok.substr(9)))
				elif tok.begins_with("hp=") and health_curve.size() < 8:
					health_curve.append(tok.substr(3))

	# (a) Damage from more than one source.
	_check(sources.size() >= 2,
		"the whale took damage from >1 source: %s" % ", ".join(sources.keys()))
	# (b) The rebuild counter is populated (the FPS suspect, exercised on the
	# carcass crush/shots).
	_check(max_rebuilds > 0,
		"the rebuild counter registered rebuilds (peak %d in a frame)" % max_rebuilds)
	_check(row_count > 0 and evt_count > 0,
		"rows and events were both captured (%d rows, %d events)"
			% [row_count, evt_count])

	# Print the sample for the report: the whale's health curve and the raw log.
	print("    [sample] living-phase pool left: %.0f of 15000" % living_left)
	print("    [sample] hp curve (first rows): %s" % ", ".join(health_curve))
	print("    [sample] --- whale_diag.log (%d lines) ---" % lines.size())
	for line in lines:
		print("    | %s" % line)
	print("    [sample] --- end log ---")

	# Free everything this test made — including any carcass piece the
	# phase-B crush may have severed off (a spawned Ship left under root
	# leaks a CanvasItem at exit and turns a passing run into exit 255).
	if is_instance_valid(whale):
		whale.queue_free()
	rammer.queue_free()
	wall.queue_free()
	await process_frame
	for child in root.get_children():
		if child is Ship or child is StaticBody2D:
			child.queue_free()
	await process_frame
	await process_frame


## The diagnostic must be near-zero-overhead while recording: it BUFFERS ROW/EVT/
## SUM lines in memory and flushes to disk only on the SUM-window boundary and on
## stop() — never per frame (the per-frame flush was an observer effect that
## inflated the very `proc` numbers F3 reads). This pins the flush cadence (no
## disk I/O between windows) AND that no data is lost (stop() flushes the tail),
## with the ROW format unchanged.
func _test_whale_diag_buffers_and_flushes_periodically() -> void:
	_t("the diagnostic buffers rows and flushes per window, not per frame — no disk I/O between flushes")
	# capture_frame is synchronous, so no physics stepping is needed to drive the
	# ROW/SUM write path — a minimal whale with a shared pool is enough.
	var whale := _make_ship({Vector2i(0, 0): BlockDB.Type.BLUBBER})
	whale.faction = 2
	whale.shared_health_max = 1000.0
	whale.shared_health = 1000.0
	var dt := 1.0 / float(Engine.physics_ticks_per_second)

	var diag := WhaleDiag.new()
	diag.start([whale])

	# The header is flushed at start(); a handful of frames FEWER than one summary
	# window must stay buffered in memory — the on-disk file grows no ROW yet.
	var few: int = WhaleDiag.SUMMARY_EVERY - 1
	for i in few:
		diag.capture_frame([whale], dt, 0)
	var early := _read_all(WhaleDiag.LOG_PATH)
	_check(early.contains("# ROW"), "the header reaches disk immediately (flushed at start)")
	_check(_count_prefix(early, "ROW ") == 0,
		"after %d frames NO ROW has hit disk — the per-frame path does no disk I/O" % few)

	# One more frame crosses the window: the buffer flushes, so exactly one
	# window of ROWs plus the SUM line appear on disk together.
	diag.capture_frame([whale], dt, 0)
	var win := _read_all(WhaleDiag.LOG_PATH)
	_check(_count_prefix(win, "ROW ") == WhaleDiag.SUMMARY_EVERY,
		"crossing the window flushed exactly one window of ROWs (%d)"
			% _count_prefix(win, "ROW "))
	_check(_count_prefix(win, "SUM ") == 1, "and the window SUM line landed with them")

	# A short tail (again < one window) stays buffered until stop() flushes it —
	# proving no data is lost on a clean toggle-off.
	for i in 3:
		diag.capture_frame([whale], dt, 0)
	var pre_stop := _read_all(WhaleDiag.LOG_PATH)
	_check(_count_prefix(pre_stop, "ROW ") == WhaleDiag.SUMMARY_EVERY,
		"the 3 tail rows are still buffered, not yet on disk")
	diag.stop([whale])
	var done := _read_all(WhaleDiag.LOG_PATH)
	_check(_count_prefix(done, "ROW ") == WhaleDiag.SUMMARY_EVERY + 3,
		"stop() flushed the buffered tail — nothing lost (%d rows on disk)"
			% _count_prefix(done, "ROW "))

	# Content integrity: a flushed ROW still carries its documented fields, and
	# the SUM its proc/phys costs — the format is unchanged by the buffering.
	var a_row := ""
	var a_sum := ""
	for line in done.split("\n", false):
		if a_row.is_empty() and line.begins_with("ROW "):
			a_row = line
		elif a_sum.is_empty() and line.begins_with("SUM "):
			a_sum = line
	for field in ["f=", "dt=", "fps=", "whale=", "hp=", "carcass=", "rebuilds=", "shots=", "srcs="]:
		_check(a_row.contains(field), "a flushed ROW still carries '%s'" % field)
	for field in ["frames=", "avg_dt=", "max_dt=", "proc=", "phys=", "nodes="]:
		_check(a_sum.contains(field), "a flushed SUM still carries '%s'" % field)

	whale.queue_free()
	await process_frame


## Read a whole user:// file to text ("" if absent). For asserting what has
## actually reached disk vs what is still buffered in memory.
func _read_all(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s


## Count lines beginning with `prefix` in `text`.
func _count_prefix(text: String, prefix: String) -> int:
	var n := 0
	for line in text.split("\n", false):
		if line.begins_with(prefix):
			n += 1
	return n


## The set of grid cells the hull collision shapes actually cover, read back
## from the live CollisionShape2D children (hull shapes are direct children;
## platform/shield shapes live on sub-bodies, so they are excluded). Used to
## prove the incremental combat drop keeps collider coverage EXACTLY the solid
## grid — no dead cell left solid, no live cell left uncovered. Valid for the
## unmirrored test ships here (a vessel and a never-flipped carcass).
func _covered_cells(s: Ship) -> Dictionary:
	var covered := {}
	for child in s.get_children():
		if child is CollisionShape2D:
			var cs := child as CollisionShape2D
			var size: Vector2 = (cs.shape as RectangleShape2D).size
			var wc := int(round(size.x / Ship.CELL))
			var hc := int(round(size.y / Ship.CELL))
			var ox := int(round(cs.position.x / Ship.CELL - (wc - 1) * 0.5))
			var oy := int(round(cs.position.y / Ship.CELL - (hc - 1) * 0.5))
			for yy in hc:
				for xx in wc:
					covered[Vector2i(ox + xx, oy + yy)] = true
	return covered


func _solid_cells(s: Ship) -> Dictionary:
	var solid := {}
	for c in s.blocks:
		if BlockDB.get_def(s.blocks[c]["type"])["solid"]:
			solid[c] = true
	return solid


## The whale-carcass FPS fix (session 5). Two layers:
##   * COALESCING — combat rebuilds collapse to at most ONE full rebuild per
##     frame (never one per killing hit), mirroring the crash batch.
##   * INCREMENTAL — a full rebuild measured ~50 ms on the 5,120-cell whale, so
##     even 1/frame under sustained fire was a slideshow. Combat on plain BULK
##     cells therefore does NOT rebuild at all: it patches mass/CoM/collider in
##     O(dead). This test drives net_damage_cell (the shot path), reads the
##     rebuild counter directly, and — crucially — verifies collider coverage
##     stays EXACTLY the solid grid so "cheaper" never meant "wrong".
func _test_combat_rebuilds_coalesce_per_frame() -> void:
	_t("combat damage: coalesced + incremental (carcass FPS fix), collider stays exact")

	# --- (1) Several bulk kills in ONE frame -> ZERO full rebuilds -----------
	var line := {}
	for x in 6:
		line[Vector2i(x, 0)] = BlockDB.Type.HULL
	var s := _make_ship(line)
	s.position = Vector2(0, 0)
	var mass0 := s.mass
	var n0 := s.blocks.size()

	# Five lethal shots at five distinct cells in one synchronous block (no frame
	# boundary between them). net_damage_cell is exactly the shot path.
	s.rebuilds_this_frame = 0
	for x in 5:
		s.net_damage_cell(Vector2i(x, 0), 1.0e6)
	_check(s.blocks.size() == n0 - 5,
		"five lethal hits destroy five cells right away (%d of %d left)"
			% [s.blocks.size(), n0])
	# Bulk deaths take the incremental path — NOT one full rebuild, not five.
	_check(s.rebuilds_this_frame == 0,
		"bulk combat deaths never fire a full rebuild (%d)" % s.rebuilds_this_frame)
	# Correctness done incrementally: mass dropped, and the collider now covers
	# exactly the five-fewer solid cells (no ghost coverage on the dead ones).
	_check(s.mass < mass0, "mass dropped incrementally (%.1f -> %.1f)" % [mass0, s.mass])
	var cov := _covered_cells(s)
	var sol := _solid_cells(s)
	_check(cov == sol,
		"collider coverage equals the live solid grid after incremental drops (%d covered, %d solid)"
			% [cov.size(), sol.size()])
	# Nothing pending — the incremental path is synchronous, so a frame later the
	# counter is still zero (no deferred rebuild snuck in).
	await process_frame
	_check(s.rebuilds_this_frame == 0,
		"still no full rebuild a frame later (%d)" % s.rebuilds_this_frame)

	# --- (2) Sustained multi-frame fire: deaths pile up, full rebuilds do not -
	# A big carcass (dead pool, so blocks break under fire), placed far from the
	# first ship so the two never touch and generate stray impact rebuilds.
	var big := {}
	for x in 40:
		for y in 3:
			big[Vector2i(x, y)] = BlockDB.Type.HULL
	var carcass := _make_ship(big)
	carcass.position = Vector2(0, 100000)
	carcass.shared_health_max = 15000.0
	carcass.shared_health = 0.0  # dead: a carcass breaks block by block
	var total0 := carcass.blocks.size()
	var cmass0 := carcass.mass

	carcass.rebuilds_this_frame = 0
	var frames := 12
	var shots_per_frame := 4
	var fired := 0
	for f in frames:
		# A volley: several lethal shots at distinct cells in the SAME frame.
		for k in shots_per_frame:
			carcass.net_damage_cell(Vector2i(fired % 40, (fired / 40) % 3), 1.0e6)
			fired += 1
		await process_frame
	await process_frame
	var deaths := total0 - carcass.blocks.size()
	var rebuilds := carcass.rebuilds_this_frame
	_check(deaths >= frames,
		"the sustained volley actually killed cells across the run (%d deaths)" % deaths)
	# The invariant the fix guarantees: NEVER one rebuild per death. (Bulk fire
	# is fully incremental, so this is ~0; the ceiling is what matters.)
	_check(rebuilds <= frames,
		"combat never rebuilds per death — at most ~one/frame (%d rebuilds, %d deaths)"
			% [rebuilds, deaths])
	_check(carcass.mass < cmass0,
		"carcass mass fell with the deaths (%.0f -> %.0f)" % [cmass0, carcass.mass])
	_check(_covered_cells(carcass) == _solid_cells(carcass),
		"collider coverage still exact after sustained incremental fire (%d cells)"
			% carcass.blocks.size())

	# --- (3) A COMPONENT death falls back to a full (coalesced) rebuild -------
	# A turret is a component: its death changes power/draw/glyphs, so combat on
	# it CANNOT be incremental — it must trigger a real rebuild (coalesced to
	# one that frame). Build hull with one turret cell.
	var withturret := {}
	for x in 5:
		withturret[Vector2i(x, 0)] = BlockDB.Type.HULL
	withturret[Vector2i(2, -1)] = BlockDB.Type.TURRET
	var tship := _make_ship(withturret)
	tship.position = Vector2(0, 200000)
	tship.rebuilds_this_frame = 0
	tship.net_damage_cell(Vector2i(2, -1), 1.0e6)  # kill the turret
	await process_frame
	await process_frame
	_check(not tship.has_block(Vector2i(2, -1)),
		"the turret cell is gone")
	_check(tship.rebuilds_this_frame == 1,
		"a component death triggers exactly one (coalesced) full rebuild (%d)"
			% tship.rebuilds_this_frame)

	s.queue_free()
	carcass.queue_free()
	tship.queue_free()
	await process_frame
	for child in root.get_children():
		if child is Ship:
			child.queue_free()
	await process_frame
	await process_frame


func _test_ramming_plows_through() -> void:
	_t("ramming: momentum crunches blocks one by one, then runs out")
	var wall := StaticBody2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(40, 400)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	wall.position = Vector2(400, -8000)
	cs.position = Vector2.ZERO
	wall.add_child(cs)
	root.add_child(wall)

	# A bar of eight hulls (mass 80) nose-first into the wall at 900 px/s.
	var cells := {}
	for x in 8:
		cells[Vector2i(x, 0)] = BlockDB.Type.HULL
	var ram := _make_ship(cells, false)
	ram.gravity_scale = 0.0
	ram.assist_enabled = false
	ram.position = Vector2(0, -8000)
	ram.linear_velocity = Vector2(900, 0)

	await _step(120)
	var destroyed := 8 - ram.blocks.size()
	_check(destroyed >= 2,
		"a hard ram crunches multiple blocks frame by frame (%d destroyed)" % destroyed)
	_check(ram.blocks.size() >= 3,
		"but the momentum runs out before the whole ship is gone (%d left)" % ram.blocks.size())
	_check(ram.linear_velocity.length() < 200.0,
		"each crunch costs speed (ended at %.0f px/s)" % ram.linear_velocity.length())
	ram.queue_free()

	# The same bar at a gentle speed stops without losing a single block.
	var soft := _make_ship(cells, false)
	soft.gravity_scale = 0.0
	soft.assist_enabled = false
	soft.position = Vector2(200, -8000)
	soft.linear_velocity = Vector2(100, 0)
	await _step(90)
	_check(soft.blocks.size() == 8, "a gentle bump costs nothing (8 blocks intact)")

	soft.queue_free()
	wall.queue_free()
	await process_frame


## Inject one COLLISION impact into a floating ship and let _process run its
## crush walk — deterministic, no physics contact needed. The hit lands on cell
## (0,0) from the left (normal +x), so the crush walks +x through the row.
## `impulse` is the momentum the impact carried; _process converts it to a crush
## budget exactly as a real crash would. Two idle frames so _process is
## guaranteed to have drained _pending_impacts by the time this returns.
func _crush(ship: Ship, impulse: float) -> void:
	ship._pending_impacts.append({
		"pos": Vector2(-Ship.CELL * 0.5, 0.0),
		"impulse": impulse,
		"normal": Vector2.RIGHT,
		"immune": false,
	})
	await process_frame
	await process_frame


## Owner 2026-08-21: "blimps should take less damage from just soft collisions."
## Gasbags carry BlockDB.collision_resist 10, applied ONLY in the crush walk, so
## a soft bump that shatters a hull cell leaves a balloon intact, a hard ram
## still pops it, and combat (shots → damage_cell, never the crush) is untouched.
func _test_gasbags_shrug_off_soft_collisions() -> void:
	_t("gasbags resist soft COLLISIONS; a hard ram and any SHOT still pop them")

	# Crush budgets, solved back through the _process conversion at 1x scale:
	#   available = (impulse - THRESHOLD) * SCALE   ->   impulse = THRESHOLD + a/SCALE.
	# 150 hp of budget destroys a hull cell (hp 100); 500 clears a gasbag
	# (effective collision-hp 35 * 10 = 350).
	var soft_impulse := Ship.IMPACT_DAMAGE_THRESHOLD + 150.0 / Ship.IMPACT_DAMAGE_SCALE
	var hard_impulse := Ship.IMPACT_DAMAGE_THRESHOLD + 500.0 / Ship.IMPACT_DAMAGE_SCALE

	# (a) The SAME soft impact: it destroys a hull cell but no gasbag.
	var hull := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.HULL,
		Vector2i(2, 0): BlockDB.Type.HULL,
	})
	hull.position = Vector2(0, -6000)
	await _crush(hull, soft_impulse)
	var hull_lost := 3 - hull.blocks.size()
	_check(hull_lost >= 1,
		"a soft collision destroys a normal hull cell (%d gone)" % hull_lost)
	hull.queue_free()

	var bag := _make_ship({
		Vector2i(0, 0): BlockDB.Type.GASBAG,
		Vector2i(1, 0): BlockDB.Type.GASBAG,
	})
	bag.position = Vector2(4000, -6000)
	var bag_before := bag.blocks.size()
	await _crush(bag, soft_impulse)
	_check(is_instance_valid(bag) and bag.blocks.size() == bag_before,
		"the SAME soft collision destroys ZERO gasbags (%d intact)"
			% (bag.blocks.size() if is_instance_valid(bag) else 0))
	if is_instance_valid(bag):
		bag.queue_free()

	# (b) A hard ram still pops the balloon — and fires collision_damage so a
	# floating number can appear at the impact point.
	var bag2 := _make_ship({
		Vector2i(0, 0): BlockDB.Type.GASBAG,
		Vector2i(1, 0): BlockDB.Type.GASBAG,
	})
	bag2.position = Vector2(8000, -6000)
	var emitted: Array = []
	bag2.collision_damage.connect(
		func(_p: Vector2, a: float) -> void: emitted.append(a))
	await _crush(bag2, hard_impulse)
	var bag2_left := bag2.blocks.size() if is_instance_valid(bag2) else 0
	_check(bag2_left < 2, "a hard ram still destroys gasbags (%d left)" % bag2_left)
	_check(not emitted.is_empty() and emitted[0] > 0.0,
		"and the crush fires collision_damage (%.0f) for the floating number"
			% (emitted[0] if not emitted.is_empty() else 0.0))
	if is_instance_valid(bag2):
		bag2.queue_free()

	# (c) COMBAT is unaffected: a shot's damage_cell pops a gasbag at its own hp.
	var bag3 := _make_ship({Vector2i(0, 0): BlockDB.Type.GASBAG})
	bag3.damage_cell(Vector2i(0, 0), BlockDB.max_hp(BlockDB.Type.GASBAG))
	_check(not (is_instance_valid(bag3) and bag3.has_block(Vector2i(0, 0))),
		"a shot still pops a gasbag at its normal hp (combat unchanged)")
	if is_instance_valid(bag3):
		bag3.queue_free()
	await process_frame


## Owner 2026-08-22: floating damage numbers at the point of collision, adding up
## multiple hits from the same source within a ~0.5s window. Tests the coalescing
## manager directly (no rendering) — maps/world/damage_numbers.gd.
func _test_damage_numbers_coalesce_per_source() -> void:
	_t("collision damage numbers coalesce per source and expire cleanly")

	# (a) Two hits, same source, same spot, inside the window: ONE number, summed.
	var m := DamageNumbers.new()
	m.add(1, Vector2(100, 100), 40.0)
	m.update(0.2)  # still inside COALESCE_WINDOW (0.5)
	m.add(1, Vector2(108, 100), 60.0)  # same 4-cell bucket
	_check(m.count() == 1, "same source within the window is one number (%d)" % m.count())
	_check_approx(m.active()[0]["total"], 100.0, 0.01, "and its value is the SUM")

	# (b) Same source and spot, but past the window: a separate number.
	var m2 := DamageNumbers.new()
	m2.add(1, Vector2(100, 100), 40.0)
	m2.update(DamageNumbers.COALESCE_WINDOW + 0.05)  # window lapsed, still alive
	m2.add(1, Vector2(100, 100), 40.0)
	_check(m2.count() == 2, "past the 0.5s window it is a separate number (%d)" % m2.count())

	# (c) Same source, clearly different spot: separate buckets, separate numbers.
	var m3 := DamageNumbers.new()
	m3.add(1, Vector2(0, 0), 40.0)
	m3.add(1, Vector2(1000, 0), 40.0)
	_check(m3.count() == 2, "a clearly different spot is a separate number (%d)" % m3.count())

	# (d) Different sources at the same spot never merge.
	var m4 := DamageNumbers.new()
	m4.add(1, Vector2(0, 0), 40.0)
	m4.add(2, Vector2(0, 0), 40.0)
	_check(m4.count() == 2, "two different ships are two numbers (%d)" % m4.count())

	# (e) A number frees after its lifetime — no leak.
	var m5 := DamageNumbers.new()
	m5.add(1, Vector2(0, 0), 40.0)
	m5.update(DamageNumbers.LIFETIME + 0.01)
	_check(m5.count() == 0, "a number expires after its lifetime (%d left)" % m5.count())

	# (f) Negligible hits spawn nothing.
	var m6 := DamageNumbers.new()
	m6.add(1, Vector2(0, 0), 0.0)
	_check(m6.count() == 0, "a zero/negligible hit spawns no number")


## Owner 2026-08-23: "turrets shooting at whales seem to produce no damage
## numbers." A whale is a shared pool, so its hits break no block and used to
## float nothing. net_damage_cell (the shot path) now fires `combat_damage` at the
## struck cell's WORLD point — the gunfire twin of the crush's collision_damage —
## so a listener floats a number for every shot that bites, whale or hull. A shot
## into empty space fires nothing.
func _test_combat_damage_floats_a_number() -> void:
	_t("gunfire floats a damage number — even on a whale's shared pool")

	# A living creature: a shared pool absorbs shots, breaking no block.
	var whale := _make_ship({
		Vector2i(0, 0): BlockDB.Type.BLUBBER,
		Vector2i(1, 0): BlockDB.Type.BLUBBER,
	})
	whale.shared_health = 5000.0
	whale.shared_health_max = 5000.0
	var hits: Array = []
	whale.combat_damage.connect(
		func(p: Vector2, a: float) -> void: hits.append({"pos": p, "amount": a}))

	var pool_before := whale.shared_health
	whale.net_damage_cell(Vector2i(0, 0), 200.0)
	_check(hits.size() == 1, "a shot into the whale floats one number (%d)" % hits.size())
	_check(whale.shared_health < pool_before,
		"and it drained the shared pool (%.0f < %.0f)" % [whale.shared_health, pool_before])
	if not hits.is_empty():
		_check_approx(float(hits[0]["amount"]), 200.0, 0.01,
			"the number is the shot's damage")
		var want := whale.to_global(whale.local_pos_of(Vector2i(0, 0)))
		_check((hits[0]["pos"] as Vector2).distance_to(want) < 1.0,
			"floated at the struck cell's world point")

	# A shot into EMPTY space (no block there) floats nothing.
	whale.net_damage_cell(Vector2i(9, 9), 200.0)
	_check(hits.size() == 1, "a shot into empty space floats nothing (%d)" % hits.size())
	whale.queue_free()
	await process_frame


## Owner 2026-08-23: "whale collision against ship still doesn't seem to transfer
## all the momentum on impact — shouldn't it be a bit more transferrable like pool
## balls?" Ships now carry a restitution (physics_material_override.bounce) from
## the ship_restitution lever, so a struck body springs off instead of sharing
## velocity inelastically. A bouncier hit kicks the target harder — verified by
## measuring the target's peak speed at two restitutions. (The bounce is wired at
## _ready, so the lever is set BEFORE each ship is built.)
func _test_restitution_transfers_more_momentum() -> void:
	_t("collisions transfer momentum like pool balls (restitution kicks the target)")

	var peak := func(bounce: float) -> float:
		Tunables.set_value("ship_restitution", bounce)
		# A 4-cell mover (mass 40) into a 1-cell target (mass 10): closing×μ stays
		# well under the impact-damage threshold, so nothing crushes — a clean
		# elastic/inelastic comparison.
		var mover := _make_ship({
			Vector2i(0, 0): BlockDB.Type.HULL, Vector2i(1, 0): BlockDB.Type.HULL,
			Vector2i(2, 0): BlockDB.Type.HULL, Vector2i(3, 0): BlockDB.Type.HULL,
		})
		mover.position = Vector2(-140, -6000)
		mover.linear_velocity = Vector2(500, 0)
		var target := _make_ship({Vector2i(0, 0): BlockDB.Type.HULL})
		target.position = Vector2(0, -6000)
		var top := 0.0
		for i in 120:
			await physics_frame
			if is_instance_valid(target):
				top = maxf(top, target.linear_velocity.length())
		_check(mover.physics_material_override != null
			and is_equal_approx(mover.physics_material_override.bounce, bounce),
			"the ship carries the restitution lever (%.2f)" % bounce)
		mover.queue_free()
		target.queue_free()
		await process_frame
		return top

	var inelastic: float = await peak.call(0.0)
	var elastic: float = await peak.call(0.9)
	Tunables.reset_all()
	_check(inelastic > 0.0, "an inelastic hit still transfers some momentum (%.0f px/s)" % inelastic)
	_check(elastic > inelastic * 1.2,
		"a bouncier hit kicks the target notably harder (%.0f > %.0f px/s)" % [elastic, inelastic])


# --- Serialisation and replication ---------------------------------------

## Regression test for a bug that broke single-player while every other test
## passed. Godot installs an OfflineMultiplayerPeer by default, so
## `has_multiplayer_peer()` is true even with no networking — code branching on
## it takes the network path with nobody on the other end. It stayed hidden
## because the offline peer also reports is_server() == true, so authority
## checks kept working. The symptom was "the game never gives you a ship".
func _test_single_player_is_not_online() -> void:
	_t("single-player is not mistaken for a network session")
	_check(not NetUtil.is_online(root), "root reports offline with no real peer")
	_check(NetUtil.is_authority(root), "and still holds authority")

	var s := _make_ship({Vector2i(0, 0): BlockDB.Type.HULL})
	_check(not s.is_online(), "a ship in single-player reports offline")
	_check(s.is_authority(), "a ship in single-player has authority")
	_check(not s.freeze, "and simulates itself rather than waiting to be driven")
	_check(not s.has_node("Sync"), "no replication node is created off-network")
	s.queue_free()
	await process_frame

## Client-side interpolation. A remote hull is eased toward the pose the
## server published rather than being teleported onto it once per packet —
## "clunk is clunk whether or not it is your ship" (DESIGN §1). The easing
## itself is pure maths on the shadow pose, so it is checkable here without a
## second process; the net smoke test covers the pose still arriving over a
## real wire. Both halves matter: too little easing is judder, and easing a
## *teleport* would glide a respawned ship across the whole map.
func _test_remote_ships_are_eased_not_snapped() -> void:
	_t("a remote ship is eased toward the server pose, but teleports snap")
	var s := _make_ship({Vector2i(0, 0): BlockDB.Type.HULL})
	var dt := 1.0 / 60.0

	s.position = Vector2.ZERO
	s.net_position = Vector2(100.0, 0.0)
	s.net_rotation = 0.0
	s.rotation = 0.0
	s._follow_net_pose(dt)
	var step := s.position.x
	_check(step > 0.0 and step < 100.0,
		"one tick closes %.1f px of a 100 px error — part of the way, not all" % step)
	_check_approx(step, 100.0 * (1.0 - exp(-Ship.NET_SMOOTH_RATE * dt)), 0.01,
		"the step is the documented exponential approach")

	# It must actually converge: presentation smoothing that lagged forever
	# would be a client quietly disagreeing with the server.
	for i in 120:
		s._follow_net_pose(dt)
	_check(s.position.distance_to(s.net_position) < 1.0,
		"two seconds of ticks converge on the server's pose")

	# A teleport — respawn, world reset, a fresh spawn far away.
	s.position = Vector2.ZERO
	s.net_position = Vector2(Ship.NET_SNAP_CELLS * Ship.CELL * 2.0, 0.0)
	s._follow_net_pose(dt)
	_check(s.position == s.net_position,
		"an error past the snap threshold is placed, never glided")

	s.queue_free()
	await process_frame


## The wire format and the save format are the same thing, and both peers must
## derive identical physics from it. If this drifts, clients desync and saves
## corrupt — so it is checked property by property, not just by block count.
func _test_serialization_roundtrip() -> void:
	_t("a ship survives a serialise / deserialise round trip")
	var a := _make_ship(_starter_ship())
	a.damage_cell(Vector2i(-5, 0), 25.0)  # partial damage must survive too

	var data := a.serialize()
	_check(data.size() == a.blocks.size() * 4, "4 ints per block, nothing else")

	var b := _make_ship({Vector2i(99, 99): BlockDB.Type.BALLAST})
	b.apply_serialized(data)

	_check(b.blocks.size() == a.blocks.size(), "same block count")
	_check(not b.has_block(Vector2i(99, 99)), "previous grid fully replaced")
	_check_approx(b.mass, a.mass, 0.01, "mass derives identically")
	_check_approx(b.center_of_mass.x, a.center_of_mass.x, 0.01, "com.x identical")
	_check_approx(b.center_of_mass.y, a.center_of_mass.y, 0.01, "com.y identical")
	_check_approx(b.blocks[Vector2i(-5, 0)]["hp"], 75.0, 0.01, "damage state preserved")
	_check(_shape_count(b) == _shape_count(a), "collider rebuilt identically")
	_check_approx(b.lift_ratio(), a.lift_ratio(), 0.001, "flight characteristics identical")

	a.queue_free()
	b.queue_free()
	await process_frame


func _test_from_data_reconstruction() -> void:
	_t("Ship.from_data rebuilds a ship from a spawn payload")
	# The path used by network spawning, severed wreckage, and (later) loading
	# a save. One construction path for all three.
	var source := _make_ship(_starter_ship())
	var data := {
		"grid": source.serialize(),
		"pos": Vector2(120.0, -340.0),
		# rot/angvel stay in the format for compatibility, but under the
		# upright rule no producer ever writes non-zero values.
		"rot": 0.0,
		"linvel": Vector2(60.0, -12.0),
		"angvel": 0.0,
		"assist": false,
		"pilot": 7,
	}
	var built := Ship.from_data(data)
	root.add_child(built)

	_check(built.blocks.size() == source.blocks.size(), "grid restored")
	_check_approx(built.mass, source.mass, 0.01, "mass restored")
	_check(built.position.is_equal_approx(Vector2(120.0, -340.0)), "position restored")
	_check(built.linear_velocity.is_equal_approx(Vector2(60.0, -12.0)), "velocity restored")
	_check(not built.assist_enabled, "assist flag restored")
	_check(built.pilot_peer == 7, "pilot restored")

	source.queue_free()
	built.queue_free()
	await process_frame


## Hosting after offline play re-creates every pre-host ship through the
## spawner (maps/world/world.gd → host_session), and it does that by feeding
## `to_payload()` back into `from_data()`. Anything missing from that
## dictionary is silently dropped on the switch — a whale that forgets its
## shared health pool starts shedding blocks, a hostile forgets it is hostile.
## Post-spawn assignment cannot patch it up either: that is server-only, and
## silent (godot-quirks). So the round trip is checked field by field.
func _test_payload_round_trip_survives_hosting() -> void:
	_t("to_payload / from_data preserve everything a peer needs")
	var source := _make_ship(_starter_ship())
	source.position = Vector2(-880.0, -1240.0)
	source.linear_velocity = Vector2(31.0, -77.0)
	source.pilot_peer = 4
	source.faction = 2
	source.assist_enabled = false
	source.scale_unit = 8.0
	source.damage_cell(Vector2i(-5, 0), 25.0)  # partial damage travels too
	# Set after the damage: a live creature absorbs hits into the pool instead
	# of into its blocks, so this order gives us both a wound AND a pool.
	source.shared_health = 1234.0
	source.shared_health_max = 3000.0

	var clone := Ship.from_data(source.to_payload())
	root.add_child(clone)

	_check(clone.blocks.size() == source.blocks.size(), "grid preserved")
	_check_approx(clone.blocks[Vector2i(-5, 0)]["hp"], source.blocks[Vector2i(-5, 0)]["hp"],
		0.01, "per-block damage preserved")
	_check(clone.position.is_equal_approx(source.position), "position preserved")
	_check(clone.linear_velocity.is_equal_approx(source.linear_velocity),
		"velocity preserved")
	_check(clone.pilot_peer == 4, "pilot state preserved")
	_check(clone.faction == 2, "faction preserved")
	_check(not clone.assist_enabled, "assist flag preserved")
	_check_approx(clone.scale_unit, 8.0, 0.001, "world scale preserved")
	_check_approx(clone.shared_health, 1234.0, 0.01, "whales keep their wounds")
	_check_approx(clone.shared_health_max, 3000.0, 0.01, "and their health pool")
	_check(clone.blueprint.size() == source.blueprint.size(),
		"the blueprint travels, so repair still knows the intended form")
	_check_approx(clone.mass, source.mass, 0.01, "and the mass re-derives identically")

	source.queue_free()
	clone.queue_free()
	await process_frame


## The WALL layer rides to_payload/from_data (task B): a damaged ship whose block
## was shot away while its wall stood must reload with the SAME walls, not a
## re-derived footprint — otherwise its severability drifts. A payload WITHOUT
## walls (a legacy save / wreckage) still loads, falling back to derive.
func _test_walls_ride_the_payload() -> void:
	_t("walls survive to_payload/from_data exactly; a wall-less payload derives")
	var s := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HELM,
		Vector2i(1, 0): BlockDB.Type.HULL,
		Vector2i(2, 0): BlockDB.Type.HULL,
		Vector2i(3, 0): BlockDB.Type.HULL,
	})
	# Combat kills the block but never touches the wall — the footprint (walls)
	# now exceeds the live blocks, the exact drift-prone state.
	s.damage_cell(Vector2i(2, 0), 99999.0)
	_check(not s.has_block(Vector2i(2, 0)), "the struck block is gone")
	_check(s.walls.has(Vector2i(2, 0)), "but its wall still stands")
	_check(s.walls.size() == 4, "the wall footprint is the full 4-cell bar")

	# Wire round trip: walls come back identically, not re-derived.
	var clone := Ship.from_data(s.to_payload())
	root.add_child(clone)
	var same := clone.walls.size() == s.walls.size()
	for cell in s.walls:
		if not clone.walls.has(cell):
			same = false
	_check(same, "every wall cell round-trips exactly through to_payload/from_data")
	_check(clone.walls.has(Vector2i(2, 0)),
		"including the shot-out cell's ghost wall (the drift this fixes)")

	# Break-the-fix reference: strip walls from the payload → derive-from-footprint
	# (the legacy behaviour), which LOSES the ghost wall. This is what serializing
	# walls prevents, and what the "exactly" check above would catch if walls were
	# dropped from to_payload.
	var legacy := s.to_payload()
	legacy.erase("walls")
	var derived := Ship.from_data(legacy)
	root.add_child(derived)
	_check(derived.walls.size() == derived.blocks.size(),
		"a wall-less legacy payload derives walls from the footprint (%d == %d blocks)"
			% [derived.walls.size(), derived.blocks.size()])
	_check(not derived.walls.has(Vector2i(2, 0)),
		"and so loses the ghost wall — proving walls-in-payload is load-bearing")

	s.queue_free()
	clone.queue_free()
	derived.queue_free()
	await process_frame


# --- Physics integration --------------------------------------------------

func _test_ship_climbs() -> void:
	_t("balloons maintain, they never propel (owner's rule)")
	# A wildly over-ballooned ship FLOATS — it does not rocket upward.
	# Buoyancy is clamped at neutral: capacity above weight is margin, not
	# thrust. Assist off, so nothing but raw physics is being tested.
	var s := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(0, -1): BlockDB.Type.GASBAG,
		Vector2i(1, -1): BlockDB.Type.GASBAG,
		Vector2i(-1, -1): BlockDB.Type.GASBAG,
	}, false)
	s.assist_enabled = false
	s.position = Vector2(0, -200)
	var start_y := s.position.y
	await _step(90)
	_check(absf(s.position.y - start_y) < 8.0,
		"three bags on one hull: floats in place (drifted %.1f px)" % (s.position.y - start_y))

	# And a deficit ship is doomed to fall — that stays real.
	var brick := _make_ship({
		Vector2i(0, 0): BlockDB.Type.BALLAST,
		Vector2i(1, 0): BlockDB.Type.BALLAST,
		Vector2i(0, -1): BlockDB.Type.GASBAG,
	}, false)
	brick.assist_enabled = false
	brick.position = Vector2(600, -200)
	await _step(60)
	_check(brick.linear_velocity.y > 50.0,
		"one bag on two ballast: doomed to fall (%.0f px/s down)" % brick.linear_velocity.y)
	s.queue_free()
	brick.queue_free()
	await process_frame


func _test_damage_cannot_strand_the_ship_airborne() -> void:
	_t("battle damage cannot leave a ship that can only go up")
	# The owner rammed off two hull blocks and could no longer descend: less
	# mass = more buoyant surplus, and the surplus crossed the lift props'
	# total down-authority. The starter must carry enough margin that losing
	# a handful of hull still leaves S functional.
	var s := _make_ship(_starter_ship(), false)
	s.position = Vector2(0, -5000)
	for cell in [Vector2i(4, -1), Vector2i(4, -2), Vector2i(4, -3), Vector2i(-5, 0)]:
		if s.has_block(cell):
			s.damage_cell(cell, 99999.0)
	await _step(10)

	s.thrust_input = Vector2(0.0, -1.0)
	await _step(90)
	_check(s.linear_velocity.y > 30.0,
		"after losing four blocks, S still descends (%.0f px/s down)" % s.linear_velocity.y)
	s.queue_free()
	await process_frame


func _test_hover_assist() -> void:
	_t("altitude hold: lift props trim buoyancy automatically")
	# The owner's complaint, twice: the ship drifts up with no input. The
	# props should do the buoyancy bookkeeping, not the player.
	# The starter floats free on its balloons: no drift, no power needed.
	var s := _make_ship(_starter_ship(), false)
	s.position = Vector2(0, -300)
	await _step(30)
	var y := s.position.y
	await _step(120)
	_check(absf(s.position.y - y) < 12.0,
		"the starter floats hands-off (drifted %.1f px in 2s)" % (s.position.y - y))

	# A deficit ship (two bags shot off) is held up by its lift props instead —
	# engaged, and drawing power for it.
	var cells := _starter_ship()
	var holed := {}
	var bags_removed := 0
	for cell in cells:
		if cells[cell] == BlockDB.Type.GASBAG and bags_removed < 2:
			bags_removed += 1
			continue
		holed[cell] = cells[cell]
	var deficit := _make_ship(holed, false)
	deficit.position = Vector2(600, -300)
	await _step(30)
	var dy := deficit.position.y
	await _step(120)
	_check(absf(deficit.position.y - dy) < 14.0,
		"a holed envelope: the props hold the ship up (drifted %.1f px)" % (deficit.position.y - dy))
	_check(deficit._hover_engaged, "the lift props are doing the work")
	_check_approx(deficit.active_draw(), 2300.0, 0.01,
		"and drawing power for it (props 1800 + turret scan 500)")

	# Hover is earned: a deficit ship without engines is doomed to fall.
	# One MORE bag gone than the holed variant — losing the engines also
	# sheds their mass, which nearly cancels a two-bag hole against the
	# starter's canopy margin (this beat once passed by 2 px/s).
	var stripped := {}
	var bags_gone := 0
	for cell in cells:
		if cells[cell] == BlockDB.Type.GASBAG and bags_gone < 3:
			bags_gone += 1
			continue
		if cells[cell] == BlockDB.Type.ENGINE:
			continue
		stripped[cell] = cells[cell]
	var dead := _make_ship(stripped, false)
	dead.position = Vector2(1200, -300)
	await _step(60)
	_check(dead.linear_velocity.y > 10.0,
		"without engines the hold is powerless and the holed ship falls (%.0f px/s)"
			% dead.linear_velocity.y)

	s.queue_free()
	dead.queue_free()
	await process_frame


func _test_heavy_ship_sinks() -> void:
	_t("a ship with weight > lift sinks")
	var cells := _starter_ship()
	for x in range(-4, 5):
		cells[Vector2i(x, 1)] = BlockDB.Type.BALLAST  # bolt on a lot of dead weight
	var s := _make_ship(cells, false)
	s.position = Vector2(0, -200)
	_check(s.lift_ratio() < 1.0, "lift ratio below 1 (%.2f)" % s.lift_ratio())
	var start_y := s.position.y
	await _step(60)
	_check(s.position.y > start_y, "ballasted ship lost altitude")
	s.queue_free()
	await process_frame


func _test_ships_stay_upright_always() -> void:
	_t("the upright rule: every ship stays level, regardless of configuration")
	# Owner spec (2026-08-20, source fidelity): the original never banks or
	# tumbles. lock_rotation makes uprightness unconditional — no helm
	# required, no configuration exempt, one block no less than a warship.
	# This replaced the earned PD assist and gasbag self-righting outright.
	var one := _make_ship({Vector2i(0, 0): BlockDB.Type.HULL}, false)
	one.gravity_scale = 0.0
	one.position = Vector2(-900, 0)
	var lop := _make_ship({
		# Deliberately lopsided: heavy ballast far off-axis under one gasbag
		# corner — everything about this build begs to pivot.
		Vector2i(-3, 1): BlockDB.Type.BALLAST,
		Vector2i(-3, 0): BlockDB.Type.HULL,
		Vector2i(-2, 0): BlockDB.Type.HULL,
		Vector2i(-1, 0): BlockDB.Type.HULL,
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(0, -1): BlockDB.Type.GASBAG,
	}, false)
	lop.position = Vector2(900, 0)

	for i in 90:
		one.apply_torque(500.0)
		lop.apply_torque(200000.0)
		await physics_frame

	_check(absf(one.rotation) < 0.001 and absf(one.angular_velocity) < 0.001,
		"even a single block cannot be rotated (%.4f rad)" % one.rotation)
	_check(absf(lop.rotation) < 0.001,
		"a lopsided helmless hull under raw torque stays level (%.4f rad)" % lop.rotation)
	_check(absf(wrapf(lop.rotation, -PI, PI)) < 0.001 and lop.lock_rotation,
		"uprightness is the solver's lock, not a tuned controller")

	one.queue_free()
	lop.queue_free()
	await process_frame


# --- The sky (WORLD_SPEC.md) ------------------------------------------------

## Test-world extents: x -10,000..10,000, ceiling -20,000, floor 0.
## Fractions used below assume this shape; the model itself is
## fraction-based, so any bounds would do.
const SKY_TEST_BOUNDS := Rect2(-10000, -20000, 20000, 20000)


func _test_sky_bands_and_winds() -> void:
	_t("airspace bands and the wind circulation cell")

	# Inactive by default: the Sprint-1 arena must feel no weather.
	_check(not Airspace.active(), "airspace is inactive until a world sets bounds")
	_check(Airspace.wind_at(Vector2(0, -1000)) == Vector2.ZERO,
		"no wind while inactive")
	_check(Airspace.band_at(Vector2(0, -1000)) == Airspace.Band.NONE,
		"no band while inactive")

	Airspace.bounds = SKY_TEST_BOUNDS
	# x=3000 is fx 0.65: clear of the centre column and both edges.
	_check(Airspace.band_at(Vector2(3000, -500)) == Airspace.Band.LAVA, "floor band is lava")
	_check(Airspace.band_at(Vector2(3000, -4000)) == Airspace.Band.DEEP, "low altitude is the deep band")
	_check(Airspace.band_at(Vector2(3000, -7500)) == Airspace.Band.GAP_LOW, "deep/mid gap where expected")
	_check(Airspace.band_at(Vector2(3000, -10000)) == Airspace.Band.MID, "mid band at half height")
	_check(Airspace.band_at(Vector2(3000, -13000)) == Airspace.Band.GAP_HIGH, "mid/top gap where expected")
	_check(Airspace.band_at(Vector2(3000, -16000)) == Airspace.Band.TOP, "high altitude is the top band")

	# Two stacked convection cells (owner 2026-08-23): centre UP, edges DOWN, and
	# four horizontal DIVIDER rows alternating out/in — ceiling OUTWARD, blue/green
	# gap INWARD, green/red gap OUTWARD [OURS], floor INWARD. Band interiors are
	# calm. (SKY_TEST_BOUNDS spans y -20000..0; y=-13000 is the GAP_HIGH gap and
	# y=-7400 the GAP_LOW gap; the top row is y<=-18800 and the bottom row y>=-1200.)
	_check(Airspace.wind_at(Vector2(0, -10000)).y < 0.0, "centre column blows up")
	_check(Airspace.wind_at(Vector2(-9800, -10000)).y > 0.0, "west edge blows down")
	_check(Airspace.wind_at(Vector2(9800, -10000)).y > 0.0, "east edge blows down")
	_check(Airspace.wind_at(Vector2(3000, -19400)).x > 0.0, "ceiling east of centre blows outward")
	_check(Airspace.wind_at(Vector2(-3000, -19400)).x < 0.0, "ceiling west of centre blows outward")
	_check(Airspace.wind_at(Vector2(3000, -13000)).x < 0.0, "blue/green gap east of centre blows INWARD")
	_check(Airspace.wind_at(Vector2(-3000, -13000)).x > 0.0, "blue/green gap west of centre blows INWARD")
	_check(Airspace.wind_at(Vector2(3000, -7400)).x > 0.0, "green/red gap east of centre blows OUTWARD [OURS]")
	_check(Airspace.wind_at(Vector2(-3000, -7400)).x < 0.0, "green/red gap west of centre blows OUTWARD [OURS]")
	_check(Airspace.wind_at(Vector2(3000, -600)).x < 0.0, "floor east of centre blows inward")
	_check(Airspace.wind_at(Vector2(-3000, -600)).x > 0.0, "floor west of centre blows inward")
	_check(Airspace.wind_at(Vector2(3000, -10000)) == Vector2.ZERO, "the mid-band interior is calm")
	_check(Airspace.wind_at(Vector2(3000, -4000)) == Vector2.ZERO, "the deep-band interior is calm")
	_check(Airspace.wind_at(Vector2(3000, -16000)) == Vector2.ZERO, "the top-band interior is calm")

	# Owner: things are lighter up top, ~10%. Everywhere else is normal.
	_check_approx(Airspace.gravity_scale_at(Vector2(3000, -16000)), Airspace.TOP_GRAVITY, 0.001,
		"top band lightens gravity")
	_check_approx(Airspace.gravity_scale_at(Vector2(3000, -10000)), 1.0, 0.001,
		"mid band gravity is normal")

	Airspace.bounds = Rect2()


func _test_sky_moves_ships() -> void:
	_t("wind and the ceiling act on real hulls")
	Airspace.bounds = SKY_TEST_BOUNDS

	# A neutrally-buoyant ship (buoyancy clamps at neutral, so an
	# over-ballooned build floats exactly) parked in the BOTTOM connector row
	# drifts toward the centre column — a dead ship travels with the inward wind.
	var adrift := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(0, -1): BlockDB.Type.GASBAG,
		Vector2i(1, -1): BlockDB.Type.GASBAG,
		Vector2i(-1, -1): BlockDB.Type.GASBAG,
	}, false)
	adrift.assist_enabled = false
	adrift.position = Vector2(3000, -700)  # bottom row, east side → inward (−x)
	await _step(120)
	_check(adrift.position.x < 3000.0 - 40.0,
		"bottom-row wind carries an adrift ship toward the centre (drifted %.0f px)"
			% (adrift.position.x - 3000.0))
	adrift.queue_free()

	# The same floater in calm mid-band air stays put — wind is a property
	# of place, not a global current.
	var parked := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(0, -1): BlockDB.Type.GASBAG,
		Vector2i(1, -1): BlockDB.Type.GASBAG,
		Vector2i(-1, -1): BlockDB.Type.GASBAG,
	}, false)
	parked.assist_enabled = false
	parked.position = Vector2(6000, -10000)  # mid band interior, clear of columns
	await _step(120)
	_check(absf(parked.position.x - 6000.0) < 8.0 and absf(parked.position.y + 10000.0) < 8.0,
		"calm air holds a floater in place (drifted %.0f, %.0f px)"
			% [parked.position.x - 6000.0, parked.position.y + 10000.0])
	parked.queue_free()

	# The hard ceiling: a hull thrown upward stops without damage and
	# without bouncing — the sky simply ends (owner spec).
	var climber := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(0, -1): BlockDB.Type.GASBAG,
		Vector2i(1, -1): BlockDB.Type.GASBAG,
		Vector2i(-1, -1): BlockDB.Type.GASBAG,
	}, false)
	climber.assist_enabled = false
	climber.position = Vector2(6000, Airspace.ceiling_y() + 300.0)
	climber.linear_velocity = Vector2(0, -400)
	var hp_before: int = climber.blocks[Vector2i(0, 0)]["hp"]
	await _step(120)
	_check(climber.position.y >= Airspace.ceiling_y() - 8.0,
		"the ceiling stops upward travel (y=%.0f, ceiling=%.0f)"
			% [climber.position.y, Airspace.ceiling_y()])
	var hp_after: int = climber.blocks[Vector2i(0, 0)]["hp"]
	_check(hp_after == hp_before, "and costs no damage")
	climber.queue_free()

	Airspace.bounds = Rect2()
	await process_frame


## Owner: "the engines should NOT try to maintain a ship stationary if
## they're being pushed — how do they know where x,y exactly is?" The
## altitude hold damps drift relative to the AIR, so a hovering ship rides
## a wind stream instead of station-keeping against it.
func _test_hover_rides_the_wind() -> void:
	_t("altitude hold references the air, not the world")
	Airspace.bounds = SKY_TEST_BOUNDS

	# Engine + hung vertical prop + one gasbag: a lift deficit the hover
	# props can cover — the standard altitude-hold configuration.
	var hover_cells := {
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.ENGINE,
		Vector2i(0, -1): BlockDB.Type.GASBAG,
		Vector2i(0, 1): BlockDB.Type.PROPELLER,
	}

	# In calm air the hover holds altitude (the existing guarantee).
	var calm := _make_ship(hover_cells.duplicate(), false)
	calm.position = Vector2(6000, -10000)  # mid band interior, no wind
	await _step(120)
	_check(absf(calm.position.y + 10000.0) < 30.0,
		"calm air: hover holds altitude (drifted %.0f px)" % (calm.position.y + 10000.0))
	calm.queue_free()

	# In the centre updraft the same ship is carried UP — the hover damps
	# drift relative to the moving air and never fights the stream.
	var carried := _make_ship(hover_cells.duplicate(), false)
	carried.position = Vector2(0, -10000)  # centre column, wind straight up
	await _step(120)
	_check(carried.position.y < -10100.0,
		"updraft: the hover rides the wind up (rose %.0f px)" % -(carried.position.y + 10000.0))
	carried.queue_free()

	Airspace.bounds = Rect2()
	await process_frame


## The world-scale experiment blows blueprints up s×; semantics that are
## per-storey (platforms) must not multiply into s-deep stacks.
func _test_blueprint_upscaling() -> void:
	_t("blueprint upscaling preserves shape and hatch semantics")
	var cells := {
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.PLATFORM,
		Vector2i(0, -1): BlockDB.Type.GASBAG,
	}
	var up := ShipLayout.upscale_cells(cells, 4)
	var hulls := 0
	var planks := 0
	var bags := 0
	for cell in up:
		match up[cell]:
			BlockDB.Type.HULL: hulls += 1
			BlockDB.Type.PLATFORM: planks += 1
			BlockDB.Type.GASBAG: bags += 1
	_check(hulls == 16, "a hull cell becomes a 4x4 slab (%d)" % hulls)
	_check(bags == 16, "a gasbag cell becomes a 4x4 slab (%d)" % bags)
	_check(planks == 4, "a platform stays ONE row — a hatch per storey, not a stack (%d)" % planks)
	_check(up.has(Vector2i(4, 0)) and up[Vector2i(4, 0)] == BlockDB.Type.PLATFORM,
		"the plank row sits at the top of its old cell")
	_check(not up.has(Vector2i(4, 1)),
		"and nothing fills the rows beneath it")
	_check(up.has(Vector2i(0, -4)) and up[Vector2i(0, -4)] == BlockDB.Type.GASBAG,
		"cells land at position × scale")
	_check(ShipLayout.upscale_cells(cells, 1) == cells, "scale 1 is the identity")

	# The REAL starter is authored native-8× (true component footprints,
	# no upscale in its spawn path). Gate the file: near-neutral trim at
	# scale is the load-bearing property everything else assumes.
	var starter := ShipLayout.load_cells("res://ships/starter.ship")
	var s := _make_ship(starter)
	s.scale_unit = 8.0
	var ratio := s.lift_ratio()
	_check(ratio > 0.95 and ratio < 1.4,
		"the native-8x starter keeps its capacity margin (ratio %.2f)" % ratio)
	_check(s.blocks.size() > 2000,
		"and is authored at 8x granularity (%d cells)" % s.blocks.size())
	_check(s.has_helm(), "with its control panel aboard")
	s.queue_free()
	await process_frame


## Regression for the owner's "can't move up or down at 8×": under the old
## per-cell axis rule, every interior cell of an upscaled prop slab saw
## prop neighbours to its sides and the whole slab derived horizontal —
## zero lift props. The axis must come from the MOUNTING (non-prop blocks).
func _test_upscaled_props_keep_their_axis() -> void:
	_t("propeller slabs derive their axis from the mounting")
	# One prop hung beneath a hull: vertical at 1×...
	var hung := {
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(0, 1): BlockDB.Type.PROPELLER,
	}
	var small := _make_ship(hung)
	_check(small._vertical_props.size() == 1, "a single hung prop is vertical")
	small.queue_free()

	# ...and still vertical as an 8×8 slab hung beneath a hull slab.
	var big := _make_ship(ShipLayout.upscale_cells(hung, 8))
	_check(big._vertical_props.size() == 64,
		"an 8× hung prop slab is entirely vertical (%d of 64)" % big._vertical_props.size())
	big.queue_free()

	# A side-mounted slab stays horizontal.
	var pusher := _make_ship(ShipLayout.upscale_cells({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.PROPELLER,
	}, 8))
	_check(pusher._vertical_props.is_empty(), "an 8× side-mounted slab is horizontal")
	pusher.queue_free()
	await process_frame


## The scale unit's whole contract: the same ship, 8× bigger in an 8×
## world, crosses 8× the distance in the same time — feel is preserved.
## The 8× ship is authored at TRUE component footprints (engine 4×4,
## prop 6×2 — WORLD_SPEC.md), which is what the normalisation contract
## promises to keep feel-equivalent: bulk cells scale as slabs, while a
## component's mass and output are its rating at the scale, independent
## of the smaller footprint.
func _test_scale_unit_preserves_feel() -> void:
	_t("scale_unit preserves flight feel across world scales")
	var cells := {
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.ENGINE,
		Vector2i(2, 0): BlockDB.Type.PROPELLER,
	}

	var one := _make_ship(cells)
	one.position = Vector2(0, -1000)
	one.thrust_input.x = 1.0
	await _step(60)
	var dx1 := one.position.x
	one.queue_free()

	# Hull cell → 8×8 bulk slab; engine → 4×4; side-mounted prop → 6×2.
	var big := ShipLayout.upscale_cells({Vector2i(0, 0): BlockDB.Type.HULL}, 8)
	for y in 4:
		for x in 4:
			big[Vector2i(8 + x, y)] = BlockDB.Type.ENGINE
	for y in 2:
		for x in 6:
			big[Vector2i(12 + x, y)] = BlockDB.Type.PROPELLER
	var eight := _make_ship(big)
	eight.scale_unit = 8.0
	eight.position = Vector2(0, -1000)
	eight.thrust_input.x = 1.0
	await _step(60)
	var dx8 := eight.position.x
	eight.queue_free()
	await process_frame

	_check(dx1 > 10.0, "the 1× ship moves under throttle (%.0f px)" % dx1)
	var ratio := dx8 / dx1 if dx1 > 0.0 else 0.0
	_check(ratio > 6.8 and ratio < 9.2,
		"the 8× ship covers 8× the distance in the same time (ratio %.2f)" % ratio)


## Owner: named components (E, H, D, P, T…) are destroyed as a whole —
## damage to any of their cells is damage to every cell. Raw blocks stay
## per-cell.
func _test_components_die_as_a_whole() -> void:
	_t("components take damage as a unit, raw blocks per cell")
	var s := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.HULL,
		Vector2i(0, -1): BlockDB.Type.ENGINE,
		Vector2i(1, -1): BlockDB.Type.ENGINE,
		Vector2i(0, -2): BlockDB.Type.ENGINE,
		Vector2i(1, -2): BlockDB.Type.ENGINE,
	})

	# Hit ONE engine cell: every engine cell shares the wound.
	s.damage_cell(Vector2i(0, -1), 30.0)
	for c in [Vector2i(0, -1), Vector2i(1, -1), Vector2i(0, -2), Vector2i(1, -2)]:
		_check_approx(s.blocks[c]["hp"], 50.0, 0.01,
			"engine cell %s shares the component's damage" % c)
	_check_approx(s.blocks[Vector2i(0, 0)]["hp"], 100.0, 0.01,
		"the hull under it is untouched")

	# Finish the engine: the whole 2×2 dies at once, the hull survives.
	s.damage_cell(Vector2i(1, -2), 50.0)
	_check(not s.has_block(Vector2i(0, -1)) and not s.has_block(Vector2i(1, -1)),
		"lethal damage removes the whole component")
	_check(s.has_block(Vector2i(0, 0)) and s.has_block(Vector2i(1, 0)),
		"raw hull remains, damaged individually or not at all")

	# Raw blocks keep per-cell damage.
	s.damage_cell(Vector2i(0, 0), 25.0)
	_check_approx(s.blocks[Vector2i(0, 0)]["hp"], 75.0, 0.01, "hull cell takes its own hit")
	_check_approx(s.blocks[Vector2i(1, 0)]["hp"], 100.0, 0.01, "its neighbour does not")
	s.queue_free()

	# Balloons are units too (owner): adjacent gasbags share their wound.
	var b := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(0, -1): BlockDB.Type.GASBAG,
		Vector2i(1, -1): BlockDB.Type.GASBAG,
	})
	b.damage_cell(Vector2i(0, -1), 10.0)
	_check_approx(b.blocks[Vector2i(1, -1)]["hp"], 25.0, 0.01,
		"a balloon damages as one unit, like P(H)/P(V)")
	b.queue_free()
	await process_frame


## Owner: same-faction infrastructure STOPS a shot but never takes damage
## from it — you cannot shoot through everything, and you can never hurt
## your own side. Hostile hulls take the hit.
func _test_shots_respect_factions() -> void:
	_t("shots are blocked harmlessly by friends and damage foes")
	var friend := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(0, -1): BlockDB.Type.HULL,
	})
	friend.position = Vector2(200, -5000)
	friend.faction = 0

	var foe := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(0, -1): BlockDB.Type.HULL,
	})
	foe.position = Vector2(420, -5000)
	foe.faction = 1

	# A player-side shot fired at the foe THROUGH the friendly hull: the
	# friend blocks it, takes nothing, and the foe behind is never touched.
	var blocked := Shot.new()
	blocked.position = Vector2(0, -5000)
	blocked.velocity = Vector2(900, 0)
	blocked.faction = 0
	blocked.damage = 30.0
	root.add_child(blocked)
	await _step(45)

	_check(friend.blocks[Vector2i(0, 0)]["hp"] == 100.0
		and friend.blocks[Vector2i(0, -1)]["hp"] == 100.0,
		"the friendly hull that stopped the shot is untouched")
	var foe_untouched := true
	for c in foe.blocks:
		if foe.blocks[c]["hp"] < 100.0:
			foe_untouched = false
	_check(foe_untouched, "and the foe behind it was never reached")
	_check(not is_instance_valid(blocked) or blocked.is_queued_for_deletion(),
		"the blocked shot is gone, not flying on")

	# A clear line to the foe: the hit lands.
	var clean := Shot.new()
	clean.position = Vector2(320, -5000)
	clean.velocity = Vector2(900, 0)
	clean.faction = 0
	clean.damage = 30.0
	root.add_child(clean)
	await _step(30)

	var foe_hit := false
	for c in foe.blocks:
		if foe.blocks[c]["hp"] < 100.0:
			foe_hit = true
	_check(foe_hit, "with a clear line, the hostile hull takes the hit")

	friend.queue_free()
	foe.queue_free()
	await process_frame


## Owner report: an 8× ship sinking onto the floor left its underside
## unmarked. Full unit³ damage normalisation meant a crash crunched the
## same NUMBER of cells at any scale — but cells shrink relative to the
## world, so the dent became invisible. The conversion now divides by
## unit² only: the same relative crash bites proportionally deeper.
func _test_crash_bite_scales_with_the_world() -> void:
	_t("a crash bites the same relative dent at any scale")
	var floor_body := StaticBody2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(4000, 100)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	floor_body.position = Vector2(0, -3000)
	floor_body.add_child(cs)
	root.add_child(floor_body)

	var cells := {}
	for y in 4:
		cells[Vector2i(0, -y)] = BlockDB.Type.HULL  # a 1×4 column

	var one := _make_ship(cells)
	one.assist_enabled = false
	one.position = Vector2(-500, -3200)
	one.linear_velocity = Vector2(0, 900)
	var before1 := one.blocks.size()
	await _step(40)
	var lost1 := before1 - one.blocks.size()
	one.queue_free()

	var two := _make_ship(ShipLayout.upscale_cells(cells, 2))
	two.scale_unit = 2.0
	two.assist_enabled = false
	two.position = Vector2(500, -3400)
	two.linear_velocity = Vector2(0, 1800)  # the same crash, 2× world speed
	var before2 := two.blocks.size()
	await _step(40)
	var lost2 := before2 - two.blocks.size()
	two.queue_free()
	floor_body.queue_free()
	await process_frame

	_check(lost1 >= 1, "the 1× crash crunches blocks (%d)" % lost1)
	_check(lost2 > lost1,
		"the equivalent 2× crash crunches deeper in cells (%d > %d)" % [lost2, lost1])


## Owner spec (from the original's model): the wall layer holds the ship
## together. Combat destroys blocking tiles but can never sever the ship
## or touch its blueprint; pieces only come off when walls themselves are
## removed (deconstruction/mining).
func _test_walls_hold_the_ship_together() -> void:
	_t("walls keep integrity: combat cannot sever, deconstruction can")
	var s := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HELM,
		Vector2i(1, 0): BlockDB.Type.HULL,
		Vector2i(2, 0): BlockDB.Type.HULL,
		Vector2i(3, 0): BlockDB.Type.HULL,
	})
	var pieces: Array = []
	s.severed.connect(func(p: Ship) -> void: pieces.append(p))

	# Shoot the joint out: the block dies, the wall stands, the ship holds.
	s.damage_cell(Vector2i(1, 0), 99999.0)
	_check(not s.has_block(Vector2i(1, 0)), "the joint block is destroyed")
	_check(pieces.is_empty(), "but the ship does NOT sever — the wall holds it")
	_check(s.blocks.size() == 3, "the far side stays aboard (%d blocks)" % s.blocks.size())

	# Deconstruct the WALL at the ghost cell: now the tail comes off.
	s.remove_block(Vector2i(1, 0))
	_check(pieces.size() == 1, "removing the wall severs the tail")
	if pieces.size() == 1:
		_check(pieces[0].blocks.size() == 2, "wreckage carries the 2 tail blocks")

	await process_frame
	s.queue_free()
	for p in pieces:
		if is_instance_valid(p):
			p.queue_free()
	await process_frame


## A turret bears on the 180° half-plane away from its mounting (owner;
## the original's arc): hung guns fire down, wall guns fire outboard.
func _test_turret_arcs_derive_from_mounting() -> void:
	_t("turret arcs derive from the mounting")
	var hung := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(0, 1): BlockDB.Type.TURRET,
	})
	_check(_turret_facing(hung).y > 0.9, "a hung turret bears downward")
	hung.queue_free()

	var wall_gun := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.TURRET,
	})
	_check(_turret_facing(wall_gun).x > 0.9, "a wall-mounted turret bears outboard")
	wall_gun.queue_free()

	# Mounted against a wall on its left AND a ceiling above: the open
	# side is down-right, so the arc centre averages to that diagonal.
	var corner := _make_ship({
		Vector2i(1, 0): BlockDB.Type.HULL,
		Vector2i(0, 1): BlockDB.Type.HULL,
		Vector2i(1, 1): BlockDB.Type.TURRET,
	})
	var f := _turret_facing(corner)
	_check(f.x > 0.4 and f.y > 0.4, "a corner mount averages to the open diagonal (%s)" % f)
	corner.queue_free()
	await process_frame


func _turret_facing(s: Ship) -> Vector2:
	for cluster in s._glyph_clusters:
		if cluster["key"] == "T":
			return cluster["facing"]
	return Vector2.ZERO


## Owner spec: ships are controllable ONLY through a standing control
## panel. The panel is furniture (bodies pass, bullets don't), and when it
## is shot away the ship coasts until repair rebuilds it.
func _test_helm_is_the_seat_of_control() -> void:
	_t("the control panel is furniture, and control dies with it")
	var s := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(1, 0): BlockDB.Type.HELM,
		Vector2i(2, 0): BlockDB.Type.HULL,
		Vector2i(1, -1): BlockDB.Type.ENGINE,
	})
	# Three SOLID blocks (two hulls + the engine) collide; the helm adds
	# nothing to the body collider.
	_check(_shape_count(s) == 3,
		"the helm has no body collider — walk-through furniture (%d shapes)" % _shape_count(s))
	var shield: Node = null
	for child in s.get_children():
		if child.name.begins_with("Shield"):
			shield = child
	_check(shield != null, "but it carries a bullet-blocking shield body")
	if shield != null:
		_check((shield as AnimatableBody2D).get_collision_layer_value(4),
			"on layer 4, where only shots look")

	s.net_set_controls(1.0, 0.0)
	_check(s.thrust_input.x == 1.0, "with a panel, controls are accepted")
	s.damage_cell(Vector2i(1, 0), 999.0)
	_check(not s.has_helm(), "the panel is destroyed")
	_check(s.thrust_input == Vector2.ZERO, "held input dies with the panel")
	s.net_set_controls(1.0, 0.0)
	_check(s.thrust_input == Vector2.ZERO, "and new control input is refused")

	# The way back: the repair wand rebuilds the panel from the blueprint.
	var restored := false
	for i in 40:
		s.repair_near(Vector2i(1, 0), 20.0)
		if s.has_helm():
			restored = true
			break
	_check(restored, "sweeping repair rebuilds the panel")
	s.net_set_controls(0.0, 1.0)
	_check(s.thrust_input.y == 1.0, "and the ship answers the helm again")
	s.queue_free()
	await process_frame


func _test_blueprint_follows_construction() -> void:
	_t("the blueprint follows construction, never combat")
	var s := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HELM,
		Vector2i(1, 0): BlockDB.Type.HULL,
	})
	s.set_block(Vector2i(2, 0), BlockDB.Type.HULL)
	_check(s.blueprint_map().has(Vector2i(2, 0)), "placing a block extends the blueprint")

	s.damage_cell(Vector2i(2, 0), 999.0)
	_check(s.blueprint_map().has(Vector2i(2, 0)), "combat cannot edit the blueprint")
	_check(s.repair_cell(Vector2i(2, 0), 999.0), "so repair can rebuild the built block")

	s.remove_block(Vector2i(2, 0))
	_check(not s.blueprint_map().has(Vector2i(2, 0)), "deconstruction shrinks the blueprint")
	_check(not s.repair_cell(Vector2i(2, 0), 999.0), "and repair honours that")
	s.queue_free()
	await process_frame


## The build ghost's readout is only worth showing if it is the TRUTH: the
## number the player reads while hovering has to be the number the ship
## reports the instant they commit. So the preview is checked against an
## actual placement, at both world granularities — component mass is
## footprint-normalised, and a preview that forgot that would quietly
## understate an engine by 4× at the shipped 8× scale.
func _test_build_preview_predicts_the_placement() -> void:
	_t("the build preview predicts exactly what placing would do")
	var s := _make_ship(_starter_ship())
	var free_cell := Vector2i(0, -5)  # empty air directly above the gasbag row
	_check(s.can_place_at(free_cell), "the test cell is a legal placement")

	var before := s.lift_ratio()
	var blocks_before := s.blocks.size()
	var predicted := BuildPreview.ratio_with(s, BlockDB.Type.ENGINE)
	_check(s.blocks.size() == blocks_before and is_equal_approx(s.lift_ratio(), before),
		"previewing mutates nothing — no block, no mass change")
	_check(predicted < before, "an engine is dead weight: the ratio drops")
	_check(BuildPreview.ratio_with(s, BlockDB.Type.GASBAG) > before,
		"a gasbag lifts more than it weighs: the ratio rises")

	s.set_block(free_cell, BlockDB.Type.ENGINE)
	_check_approx(s.lift_ratio(), predicted, 0.0001,
		"placing the engine lands on the predicted ratio")
	s.queue_free()

	# Same promise at the shipped scale, where an engine cell carries a
	# whole engine's rated mass rather than a slab cell's share.
	var big := _make_ship(_starter_ship())
	big.scale_unit = 8.0
	var big_predicted := BuildPreview.ratio_with(big, BlockDB.Type.ENGINE)
	big.set_block(free_cell, BlockDB.Type.ENGINE)
	_check_approx(big.lift_ratio(), big_predicted, 0.0001,
		"and at 8x, where component mass normalises by footprint")
	big.queue_free()

	# The pure arithmetic behind it, independent of any ship.
	_check_approx(BuildPreview.ratio_of(1.0, BlockDB.LIFT_PER_MASS / 980.0, 1.0),
		1.0, 0.0001, "one unit of lift holds up exactly its own mass rating")
	_check_approx(BuildPreview.ratio_of(10.0, 5.0, 0.0), 0.0, 0.0001,
		"no air, no lift")
	_check_approx(BuildPreview.ratio_of(10.0, 0.0, 1.0), 0.0, 0.0001,
		"a weightless ship reports 0 rather than dividing by zero")
	_check(BuildPreview.readout(1.29, 1.27) == "lift 1.29 -> 1.27",
		"the readout reads as before -> after at a glance")
	await process_frame


# --- Terrain (Sprint 2: chunked, resident, destructible) ------------------

## A resident Terrain in the tree. scale_unit defaults to 1 so the tests reason
## in plain 16px cells / 512px chunks.
func _make_terrain(scale := 1.0) -> Terrain:
	var t := Terrain.new()
	t.scale_unit = scale
	root.add_child(t)
	return t


## Centre of chunk (cx, cy) in world px, for aiming a focus at a chunk.
func _chunk_centre(t: Terrain, cx: int, cy: int) -> Vector2:
	var cp := t.chunk_px()
	return Vector2((cx + 0.5) * cp, (cy + 0.5) * cp)


func _test_terrain_far_chunk_is_inert() -> void:
	_t("a chunk far from every focus is pure data — zero live nodes")
	var t := _make_terrain()
	# An 8×8 solid slab entirely inside chunk (0,0): cells (2..9, 2..9) = 64.
	t.fill_rect(Rect2i(2, 2, 8, 8), TerrainDB.Type.STONE)
	_check(t.solid_cells_in_chunk(Vector2i(0, 0)) == 64,
		"the resident data holds 64 solid cells in chunk (0,0)")

	# Focus 20 chunks away: the terrain chunk stays inert — no node, no collider.
	t.update_streaming([_chunk_centre(t, 20, 20)])
	_check(t.live_chunk_count() == 0, "far from any focus, nothing is promoted")
	_check(not t.is_promoted(Vector2i(0, 0)),
		"the chunk holding terrain is inert — data only, no live node")
	_check(t.get_child_count() == 0, "and it owns no child nodes at all")

	# Bring a focus onto the chunk: it promotes, and the greedy-merged collider
	# covers EXACTLY the solid cells (a solid slab → one merged rect → 64 cells).
	t.update_streaming([_chunk_centre(t, 0, 0)])
	_check(t.is_promoted(Vector2i(0, 0)), "a focus on the chunk promotes it")
	var chunk := t.promoted_chunk(Vector2i(0, 0))
	_check(chunk != null and chunk is StaticBody2D,
		"the promoted chunk is a StaticBody2D (terrain is static, layer 1)")
	if chunk != null:
		_check(chunk.collision_layer == 1,
			"on collision layer 1 like ships/terrain (DECISIONS)")
		_check(chunk.collider_cell_count() == 64,
			"its merged collider covers exactly the 64 solid cells (%d)"
				% chunk.collider_cell_count())
		_check(chunk.get_child_count() == 1,
			"a solid 8×8 slab is ONE greedy-merged shape, not 64 (%d)"
				% chunk.get_child_count())

	t.queue_free()
	await process_frame


func _test_terrain_promotes_and_demotes_with_hysteresis() -> void:
	_t("a moving probe promotes then demotes chunks — with hysteresis, no thrash")
	var t := _make_terrain()
	t.fill_rect(Rect2i(2, 2, 8, 8), TerrainDB.Type.STONE)
	var truth := t.total_solid_cells()
	_check(truth == 64, "resident data starts at 64 solid cells")

	# Distance 3 chunks > PROMOTE_RADIUS (2): not promoted yet.
	t.update_streaming([_chunk_centre(t, 3, 0)])
	_check(not t.is_promoted(Vector2i(0, 0)),
		"outside the promote radius (3 > %d chunks) it stays inert"
			% Terrain.PROMOTE_RADIUS)

	# Distance 2 == PROMOTE_RADIUS: promotes.
	t.update_streaming([_chunk_centre(t, 2, 0)])
	_check(t.is_promoted(Vector2i(0, 0)),
		"crossing into the promote radius (%d chunks) promotes it"
			% Terrain.PROMOTE_RADIUS)

	# Back out to distance 3: still within DEMOTE_RADIUS (3), so it HOLDS — this
	# is the hysteresis that stops a boundary-hovering focus thrashing.
	t.update_streaming([_chunk_centre(t, 3, 0)])
	_check(t.is_promoted(Vector2i(0, 0)),
		"backing to distance 3 (<= demote radius %d) HOLDS it promoted — hysteresis"
			% Terrain.DEMOTE_RADIUS)

	# Distance 4 > DEMOTE_RADIUS: now it demotes.
	t.update_streaming([_chunk_centre(t, 4, 0)])
	_check(not t.is_promoted(Vector2i(0, 0)),
		"past the demote radius it finally demotes")

	# Through every promote/demote the resident data — the truth — never moved.
	_check(t.total_solid_cells() == truth,
		"promote/demote is a VIEW: the resident data is unchanged (%d)"
			% t.total_solid_cells())

	t.queue_free()
	await process_frame


## THE DIRTY BATCH (owner 2026-08-25, "considerable FPS drop from just moving
## slowly"): a promoted chunk used to rebuild — full rescan, greedy merge, every
## collision shape freed and recreated — PER CELL WRITTEN. A subdiv-4 scoop is
## 16 cells, a ram-mining whale digs a swath per frame, and reapply_all_edits
## replays every recorded edit after each lazy region: all rebuild storms. Edits
## now mark the chunk dirty and flush_rebuilds rebuilds it ONCE per frame.
func _test_terrain_edits_batch_into_one_rebuild_per_frame() -> void:
	_t("many terrain edits into one chunk cost ONE rebuild at the flush")
	var t := _make_terrain()
	t.fill_rect(Rect2i(0, 0, 12, 12), TerrainDB.Type.STONE)
	t.update_streaming([_chunk_centre(t, 0, 0)])
	var chunk := t.promoted_chunk(Vector2i(0, 0))
	_check(chunk != null, "the chunk promoted")
	var rb0: int = chunk.rebuild_count
	# A scoop-sized burst of writes — the storm case.
	for i in 16:
		t.set_cell(Vector2i(i % 4, 3 + i / 4), TerrainDB.Type.AIR)
	_check(chunk.rebuild_count == rb0,
		"16 writes trigger ZERO inline rebuilds (they mark the chunk dirty)")
	t.flush_rebuilds()
	_check(chunk.rebuild_count == rb0 + 1,
		"...and the flush pays exactly ONE (%d)" % (chunk.rebuild_count - rb0))
	_check(t.solid_cells_in_chunk(Vector2i(0, 0)) == chunk.collider_cell_count(),
		"after which the collider matches the data exactly")
	t.flush_rebuilds()
	_check(chunk.rebuild_count == rb0 + 1, "a clean flush is free — no dirty, no rebuild")
	t.queue_free()
	await _step(1)


func _test_terrain_dig_removes_cell_and_shrinks_collider() -> void:
	_t("dig removes a cell from data AND the collider, returns its type")
	var t := _make_terrain()
	t.fill_rect(Rect2i(2, 2, 8, 8), TerrainDB.Type.STONE)
	t.update_streaming([_chunk_centre(t, 0, 0)])
	var chunk := t.promoted_chunk(Vector2i(0, 0))
	_check(chunk != null and chunk.collider_cell_count() == 64,
		"before digging, the collider covers all 64 cells")

	# Dig one solid cell — the seam mining calls.
	var dug := t.dig(Vector2i(5, 5))
	_check(dug == TerrainDB.Type.STONE,
		"dig returns the removed cell's TYPE (for mining → item)")
	_check(t.cell_type(Vector2i(5, 5)) == TerrainDB.Type.AIR,
		"the cell is gone from the resident data")
	_check(not t.is_solid(Vector2i(5, 5)), "and reads as not solid")
	# The promoted chunk re-merged ON THE FLUSH (edits are batched per frame
	# since 2026-08-25 — the per-cell inline rebuild was the moving-FPS drop):
	# coverage shrinks by EXACTLY one cell.
	t.flush_rebuilds()
	_check(chunk.collider_cell_count() == 63,
		"the promoted collider shrank by exactly the dug cell (%d)"
			% chunk.collider_cell_count())
	_check(t.solid_cells_in_chunk(Vector2i(0, 0)) == 63,
		"and the resident data agrees (63)")

	# Digging air returns AIR and changes nothing.
	_check(t.dig(Vector2i(5, 5)) == TerrainDB.Type.AIR,
		"digging an already-empty cell returns AIR")
	t.flush_rebuilds()
	_check(chunk.collider_cell_count() == 63, "and touches nothing")

	# A re-promote reflects the dug hole (the data is the truth, not the node).
	t.update_streaming([_chunk_centre(t, 20, 0)])  # demote
	_check(not t.is_promoted(Vector2i(0, 0)), "demoted")
	t.update_streaming([_chunk_centre(t, 0, 0)])   # re-promote
	var fresh := t.promoted_chunk(Vector2i(0, 0))
	_check(fresh != null and fresh.collider_cell_count() == 63,
		"a fresh promote shows the hole — the dug cell stays gone (%d)"
			% (fresh.collider_cell_count() if fresh != null else -1))

	t.queue_free()
	await process_frame


## Terrain replication is unit-testable without two processes (task A): applying a
## broadcast edit to a Terrain mutates its grid + promoted chunk exactly as a
## peer would, and the join diff-sync (encode on the server, apply on a fresh
## client) reproduces the server's edits on top of an identical base. The
## two-process wire path is exercised by tests/net_smoke.gd.
func _test_terrain_edit_replication_applies_and_diffs() -> void:
	_t("a broadcast edit + a join diff-set apply onto a peer's terrain exactly")
	# The "server": a base slab, then two authoritative edits (single-player is
	# the authority, so net_dig/net_place mutate + record diffs directly).
	var server := _make_terrain()
	server.fill_rect(Rect2i(0, 0, 6, 4), TerrainDB.Type.STONE)  # 24-cell slab
	var dug := server.net_dig(Vector2i(1, 1), 1)
	_check(dug == TerrainDB.Type.STONE, "the server dug a solid cell")
	_check(server.net_place(Vector2i(0, 5), TerrainDB.Type.ORE, 1),
		"the server placed into an empty cell")
	_check(server.edit_diffs().size() == 2, "exactly two edits recorded as diffs")

	# A "peer" applying a single broadcast edit (Terrain._apply_edit is the RPC
	# body; called directly here it is the pure apply logic). Promote first so the
	# collider re-merge on apply is observable.
	var peer := _make_terrain()
	peer.fill_rect(Rect2i(0, 0, 6, 4), TerrainDB.Type.STONE)
	peer.update_streaming([_chunk_centre(peer, 0, 0)])
	var chunk := peer.promoted_chunk(Vector2i(0, 0))
	_check(chunk != null and chunk.collider_cell_count() == 24,
		"the peer starts with the full 24-cell collider")
	peer._apply_edit(Vector2i(1, 1), TerrainDB.Type.AIR)  # a broadcast dig
	_check(not peer.is_solid(Vector2i(1, 1)), "a broadcast dig removed the cell on the peer")
	peer.flush_rebuilds()  # the batched rebuild (one per frame in live play)
	_check(chunk.collider_cell_count() == 23,
		"and re-merged the promoted collider (24 → %d)" % chunk.collider_cell_count())
	_check(peer.edit_diffs().has(Vector2i(1, 1)),
		"the peer records the applied edit into its own diff set")

	# The late-join diff-sync: a FRESH client with only the base, catching up on
	# the whole server diff set, ends bit-identical to the server's grid.
	var joiner := _make_terrain()
	joiner.fill_rect(Rect2i(0, 0, 6, 4), TerrainDB.Type.STONE)
	joiner._receive_diffs(server._encode_diffs())  # the RPC body = the apply logic
	_check(not joiner.is_solid(Vector2i(1, 1)),
		"the joiner replayed the server's dig")
	_check(joiner.cell_type(Vector2i(0, 5)) == TerrainDB.Type.ORE,
		"and the server's placement")
	_check(joiner.total_solid_cells() == server.total_solid_cells(),
		"the joiner's grid matches the server exactly (%d == %d cells)"
			% [joiner.total_solid_cells(), server.total_solid_cells()])

	server.queue_free()
	peer.queue_free()
	joiner.queue_free()
	await process_frame


# --- Environmental hazards (maps/world/hazards.gd + hazard_fireball.gd) -----

## A Hazards node over the real (1×) world rect, the same rect world.gd frames
## from IslandGen.WORLD_CELLS. Band Y ranges follow Airspace's fractions.
func _make_hazards() -> Hazards:
	var h := Hazards.new()
	var wr := IslandGen.WORLD_CELLS
	var cp := 16.0
	h.world_rect = Rect2(Vector2(wr.position) * cp, Vector2(wr.size) * cp)
	h.scale_unit = 1.0
	# Seed the hazard RNG so the spawn-spread assertions are DETERMINISTIC. An
	# unseeded RandomNumberGenerator randomizes per run, and the broad-spread
	# checks (e.g. some meteor must land near the focus column) then failed about
	# 1 run in ~650 — a flaky green. A fixed seed makes green mean green.
	h._rng.seed = 20260822
	root.add_child(h)
	return h


func _hazard_count(h: Hazards) -> int:
	var n := 0
	for c in h.get_children():
		if c is HazardFireball:
			n += 1
	return n


func _test_hazards_gate_on_band() -> void:
	_t("hazards spawn only when a focus is in a hazard band — off-cost otherwise")
	# Foci as FRACTIONS of the live world rect (hard px broke when the world
	# went ×4 — altitude_frac = (end.y - y)/size.y). TOP band is frac >=
	# GAP_HIGH_TOP (0.68); the DEEP/floor gate is frac <= DEEP_TOP (0.34).
	var h := _make_hazards()
	var wr: Rect2 = h.world_rect
	var top := Vector2(0.0, wr.end.y - 0.85 * wr.size.y)  # deep inside TOP
	var mid := Vector2(0.0, wr.end.y - 0.50 * wr.size.y)  # home, mid-band
	var flr := Vector2(0.0, wr.end.y - 0.04 * wr.size.y)  # near the floor
	_check(h.any_in_top([top]) and not h.any_in_top([mid]),
		"the TOP-band gate reads true up top, false mid-band")
	_check(h.any_near_floor([flr]) and not h.any_near_floor([mid]),
		"the floor gate reads true near the floor, false mid-band")

	# Mid-band: step a full second — NOTHING spawns. This is the band gate AND the
	# off-cost early-out. Break-the-fix: remove the gate in Hazards.update (spawn
	# regardless of band) and this check fails.
	for i in 60:
		h.update(1.0 / 60.0, [mid])
	_check(_hazard_count(h) == 0,
		"a mid-band focus triggers NO hazards (%d)" % _hazard_count(h))

	# A focus up top spawns a meteor (cadence cd starts at 0 → first update fires).
	h.update(1.0 / 60.0, [top])
	_check(_hazard_count(h) >= 1, "a focus in the TOP band spawns a meteor")

	# A focus near the floor erupts a lava fireball.
	var h2 := _make_hazards()
	h2.update(1.0 / 60.0, [flr])
	_check(_hazard_count(h2) >= 1, "a focus near the floor erupts a lava fireball")

	# No foci at all: nothing runs, ever (off-cost).
	var h3 := _make_hazards()
	for i in 60:
		h3.update(1.0 / 60.0, [])
	_check(_hazard_count(h3) == 0, "no foci → no hazard activity at all (off-cost)")

	h.queue_free()
	h2.queue_free()
	h3.queue_free()
	await process_frame


func _test_meteors_are_broad_and_world_anchored() -> void:
	_t("meteors are a broad, world-anchored spread — never a fixed camera-radius ring")
	var h := _make_hazards()
	var focus := Vector2(1234.0, -13000.0)
	var xs: Array = []
	var all_above := true
	for i in 40:
		var fb := h.spawn_meteor(focus)
		xs.append(fb.position.x)
		if fb.position.y > focus.y - 1.0:
			all_above = false
	_check(all_above,
		"every meteor spawns ABOVE the focus — seen coming, never dropped on your head")

	# 1) BROAD: 40 spawns fan out across a wide world-X range, not a single point.
	var lo: float = xs.min()
	var hi: float = xs.max()
	_check(hi - lo > 1500.0,
		"the spawns span a wide world X range (%.0f px) — broad across the band" % (hi - lo))

	# 2) NOT a camera ring: a ring gives |x - focus.x| ≈ constant. Here the offsets
	#    range from near-zero to the full spread — some meteors fall in your own
	#    column, others far to the side.
	var offsets: Array = []
	for x in xs:
		offsets.append(absf(float(x) - focus.x))
	_check(float(offsets.min()) < 400.0 and float(offsets.max()) > 1500.0,
		"offsets from the focus range widely (%.0f..%.0f) — not a fixed radius"
			% [float(offsets.min()), float(offsets.max())])

	# 3) WORLD-ANCHORED: every spawn X is snapped to a world column grid, so it
	#    names a world position rather than a screen pixel.
	var col := float(Hazards.METEOR_COLUMN)
	var snapped := true
	for x in xs:
		if absf(float(x) - roundf(float(x) / col) * col) > 0.01:
			snapped = false
	_check(snapped, "every spawn X snaps to a world column — anchored, not camera-relative")
	_check(lo >= h.world_rect.position.x and hi <= h.world_rect.end.x,
		"and every spawn stays within the world bounds")

	h.queue_free()
	await process_frame


func _test_hazard_fireball_damages_and_cannot_tunnel() -> void:
	_t("a hazard fireball damages a block via the existing path, then dies — no tunnel")
	# A thin one-cell-WIDE hull wall, and a very fast fireball straight at it: the
	# ray-step must catch it where a RigidBody2D at this speed would tunnel through.
	var wall := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(0, 1): BlockDB.Type.HULL,
		Vector2i(0, 2): BlockDB.Type.HULL,
	})
	wall.position = Vector2(0.0, 0.0)
	await _step(2)   # let the collider register with the space
	var target_cell := Vector2i(0, 1)
	var hp0: float = wall.blocks[target_cell]["hp"]

	var fb := HazardFireball.new()
	fb.kind = HazardFireball.Kind.METEOR
	fb.damage = 9999.0        # plenty to destroy the struck cell
	fb.gravity = 0.0
	fb.mass = 3.0
	fb.position = Vector2(-400.0,
		wall.to_global(wall.local_pos_of(target_cell)).y)   # dead level with the middle cell
	fb.velocity = Vector2(6000.0, 0.0)   # very fast — the tunneling stress case
	root.add_child(fb)
	await _step(6)
	_check(not is_instance_valid(fb),
		"the thin hull stopped the fireball (ray-step catches it — no tunnel)")
	_check(not wall.blocks.has(target_cell) or wall.blocks[target_cell]["hp"] < hp0,
		"and the struck cell took damage through net_damage_cell")

	wall.queue_free()
	await process_frame


func _test_lava_erupts_and_arcs() -> void:
	_t("lava erupts from the floor: launched up, gravity arcs it back down")
	var h := _make_hazards()
	var flr := Vector2(500.0, 17000.0)
	var fb := h.spawn_lava(flr)
	_check(fb.velocity.y < 0.0, "the fireball launches UPWARD (vy %.0f)" % fb.velocity.y)
	_check(absf(fb.position.y - h.world_rect.end.y) < 40.0,
		"and erupts AT the floor (y %.0f, floor %.0f)" % [fb.position.y, h.world_rect.end.y])

	var vy0 := fb.velocity.y
	var y_start := fb.position.y
	await _step(30)   # half a second of flight, no geometry to hit
	_check(is_instance_valid(fb) and fb.velocity.y > vy0,
		"gravity bleeds the upward launch — it will arc back (vy %.0f → %.0f)"
			% [vy0, fb.velocity.y if is_instance_valid(fb) else 0.0])
	_check(is_instance_valid(fb) and fb.position.y < y_start,
		"and it has risen above the floor on the way up (%.0f < %.0f)"
			% [fb.position.y if is_instance_valid(fb) else 0.0, y_start])

	if is_instance_valid(fb):
		fb.queue_free()
	h.queue_free()
	await process_frame


## The earth's core (maps/world/lava_core.gd, owner 2026-08-23): the bottom slice
## of the world is lethal lava. The geometry is a pure predicate the render and the
## world's lethal check share — pin it. (The consume/respawn behaviour is checked
## end-to-end on the real scene in world_startup_test._check_lava_core.)
func _test_lava_core_is_the_bottom_slice() -> void:
	_t("the lava core is the bottom slice of the world; contact is lethal geometry")
	# A world with floor y=0, ceiling y=-1000. Test the formula with an EXPLICIT
	# fraction (0.10 → the bottom 100 px), decoupled from the tuning constant so
	# nudging DEFAULT_TOP_FRAC never breaks the math pin.
	var rect := Rect2(-100.0, -1000.0, 200.0, 1000.0)
	var frac := 0.10
	_check(is_equal_approx(LavaCore.surface_y_for(rect, frac), -100.0),
		"the surface sits at the bottom-frac line (y=%.0f)" % LavaCore.surface_y_for(rect, frac))
	_check(LavaCore.is_in_core(rect, frac, -50.0), "a point below the surface is IN the core")
	_check(LavaCore.is_in_core(rect, frac, 0.0), "the very floor is in the core")
	_check(not LavaCore.is_in_core(rect, frac, -100.0 - 1.0), "a point above the surface is safe")
	_check(not LavaCore.is_in_core(Rect2(), frac, 999.0),
		"no world mapped → the core is inert (nothing is lethal)")
	# The shipped tuning is a thin sea hugging the floor (owner lowered it).
	_check(LavaCore.DEFAULT_TOP_FRAC <= 0.08,
		"the core hugs the floor (top frac %.2f)" % LavaCore.DEFAULT_TOP_FRAC)


## The deep-band ember haze (maps/world/deep_fog.gd): a pure density ramp — 0 in
## the breathable bands, thickening to a murk at the floor. The render reads this,
## so pinning the ramp pins the fog (owner: the "Core of Cordeus" deep fog).
func _test_deep_fog_thickens_with_depth() -> void:
	_t("the deep-band fog is clear up high and thickens toward the floor")
	# Clear at and above the deep-band top; the breathable bands never fog.
	_check(DeepFog.density_at(Airspace.DEEP_TOP) == 0.0, "no fog at the deep-band top")
	_check(DeepFog.density_at(0.5) == 0.0, "no fog in the mid band")
	_check(DeepFog.density_at(0.9) == 0.0, "no fog up high")
	# Thickening downward, full at the floor.
	var mid := DeepFog.density_at(Airspace.DEEP_TOP * 0.5)
	var low := DeepFog.density_at(Airspace.DEEP_TOP * 0.2)
	_check(mid > 0.0 and low > mid, "it thickens as you descend (%.2f → %.2f)" % [mid, low])
	_check(is_equal_approx(DeepFog.density_at(0.0), 1.0), "and is thickest at the very floor")
	await process_frame


## The Inventory data structure (player/inventory.gd): counts per item type, the
## carry that mining fills and future crafting/economy reads. Pure logic.
func _test_inventory_add_remove_count() -> void:
	_t("inventory counts multiple types and multiples of a type")
	var inv := Inventory.new()
	_check(inv.is_empty(), "a fresh inventory is empty")
	_check(inv.count(TerrainDB.Type.STONE) == 0, "an unheld type counts 0")

	inv.add(TerrainDB.Type.STONE)          # one, the mining default
	inv.add(TerrainDB.Type.STONE, 4)       # a stack
	inv.add(TerrainDB.Type.DIRT, 2)
	_check(inv.count(TerrainDB.Type.STONE) == 5, "5 stone accumulated (%d)" % inv.count(TerrainDB.Type.STONE))
	_check(inv.count(TerrainDB.Type.DIRT) == 2, "2 dirt, tracked separately (%d)" % inv.count(TerrainDB.Type.DIRT))
	_check(inv.total() == 7, "total across types is 7 (%d)" % inv.total())
	_check(inv.types() == [TerrainDB.Type.DIRT, TerrainDB.Type.STONE],
		"types() lists what is held, sorted (%s)" % str(inv.types()))
	_check(not inv.is_empty(), "and it is no longer empty")

	# Amounts below one add/remove nothing.
	inv.add(TerrainDB.Type.ORE, 0)
	_check(inv.count(TerrainDB.Type.ORE) == 0, "adding zero adds nothing")

	# Remove returns how many were ACTUALLY taken, never more than held.
	_check(inv.remove(TerrainDB.Type.STONE, 2) == 2, "removing 2 of 5 takes 2")
	_check(inv.count(TerrainDB.Type.STONE) == 3, "leaving 3 (%d)" % inv.count(TerrainDB.Type.STONE))
	_check(inv.remove(TerrainDB.Type.DIRT, 9) == 2, "removing more than held takes only what is there (2)")
	_check(inv.count(TerrainDB.Type.DIRT) == 0, "dirt is now 0")
	_check(inv.types() == [TerrainDB.Type.STONE],
		"a type driven to zero is dropped from the listing (%s)" % str(inv.types()))
	_check(inv.remove(TerrainDB.Type.ORE) == 0, "removing an unheld type takes 0")

	inv.clear()
	_check(inv.is_empty() and inv.total() == 0, "clear empties it")


## The mining seam (Terrain.net_dig + the `dug` signal): the authority digs a
## solid cell, credits the miner via the signal, and returns the removed type;
## an air cell yields nothing and emits nothing. This is the whole hook the
## mine action rides — reach/dig-time live in the world (world_startup_test).
func _test_mining_seam_digs_and_credits() -> void:
	_t("net_dig removes a solid cell, returns its type, and emits dug once")
	var t := _make_terrain()
	t.fill_rect(Rect2i(2, 2, 4, 4), TerrainDB.Type.ORE)

	# Wire an inventory to the signal exactly as the world does.
	var inv := Inventory.new()
	var events: Array = []
	t.dug.connect(func(peer: int, cell: Vector2i, type: int) -> void:
		events.append([peer, cell, type])
		inv.add(type))

	var before := t.total_solid_cells()
	var dug := t.net_dig(Vector2i(3, 3), 1)
	_check(dug == TerrainDB.Type.ORE, "digging a solid cell returns its type (ORE)")
	_check(not t.is_solid(Vector2i(3, 3)), "the cell is gone from the resident data")
	_check(t.total_solid_cells() == before - 1, "exactly one cell was removed")
	_check(events.size() == 1, "the authority emitted dug exactly once (%d)" % events.size())
	_check(inv.count(TerrainDB.Type.ORE) == 1,
		"and the miner was credited exactly one ORE (%d)" % inv.count(TerrainDB.Type.ORE))

	# Mining AIR yields nothing: no removal, no credit, no signal.
	var dug_air := t.net_dig(Vector2i(3, 3), 1)  # already air now
	_check(dug_air == TerrainDB.Type.AIR, "digging an already-empty cell returns AIR")
	_check(events.size() == 1, "and emits no dug — mining air yields nothing")
	_check(inv.total() == 1, "the inventory is unchanged by an air dig")

	t.queue_free()
	await process_frame


## Pickup floats (maps/world/pickup_floats.gd): the "+1 Stone" flourish that
## pops on a dig, rises and fades, then frees itself. Pure logic.
func _test_pickup_floats_rise_and_expire() -> void:
	_t("pickup floats accumulate, then expire cleanly after their lifetime")
	var p := PickupFloats.new()
	p.add(Vector2(10, 10), "+1 Stone")
	p.add(Vector2(20, 20), "+1 Dirt", 8.0)
	_check(p.count() == 2, "each dig is its own float — no coalescing (%d)" % p.count())
	p.update(PickupFloats.LIFETIME * 0.5)
	_check(p.count() == 2, "both still alive at half life")
	p.update(PickupFloats.LIFETIME)  # past the end
	_check(p.count() == 0, "and both freed after their lifetime (%d left)" % p.count())


func _test_body_rests_on_promoted_terrain() -> void:
	_t("a ship falls onto promoted terrain and rests on it (collides)")
	var t := _make_terrain()
	# A floor slab: cells x[-10..10), y[10..14). Its top surface sits at world
	# y = 10 * 16 = 160.
	t.fill_rect(Rect2i(-10, 10, 20, 4), TerrainDB.Type.STONE)

	# A lift-less two-cell hull, so it simply falls under gravity.
	var s := _make_ship({
		Vector2i(0, 0): BlockDB.Type.HULL,
		Vector2i(0, 1): BlockDB.Type.HULL,
	}, false)
	s.gravity_scale = 1.0
	s.position = Vector2(0, 0)  # above the floor, over chunk (0,0)
	# The ship is the focus: promote the floor under it, then let it drop.
	for i in 180:
		t.update_streaming([s.global_position])
		await physics_frame

	# Its collider bottom edge is local y=24 (a 2-cell rect centred at y=8,
	# half-height 16), so resting on a floor top of 160 puts the body at y≈136.
	_check(absf(s.position.y - 136.0) < 16.0,
		"the ship settled on the floor top, not through it (y=%.0f, expected ~136)"
			% s.position.y)
	_check(absf(s.linear_velocity.y) < 40.0,
		"and it is at rest, not still falling (vy=%.0f)" % s.linear_velocity.y)

	s.queue_free()
	t.queue_free()
	await process_frame


func _test_terrain_promote_demote_leaks_no_nodes() -> void:
	_t("promote then demote leaks no nodes — a demoted chunk frees cleanly")
	var t := _make_terrain()
	t.fill_rect(Rect2i(2, 2, 8, 8), TerrainDB.Type.STONE)
	_check(t.get_child_count() == 0, "starts with no live chunk nodes")

	t.update_streaming([_chunk_centre(t, 0, 0)])
	_check(t.get_child_count() == 1 and t.live_chunk_count() == 1,
		"one promoted chunk node exists")

	t.update_streaming([_chunk_centre(t, 20, 0)])  # demote
	_check(t.live_chunk_count() == 0, "the chunk is demoted from the live set")
	await process_frame  # let the deferred free land
	_check(t.get_child_count() == 0,
		"and its node (with its colliders) is freed — nothing leaked (%d left)"
			% t.get_child_count())

	t.queue_free()
	await process_frame


## When a player first flies up to terrain, every chunk inside PROMOTE_RADIUS
## wants to promote in the SAME frame — a burst of greedy merges + node creation
## that hitched (~73 ms for 25 chunks, measured). update_streaming now AMORTIZES:
## at most PROMOTE_PER_CALL promotions per call, nearest-first, draining over
## frames. A still focus still reaches full promotion; demotion stays immediate;
## far chunks never promote; the resident data is never touched.
func _test_terrain_promotion_is_amortized() -> void:
	_t("a burst of in-radius chunks promotes at most K per call, nearest-first, then fully")
	var t := _make_terrain()
	# Solid terrain wide enough that every chunk within PROMOTE_RADIUS of the
	# origin focus holds data and wants promotion at once — the fly-up burst.
	t.fill_rect(Rect2i(-4 * Terrain.CHUNK, -4 * Terrain.CHUNK,
		8 * Terrain.CHUNK, 8 * Terrain.CHUNK), TerrainDB.Type.STONE)
	var truth := t.total_solid_cells()
	var span := 2 * Terrain.PROMOTE_RADIUS + 1
	var want := span * span  # the (2R+1)^2 block the focus ends up promoting
	var focus := _chunk_centre(t, 0, 0)

	# First call promotes at most K — NOT the whole block (that was the hitch).
	t.update_streaming([focus])
	_check(t.live_chunk_count() <= Terrain.PROMOTE_PER_CALL,
		"one update promotes at most K=%d chunks (got %d), not the whole %d-chunk burst"
			% [Terrain.PROMOTE_PER_CALL, t.live_chunk_count(), want])
	_check(t.live_chunk_count() >= 1, "but it makes progress (>=1 promoted)")
	_check(t.is_promoted(Vector2i(0, 0)),
		"nearest-first: the focus's own chunk (distance 0) is promoted first")

	# Held still, it drains K per call and reaches full promotion — spread over
	# frames, never a single hitch.
	var calls := 1
	while t.live_chunk_count() < want and calls < 100:
		t.update_streaming([focus])
		calls += 1
	_check(t.live_chunk_count() == want,
		"held still, the focus reaches full promotion (%d chunks)" % want)
	_check(calls >= int(ceil(float(want) / float(Terrain.PROMOTE_PER_CALL))),
		"and it genuinely took multiple calls (%d), not one burst" % calls)

	# Demotion stays immediate: fly far away and EVERY live chunk drops in one call.
	t.update_streaming([_chunk_centre(t, 40, 40)])
	_check(t.live_chunk_count() == 0,
		"demotion is still immediate — one update frees every out-of-range chunk")

	# A chunk beyond the radius never promoted, and the resident data is intact.
	_check(not t.is_promoted(Vector2i(10, 10)),
		"a far chunk was never promoted (resident-world guarantee)")
	_check(t.total_solid_cells() == truth,
		"the resident data — the truth — is untouched through the whole burst (%d)"
			% t.total_solid_cells())

	t.queue_free()
	await process_frame


# --- Procedural island generation (Sprint 2: the world worth flying to) ----

## Build a terrain, generate a seeded world into it, and return it. scale_unit 1
## so the tests reason in plain cells; the banding is scale-invariant anyway
## (Airspace works in fractions), so a seed pins the same CELLS at any scale.
## Generated over the ORIGINAL 3072×2304 window (the pre-×4 world size), so the
## banding/coherence tests' hardcoded band ranges — written for that geometry —
## stay valid. Band fractions follow the generated window's px, so this window
## reproduces the old world's band layout exactly (and generates 16× faster
## than the full ×4 default).
const GEN_TEST_WINDOW := Rect2i(-1536, -1152, 3072, 2304)


func _make_generated_terrain(seed_value: int) -> Terrain:
	var t := _make_terrain()
	IslandGen.generate(t, seed_value, GEN_TEST_WINDOW)
	return t


## A coarse fingerprint of a terrain's cells over a sampled lattice — enough to
## prove two worlds are identical (same seed) or different (different seed)
## without hashing millions of cells.
func _terrain_fingerprint(t: Terrain) -> String:
	var parts: PackedStringArray = []
	var w := IslandGen.WORLD_CELLS
	var step := 23  # coprime-ish with SPACING so the lattice samples island interiors
	var y := w.position.y
	while y < w.end.y:
		var x := w.position.x
		while x < w.end.x:
			parts.append(str(t.cell_type(Vector2i(x, y))))
			x += step
		y += step
	return "|".join(parts)


## Count solid cells in a cell window [x0,x1) × [y0,y1) — the density probe.
func _solid_in_window(t: Terrain, x0: int, y0: int, x1: int, y1: int) -> int:
	var n := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			if t.is_solid(Vector2i(x, y)):
				n += 1
	return n


## Does the window contain any cell of `type`?
func _window_has_type(t: Terrain, type: int, x0: int, y0: int, x1: int, y1: int) -> bool:
	for y in range(y0, y1):
		for x in range(x0, x1):
			if t.cell_type(Vector2i(x, y)) == type:
				return true
	return false


## Same seed → identical world; different seed → a different world.
func _test_island_gen_is_deterministic() -> void:
	_t("island generation is deterministic: a seed pins the world, a new seed changes it")
	var a := _make_generated_terrain(1234)
	var b := _make_generated_terrain(1234)
	var c := _make_generated_terrain(9999)

	_check(a.total_solid_cells() > 0, "the generator actually built a world (%d solid cells)"
		% a.total_solid_cells())
	_check(a.total_solid_cells() == b.total_solid_cells(),
		"same seed → identical solid-cell count (%d == %d)"
			% [a.total_solid_cells(), b.total_solid_cells()])
	_check(_terrain_fingerprint(a) == _terrain_fingerprint(b),
		"same seed → byte-identical sampled grid")
	_check(_terrain_fingerprint(a) != _terrain_fingerprint(c),
		"a different seed → a different world")

	# Airspace was restored (generation-only — no wind left active on ships).
	_check(not Airspace.active(),
		"generation restored Airspace.bounds — the band model is not left live on ships")

	a.queue_free()
	b.queue_free()
	c.queue_free()
	await process_frame


## Banding: density is higher inside a band than in a gap, the downdraft columns
## are empty, and the deep band carries an exotic material the top band does not.
func _test_island_gen_is_banded_and_columns_clear() -> void:
	_t("islands are banded: bands denser than gaps, columns empty, exotic ore only deep")
	var t := _make_generated_terrain(42)

	# Band cell-y ranges for WORLD_CELLS (height 2304, floor at +1152): MID spans
	# roughly y(-276..230], GAP_LOW y(230..369], DEEP y(369..1037]. Sample equal-
	# area windows well clear of the spawn keep-out and the wind columns (x right
	# of centre, left of the right-edge column).
	var x0 := 300
	var x1 := 1100
	var mid := _solid_in_window(t, x0, 40, x1, 200)     # MID interior
	var gap := _solid_in_window(t, x0, 240, x1, 360)    # GAP_LOW (very sparse)
	var deep := _solid_in_window(t, x0, 450, x1, 900)   # DEEP
	# Normalise the gap window to the MID window's area for an honest comparison.
	var mid_area := float((x1 - x0) * (200 - 40))
	var gap_area := float((x1 - x0) * (360 - 240))
	var gap_norm := gap * (mid_area / gap_area)
	_check(mid > 0, "the MID band has islands (%d solid cells)" % mid)
	_check(deep > 0, "the DEEP band has islands (%d solid cells)" % deep)
	_check(float(mid) > gap_norm * 1.5,
		"a band is markedly denser than a gap (mid %d vs gap ~%.0f/equal-area)"
			% [mid, gap_norm])

	# The left EDGE downdraft column (x_frac <= EDGE_W 0.04): x cells <= ~-1413.
	# Not one solid cell — the vertical wind limbs stay clear sky.
	var col := _solid_in_window(t, -1536, -1000, -1414, 1000)
	_check(col == 0, "the downdraft edge column is empty — no islands in a wind limb (%d)" % col)

	# Per-band MATERIALS: aetherite (the exotic prize) appears in the DEEP band
	# and NOT in the TOP band (which carries pumice/copper instead).
	var deep_exotic := _window_has_type(t, TerrainDB.Type.AETHERITE, x0, 450, x1, 950)
	var top_exotic := _window_has_type(t, TerrainDB.Type.AETHERITE, x0, -1050, x1, -550)
	_check(deep_exotic, "the deep band contains exotic Aetherite")
	_check(not top_exotic, "the top band contains NO Aetherite — exotic ore is a deep-band prize")

	# Mining works on generated terrain: a solid island cell digs to its type.
	var sample := Vector2i.ZERO
	var found := false
	for y in range(450, 900):
		for x in range(x0, x1):
			if t.is_solid(Vector2i(x, y)):
				sample = Vector2i(x, y)
				found = true
				break
		if found:
			break
	_check(found, "found a generated island cell to mine")
	if found:
		var type := t.cell_type(sample)
		var dug := t.dig(sample)
		_check(dug == type and not t.is_solid(sample),
			"digging a generated island cell removes it and returns its type")

	t.queue_free()
	await process_frame


## Coherence: generated solid cells form connected clusters (islands), not
## per-cell noise. Flood-fill a sample window and assert big components exist and
## isolated single cells are rare.
func _test_island_gen_islands_are_coherent() -> void:
	_t("generated islands are coherent connected clusters, not per-cell noise")
	var t := _make_generated_terrain(7)

	# A DEEP window (dense enough to hold several islands).
	var x0 := 300
	var y0 := 450
	var x1 := 1100
	var y1 := 900
	# Collect the solid set.
	var solid := {}
	for y in range(y0, y1):
		for x in range(x0, x1):
			if t.is_solid(Vector2i(x, y)):
				solid[Vector2i(x, y)] = true
	_check(solid.size() > 0, "the sample window has solid cells (%d)" % solid.size())

	# 4-neighbour flood fill → component sizes.
	var seen := {}
	var biggest := 0
	var singletons := 0
	var components := 0
	for start in solid:
		if seen.has(start):
			continue
		components += 1
		var size := 0
		var stack: Array[Vector2i] = [start]
		seen[start] = true
		while not stack.is_empty():
			var cur: Vector2i = stack.pop_back()
			size += 1
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb: Vector2i = cur + d
				if solid.has(nb) and not seen.has(nb):
					seen[nb] = true
					stack.append(nb)
		biggest = maxi(biggest, size)
		if size == 1:
			singletons += 1

	_check(biggest >= 25,
		"the largest cluster is a real island, not a speck (%d cells)" % biggest)
	_check(float(singletons) / float(components) < 0.10,
		"isolated single cells are rare — the world is blobs, not noise (%d/%d)"
			% [singletons, components])

	t.queue_free()
	await process_frame


## Generation is data-only (no live chunk nodes) and sparse (a small fraction of
## the world's cells are solid — empty sky costs nothing).
func _test_island_gen_is_data_only_and_sparse() -> void:
	_t("generation writes data only — no live nodes — and leaves the world sparse")
	var t := _make_generated_terrain(IslandGen.DEFAULT_SEED)

	_check(t.live_chunk_count() == 0,
		"no chunk was promoted during generation — pure data (%d live)"
			% t.live_chunk_count())
	_check(t.get_child_count() == 0,
		"the Terrain owns no child nodes after generation (%d)" % t.get_child_count())

	var total := t.total_solid_cells()
	var world_cells := IslandGen.WORLD_CELLS.size.x * IslandGen.WORLD_CELLS.size.y
	_check(total > 50000, "the world is substantial (%d solid cells)" % total)
	_check(float(total) / float(world_cells) < 0.30,
		"and SPARSE — far less than a third of the sky is solid (%.1f%%)"
			% (100.0 * float(total) / float(world_cells)))

	# The guaranteed spawn ground under SHIP_START (~origin) is present.
	_check(t.is_solid(Vector2i(0, 8)) and t.is_solid(Vector2i(0, 16)),
		"there is solid spawn ground directly under SHIP_START")

	t.queue_free()
	await process_frame


## The ×4 world (owner 2026-08-24: "the world still feels TINY") forced LAZY
## region generation — eager painting of the full extent was a ~25 s boot. Pins:
## the lazy path is CELL-IDENTICAL to the eager path (both call the same
## per-lattice-index hashed-RNG region painter, order-independent); the region
## ledger makes re-asking free; a recorded EDIT survives a later region
## generation (the reapply guarantee — a loaded save's dig must never be
## painted back over); and islands CLIP to the world rect (owner: "generated
## terrain appears out of bounds of the map").
func _test_lazy_generation_matches_eager_and_clips() -> void:
	_t("lazy region generation == eager, edits survive, islands clip to the world")
	var world := IslandGen.world_cells(1)
	_check(world.size == Vector2i(12288, 9216),
		"the world is ×4 the old extent (%s)" % world.size)

	# Eager reference over a mid-band window away from spawn.
	var probe := Vector2i(2000, 500)
	var eager := _make_terrain()
	IslandGen.generate(eager, 7, Rect2i())  # full default world (×4)
	# Lazy: prime + ensure around the probe point (px).
	var lazy := _make_terrain()
	IslandGen.prime(lazy)
	var probe_px := lazy.cell_center(probe)
	var made := IslandGen.ensure_generated(lazy, 7, [probe_px], 3000.0, 1000)
	_check(made > 0, "lazy generation made regions near the focus (%d)" % made)
	var same := true
	for y in range(probe.y - 150, probe.y + 150, 3):
		for x in range(probe.x - 150, probe.x + 150, 3):
			if eager.cell_type(Vector2i(x, y)) != lazy.cell_type(Vector2i(x, y)):
				same = false
	_check(same, "lazy cells == eager cells around the focus (order-independent RNG)")
	_check(IslandGen.ensure_generated(lazy, 7, [probe_px], 3000.0, 1000) == 0,
		"asking again generates nothing — the region ledger holds")

	# THE EDIT GUARANTEE: record a dig (as a load would) BEFORE the region
	# exists, then generate it — the recorded edit must win over the paint.
	var solid := Vector2i.ZERO
	var found := false
	for y in range(probe.y - 150, probe.y + 150):
		for x in range(probe.x - 150, probe.x + 150):
			if eager.is_solid(Vector2i(x, y)):
				solid = Vector2i(x, y)
				found = true
				break
		if found:
			break
	_check(found, "found a cell an island will occupy")
	var fresh := _make_terrain()
	IslandGen.prime(fresh)
	fresh.apply_diffs({solid: TerrainDB.Type.AIR})  # the "saved dig"
	IslandGen.ensure_generated(fresh, 7, [fresh.cell_center(solid)], 3000.0, 1000)
	_check(not fresh.is_solid(solid),
		"a recorded dig SURVIVES lazy region generation (reapply_all_edits)")

	# THE CLIP: nothing solid outside the world rect on any side (strips at a
	# mid-band latitude for the sides; above/below scan the full width edges).
	var oob := _solid_in_window(eager, world.position.x - 100, 300, world.position.x - 1, 900) 		+ _solid_in_window(eager, world.end.x, 300, world.end.x + 99, 900) 		+ _solid_in_window(eager, 1500, world.position.y - 100, 2500, world.position.y - 1) 		+ _solid_in_window(eager, 1500, world.end.y, 2500, world.end.y + 99)
	_check(oob == 0, "no generated cell lies outside the world rect (%d)" % oob)

	eager.queue_free()
	lazy.queue_free()
	fresh.queue_free()
	await process_frame


## The subdiv-8 lag fix (owner 2026-08-24, "so heckin' laggy"): streaming is
## TIERED — a primary focus (the player/camera) promotes a wide neighbourhood, a
## secondary focus (any other ship) only a small collision bubble — and a frame
## where no focus crossed a chunk boundary SKIPS the scan outright (measured
## 2.6 ms/frame of pure scan at 15 foci before). Break-the-fix pins: the skip
## must re-arm when a focus moves AND when new data lands near a still focus.
func _test_streaming_is_tiered_and_skips_still_frames() -> void:
	_t("terrain streaming: tiered radii + still-frame scan skip")
	var t := Terrain.new()
	t.subdiv = 8
	root.add_child(t)
	# One long solid band so both foci have promotable data everywhere.
	t.fill_rect(Rect2i(-400, 0, 800, 8), TerrainDB.Type.STONE)
	var cpx := t.chunk_px()
	var primary := t.to_global(Vector2(0.5, 0.5) * cpx)
	var secondary := t.to_global(Vector2(-300.0 / Terrain.CHUNK, 0.5) * cpx * Terrain.CHUNK / cpx)
	secondary = t.cell_center(Vector2i(-300, 4))
	for i in 400:
		t.update_streaming([primary], [secondary])
	# Tiered: count live chunks near each focus — the primary neighbourhood is
	# strictly wider than the secondary collision bubble.
	var pc := Vector2i(0, 0)
	var sc := Vector2i(floori(-300.0 / Terrain.CHUNK), 0)
	var near_p := 0
	var near_s := 0
	for c in t._live:
		if absi(c.x - pc.x) <= t._primary_promote_r():
			near_p += 1
		if absi(c.x - sc.x) <= t._primary_promote_r():
			near_s += 1
	_check(near_s > 0, "a secondary focus still gets its collision bubble (%d chunks)" % near_s)
	_check(near_p > near_s,
		"the primary focus promotes a wider neighbourhood (%d > %d)" % [near_p, near_s])

	# Scan skip: with nothing moving and the queue drained, further calls do NO
	# scan at all (the 2.6 ms/frame steady bill).
	var scans_before: int = t.scan_count
	for i in 50:
		t.update_streaming([primary], [secondary])
	_check(t.scan_count == scans_before, "still frames skip the scan entirely")
	# ...a focus crossing a chunk boundary re-arms it...
	t.update_streaming([primary + Vector2(cpx * 1.5, 0.0)], [secondary])
	_check(t.scan_count == scans_before + 1, "a focus crossing a boundary re-scans")
	# ...and NEW data near a still focus re-arms it too (the _stream_dirty
	# break-the-fix: without it, terrain placed near a parked player would
	# never gain a collider until they wandered).
	var before2: int = t.scan_count
	t.update_streaming([primary], [secondary])  # drain the move above
	var drained: int = t.scan_count
	while t.scan_count > before2 and t.scan_count - before2 < 300:
		before2 = t.scan_count
		t.update_streaming([primary], [secondary])
	var still: int = t.scan_count
	t.update_streaming([primary], [secondary])
	_check(t.scan_count == still, "drained + still again: skipping again")
	t.set_cell(Vector2i(2000, 2000), TerrainDB.Type.STONE)  # a brand-new chunk
	t.update_streaming([primary], [secondary])
	_check(t.scan_count == still + 1, "writing into a NEW chunk re-arms the scan")

	# RENDER RANGE follows the camera (owner: "render distance is not matching
	# active zoom"): the primary radius derives from primary_range_px, so a
	# wider view widens the promoted neighbourhood — and changing it re-arms
	# the scan-skip (a zoom change re-scans once).
	var r_default: int = t._primary_promote_r()
	t.primary_range_px = t.chunk_px() * 14.0
	_check(t._primary_promote_r() > r_default,
		"a wider camera view widens the promote radius (%d > %d)"
			% [t._primary_promote_r(), r_default])
	t.primary_range_px = t.chunk_px() * 500.0
	_check(t._primary_promote_r() <= 20 * maxi(t.subdiv, 1) / 8,
		"an extreme zoom-out is CAPPED (%d)" % t._primary_promote_r())
	var scans_z: int = t.scan_count
	t.update_streaming([primary], [secondary])
	_check(t.scan_count == scans_z + 1, "a zoom change re-arms the scan once")
	t.queue_free()
	await process_frame


## The SUBDIV fast path (fill_row) must be behaviour-identical to per-cell
## set_cell — it exists only because per-cell chunk lookups made 64×-cell
## generation a multi-second stall. Same spans through both paths, byte-equal
## resident data; chunk-boundary crossings and negative coordinates included.
func _test_fill_row_matches_set_cell() -> void:
	_t("terrain fill_row is byte-identical to per-cell set_cell")
	var a := Terrain.new()
	var b := Terrain.new()
	root.add_child(a)
	root.add_child(b)
	# Spans crossing chunk boundaries, negative space, single cells, and an
	# air-only span over an absent chunk (must stay absent).
	var spans := [
		[-40, 70, 5, TerrainDB.Type.STONE],    # crosses three chunks
		[0, 0, -3, TerrainDB.Type.DIRT],       # single cell
		[-100, -90, -70, TerrainDB.Type.ORE],  # fully negative
		[30, 33, 5, TerrainDB.Type.AIR],       # air over solid (a real erase)
		[500, 520, 500, TerrainDB.Type.AIR],   # air over ABSENT chunks (no-op)
	]
	for s in spans:
		a.fill_row(s[0], s[1], s[2], s[3])
		for x in range(int(s[0]), int(s[1]) + 1):
			b.set_cell(Vector2i(x, int(s[2])), int(s[3]))
	_check(a.chunk_coords().size() == b.chunk_coords().size(),
		"same chunks allocated (%d == %d)" % [a.chunk_coords().size(), b.chunk_coords().size()])
	var same := true
	for c in b.chunk_coords():
		for y in Terrain.CHUNK:
			for x in Terrain.CHUNK:
				var cell := Vector2i(c.x * Terrain.CHUNK + x, c.y * Terrain.CHUNK + y)
				if a.cell_type(cell) != b.cell_type(cell):
					same = false
	_check(same, "every cell agrees between the two paths")
	_check(a.total_solid_cells() == b.total_solid_cells(),
		"same solid count (%d)" % a.total_solid_cells())
	a.queue_free()
	b.queue_free()
	await process_frame


## Terrain SUBDIV (the owner's full-8× resolution): a subdiv-S world is the SAME
## world at S× finer cells — same pixel geography, ~the same solid AREA in px²,
## the spawn floor under the same px footprint — never a different world. Uses a
## small explicit window so the test is fast; the invariance is in the shared
## constants (×sub) and the px-fixed Airspace geometry.
func _test_subdiv_world_is_the_same_world_finer() -> void:
	_t("a subdiv-8 world is the subdiv-1 world at 8x resolution (px-invariant)")
	var coarse := Terrain.new()
	var fine := Terrain.new()
	fine.subdiv = 8
	root.add_child(coarse)
	root.add_child(fine)
	_check(is_equal_approx(fine.cell_px() * 8.0, coarse.cell_px()),
		"a fine cell is exactly 1/8 the px of a coarse cell")

	var window := Rect2i(-384, -384, 768, 768)  # cells at subdiv 1
	var window8 := Rect2i(window.position * 8, window.size * 8)
	IslandGen.generate(coarse, IslandGen.DEFAULT_SEED, window)
	IslandGen.generate(fine, IslandGen.DEFAULT_SEED, window8)

	# The spawn floor occupies the identical px footprint: the coarse floor top
	# row (0,8) maps to fine (0,64) — and both are DIRT.
	_check(coarse.cell_type(Vector2i(0, 8)) == TerrainDB.Type.DIRT
			and fine.cell_type(Vector2i(0, 64)) == TerrainDB.Type.DIRT,
		"the spawn floor sits at the same px spot in both worlds (dirt top)")
	# Solid AREA in px² agrees within tolerance (finer edges differ slightly:
	# the wobble roughens at cell granularity, so a few % is expected).
	var area_c := float(coarse.total_solid_cells()) * coarse.cell_px() * coarse.cell_px()
	var area_f := float(fine.total_solid_cells()) * fine.cell_px() * fine.cell_px()
	_check(area_c > 0.0 and area_f > 0.0, "both windows generated land")
	var ratio := area_f / area_c
	_check(ratio > 0.8 and ratio < 1.25,
		"solid AREA is px-invariant within tolerance (fine/coarse = %.3f)" % ratio)
	# Determinism at subdiv 8: a second fine generation is byte-identical.
	var fine2 := Terrain.new()
	fine2.subdiv = 8
	root.add_child(fine2)
	IslandGen.generate(fine2, IslandGen.DEFAULT_SEED, window8)
	_check(fine2.total_solid_cells() == fine.total_solid_cells()
			and fine2.chunk_coords().size() == fine.chunk_coords().size(),
		"subdiv-8 generation is deterministic (%d cells)" % fine.total_solid_cells())
	coarse.queue_free()
	fine.queue_free()
	fine2.queue_free()
	await process_frame


# --- The make/use loop (v0.25.0) -------------------------------------------

## The unified item-id space (items/item_db.gd): terrain materials, whale
## products and crafted goods share ONE Inventory without their ids ever
## colliding, and name/color lookups dispatch on the range.
func _test_item_id_scheme_keeps_kinds_distinct() -> void:
	_t("the item-id scheme keeps terrain, products and crafted goods distinct")
	# The ranges do not overlap: terrain tops out well below the product base.
	_check(TerrainDB.Type.AETHERITE < ItemDB.PRODUCT_BASE,
		"every terrain type sits below the product range (%d < %d)"
			% [TerrainDB.Type.AETHERITE, ItemDB.PRODUCT_BASE])
	_check(ItemDB.PRODUCT_BASE < ItemDB.CRAFTED_BASE, "products sit below crafted")

	# Kind predicates classify each id to exactly one range.
	_check(ItemDB.is_terrain(TerrainDB.Type.STONE), "stone is a terrain item")
	_check(ItemDB.is_product(ItemDB.Product.BLUBBER), "blubber is a product item")
	_check(ItemDB.is_crafted(ItemDB.Crafted.WHALE_OIL), "whale oil is a crafted item")
	_check(not ItemDB.is_terrain(ItemDB.Product.BLUBBER),
		"a product is NOT mistaken for terrain (no collision)")
	_check(not ItemDB.is_product(ItemDB.Crafted.WHALE_OIL),
		"a crafted good is NOT mistaken for a product")

	# Only real terrain materials are placeable; AIR and non-terrain items are not.
	_check(ItemDB.is_placeable_terrain(TerrainDB.Type.STONE), "stone is placeable")
	_check(not ItemDB.is_placeable_terrain(TerrainDB.Type.AIR), "AIR is not placeable")
	_check(not ItemDB.is_placeable_terrain(ItemDB.Product.BLUBBER),
		"a whale product cannot be placed as terrain")

	# Block-type -> product-item mapping (the harvest hook).
	_check(ItemDB.whale_product_for(BlockDB.Type.BLUBBER) == ItemDB.Product.BLUBBER,
		"a blubber block harvests to a blubber product")
	_check(ItemDB.whale_product_for(BlockDB.Type.MEAT) == ItemDB.Product.MEAT,
		"a meat block harvests to a meat product")
	_check(ItemDB.whale_product_for(BlockDB.Type.HULL) == -1,
		"a non-flesh block harvests to nothing")

	# All three kinds coexist in ONE inventory, counted separately.
	var inv := Inventory.new()
	inv.add(TerrainDB.Type.STONE, 3)
	inv.add(ItemDB.Product.BLUBBER, 2)
	inv.add(ItemDB.Crafted.WHALE_OIL, 1)
	_check(inv.count(TerrainDB.Type.STONE) == 3 and inv.count(ItemDB.Product.BLUBBER) == 2
			and inv.count(ItemDB.Crafted.WHALE_OIL) == 1 and inv.total() == 6,
		"three kinds share one inventory with no key collision (total %d)" % inv.total())

	# Names dispatch by range to the right table.
	_check(ItemDB.name_of(TerrainDB.Type.STONE) == "Stone", "terrain name via TerrainDB")
	_check(ItemDB.name_of(ItemDB.Product.BLUBBER) == "Blubber", "product name via ItemDB")
	_check(ItemDB.name_of(ItemDB.Crafted.WHALE_OIL) == "Whale Oil", "crafted name via ItemDB")


## Placement (Terrain.net_place, the inverse of net_dig): writes a solid material
## into an EMPTY cell, emits `placed` once (so the world spends one item), refuses
## a solid cell or a non-solid material, and the placed cell mines back cleanly.
func _test_terrain_placement_writes_consumes_and_digs_back() -> void:
	_t("net_place writes an empty cell, refuses solid/invalid, and the cell digs back")
	var t := _make_terrain()
	var events: Array = []
	t.placed.connect(func(peer: int, cell: Vector2i, type: int) -> void:
		events.append([peer, cell, type]))

	var cell := Vector2i(3, 3)
	_check(not t.is_solid(cell), "the target cell starts empty (air)")
	var ok := t.net_place(cell, TerrainDB.Type.STONE, 1)
	_check(ok and t.is_solid(cell) and t.cell_type(cell) == TerrainDB.Type.STONE,
		"placing writes a solid stone cell into the empty target")
	_check(events.size() == 1 and events[0][2] == TerrainDB.Type.STONE,
		"the authority emitted placed exactly once, with the material (%d)" % events.size())

	# Refuse placing into an already-solid cell — no overwrite, no event.
	var ok2 := t.net_place(cell, TerrainDB.Type.DIRT, 1)
	_check(not ok2 and t.cell_type(cell) == TerrainDB.Type.STONE,
		"placing into a solid cell does nothing — the stone stands")
	_check(events.size() == 1, "and emits no placed for the refused placement")

	# Refuse a non-solid material (AIR is not a placeable material).
	var ok3 := t.net_place(Vector2i(4, 4), TerrainDB.Type.AIR, 1)
	_check(not ok3 and not t.is_solid(Vector2i(4, 4)),
		"AIR is not a material — placing it writes nothing")

	# The placed cell is ordinary terrain: it mines back to its type.
	var dug := t.dig(cell)
	_check(dug == TerrainDB.Type.STONE and not t.is_solid(cell),
		"the placed cell digs back to its type — placement is the true inverse of mining")

	t.queue_free()
	await process_frame


## Harvesting (Ship.harvest_cell + is_carcass + take_stomach_loot): only a
## CARCASS yields whale-PRODUCT items; a LIVING whale yields nothing and keeps
## every block. Blubber -> blubber product, meat -> meat product, plus a one-time
## stomach drop.
func _test_whale_carcass_harvest_yields_products() -> void:
	_t("only a carcass yields whale products; a living whale keeps its blocks")
	var cells := {
		Vector2i(0, 0): BlockDB.Type.BLUBBER,
		Vector2i(1, 0): BlockDB.Type.BLUBBER,
		Vector2i(0, 1): BlockDB.Type.MEAT,
		Vector2i(1, 1): BlockDB.Type.MEAT,
	}

	# --- A LIVING whale: one unit, no harvest -------------------------------
	var live := _make_ship(cells.duplicate())
	live.position = Vector2(-42000, 0)
	live.shared_health_max = 100.0
	live.shared_health = 100.0
	_check(not live.is_carcass(), "a whale with a full pool is not a carcass")
	var n0 := live.blocks.size()
	_check(live.harvest_cell(Vector2i(0, 0)) == -1,
		"harvesting a LIVING whale yields nothing (-1)")
	_check(live.blocks.size() == n0 and live.has_block(Vector2i(0, 0)),
		"and it keeps every block — the live body is untouched")
	_check(live.take_stomach_loot() == -1, "a live whale has no stomach loot to take")
	live.queue_free()

	# --- A CARCASS: flesh blocks harvest to products ------------------------
	var corpse := _make_ship(cells.duplicate())
	corpse.position = Vector2(-42000, -6000)
	corpse.shared_health_max = 100.0
	corpse.shared_health = 0.0  # dead → a carcass
	_check(corpse.is_carcass(), "an emptied pool makes it a carcass")

	var blubber := corpse.harvest_cell(Vector2i(0, 0))
	_check(blubber == ItemDB.Product.BLUBBER,
		"harvesting a blubber block yields a BLUBBER PRODUCT item (not a terrain type)")
	_check(not corpse.has_block(Vector2i(0, 0)), "and the block is removed from the corpse")

	var meat := corpse.harvest_cell(Vector2i(0, 1))
	_check(meat == ItemDB.Product.MEAT, "harvesting a meat block yields a MEAT product")
	_check(not corpse.has_block(Vector2i(0, 1)), "and that block is gone too")

	# The stomach drop comes out once, then never again.
	_check(corpse.take_stomach_loot() == ItemDB.Product.STOMACH_LOOT,
		"the corpse spills its stomach loot once")
	_check(corpse.take_stomach_loot() == -1, "and only once — the stomach is emptied")

	# The product ids are distinct from any terrain type — no collision with the
	# ids mining would credit.
	_check(not ItemDB.is_terrain(blubber) and not ItemDB.is_terrain(meat),
		"harvested products are product-range ids, never terrain ids")

	if is_instance_valid(corpse):
		corpse.queue_free()
	await process_frame


## Crafting (items/recipes.gd): a recipe whose inputs are present consumes them
## and adds the output; a recipe missing an input crafts nothing and leaves the
## inventory exactly as it was (no partial spend).
func _test_crafting_consumes_inputs_and_yields_output() -> void:
	_t("crafting consumes inputs and yields output; missing inputs change nothing")
	# Find the whale-oil recipe by its output (robust to recipe-order changes).
	var oil_recipe := {}
	for r in Recipes.RECIPES:
		if int(r["output"]) == ItemDB.Crafted.WHALE_OIL:
			oil_recipe = r
			break
	_check(not oil_recipe.is_empty(), "there is a recipe that outputs whale oil")

	# Inputs present: it crafts.
	var inv := Inventory.new()
	var need := int(oil_recipe["inputs"][ItemDB.Product.BLUBBER])
	inv.add(ItemDB.Product.BLUBBER, need)
	_check(Recipes.can_craft(inv, oil_recipe), "with the blubber present it is craftable")
	_check(Recipes.craft(inv, oil_recipe), "and craft() succeeds")
	_check(inv.count(ItemDB.Product.BLUBBER) == 0,
		"the blubber inputs were consumed (%d left)" % inv.count(ItemDB.Product.BLUBBER))
	_check(inv.count(ItemDB.Crafted.WHALE_OIL) == int(oil_recipe.get("count", 1)),
		"and the whale oil output was added (%d)" % inv.count(ItemDB.Crafted.WHALE_OIL))

	# Missing inputs: nothing happens, inventory unchanged.
	var poor := Inventory.new()
	poor.add(ItemDB.Product.BLUBBER, need - 1)  # one short
	_check(not Recipes.can_craft(poor, oil_recipe), "one short is not craftable")
	_check(not Recipes.craft(poor, oil_recipe), "craft() refuses")
	_check(poor.count(ItemDB.Product.BLUBBER) == need - 1 and poor.total() == need - 1,
		"and the inventory is untouched — no partial spend")
	await process_frame


## Balloons became CRAFTED, SPENDABLE items (v0.49.0) — the end of free-build
## lift. Three things have to hold together or the loop breaks silently: the
## size<->item mapping is a bijection (a size that maps to the wrong item spends
## the wrong stack), every size has a recipe whose output is exactly that item
## (a missing one is an unobtainable balloon), and the cost tracks the TETHER
## COUNT so the ladder means something.
func _test_balloons_are_crafted_items() -> void:
	_t("every balloon size is a crafted item with a recipe priced by its tethers")

	var seen := {}
	for size in Ship.BALLOON_LIFT.size():
		var item := ItemDB.balloon_item_for(size)
		_check(ItemDB.is_crafted(item),
			"%s is in the CRAFTED id range" % ItemDB.name_of(item))
		_check(ItemDB.balloon_size_of(item) == size,
			"and maps back to its own size (%d)" % size)
		_check(not seen.has(item), "no two sizes share an item id")
		seen[item] = true

		# The recipe for exactly this item.
		var recipe := {}
		for r in Recipes.RECIPES:
			if int(r["output"]) == item:
				recipe = r
		_check(not recipe.is_empty(), "a recipe outputs the %s" % ItemDB.name_of(item))
		if recipe.is_empty():
			continue
		# Priced by tethers: one copper ingot per cable, blubber twice that. The
		# break-the-fix for a flat price list — make all three cost the same and
		# this fails.
		var cables: int = Ship.BALLOON_CABLES[size]
		_check(int(recipe["inputs"].get(ItemDB.Crafted.INGOT, 0)) == cables,
			"%s costs one ingot per tether (%d)" % [ItemDB.name_of(item), cables])
		_check(int(recipe["inputs"].get(ItemDB.Product.BLUBBER, 0)) == cables * 2,
			"and twice that in blubber (%d)" % (cables * 2))
		_check(not recipe["inputs"].has(TerrainDB.Type.AETHERITE),
			"aetherite is NOT an input — the deep's prize is a reward, not a gate")

		# It actually crafts, from an inventory holding exactly the cost.
		var inv := Inventory.new()
		for id in recipe["inputs"]:
			inv.add(id, int(recipe["inputs"][id]))
		_check(Recipes.craft(inv, recipe) and inv.count(item) == 1,
			"and the exact cost buys one %s" % ItemDB.name_of(item))
		_check(inv.count(ItemDB.Crafted.INGOT) == 0 and inv.count(ItemDB.Product.BLUBBER) == 0,
			"spending everything it needed and nothing it did not")

		# GEAR, NOT SALVAGE: a balloon must be worth 0 to the bulk sell, exactly
		# like the Aether Lung. "Sell salvage" is one keypress that dumps
		# everything with a price — a balloon with a price is lift you can lose
		# by leaning on 0 at a trainer.
		_check(Economy.sell_value(item) == 0,
			"%s is not swept up by the bulk salvage sale" % ItemDB.name_of(item))

	# A non-balloon item is not mistaken for one (the -1 contract).
	_check(ItemDB.balloon_size_of(ItemDB.Crafted.WHALE_OIL) == -1,
		"whale oil is not a balloon")
	_check(ItemDB.balloon_size_of(TerrainDB.Type.STONE) == -1, "and neither is stone")
	# An out-of-range size clamps rather than crashing (a caller bug must not
	# take the frame down mid-attach).
	_check(ItemDB.balloon_item_for(99) == ItemDB.balloon_item_for(Ship.BalloonSize.LARGE),
		"an over-range size clamps to the largest balloon")
	_check(ItemDB.balloon_item_for(-3) == ItemDB.balloon_item_for(Ship.BalloonSize.SMALL),
		"and an under-range one to the smallest")
	await _step(1)


## MACHINES PLACE AS BUNDLES (owner 2026-08-25: "an engine will never be a
## single block, but a rectangle or square — same for other NONPRIMITIVE
## buildables"). The geometry layer: BlockDB.BUNDLE_8X shapes must agree with
## the FOOTPRINT_8X areas the output normalisation already assumes (a drifted
## shape would make a full hand-built machine out-produce or under-produce its
## rating), stamps must be all-or-nothing, and the BFS order must satisfy the
## per-cell can_place_at law the server enforces.
func _test_machine_bundles_geometry() -> void:
	_t("machine bundles: shapes match footprints; stamps land whole and in legal order")

	# --- Shape × area consistency (break-the-fix for a careless reshape) ----
	for type in BlockDB.BUNDLE_8X:
		if BlockDB.FOOTPRINT_8X.has(type):
			var dims: Vector2i = BlockDB.bundle_dims(type, 8.0)
			_check(dims.x * dims.y == int(BlockDB.FOOTPRINT_8X[type]),
				"%s bundle %d×%d covers exactly its normalised footprint (%d cells)"
					% [BlockDB.get_def(type)["name"], dims.x, dims.y,
						int(BlockDB.FOOTPRINT_8X[type])])
	var eng: Vector2i = BlockDB.bundle_dims(BlockDB.Type.ENGINE, 8.0)
	_check(eng == Vector2i(4, 4), "the engine is the owner's surveyed 4×4 square")
	_check(BlockDB.bundle_dims(BlockDB.Type.PROPELLER, 8.0, true) == Vector2i(2, 6),
		"rot swaps the propeller to its 2×6 mounting")
	_check(BlockDB.bundle_dims(BlockDB.Type.ENGINE, 1.0) == Vector2i.ONE,
		"at 1× every bundle collapses to one cell (the legacy fixtures)")
	_check(BlockDB.bundle_dims(BlockDB.Type.HULL, 8.0) == Vector2i.ONE,
		"hull is a PRIMITIVE — single-cell freeform at any scale")
	_check(BlockDB.is_bundle(BlockDB.Type.ENGINE, 8.0)
			and not BlockDB.is_bundle(BlockDB.Type.ENGINE, 1.0),
		"is_bundle says bundled-at-8×, collapses at 1×")
	_check(BlockDB.bundle_dims(BlockDB.Type.GASBAG, 8.0) == Vector2i(4, 4),
		"the gasbag PLACES as a 4×4 bag — the helium-balloon rule, never a loose cell")
	_check(BlockDB.deconstructs_whole(BlockDB.Type.ENGINE, 8.0)
			and not BlockDB.deconstructs_whole(BlockDB.Type.GASBAG, 8.0)
			and not BlockDB.deconstructs_whole(BlockDB.Type.HULL, 8.0),
		"machines deconstruct whole; the gasbag (bulk) and hull sculpt cell by cell")

	# --- Stamp geometry + validity on a real grid ---------------------------
	# A 10-wide hull wall at y=0, scale_unit 8 so bundles are live.
	var cells := {}
	for x in 10:
		cells[Vector2i(x, 0)] = BlockDB.Type.HULL
	var s8 := _make_ship(cells)
	s8.position = Vector2(-56000, 0)
	s8.scale_unit = 8.0

	var stamp := BuildPreview.stamp_cells(s8, Vector2i(4, -2), BlockDB.Type.ENGINE)
	_check(stamp.size() == 16, "an engine stamp is 16 cells")
	_check(stamp[0] == Vector2i(2, -4),
		"...centred on the cursor (origin %s)" % str(stamp[0]))
	_check(BuildPreview.stamp_valid(s8, stamp),
		"empty cells touching the wall from outside — a legal stamp")
	_check(not BuildPreview.stamp_valid(s8,
			BuildPreview.stamp_cells(s8, Vector2i(4, -1), BlockDB.Type.ENGINE)),
		"a stamp overlapping the wall is refused outright (all-or-nothing)")
	_check(not BuildPreview.stamp_valid(s8,
			BuildPreview.stamp_cells(s8, Vector2i(40, -40), BlockDB.Type.ENGINE)),
		"a stamp floating in the void is refused (grow off a neighbour)")
	_check(BuildPreview.stamp_cells(s8, Vector2i(3, -1), BlockDB.Type.HULL) == [Vector2i(3, -1)],
		"a primitive's stamp is exactly the cursor cell")

	# --- The order really satisfies the per-cell law ------------------------
	# net_set_block enforces can_place_at cell by cell; walking stamp_order
	# through it must land ALL 16. (A naive row-major order fails: the top
	# rows have no neighbour yet.)
	var placed := 0
	for c in BuildPreview.stamp_order(s8, stamp):
		s8.net_set_block(c, BlockDB.Type.ENGINE)
	for c in stamp:
		if s8.has_block(c) and int(s8.blocks[c]["type"]) == BlockDB.Type.ENGINE:
			placed += 1
	_check(placed == 16,
		"stamp_order lands every cell through net_set_block's own gate (%d/16)" % placed)

	# --- The machine region is the whole machine and only the machine -------
	var region := BuildPreview.machine_region(s8, Vector2i(3, -4))
	_check(region.size() == 16, "the engine's region is its 16 cells (%d)" % region.size())
	var leaked := false
	for c in region:
		if int(s8.blocks[c]["type"]) != BlockDB.Type.ENGINE:
			leaked = true
	_check(not leaked, "...and never leaks into the hull it stands on")
	_check(BuildPreview.machine_region(s8, Vector2i(0, 0)).size() == 10,
		"a same-type region follows type boundaries (the hull wall is one region)")

	# --- THE MAGNET (owner 2026-08-25: "almost impossible to place... it does
	# not snap"). The engine placed above occupies rows -4..-1 over the wall;
	# clear it first so the snap probes a clean sky.
	for c in BuildPreview.machine_region(s8, Vector2i(3, -4)):
		s8.remove_block(c)
	# Aim 3 cells too high: the centred stamp floats (refused before the snap
	# existed) — snapped_stamp slides it down onto the wall.
	var snapped := BuildPreview.snapped_stamp(s8, Vector2i(4, -5), BlockDB.Type.ENGINE)
	_check(not snapped.is_empty(), "a floating aim near the wall SNAPS to a legal spot")
	_check(BuildPreview.stamp_valid(s8, snapped),
		"...and the snapped stamp is itself legal")
	var touches_wall := false
	for c in snapped:
		if s8.blocks.has(c + Vector2i(0, 1)):
			touches_wall = true
	_check(touches_wall, "...seated against the wall, not floating")
	_check(BuildPreview.snapped_stamp(s8, Vector2i(4, -40), BlockDB.Type.ENGINE).is_empty(),
		"an aim far out in the void snaps to nothing — the magnet has a range")
	_check(BuildPreview.snapped_stamp(s8, Vector2i(4, -5), BlockDB.Type.HULL).is_empty(),
		"a PRIMITIVE never snaps — a floating hull cell is simply refused")

	# --- Gasbag: stamps as a bag, sculpts cell by cell ----------------------
	var bag := BuildPreview.snapped_stamp(s8, Vector2i(4, -3), BlockDB.Type.GASBAG)
	_check(bag.size() == 16, "the gasbag stamps 16 cells (4×4)")
	for c in BuildPreview.stamp_order(s8, bag):
		s8.net_set_block(c, BlockDB.Type.GASBAG)
	_check(BuildPreview.machine_region(s8, bag[0]).size() == 16,
		"the placed bag is one 16-cell region")

	s8.queue_free()
	await _step(1)


## THE REDRAW/REBUILD BATCH (owner lag audit 2026-08-25, "are they really
## being clustered properly?"): the cluster OUTPUTS were fine — the cost was
## re-clustering per event. A redraw regroups every cell (38-53 ms on a
## creature, ~1.1 s on the 194k-cell starter) and used to queue on EVERY
## damage/repair tick; a rebuild is O(all cells) and fired once PER CELL of a
## machine stamp. Now: redraws gate on the 6-step shade BUCKET actually
## moving, and a stamp/machine-removal pays exactly ONE rebuild.
func _test_redraws_and_rebuilds_are_batched() -> void:
	_t("invisible damage queues no redraw; a stamp or machine removal is one rebuild")

	# --- The bucket math _draw and the gate share ---------------------------
	_check(Ship.shade_bucket(100.0, 100.0) == 5 and Ship.shade_bucket(0.0, 100.0) == 0,
		"full hp is shade 5, dead is shade 0")
	_check(Ship.shade_bucket(95.0, 100.0) == 5 and Ship.shade_bucket(84.0, 100.0) == 4,
		"the six steps quantise where _draw does")

	# --- A LIVING creature: sub-bucket chewing queues nothing ---------------
	var cells := {}
	for x in 6:
		for y in 2:
			cells[Vector2i(x, y)] = BlockDB.Type.MEAT
	var beast := _make_ship(cells.duplicate())
	beast.position = Vector2(-58000, 0)
	beast.shared_health_max = 1000.0
	beast.shared_health = 1000.0
	var marks0: int = beast.redraw_marks
	for i in 8:
		beast.damage_cell(Vector2i(0, 0), 1.0)  # 8 hp off 1000 — invisible
	_check(beast.redraw_marks == marks0,
		"8 ticks of invisible pool damage queue ZERO redraws (was: 8 full regroups)")
	beast.damage_cell(Vector2i(0, 0), 200.0)  # 992 -> 792: bucket 5 -> 4
	_check(beast.redraw_marks == marks0 + 1,
		"the hit that crosses a shade step queues exactly one")

	# --- A VESSEL: same gate per cell ---------------------------------------
	var hull := _make_ship({Vector2i(0, 0): BlockDB.Type.HULL, Vector2i(1, 0): BlockDB.Type.HULL})
	hull.position = Vector2(-58000, -4000)
	var h0: int = hull.redraw_marks
	hull.damage_cell(Vector2i(0, 0), 4.0)   # 100 -> 96: still shade 5
	_check(hull.redraw_marks == h0, "a scratch below the first step queues nothing")
	hull.damage_cell(Vector2i(0, 0), 20.0)  # 96 -> 76: shade 5 -> 4
	_check(hull.redraw_marks == h0 + 1, "crossing a step queues one")

	# --- The repair wand's sips ---------------------------------------------
	var r0: int = hull.redraw_marks
	hull.repair_cell(Vector2i(0, 0), 2.0)   # 76 -> 78: still shade 4
	_check(hull.redraw_marks == r0, "a sip of repair below the step queues nothing")
	hull.repair_cell(Vector2i(0, 0), 15.0)  # 78 -> 93: shade 4 -> 5
	_check(hull.redraw_marks == r0 + 1, "and the visible lightening queues one")

	# --- One stamp, ONE rebuild ---------------------------------------------
	var wall := {}
	for x in 10:
		wall[Vector2i(x, 0)] = BlockDB.Type.HULL
	var s8 := _make_ship(wall)
	s8.position = Vector2(-58000, -8000)
	s8.scale_unit = 8.0
	var stamp := BuildPreview.stamp_cells(s8, Vector2i(4, -2), BlockDB.Type.ENGINE)
	var rb0: int = s8.rebuild_count
	s8.net_set_blocks(BuildPreview.stamp_order(s8, stamp), BlockDB.Type.ENGINE)
	_check(s8.rebuild_count == rb0 + 1,
		"a 16-cell engine stamp pays ONE rebuild (was 16; %d)" % (s8.rebuild_count - rb0))
	var landed := 0
	for c in stamp:
		if s8.has_block(c) and int(s8.blocks[c]["type"]) == BlockDB.Type.ENGINE:
			landed += 1
	_check(landed == 16, "and the whole machine landed (%d/16)" % landed)

	# --- One machine removal, ONE rebuild + ONE severance pass --------------
	rb0 = s8.rebuild_count
	s8.net_remove_blocks(BuildPreview.machine_region(s8, stamp[0]))
	_check(s8.rebuild_count == rb0 + 1,
		"removing the whole machine pays ONE rebuild (%d)" % (s8.rebuild_count - rb0))
	_check(s8.blocks.size() == 10, "the wall stands, the machine is gone")

	beast.queue_free()
	hull.queue_free()
	s8.queue_free()
	await _step(1)


## Crafting without repetition (items/recipes.gd, v0.44.x): craftable_count is the
## min over inputs of have/need, and craft_all spends exactly that batch in ONE
## call — the anti-grind fix for a recipe you would otherwise press M at ten times.
## The last block is the break-the-fix check: too poor to craft even once must
## consume NOTHING (a naive loop-until-broke implementation fails it).
func _test_craft_all_makes_the_whole_stack_in_one_action() -> void:
	_t("craft-all makes every affordable copy in one action, and never part-spends")

	# The multi-input recipe is the interesting one: the batch is bounded by the
	# SCARCEST input, not by the first one checked.
	var recipe := {}
	for r in Recipes.RECIPES:
		if int(r["output"]) == ItemDB.Crafted.LIFE_SUPPORT:
			recipe = r
			break
	_check(not recipe.is_empty(), "there is a multi-input recipe to batch (the Aether Lung)")
	var ids: Array = recipe["inputs"].keys()
	var ingot := int(ids[0])
	var blubber := int(ids[1])
	var ingot_need := int(recipe["inputs"][ingot])
	var blubber_need := int(recipe["inputs"][blubber])
	var yield_each := int(recipe.get("count", 1))

	# --- craftable_count is the MIN over inputs -----------------------------
	var empty := Inventory.new()
	_check(Recipes.craftable_count(empty, recipe) == 0, "an empty inventory affords 0")
	_check(Recipes.craftable_count(null, recipe) == 0, "a null inventory affords 0 (0-safe)")

	var one_missing := Inventory.new()
	one_missing.add(ingot, ingot_need * 5)   # plenty of one input, none of the other
	_check(Recipes.craftable_count(one_missing, recipe) == 0,
		"a missing input floors the count to 0 however much of the rest you hold")

	var mixed := Inventory.new()
	mixed.add(ingot, ingot_need * 4)         # enough for 4
	mixed.add(blubber, blubber_need * 3 + 1) # enough for 3 (+ a partial that buys nothing)
	_check(Recipes.craftable_count(mixed, recipe) == 3,
		"the count is the min over inputs, partials floored (got %d, want 3)"
			% Recipes.craftable_count(mixed, recipe))

	# --- craft_all spends exactly that batch, once --------------------------
	var made := Recipes.craft_all(mixed, recipe)
	_check(made == 3, "craft_all made exactly the affordable number (%d)" % made)
	_check(mixed.count(ItemDB.Crafted.LIFE_SUPPORT) == yield_each * 3,
		"and added the whole yield (%d)" % mixed.count(ItemDB.Crafted.LIFE_SUPPORT))
	_check(mixed.count(ingot) == ingot_need * 4 - ingot_need * 3,
		"the surplus input was left alone (%d ingots)" % mixed.count(ingot))
	_check(mixed.count(blubber) == 1,
		"and the scarce input is spent down to its unusable remainder (%d)"
			% mixed.count(blubber))
	_check(Recipes.craftable_count(mixed, recipe) == 0, "nothing left to batch afterwards")

	# --- break-the-fix: too poor to craft even once changes NOTHING ---------
	var poor := Inventory.new()
	poor.add(ingot, ingot_need)              # a full one input...
	poor.add(blubber, blubber_need - 1)      # ...and one short of the other
	var before := poor.total()
	_check(Recipes.craft_all(poor, recipe) == 0, "craft_all with insufficient inputs makes 0")
	_check(poor.count(ItemDB.Crafted.LIFE_SUPPORT) == 0, "no output appeared")
	_check(poor.count(ingot) == ingot_need and poor.count(blubber) == blubber_need - 1
			and poor.total() == before,
		"and NOTHING was consumed — no partial spend on a failed batch")
	await process_frame


# --- The decluttered HUD, the map, and the easter eggs (v0.26.0) -----------

## The contextual-cue decision (maps/world/hud_cues.gd): only the actions usable
## RIGHT NOW are active, and the others are not — the calm screen's replacement
## for the always-on key dump (owner 2026-08-22). Pure logic, no Labels.
func _test_hud_cues_show_only_usable_actions() -> void:
	_t("contextual cues show only the actions usable now, nothing else")

	# Nothing usable → no cues at all (a truly calm screen).
	_check(HudCues.active({}).is_empty(), "with nothing in reach, no cues show")

	# Near a helm on foot → the helm cue, and ONLY it.
	var helm := HudCues.active({"near_helm": true})
	_check(helm.has(HudCues.Cue.HELM) and helm.size() == 1,
		"near a helm, the helm cue is the only one active")

	# Aiming at a mineable cell in reach → mine, not place/harvest.
	var mine := HudCues.active({"mineable": true})
	_check(mine.has(HudCues.Cue.MINE)
			and not mine.has(HudCues.Cue.PLACE) and not mine.has(HudCues.Cue.HARVEST),
		"aiming at mineable terrain shows MINE and not PLACE/HARVEST")

	# Mine / harvest / place are mutually exclusive even if the caller sets more
	# than one — a cell is solid, a corpse, OR empty, never two at once.
	var both := HudCues.active({"mineable": true, "placeable": true, "harvestable": true})
	_check(both.has(HudCues.Cue.MINE)
			and not both.has(HudCues.Cue.HARVEST) and not both.has(HudCues.Cue.PLACE),
		"cursor cues are mutually exclusive — solid wins over corpse/empty")

	# A craftable recipe is independent of the cursor: it can ride alongside a
	# cursor cue (e.g. placing while a recipe is ready).
	var place_craft := HudCues.active({"placeable": true, "craftable": true})
	_check(place_craft.has(HudCues.Cue.PLACE) and place_craft.has(HudCues.Cue.CRAFT),
		"placeable + craftable shows both PLACE and CRAFT")

	# Piloting: your hands fly the ship — only the step-off helm cue, no foot cues.
	var flying := HudCues.active({"piloting": true, "mineable": true, "craftable": true})
	_check(flying.has(HudCues.Cue.HELM) and flying.size() == 1,
		"while piloting, only the helm (step-off) cue shows — foot cues suppressed")
	await process_frame


## Fog-of-war (maps/world/map_discovery.gd): a region is undiscovered until a
## focus comes NEAR it, then stays discovered forever; a far focus reveals
## nothing. Break-the-fix: reveal that ignores distance fails the far-focus check.
func _test_fog_of_war_reveals_by_distance() -> void:
	_t("fog-of-war: near reveals, far does not, and discovery is monotonic")
	var d := MapDiscovery.new()
	d.cell_px = 100.0
	d.reveal_radius = 150.0   # 1.5 cells; the scan box is ~3 cells, so...

	var here := Vector2(50.0, 50.0)          # centre of cell (0,0)
	# INSIDE the reveal scan box (Chebyshev 2 ≤ ~3) but its centre (250,50) is
	# 200 px away — BEYOND the 150 px radius. This is the cell the distance gate
	# actually decides: fogged with the gate, revealed without it. (A cell far
	# outside the box would test the box, not the gate — the trap this round hit.)
	var edge_cell := Vector2i(2, 0)
	var far_cell := Vector2i(20, 0)          # ~2000 px away — well past the box
	var far_pos := d.cell_centre(far_cell)

	_check(not d.is_discovered_at(here), "the starting region is undiscovered (fog)")
	_check(not d.is_discovered(edge_cell), "an in-box-but-far region is undiscovered too")

	# A nearby focus reveals the region around it.
	d.reveal([here])
	_check(d.is_discovered_at(here), "a focus reveals the region it stands in")
	_check(not d.is_discovered(edge_cell),
		"a cell inside the scan box but beyond the radius stays fogged (the reveal-radius gate)")
	_check(not d.is_discovered(far_cell),
		"and a region far from every focus stays fogged")

	# Monotonic: revealing elsewhere never un-discovers what was seen.
	var before := d.discovered_count()
	d.reveal([far_pos])
	_check(d.is_discovered(far_cell), "moving the focus far away reveals the new region")
	_check(d.is_discovered_at(here),
		"and the first region STAYS discovered — discovery is monotonic")
	_check(d.discovered_count() > before, "the discovered set only grew")

	# Break-the-fix guard: bring a focus near the edge cell and it DOES reveal —
	# so the gate is a real distance test, not an accident of the scan box.
	d.reveal([d.cell_centre(edge_cell)])
	_check(d.is_discovered(edge_cell),
		"a focus standing on the edge cell reveals it — the gate is genuine distance (break-the-fix: drop the distance test and the far check above turns green)")
	await process_frame


## The map view is a toggle (maps/world/map_view.gd): hidden by default, its
## visibility flag flips on toggle() and flips back. The help panel toggles the
## same way (asserted end-to-end in world_startup, which owns a real world).
func _test_map_view_toggles_visibility() -> void:
	_t("the world map toggles: hidden by default, flips visible on the key")
	var m := MapView.new()
	root.add_child(m)
	await process_frame  # let _ready run (it hides the map by default)
	_check(not m.visible, "the map starts hidden — not part of the always-on screen")
	m.toggle()
	_check(m.visible, "the map key shows it")
	m.toggle()
	_check(not m.visible, "and the key hides it again")
	m.queue_free()
	await process_frame


## The map draws the wind circulation from a PURE direction helper
## (Airspace.wind_dir_at) that reads the same fraction constants the sim's
## wind_at uses — so the drawn arrows and the felt wind can never drift apart.
## We test the DIRECTION MODEL, not pixels: the sign of the wind at representative
## points, that the column/gap boundaries move when the constants move (the helper
## reads them, doesn't duplicate a literal), and that it is bounds-free (the map
## has no live Airspace.bounds at runtime).
func _test_wind_map_helper_reads_the_circulation() -> void:
	_t("the map's wind helper reads the circulation cell from the Airspace constants")

	# Bounds-free: the map calls this with Airspace deliberately inactive, so the
	# helper must answer from fractions alone, never from a placed world rect.
	Airspace.bounds = Rect2()
	_check(not Airspace.active(), "helper is tested with Airspace inactive (as the map uses it)")

	# fx 0.65 / 0.35 are clear of the centre column and both edges. (a is 0 = floor,
	# 1 = ceiling.) The wind lives ONLY on the spine and rim — NOT per band.
	# Centre column: UP, full height.
	_check(Airspace.wind_dir_at(0.5, 0.2).y < 0.0, "centre column blows UP low down")
	_check(Airspace.wind_dir_at(0.5, 0.9).y < 0.0, "centre column blows UP high up (full height)")
	# Edge columns: DOWN, both sides, full height.
	_check(Airspace.wind_dir_at(0.0, 0.5).y > 0.0, "west edge blows DOWN")
	_check(Airspace.wind_dir_at(1.0, 0.5).y > 0.0, "east edge blows DOWN")
	# The four horizontal DIVIDER rows alternate out/in, top to bottom.
	# Ceiling (a >= 1 - EDGE_H): OUTWARD.
	_check(Airspace.wind_dir_at(0.65, 0.97).x > 0.0, "ceiling east of centre blows OUTWARD (+x)")
	_check(Airspace.wind_dir_at(0.35, 0.97).x < 0.0, "ceiling west of centre blows OUTWARD (-x)")
	# Blue/green gap (GAP_HIGH, ~0.65): INWARD.
	_check(Airspace.wind_dir_at(0.65, 0.65).x < 0.0, "blue/green gap east of centre blows INWARD (-x)")
	_check(Airspace.wind_dir_at(0.35, 0.65).x > 0.0, "blue/green gap west of centre blows INWARD (+x)")
	# Green/red gap (GAP_LOW, ~0.37): OUTWARD [OURS — source is calm here].
	_check(Airspace.wind_dir_at(0.65, 0.37).x > 0.0, "green/red gap east of centre blows OUTWARD [OURS]")
	_check(Airspace.wind_dir_at(0.35, 0.37).x < 0.0, "green/red gap west of centre blows OUTWARD [OURS]")
	# Floor (a <= EDGE_H): INWARD.
	_check(Airspace.wind_dir_at(0.65, 0.03).x < 0.0, "floor east of centre blows INWARD (-x)")
	_check(Airspace.wind_dir_at(0.35, 0.03).x > 0.0, "floor west of centre blows INWARD (+x)")
	# The band INTERIORS between the dividers are calm.
	_check(Airspace.wind_dir_at(0.65, 0.5) == Vector2.ZERO, "the mid-band interior is calm")
	_check(Airspace.wind_dir_at(0.65, 0.2) == Vector2.ZERO, "the deep-band interior is calm")
	_check(Airspace.wind_dir_at(0.65, 0.8) == Vector2.ZERO, "the top-band interior is calm")

	# Boundaries DERIVE from the constants — not baked literals. Straddling each
	# constant flips the answer, so editing airspace.gd moves the map's arrows too.
	var eps := 0.0005
	_check(Airspace.wind_dir_at(0.5 + Airspace.CENTRE_HALF_W - eps, 0.5) == Vector2.UP,
		"just inside the centre half-width is still the updraft")
	_check(Airspace.wind_dir_at(0.5 + Airspace.CENTRE_HALF_W + eps, 0.5) != Vector2.UP,
		"just outside CENTRE_HALF_W is no longer the updraft (boundary reads the constant)")
	_check(Airspace.wind_dir_at(Airspace.EDGE_W - eps, 0.5) == Vector2.DOWN,
		"just inside the edge width is still the downdraft")
	_check(Airspace.wind_dir_at(Airspace.EDGE_W + eps, 0.5) != Vector2.DOWN,
		"just outside EDGE_W is no longer the downdraft (boundary reads the constant)")
	# The top/bottom connector rows read EDGE_H — straddling it flips wind on/off.
	_check(Airspace.wind_dir_at(0.65, 1.0 - Airspace.EDGE_H + eps).x > 0.0,
		"just inside the top row is the outward connector")
	_check(Airspace.wind_dir_at(0.65, 1.0 - Airspace.EDGE_H - eps) == Vector2.ZERO,
		"just below the top row is calm (boundary reads EDGE_H)")
	_check(Airspace.wind_dir_at(0.65, Airspace.EDGE_H - eps).x < 0.0,
		"just inside the bottom row is the inward connector")
	_check(Airspace.wind_dir_at(0.65, Airspace.EDGE_H + eps) == Vector2.ZERO,
		"just above the bottom row is calm (boundary reads EDGE_H)")
	# The band model still exists (islands/hazards/suffocation read it) — pin that
	# band_at_frac reads its own constant, independent of the wind now.
	_check(Airspace.band_at_frac(Airspace.MID_TOP - eps) == Airspace.Band.MID,
		"just below MID_TOP is the mid band")
	_check(Airspace.band_at_frac(Airspace.MID_TOP + eps) == Airspace.Band.GAP_HIGH,
		"just above MID_TOP is the high gap (band boundary reads the constant)")

	# band_at_frac is the pure core band_at delegates to: they agree on a live world.
	Airspace.bounds = SKY_TEST_BOUNDS
	var probe := Vector2(3000, -10000)
	_check(Airspace.band_at(probe) == Airspace.band_at_frac(Airspace.altitude_frac(probe.y)),
		"band_at is band_at_frac on the live altitude — one source of truth")
	Airspace.bounds = Rect2()

	# Break-the-fix: flip the centre column's sign here and the "centre blows UP"
	# checks above go red — proving they pin the direction, not merely non-zero.
	await process_frame


## The easter eggs exist and are deterministic (maps/world/easter_eggs.gd),
## without being surfaced in play. Pinned so they can't silently vanish; WHAT they
## are and HOW to find them is dev-facing in docs/DECISIONS.md, never in the HUD.
func _test_easter_eggs_are_present_but_hidden() -> void:
	_t("the hidden easter eggs are present and pinned (Cairn, ghost whale, salute)")

	# 1. THE CAIRN — planted into the generated world, always solid aetherite at
	#    its fixed coordinate (mirrors world._build_generated_terrain).
	var t := _make_generated_terrain(IslandGen.DEFAULT_SEED)
	EasterEggs.plant_cairn(t)
	_check(t.is_solid(EasterEggs.CAIRN_CELL)
			and t.cell_type(EasterEggs.CAIRN_CELL) == TerrainDB.Type.AETHERITE,
		"the secret Cairn is a solid aetherite beacon at its fixed coordinate")
	# Its arms exist too — a deliberate plus, not a stray cell.
	_check(t.is_solid(EasterEggs.CAIRN_CELL + Vector2i(5, 0))
			and t.is_solid(EasterEggs.CAIRN_CELL + Vector2i(0, -5)),
		"the Cairn's beacon arms are present (it reads as placed, not grown)")
	t.queue_free()

	# 2. THE PALE WANDERER — a deterministic rare-whale roll. A known ghost seed
	#    rolls true, the default world does not, and a seed always agrees with
	#    itself (rare, reproducible).
	var ghost_seed := EasterEggs.GHOST_WHALE_RESIDUE  # residue itself rolls ghost
	_check(EasterEggs.is_ghost_whale(ghost_seed), "a known ghost seed rolls the Pale Wanderer")
	_check(not EasterEggs.is_ghost_whale(IslandGen.DEFAULT_SEED),
		"the default world carries an ordinary whale (the ghost is rare)")
	_check(EasterEggs.is_ghost_whale(ghost_seed) == EasterEggs.is_ghost_whale(ghost_seed),
		"the roll is deterministic — a seed always agrees with itself")

	# 3. THE OLD SALUTE — the Konami sequence matches only its exact tail.
	_check(EasterEggs.konami_matches(EasterEggs.KONAMI.duplicate()),
		"the full salute sequence matches")
	var wrong := EasterEggs.KONAMI.duplicate()
	wrong[wrong.size() - 1] = KEY_Z  # break the last key
	_check(not EasterEggs.konami_matches(wrong), "a wrong final key does not match")
	_check(not EasterEggs.konami_matches([KEY_UP, KEY_UP]),
		"a too-short buffer never matches")
	# It matches on the TAIL of a longer rolling buffer (keys pressed before it
	# don't spoil the salute).
	var padded: Array = [KEY_X, KEY_Y]
	padded.append_array(EasterEggs.KONAMI)
	_check(EasterEggs.konami_matches(padded),
		"the salute matches at the tail of a longer key history")
	await process_frame


# --- The RPG progression layer (Sprint 5) ----------------------------------

## Stats default to level 1 (perk 1 granted), a purchase raises the level and
## grants the next perk, and a stat cannot pass level 5 (the ROADMAP ruling).
func _test_stats_default_raise_and_cap() -> void:
	_t("stats default to level 1, raise by a level, and cap at 5")
	var st := Stats.new()
	# Default: every stat at level 1, with perk 1 unlocked and perk 2 not yet.
	for stat in StatDB.names():
		_check(st.level_of(stat) == StatDB.MIN_LEVEL,
			"%s starts at level 1" % StatDB.stat_name(stat))
		_check(st.has_perk(stat, 1), "and its perk 1 is already granted")
		_check(not st.has_perk(stat, 2), "but not perk 2")

	# Raising one level grants exactly the next perk.
	_check(st.raise_level(StatDB.Stat.BRAWN), "raising Brawn succeeds")
	_check(st.level_of(StatDB.Stat.BRAWN) == 2, "Brawn is now level 2")
	_check(st.has_perk(StatDB.Stat.BRAWN, 2), "and perk 2 is unlocked")
	_check(not st.has_perk(StatDB.Stat.BRAWN, 3), "perk 3 still locked")
	# Other stats are untouched — levels are independent.
	_check(st.level_of(StatDB.Stat.GRACE) == 1, "raising Brawn left Grace at 1")

	# Cap: drive to 5, then the sixth raise is refused and changes nothing.
	while st.can_raise(StatDB.Stat.BRAWN):
		st.raise_level(StatDB.Stat.BRAWN)
	_check(st.level_of(StatDB.Stat.BRAWN) == StatDB.MAX_LEVEL, "Brawn maxes at level 5")
	_check(st.has_perk(StatDB.Stat.BRAWN, 5), "all five perks unlocked at max")
	_check(not st.raise_level(StatDB.Stat.BRAWN),
		"a raise past the cap is refused")
	_check(st.level_of(StatDB.Stat.BRAWN) == StatDB.MAX_LEVEL,
		"and the level is unchanged — cannot exceed 5")
	await process_frame


## Perks change the derived EFFECTS at the right thresholds — not just a flag.
## Each threshold carries its own break-the-fix: an effect that appears at the
## WRONG level would flip one of these checks red.
func _test_stat_perks_change_effects() -> void:
	_t("perks change effects at their thresholds (mining, reach, speed, gates)")
	var st := Stats.new()

	# BRAWN mining speed: baseline 1.0 at level 1, jumps at level 2 (Strong Arm).
	_check(is_equal_approx(st.mine_power_mult(), StatDB.BASE_MINE_MULT),
		"Brawn 1: mining is baseline (%.2f)" % st.mine_power_mult())
	st.set_level(StatDB.Stat.BRAWN, 2)
	_check(st.mine_power_mult() > StatDB.BASE_MINE_MULT,
		"Brawn 2 (Strong Arm): mining is faster (%.2f)" % st.mine_power_mult())

	# BRAWN reach: 0 until level 3 (Long Reach) — the break-the-fix threshold.
	_check(is_equal_approx(st.mine_reach_bonus(), 0.0),
		"Brawn 2: no reach bonus yet (%.2f)" % st.mine_reach_bonus())
	st.set_level(StatDB.Stat.BRAWN, 3)
	_check(st.mine_reach_bonus() > 0.0,
		"Brawn 3 (Long Reach): reach bonus appears (%.2f)" % st.mine_reach_bonus())
	# And a stronger mining multiplier supersedes the weaker at level 4 (Quarryman).
	var m3 := st.mine_power_mult()
	st.set_level(StatDB.Stat.BRAWN, 4)
	_check(st.mine_power_mult() > m3,
		"Brawn 4 (Quarryman): a stronger multiplier supersedes (%.2f > %.2f)"
			% [st.mine_power_mult(), m3])

	# GRACE move speed and the double-jump GATE (only at level 3).
	var g := Stats.new()
	_check(is_equal_approx(g.move_speed_mult(), StatDB.BASE_MOVE_MULT),
		"Grace 1: baseline move speed")
	_check(not g.double_jump_enabled(), "Grace 1: no double jump")
	g.set_level(StatDB.Stat.GRACE, 2)
	_check(g.move_speed_mult() > StatDB.BASE_MOVE_MULT,
		"Grace 2 (Fleet Foot): faster on foot (%.2f)" % g.move_speed_mult())
	_check(not g.double_jump_enabled(),
		"Grace 2: STILL no double jump — it is a level-3 perk (break-the-fix)")
	g.set_level(StatDB.Stat.GRACE, 3)
	_check(g.double_jump_enabled(), "Grace 3 (Double Jump): the second jump unlocks")

	# GRIT health pool + regen gate (regen only at level 3).
	var v := Stats.new()
	var base_hp := v.max_health()
	_check(is_equal_approx(base_hp, StatDB.BASE_HEALTH), "Grit 1: baseline health")
	_check(is_equal_approx(v.regen_rate(), 0.0), "Grit 1: no regen")
	v.set_level(StatDB.Stat.GRIT, 2)
	_check(v.max_health() > base_hp, "Grit 2 (Toughened): more hit points (%.0f)" % v.max_health())
	_check(is_equal_approx(v.regen_rate(), 0.0),
		"Grit 2: still no regen — it is level 3 (break-the-fix)")
	v.set_level(StatDB.Stat.GRIT, 3)
	_check(v.regen_rate() > 0.0, "Grit 3 (Second Wind): regen begins (%.1f/s)" % v.regen_rate())

	# LORE taming GATE (only at level 3) and the trade bonus.
	var l := Stats.new()
	_check(not l.taming_enabled(), "Lore 1: taming disabled")
	_check(is_equal_approx(l.trade_bonus(), 0.0), "Lore 1: no trade bonus")
	l.set_level(StatDB.Stat.LORE, 2)
	_check(l.trade_bonus() > 0.0, "Lore 2 (Haggler): salvage sells for more (%.2f)" % l.trade_bonus())
	_check(not l.taming_enabled(),
		"Lore 2: STILL cannot tame — it is a level-3 perk (break-the-fix)")
	l.set_level(StatDB.Stat.LORE, 3)
	_check(l.taming_enabled(), "Lore 3 (Beast Whisperer): taming is enabled (the gate)")
	await process_frame


## The double-jump perk changes real player BEHAVIOUR: can_air_jump() — the exact
## predicate the jump path uses — is true only with the perk unlocked AND an air
## jump left in the budget.
func _test_double_jump_gated_by_grace() -> void:
	_t("a player can air-jump only with the Grace double-jump perk and a jump to spare")
	# can_air_jump() reads only the perk state and the air-jump budget, so no tree
	# (and no collider) is needed — keeps the test node-free and leak-free.
	var p := Player.new()

	# No perk: no air jump, even fresh off the ground.
	p._air_jumps = 0
	_check(not p.can_air_jump(), "Grace 1: no air jump (perk locked)")

	# One short of the threshold: still refused — the break-the-fix boundary.
	p.stats.set_level(StatDB.Stat.GRACE, 2)
	_check(not p.can_air_jump(), "Grace 2: still no air jump (double jump is level 3)")

	# Perk unlocked: one air jump available, then spent.
	p.stats.set_level(StatDB.Stat.GRACE, 3)
	_check(p.can_air_jump(), "Grace 3: an air jump is available")
	p._air_jumps = Player.MAX_AIR_JUMPS
	_check(not p.can_air_jump(),
		"and once the air-jump budget is spent, no more until landing")

	p.free()  # never entered the tree — a plain free, no children to reap
	await process_frame


## The take-damage payoff: a HOSTILE shell drains the player's GRIT pool; a
## FRIENDLY one (the player's own side) is stopped harmlessly — a shot never
## damages its own faction. The friendly assertion is the break-the-fix: drop the
## faction guard in combat/shot.gd and the own-side shot would drain the pool.
func _test_hostile_shot_hits_player_friendly_does_not() -> void:
	_t("a hostile shot drains the player's GRIT pool; a friendly one does not")
	var p := Player.new()
	p.GRAVITY = 0.0                    # hold it still while we fire at it
	p.position = Vector2(0.0, -6000.0)
	root.add_child(p)
	await _step(3)                     # let the character collider register in the space
	p.velocity = Vector2.ZERO
	var hp0 := p.health
	_check(hp0 > 0.0, "the player starts with a live GRIT pool (%.0f)" % hp0)

	var hurt_total := [0.0]
	p.hurt.connect(func(a: float) -> void: hurt_total[0] += a)

	# A HOSTILE shell (faction 1) straight at the faction-0 player.
	var hostile := Shot.new()
	hostile.position = Vector2(-300.0, -6000.0)
	hostile.velocity = Vector2(1400.0, 0.0)
	hostile.gravity = 0.0
	hostile.faction = 1
	hostile.damage = 25.0
	root.add_child(hostile)
	await _step(25)
	_check(p.health < hp0, "the hostile shell drained the pool (%.0f < %.0f)" % [p.health, hp0])
	_check(is_equal_approx(hurt_total[0], 25.0), "and the hurt signal carried the amount")
	_check(not is_instance_valid(hostile) or hostile.is_queued_for_deletion(),
		"the spent shell is gone, not flying on")

	# A FRIENDLY shell (faction 0, the player's own side): stopped harmlessly.
	var hp1 := p.health
	var friendly := Shot.new()
	friendly.position = Vector2(-300.0, -6000.0)
	friendly.velocity = Vector2(1400.0, 0.0)
	friendly.gravity = 0.0
	friendly.faction = 0
	friendly.damage = 25.0
	root.add_child(friendly)
	await _step(25)
	_check(is_equal_approx(p.health, hp1),
		"the friendly shell left the pool untouched (%.0f) — own side never bites" % p.health)

	p.queue_free()
	await process_frame


## Hazards burn people: a meteor/lava slug that strikes the player drains the GRIT
## pool (no faction — a hazard hits whoever it touches).
func _test_hazard_fireball_burns_the_player() -> void:
	_t("a hazard fireball burns the player on contact")
	var p := Player.new()
	p.GRAVITY = 0.0
	p.position = Vector2(0.0, -6000.0)
	root.add_child(p)
	await _step(3)
	p.velocity = Vector2.ZERO
	var hp0 := p.health

	var fb := HazardFireball.new()
	fb.kind = HazardFireball.Kind.METEOR
	fb.gravity = 0.0
	fb.damage = 40.0
	fb.position = Vector2(0.0, -6300.0)
	fb.velocity = Vector2(0.0, 1000.0)      # straight down onto the player
	root.add_child(fb)
	await _step(30)
	_check(p.health < hp0, "the fireball drained the pool (%.0f < %.0f)" % [p.health, hp0])
	_check(not is_instance_valid(fb) or fb.is_queued_for_deletion(),
		"and the fireball is spent on impact")

	p.queue_free()
	await process_frame


## GRIT measurably matters now that damage is real: the same burst kills a base
## body but not a toughened one, and GRIT regen mends the pool between hits.
func _test_grit_matters_and_regen_heals() -> void:
	_t("higher GRIT survives a killing burst; regen mends between hits")
	# Two bodies, one burst. Base (GRIT 1, pool 100) dies; tough (GRIT 4, pool 250)
	# lives. Sized from the stat, exactly as spawn/respawn does in the world.
	var base := Player.new()
	var tough := Player.new()
	tough.stats.set_level(StatDB.Stat.GRIT, 4)   # Toughened +50, Ironhide +100
	base.max_health = base.stats.max_health(); base.health = base.max_health
	tough.max_health = tough.stats.max_health(); tough.health = tough.max_health
	_check(tough.max_health > base.max_health,
		"GRIT 4 has a bigger pool than GRIT 1 (%.0f > %.0f)" % [tough.max_health, base.max_health])

	var base_died := [false]
	var tough_died := [false]
	base.died.connect(func() -> void: base_died[0] = true)
	tough.died.connect(func() -> void: tough_died[0] = true)

	for _i in 3:                                 # a burst of 3 x 50 = 150 damage
		base.take_damage(50.0)
		tough.take_damage(50.0)
	_check(base.health <= 0.0 and base_died[0], "the base body dies to the burst")
	_check(tough.health > 0.0 and not tough_died[0],
		"the toughened body survives it (%.0f left)" % tough.health)
	base.free(); tough.free()

	# Regen (GRIT 5, Undying = 6/s) climbs the pool back between hits. This is the
	# real _physics_process path, so the body lives in the tree.
	var mender := Player.new()
	mender.GRAVITY = 0.0
	mender.stats.set_level(StatDB.Stat.GRIT, 5)
	mender.max_health = mender.stats.max_health()
	mender.health = mender.max_health
	root.add_child(mender)
	await _step(2)
	mender.take_damage(100.0)
	var wounded := mender.health
	await _step(30)                              # ~0.5s of regen at 6/s ≈ +3 hp
	_check(mender.health > wounded,
		"regen mends the pool between hits (%.1f > %.1f)" % [mender.health, wounded])
	_check(mender.health <= mender.max_health + 0.001, "and never past the max")

	# REGRESSION (owner 2026-08-23: "the hp regen traits aren't working"): regen
	# must mend WHILE PILOTING too. Combat happens at the helm, but the regen tick
	# used to sit BELOW the is_piloting() early-return, so wounds taken flying never
	# healed. Board a helm, take a hit, and prove the pool climbs while piloting.
	var helm := _make_ship({Vector2i(0, 0): BlockDB.Type.HELM})
	helm.position = Vector2(0, -6000)
	var flier := Player.new()
	flier.GRAVITY = 0.0
	flier.stats.set_level(StatDB.Stat.GRIT, 5)
	flier.max_health = flier.stats.max_health()
	flier.health = flier.max_health
	root.add_child(flier)
	await _step(2)
	flier.global_position = helm.global_position
	_check(flier.board(helm, Vector2i(0, 0)) and flier.is_piloting(),
		"the flier took the helm")
	flier.take_damage(100.0)
	var flown_wounded := flier.health
	await _step(30)
	_check(flier.health > flown_wounded,
		"regen mends WHILE PILOTING too (%.1f > %.1f)" % [flier.health, flown_wounded])
	flier.queue_free()
	helm.queue_free()

	mender.queue_free()
	await process_frame


# --- Deep-band unbreathable air: the depth survival gate (life_support.gd) ---

## The depth hazard (WORLD_SPEC / ROADMAP Phase 2): below the deep-band threshold
## the air is unbreathable and an unprotected person suffocates — the GRIT pool
## drains over time; the same person in the breathable mid/top bands takes nothing,
## and the deep gate is OFF-COST up there (nothing runs). LifeSupport.tick is the
## whole tick, so the pool actually falls, exercised without a live world.
func _test_deep_air_suffocates_the_unprotected() -> void:
	_t("unprotected deep air drains the pool over time; mid/top air never bites")
	Tunables.reset_all()
	# The band authority: the deep band (and the lava floor below it) reads as
	# unbreathable; the mid and top bands do not. This is the depth threshold.
	_check(Airspace.is_unbreathable_frac(0.20) and Airspace.is_unbreathable_frac(0.02),
		"the deep band (and below) is unbreathable")
	_check(not Airspace.is_unbreathable_frac(0.50) and not Airspace.is_unbreathable_frac(0.90),
		"the mid and top bands are breathable")

	var p := Player.new()
	p.GRAVITY = 0.0
	root.add_child(p)
	await _step(2)

	# Deep and unprotected: the pool falls as the suffocation ticks land. The tick
	# loop steps time WITHOUT awaiting frames, so the body's own regen never runs —
	# the drop is the deep air alone.
	p.health = p.max_health
	var hp0 := p.health
	var cd := 0.0
	for i in 180:                       # ~3 s deep in the band
		cd = LifeSupport.tick(p, 0.20, 1.0 / 60.0, cd)
	_check(p.health < hp0,
		"3 s of deep air drained the pool (%.0f < %.0f)" % [p.health, hp0])

	# The SAME body in mid-band air: the gate is off-cost — nothing runs, the pool
	# is untouched (this is the "no suffocation when not deep" case).
	p.health = p.max_health
	var hp1 := p.health
	cd = 0.0
	for i in 180:
		cd = LifeSupport.tick(p, 0.50, 1.0 / 60.0, cd)
	_check(is_equal_approx(p.health, hp1),
		"mid-band air never bites (%.0f) — the deep gate is off-cost up here" % p.health)

	# And the top band, for the both-directions world (up is a separate gate).
	cd = 0.0
	for i in 180:
		cd = LifeSupport.tick(p, 0.90, 1.0 / 60.0, cd)
	_check(is_equal_approx(p.health, hp1), "top-band air never bites either")

	p.queue_free()
	await process_frame


## The GATE: carrying the life-support item (possession model) protects you in the
## deep. Break-the-fix — drop the item and the SAME deep run suffocates — proves the
## gate is load-bearing (ignore life-support and "protected takes no damage" fails).
func _test_life_support_gates_the_deep() -> void:
	_t("carrying an Aether Lung protects you in the deep — the equipment gate")
	Tunables.reset_all()
	var p := Player.new()
	p.GRAVITY = 0.0
	root.add_child(p)
	await _step(2)
	p.health = p.max_health
	var hp0 := p.health

	# Possession is the whole gate: one life-support item marks the person protected.
	p.inventory.add(ItemDB.Crafted.LIFE_SUPPORT, 1)
	_check(LifeSupport.protected(p.inventory), "the life-support item marks the person protected")
	var cd := 0.0
	for i in 300:                       # 5 s deep — far past what kills the unprotected
		cd = LifeSupport.tick(p, 0.15, 1.0 / 60.0, cd)
	_check(is_equal_approx(p.health, hp0),
		"protected, the deep air never bit (%.0f) — the gate works" % p.health)

	# Break-the-fix: remove the item and the identical deep run drains the pool.
	p.inventory.remove(ItemDB.Crafted.LIFE_SUPPORT, 1)
	_check(not LifeSupport.protected(p.inventory), "without the item the person is unprotected")
	cd = 0.0
	for i in 300:
		cd = LifeSupport.tick(p, 0.15, 1.0 / 60.0, cd)
	_check(p.health < hp0,
		"drop the Lung and the same deep run suffocates (%.0f) — the gate is load-bearing" % p.health)

	p.queue_free()
	await process_frame


## The recipe (items/recipes.gd): the Aether Lung crafts from its inputs (copper
## ingot + blubber) and consumes them; one input short crafts nothing and leaves
## the inventory untouched.
func _test_life_support_recipe_crafts() -> void:
	_t("the life-support recipe crafts from its inputs; missing an input changes nothing")
	var recipe := {}
	for r in Recipes.RECIPES:
		if int(r["output"]) == ItemDB.Crafted.LIFE_SUPPORT:
			recipe = r
			break
	_check(not recipe.is_empty(), "there is a recipe that outputs the Aether Lung")
	_check(recipe["inputs"].size() >= 2, "and it takes more than one material (a real make step)")

	# Every input present: it crafts, consumes the inputs, yields the item.
	var inv := Inventory.new()
	for id in recipe["inputs"]:
		inv.add(int(id), int(recipe["inputs"][id]))
	_check(Recipes.can_craft(inv, recipe), "with every input present it is craftable")
	_check(Recipes.craft(inv, recipe), "and craft() succeeds")
	_check(inv.count(ItemDB.Crafted.LIFE_SUPPORT) == int(recipe.get("count", 1)),
		"the Aether Lung was produced (%d)" % inv.count(ItemDB.Crafted.LIFE_SUPPORT))
	var consumed := true
	for id in recipe["inputs"]:
		if inv.count(int(id)) != 0:
			consumed = false
	_check(consumed, "and every input was consumed")

	# One input short: nothing crafts, the inventory is left exactly as it was.
	var poor := Inventory.new()
	var first_id := int(recipe["inputs"].keys()[0])
	poor.add(first_id, int(recipe["inputs"][first_id]))   # only the first input, in full
	_check(not Recipes.can_craft(poor, recipe), "one input missing is not craftable")
	_check(not Recipes.craft(poor, recipe), "craft() refuses")
	_check(poor.count(ItemDB.Crafted.LIFE_SUPPORT) == 0
			and poor.count(first_id) == int(recipe["inputs"][first_id]),
		"and nothing was consumed or produced — no partial spend")
	await process_frame


## Firing speed is a real, upgradable + tunable rate of fire: the GRACE quickness
## perk shortens the SIDEARM interval, the F2 fire_rate lever shortens it further,
## and turret brownout still STRETCHES the ship's cadence (the lever shortens that
## too, but the personal perk does not reach the ship's guns).
func _test_firing_speed_is_upgradable_and_tunable() -> void:
	_t("firing speed: a perk + the F2 lever shorten the interval; brownout still stretches turrets")
	var base := Player.new()
	var quick := Player.new()
	quick.stats.set_level(StatDB.Stat.GRACE, 2)   # Fleet Foot: fire_rate 1.25
	var cd := 0.18

	# Perk: the multiplier rises, so the interval shrinks (measurably faster).
	_check(is_equal_approx(base.fire_rate_mult(), 1.0), "base fire-rate multiplier is 1.0")
	_check(quick.fire_rate_mult() > 1.0,
		"Grace 2 (Fleet Foot) raises the multiplier (%.2f)" % quick.fire_rate_mult())
	_check(quick.sidearm_interval(cd) < base.sidearm_interval(cd),
		"a perked player fires faster (%.3fs < %.3fs)"
			% [quick.sidearm_interval(cd), base.sidearm_interval(cd)])
	# Sprinter (Grace 5) supersedes with the stronger quickness — faster still.
	var fleet_interval := quick.sidearm_interval(cd)
	quick.stats.set_level(StatDB.Stat.GRACE, 5)
	_check(quick.sidearm_interval(cd) < fleet_interval,
		"Grace 5 (Sprinter) is faster still (%.3fs < %.3fs)"
			% [quick.sidearm_interval(cd), fleet_interval])

	# The F2 lever: a 2x fire-rate halves the base interval, independent of perks.
	var levered := base.sidearm_interval(cd, 2.0)
	_check(levered < base.sidearm_interval(cd),
		"the fire_rate lever shortens the interval (%.3fs < %.3fs)"
			% [levered, base.sidearm_interval(cd)])
	_check(is_equal_approx(levered, cd / 2.0), "a 2x lever halves it exactly")

	# Turret brownout still STRETCHES the cadence; the lever shortens it. The
	# static helper carries no perk term — the ship's guns are the ship's.
	var full := Player.turret_interval(0.5, 1.0, 1.0)
	var browned := Player.turret_interval(0.5, 0.5, 1.0)
	_check(browned > full,
		"a browned-out ship fires slower (%.3fs > %.3fs)" % [browned, full])
	_check(is_equal_approx(Player.turret_interval(0.5, 1.0, 2.0), 0.25),
		"and the fire_rate lever halves the turret cadence too")

	base.free(); quick.free()
	await process_frame


## The salvage economy: items have money values, appraise sums without mutating,
## sell_all clears the sellable items and returns the money, and the LORE trade
## bonus raises the payout.
func _test_salvage_economy_values_and_selling() -> void:
	_t("salvage sells by material value, trade bonus raises the payout")
	# Known values (grounded in the wiki): blubber 7, whale oil 50, aetherite 40.
	_check(Economy.sell_value(ItemDB.Product.BLUBBER) == 7, "a blubber product is worth 7")
	_check(Economy.sell_value(ItemDB.Crafted.WHALE_OIL) == 50, "whale oil is worth 50")
	_check(Economy.sell_value(TerrainDB.Type.AETHERITE) == 40, "aetherite is the prize (40)")

	var inv := Inventory.new()
	inv.add(ItemDB.Product.BLUBBER, 3)         # 21
	inv.add(TerrainDB.Type.STONE, 5)           # 10
	var expected := 3 * 7 + 5 * 2               # 31
	_check(Economy.appraise(inv, 0.0) == expected,
		"appraise sums material value (%d)" % Economy.appraise(inv, 0.0))
	_check(inv.total() == 8, "appraise does NOT mutate the pack (%d items)" % inv.total())

	# Trade bonus (LORE): +25% raises the appraisal, floored.
	_check(Economy.appraise(inv, 0.25) == int(floor(expected * 1.25)),
		"a 25%% trade bonus raises the price (%d)" % Economy.appraise(inv, 0.25))

	# Selling everything empties the sellable items and returns the money.
	var gained := Economy.sell_all(inv, 0.0)
	_check(gained == expected, "sell_all returns the total (%d)" % gained)
	_check(inv.is_empty(), "and the sold items leave the pack")
	await process_frame


## Training: cost rises with the level, a purchase deducts money and raises the
## stat, and it is refused when broke or maxed (no half-spend either way).
func _test_training_costs_deducts_and_refuses() -> void:
	_t("training costs money that rises, deducts on success, refuses broke or maxed")
	var st := Stats.new()
	var w := Wallet.new()

	# Cost rises with the current level: 1->2 is 100, 2->3 is 200.
	_check(Training.cost_to_raise(st, StatDB.Stat.BRAWN) == Training.BASE_COST,
		"raising from level 1 costs the base (%d)" % Training.cost_to_raise(st, StatDB.Stat.BRAWN))

	# Broke: refused, nothing changes.
	_check(not Training.can_train(st, w, StatDB.Stat.BRAWN), "broke: cannot afford it")
	_check(not Training.train(st, w, StatDB.Stat.BRAWN), "broke: the purchase is refused")
	_check(st.level_of(StatDB.Stat.BRAWN) == 1 and w.balance == 0,
		"and nothing changed — no level, no debt")

	# Funded: it buys the level and deducts exactly the cost.
	w.add(1000)
	var before := w.balance
	var cost := Training.cost_to_raise(st, StatDB.Stat.BRAWN)
	_check(Training.train(st, w, StatDB.Stat.BRAWN), "funded: the purchase succeeds")
	_check(st.level_of(StatDB.Stat.BRAWN) == 2, "the stat rose a level")
	_check(w.balance == before - cost, "and exactly the cost was deducted (%d)" % (before - w.balance))
	_check(Training.cost_to_raise(st, StatDB.Stat.BRAWN) > cost,
		"the next level costs more (%d > %d)"
			% [Training.cost_to_raise(st, StatDB.Stat.BRAWN), cost])

	# Maxed: drive to 5, then it refuses regardless of money.
	while st.can_raise(StatDB.Stat.BRAWN):
		w.add(10000)
		Training.train(st, w, StatDB.Stat.BRAWN)
	_check(st.level_of(StatDB.Stat.BRAWN) == StatDB.MAX_LEVEL, "Brawn is maxed")
	_check(Training.cost_to_raise(st, StatDB.Stat.BRAWN) == -1,
		"a maxed stat has no next cost (-1)")
	var rich := w.balance
	_check(not Training.train(st, w, StatDB.Stat.BRAWN),
		"a maxed stat refuses training even when rich")
	_check(w.balance == rich, "and no money is taken for the refused purchase")
	await process_frame


# --- Save / load ----------------------------------------------------------

## Terrain persists as SEED + DIFFS: a loaded world regenerates from the seed and
## re-applies only the cells the player dug/placed. The break-the-fix is the
## apply step — skip it and a dug cell is still solid after load.
func _test_save_terrain_diffs_round_trip() -> void:
	_t("terrain saves as seed + diffs: load regenerates then re-applies edits")
	var seed_value := 4242
	var t := _make_generated_terrain(seed_value)

	var dug := _find_solid_cell(t)
	_check(dug.x != 0x7fffffff, "found a generated solid cell to dig")
	var placed := _find_air_above(t, dug)
	_check(not t.is_solid(placed), "the place target starts as air")

	# Edit the world: dig one solid cell, place a material into an air cell.
	_check(t.dig(dug) != TerrainDB.Type.AIR, "dug a real cell")
	_check(not t.is_solid(dug), "the dug cell is now air")
	_check(t.place(placed, TerrainDB.Type.STONE), "placed a material into the air cell")
	_check(t.is_solid(placed), "the placed cell is now solid")

	# A save stores only these diffs (plus the seed).
	var diffs := SaveGame.encode_terrain_diffs(t)
	_check(diffs.size() == 6, "two edits captured as 3 ints each (%d)" % diffs.size())

	# Load: a fresh terrain regenerated from the same seed. BEFORE diffs it is the
	# pristine world — the break-the-fix witness.
	var loaded := _make_generated_terrain(seed_value)
	_check(loaded.is_solid(dug),
		"regenerated-from-seed: the dug cell is solid again (pre-diff — break-the-fix)")
	_check(not loaded.is_solid(placed),
		"regenerated-from-seed: the placed cell is air again (pre-diff)")

	# Apply the saved diffs — the load step that puts the player's mark back.
	SaveGame.apply_terrain_diffs(loaded, diffs)
	_check(not loaded.is_solid(dug), "after applying diffs: the dug cell is AIR")
	_check(loaded.is_solid(placed), "after applying diffs: the placed cell is present")
	_check(loaded.cell_type(placed) == TerrainDB.Type.STONE, "and the placed material is right")

	# Determinism vs diffs: the loaded world equals the saved grid by fingerprint.
	_check(_terrain_fingerprint(t) == _terrain_fingerprint(loaded),
		"a loaded world (seed + diffs) matches the saved grid fingerprint")

	t.queue_free()
	loaded.queue_free()
	await process_frame


## Ships round-trip through to_payload/from_data (the wire/severing path), and the
## player through its clean Stats/Wallet/Inventory/health fields. Covers the whale
## carcass state and the coarse-collider ordering (rebuild after the pool is set).
func _test_save_ships_and_player_round_trip() -> void:
	_t("ships (payload) and player (stats/money/inventory/health/pos) survive save/load")
	var fleet := Fleet.new()
	root.add_child(fleet)
	await process_frame

	var ship := fleet.spawn_ship_from_cells(_starter_ship(), Vector2(120, -300), 1, 0.0, 1.0, 0)
	ship.damage_cell(Vector2i(-5, 0), 25.0)
	# Fully destroy a hull cell so its WALL becomes a ghost (block gone, wall
	# stands) — the case where re-deriving walls from the footprint on load would
	# drift severability. The save must bring the exact wall layer back.
	ship.damage_cell(Vector2i(-4, 0), 99999.0)
	_check(not ship.has_block(Vector2i(-4, 0)) and ship.walls.has(Vector2i(-4, 0)),
		"the vessel has a ghost wall (block destroyed, wall standing) before save")
	var ship_walls: int = ship.walls.size()
	var whale := fleet.spawn_ship_from_cells(
		ShipLayout.load_cells("res://ships/whale.ship"), Vector2(-600, -200), 0, 0.0, 1.0, 2)
	whale.shared_health_max = 15000.0
	whale.shared_health = 0.0  # dead → a carcass
	whale.rebuild()
	_check(whale.is_carcass(), "the whale starts as a carcass")

	var ship_mass := ship.mass
	var ship_blocks := ship.blocks.size()
	var ship_hp: float = ship.blocks[Vector2i(-5, 0)]["hp"]

	var encoded: Array = []
	for s in fleet.ships():
		encoded.append(SaveGame.encode_ship(s))

	var loaded_fleet := Fleet.new()
	root.add_child(loaded_fleet)
	await process_frame
	for sd in encoded:
		SaveGame.spawn_ship_from_encoded(loaded_fleet, sd)

	_check(loaded_fleet.ships().size() == 2, "both ships restored (%d)" % loaded_fleet.ships().size())
	var r_ship: Ship = null
	var r_whale: Ship = null
	for s in loaded_fleet.ships():
		if s.faction == 2:
			r_whale = s
		else:
			r_ship = s
	_check(r_ship != null and r_whale != null, "the vessel and the whale both came back")
	if r_ship != null:
		_check_approx(r_ship.mass, ship_mass, 0.01, "vessel mass restored")
		_check(r_ship.blocks.size() == ship_blocks, "vessel block count restored")
		_check_approx(r_ship.blocks[Vector2i(-5, 0)]["hp"], ship_hp, 0.01,
			"vessel damage state restored")
		_check(r_ship.walls.size() == ship_walls,
			"vessel wall layer restored exactly (%d walls)" % r_ship.walls.size())
		_check(r_ship.walls.has(Vector2i(-4, 0)) and not r_ship.has_block(Vector2i(-4, 0)),
			"the ghost wall survived save/load (not re-derived from the footprint)")
	if r_whale != null:
		_check(r_whale.is_carcass(), "the whale is still a carcass after load")
		_check(r_whale.shared_health_max > 0.0, "the whale kept its shared-health pool")
		_check(_shape_count(r_whale) == r_whale._merge_rects().size(),
			"the carcass got the precise collider (pool empty → exact grid, rebuilt after)")

	# Player round trip.
	var p := Player.new()
	root.add_child(p)
	p.stats.set_level(StatDB.Stat.BRAWN, 3)
	p.wallet.add(450)
	p.inventory.add(TerrainDB.Type.STONE, 7)
	p.inventory.add(TerrainDB.Type.ORE, 2)
	p.global_position = Vector2(333, -222)
	p.health = 42.0
	var pd := SaveGame.encode_player(p)

	var p2 := Player.new()
	root.add_child(p2)
	SaveGame.apply_player(p2, pd)
	_check(p2.stats.level_of(StatDB.Stat.BRAWN) == 3, "player stat level restored")
	_check(p2.wallet.balance == 450, "player money restored")
	_check(p2.inventory.count(TerrainDB.Type.STONE) == 7, "inventory stone restored")
	_check(p2.inventory.count(TerrainDB.Type.ORE) == 2, "inventory ore restored")
	_check(p2.global_position.is_equal_approx(Vector2(333, -222)), "player position restored")
	_check_approx(p2.health, 42.0, 0.01, "player health restored")

	ship.queue_free()
	whale.queue_free()
	p.queue_free()
	p2.queue_free()
	fleet.queue_free()
	loaded_fleet.queue_free()
	await process_frame


## The save-panel list reads name/timestamp/playtime/location straight from the
## header, with no ship/terrain restore — so a load menu is cheap to draw.
func _test_save_metadata_readable_without_full_load() -> void:
	_t("save metadata (name/timestamp/playtime/location) is readable without a full load")
	var name := "unittest_meta"
	var data := {
		"format": SaveGame.FORMAT_VERSION,
		"name": name,
		"timestamp": 1000,
		"timestamp_str": "2026-08-22T12:00:00",
		"playtime": 125.0,
		"location": "The Deep Reaches",
		"world_seed": 7,
		"terrain_diffs": [],
		"ships": [],
		"player": {},
	}
	_check(SaveGame.save_to(name, data), "the save wrote to disk")

	var found := {}
	for row in SaveGame.list_saves():
		if row["name"] == name:
			found = row
	_check(not found.is_empty(), "the save appears in the list")
	_check(bool(found.get("valid", false)), "and is marked loadable")
	_check(int(found.get("timestamp", 0)) == 1000, "timestamp read from the header")
	_check_approx(float(found.get("playtime", 0.0)), 125.0, 0.01, "playtime read from the header")
	_check(String(found.get("location", "")) == "The Deep Reaches", "location read from the header")

	DirAccess.remove_absolute("%s/%s.json" % [SaveGame.SAVE_DIR, name])
	await process_frame


## A missing, corrupt or unsupported-version save must fail cleanly — false / {},
## never a crash, and the game stays valid.
func _test_save_load_fails_gracefully() -> void:
	_t("loading a missing / corrupt / older-version save fails without crashing")
	DirAccess.make_dir_recursive_absolute(SaveGame.SAVE_DIR)

	_check(SaveGame.load_from("does_not_exist_12345").is_empty(),
		"a missing save loads as empty, no crash")

	var corrupt := "unittest_corrupt"
	var cf := FileAccess.open("%s/%s.json" % [SaveGame.SAVE_DIR, corrupt], FileAccess.WRITE)
	cf.store_string("{ this is not valid json ]]")
	cf.close()
	_check(SaveGame.load_from(corrupt).is_empty(), "a corrupt save loads as empty, no crash")

	var older := "unittest_oldver"
	SaveGame.save_to(older, {"format": 0, "world_seed": 1})
	var od := SaveGame.load_from(older)
	_check(not od.is_empty(), "the older-version file still parses as JSON")
	_check(not SaveGame._supported(od), "but its format is flagged unsupported")
	_check(not SaveGame.restore(null, od), "restore refuses an unsupported save outright")

	var invalid_flagged := false
	for row in SaveGame.list_saves():
		if row["name"] == older:
			invalid_flagged = not bool(row["valid"])
	_check(invalid_flagged, "the saves list flags the unsupported file as unreadable")

	DirAccess.remove_absolute("%s/%s.json" % [SaveGame.SAVE_DIR, corrupt])
	DirAccess.remove_absolute("%s/%s.json" % [SaveGame.SAVE_DIR, older])
	await process_frame


## First generated solid cell (scans the sparse resident chunks). Returns a
## sentinel x of 0x7fffffff if the world has none (a bad seed).
func _find_solid_cell(t: Terrain) -> Vector2i:
	for coord in t.chunk_coords():
		var base: Vector2i = coord * Terrain.CHUNK
		for ly in Terrain.CHUNK:
			for lx in Terrain.CHUNK:
				var c := Vector2i(base.x + lx, base.y + ly)
				if t.is_solid(c):
					return c
	return Vector2i(0x7fffffff, 0)


## The nearest air cell above `from` — a safe place to test placement.
func _find_air_above(t: Terrain, from: Vector2i) -> Vector2i:
	for dy in range(1, 300):
		var c := from - Vector2i(0, dy)
		if not t.is_solid(c):
			return c
	return from - Vector2i(0, 400)


# --- Tunables + debug window (session 5: the live-tuning console) -----------

func _test_tunables_get_set_reset_and_clamp() -> void:
	_t("Tunables: get / set / reset-to-default, clamped to min/max")
	# Defaults mirror the origin consts (parity — behaviour identical until touched).
	_check_approx(Tunables.get_num("whale_health"), 15000.0, 0.001,
		"whale_health default = WHALE_HEALTH")
	_check(Tunables.get_int("whale_pod_size") == 3,
		"whale_pod_size default = WHALE_POD_SIZE (3)")

	Tunables.set_value("whale_health", 8000.0)
	_check_approx(Tunables.get_num("whale_health"), 8000.0, 0.001, "set stores the value")

	# Clamp above max and below min.
	Tunables.set_value("whale_health", 1.0e9)
	_check_approx(Tunables.get_num("whale_health"),
		float(Tunables.def("whale_health")["max"]), 0.001, "set clamps to max")
	Tunables.set_value("whale_health", -50.0)
	_check_approx(Tunables.get_num("whale_health"),
		float(Tunables.def("whale_health")["min"]), 0.001, "set clamps to min")

	# Int lever: rounds and clamps.
	Tunables.set_value("whale_pod_size", 5.7)
	_check(Tunables.get_int("whale_pod_size") == 6, "int lever rounds")
	Tunables.set_value("whale_pod_size", 99)
	_check(Tunables.get_int("whale_pod_size") == int(Tunables.def("whale_pod_size")["max"]),
		"int lever clamps to max")

	# Unknown id is a safe no-op.
	_check(Tunables.set_value("nope_not_a_lever", 1.0) == null, "unknown id is ignored")

	# reset one, reset all.
	Tunables.reset("whale_health")
	_check_approx(Tunables.get_num("whale_health"), 15000.0, 0.001,
		"reset restores the default")
	Tunables.reset_all()
	_check(Tunables.get_int("whale_pod_size") == 3, "reset_all restores every default")


func _test_a_system_reads_the_tunable() -> void:
	_t("a system READS the tunable: Hazards meteor damage reflects the lever")
	var hz := Hazards.new()
	hz.world_rect = Rect2(0, 0, 10000, 10000)
	hz.scale_unit = 1.0
	root.add_child(hz)

	# Default: a spawned meteor carries METEOR_DAMAGE (60).
	var m1 := hz.spawn_meteor(Vector2(5000, 1000))
	_check_approx(m1.damage, 60.0, 0.001, "default meteor damage = 60 (parity)")

	# Change the lever; a freshly spawned meteor reflects it live. (Break-the-fix:
	# if spawn_meteor hardcoded METEOR_DAMAGE, m2.damage would stay 60 and fail.)
	Tunables.set_value("meteor_damage", 200.0)
	var m2 := hz.spawn_meteor(Vector2(5000, 1000))
	_check_approx(m2.damage, 200.0, 0.001, "set meteor_damage changes the spawned meteor")

	Tunables.reset_all()
	hz.queue_free()
	await process_frame


func _test_whale_ai_reads_the_ram_tunable() -> void:
	_t("WhaleAI READS the ram tunable: a stronger push accel rams harder")
	var cells := {}
	for x in 3:
		for y in 3:
			cells[Vector2i(x, y)] = BlockDB.Type.BLUBBER
	var whale := _make_ship(cells, true)  # floating: gravity off, only the push acts
	whale.shared_health_max = 1000.0
	whale.shared_health = 1000.0
	whale.global_position = Vector2.ZERO

	# Run A: a weak ram.
	Tunables.set_value("whale_push_accel", 200.0)
	var target_a := _make_ship({Vector2i(0, 0): BlockDB.Type.HULL}, true)
	target_a.global_position = Vector2(600, 0)
	var ai_a := WhaleAI.new()
	ai_a.whale = whale
	ai_a.home = whale.global_position
	ai_a.provoke()
	whale.linear_velocity = Vector2.ZERO
	for i in 10:
		ai_a.tick(1.0 / 60.0, target_a)
		await physics_frame
	var speed_a := whale.linear_velocity.length()

	# Run B: a strong ram, fresh brain, reset motion/position.
	whale.linear_velocity = Vector2.ZERO
	whale.global_position = Vector2.ZERO
	Tunables.set_value("whale_push_accel", 1600.0)
	var target_b := _make_ship({Vector2i(0, 0): BlockDB.Type.HULL}, true)
	target_b.global_position = Vector2(600, 0)
	var ai_b := WhaleAI.new()
	ai_b.whale = whale
	ai_b.home = whale.global_position
	ai_b.provoke()
	for i in 10:
		ai_b.tick(1.0 / 60.0, target_b)
		await physics_frame
	var speed_b := whale.linear_velocity.length()

	_check(speed_a > 1.0, "the weak ram still moves the whale (%.1f px/s)" % speed_a)
	_check(speed_b > speed_a * 2.0,
		"a stronger push tunable rams harder (%.1f vs %.1f px/s)" % [speed_b, speed_a])

	Tunables.reset_all()
	whale.queue_free()
	target_a.queue_free()
	target_b.queue_free()
	await process_frame


func _test_debug_window_toggles_and_switches_tabs() -> void:
	_t("debug window: toggle visibility + tab switching (state, not pixels)")
	var win := DebugWindow.new()
	root.add_child(win)
	await process_frame  # let _ready build the tabs

	_check(not win.visible, "hidden by default (a dev overlay, not always-on chrome)")
	win.toggle()
	_check(win.visible, "toggle shows it")
	win.toggle()
	_check(not win.visible, "toggle hides it again")

	# Spawn + one tab per Tunables group + Player + Perf.
	var expected := 3 + Tunables.groups().size()
	_check(win._tabs.get_tab_count() == expected,
		"built %d tabs (Spawn/Player/Perf + %d lever groups)"
			% [expected, Tunables.groups().size()])

	win.set_tab(2)
	_check(win.active_tab() == 2, "set_tab switches the active tab")
	win.set_tab(0)
	_check(win.active_tab() == 0, "and back to the first")

	win.queue_free()
	await process_frame


## The web build's browser-safe key aliases (maps/world/web_keys.gd). The
## harness cannot press browser keys, so this tests the PURE mapping — which is
## exactly why the helper takes `web` as an argument (OS.has_feature cannot be
## faked). The property that actually matters is the last one: an alias that
## collides with a key the game already reads is worse than the F-key it
## replaces, and only a test can keep that true as bindings are added.
func _test_web_key_aliases() -> void:
	_t("web key aliases remap the browser-reserved F-row and collide with nothing")

	# 1. DESKTOP — pure identity, for every key, reserved or not.
	for key: int in [KEY_F1, KEY_F3, KEY_F5, KEY_F9, KEY_F2, KEY_TAB, KEY_A, KEY_0]:
		_check(WebKeys.remap_for(key, false) == key,
			"desktop leaves %s alone" % OS.get_keycode_string(key))
	_check(WebKeys.unalias_for(KEY_P, false) == KEY_P,
		"desktop never folds a letter onto an F-key (P stays P)")

	# 2. WEB — the four keys the browser steals get an alias.
	_check(WebKeys.remap_for(KEY_F1, true) == KEY_I, "web: F1 (browser help) -> I")
	_check(WebKeys.remap_for(KEY_F3, true) == KEY_L, "web: F3 (find-in-page) -> L")
	_check(WebKeys.remap_for(KEY_F5, true) == KEY_P, "web: F5 (PAGE RELOAD) -> P")
	_check(WebKeys.remap_for(KEY_F9, true) == KEY_O, "web: F9 -> O")
	# Everything else is untouched even on web — F2 is not reserved, and the
	# game's own bindings must not shift under the player.
	for key: int in [KEY_F2, KEY_TAB, KEY_A, KEY_0, KEY_H]:
		_check(WebKeys.remap_for(key, true) == key,
			"web leaves the unreserved %s alone" % OS.get_keycode_string(key))

	# 3. THE REVERSE FOLD — what world._input actually calls. On web an alias
	#    resolves to its F-key, and the F-key still resolves to itself, so BOTH
	#    reach the toggle (a browser that lets F1 through keeps working).
	for source: int in WebKeys.WEB_ALIASES.keys():
		var alias: int = WebKeys.remap_for(source, true)
		_check(WebKeys.unalias_for(alias, true) == source,
			"web: pressing %s reaches the %s toggle"
				% [OS.get_keycode_string(alias), OS.get_keycode_string(source)])
		_check(WebKeys.unalias_for(source, true) == source,
			"web: %s itself still reaches its toggle" % OS.get_keycode_string(source))

	# 4. NO COLLISION — targets are distinct, none is itself a source (so the
	#    fold can never chain), and none is a key the game already reads:
	#    neither a bound action in project.godot nor a raw key in world.gd.
	var targets: Array = WebKeys.WEB_ALIASES.values()
	var unique: Dictionary = {}
	for target: int in targets:
		unique[target] = true
	_check(unique.size() == targets.size(),
		"every alias is a different key (%d targets)" % targets.size())
	for target: int in targets:
		_check(not WebKeys.WEB_ALIASES.has(target),
			"%s is not itself remapped (the fold cannot chain)"
				% OS.get_keycode_string(target))

	# The action map is the authority on bound keys — read it rather than
	# restating it, so a future binding of P breaks this test loudly.
	_check(InputMap.has_action("move_left"),
		"the action map is loaded (so the collision check below is not vacuous)")
	var bound: Dictionary = {}
	for action: StringName in InputMap.get_actions():
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey:
				var k := event as InputEventKey
				# Only PLAIN presses collide — Godot's built-in ui_* actions bind
				# Ctrl+L and Ctrl+O, which a bare L or O never triggers.
				if k.ctrl_pressed or k.alt_pressed or k.shift_pressed or k.meta_pressed:
					continue
				# This project binds by physical_keycode, leaving keycode 0.
				var code: int = k.keycode if k.keycode != 0 else k.physical_keycode
				bound[code] = action
	for target: int in targets:
		_check(not bound.has(target),
			"%s is not bound to a game action" % OS.get_keycode_string(target))

	# The raw keys world.gd reads directly (not in the action map): the UI
	# toggles, host/join, the balloon keys and the trainer number row — 0 sells
	# salvage, which is why the diagnostic alias is not 0.
	var raw_keys: Array[int] = [KEY_TAB, KEY_K, KEY_H, KEY_J, KEY_Y, KEY_U,
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_0, KEY_UP, KEY_DOWN, KEY_ENTER,
		KEY_F1, KEY_F2, KEY_F3, KEY_F5, KEY_F9]
	for target: int in targets:
		_check(not raw_keys.has(target),
			"%s is not a raw key world.gd already reads" % OS.get_keycode_string(target))
