class_name Backdrop
extends Control

## THE LAYERED BACKGROUND (owner 2026-08-29: "the Source also has SOME layered
## background designs to enrich the world one is in… it'd change based on CELL
## in the map's grid").
##
## Three parallax depths of code-drawn silhouettes behind the world — distant
## crag islands, drifting cloud banks, thin spires — over a soft altitude
## gradient. Two rules give it its character:
##
##   * WHAT is drawn comes from the MAP CELL (the same 512-fine-tile grid
##     MapDiscovery uses): each map cell rolls a MOTIF from the world seed, so
##     one region of the sky is spire country and another is cloud shoals, and
##     crossing a map cell changes the scenery — the owner's ask, literally.
##     Deterministic in (seed, cell): the same world always wears the same sky.
##   * The PALETTE comes from the airspace BAND at the camera's altitude,
##     blended smoothly across the gaps — the same three-band colour language
##     the map's tints and the deep fog already speak, so the backdrop never
##     invents a fourth vocabulary.
##
## It sits on its OWN CanvasLayer at layer -1 (behind the world's default
## layer 0), so everything real draws over it. Screen-space, so it never
## scales with world_scale; parallax is a fraction of the camera's position,
## which is scale-agnostic by nature.
##
## Rendering ONLY, per the standing split: the world hands over plain values
## (backdrop_status), and the generative half is STATIC PURE functions
## (cell_motif / cell_features / band_palette) so the suite can pin
## determinism, variety and the band language without a renderer.

var world: Node2D

## Each layer's accumulated scroll in screen px, and the camera position the last
## frame was drawn from. Integrated rather than derived, so a ZOOM CHANGE never
## moves the backdrop on its own — see `layer_step`.
## MEMOISED FEATURES. `cell_features` is pure in (seed, layer, cell) and its
## answer is fixed forever — but it was being recomputed for every lattice cell
## of every layer on EVERY FRAME, and each call allocates a
## `RandomNumberGenerator`, an array for the hash and a dictionary per feature.
## Measured: 107 calls and 0.475 ms per frame, all of it garbage. A frame's worth
## of cells is about a hundred entries, so the whole visible sky fits in the
## cache and a quiet frame does lookups instead of allocations.
##
## Keyed by (layer, cell); the cache is dropped whole if the WORLD changes under
## it (`_cache_key` = seed + map cell size), which is the only thing that can
## make a remembered answer wrong.
var _features := {}
var _cache_key := ""
## The visible sky is ~100 cells; this is room for a big window and some
## scrolling slack before the whole thing is dropped and refilled.
const FEATURE_CACHE_MAX := 3000

var _scroll: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var _last_cam := Vector2.ZERO
var _primed := false

## Parallax factor per depth layer, far to near. A factor is how much of the
## WORLD'S APPARENT motion the layer rides — see `layer_scroll`: the camera's
## motion is multiplied by the live zoom before the factor is applied, so a
## factor is an honest "fraction of the speed the terrain appears to move",
## and a layer does not creep closer when the helm pulls the camera back.
##
## CALM-DOWN PASS (owner 2026-08-29: "too bright and moves TOO fast, makes me
## dizzy — should not feel so 'close'"). The first cut applied the factor to
## RAW world pixels, so at the on-foot zoom of 0.9 the near layer really rode
## 56% of the terrain's apparent speed — and 72% at the helm. That is not a
## backdrop, that is a second foreground. These factors are what is left after
## reading them as apparent speed and then cutting them hard; `backdrop_parallax`
## (F2) is the dial if the owner wants some of it back.
const LAYERS := [0.02, 0.05, 0.10]

## Lattice spacing of backdrop features per layer, in SCREEN px — far layers
## pack tighter (smaller, denser shapes read as distance).
const LATTICE := [340.0, 460.0, 640.0]

## Motifs a map cell can roll. The names are the contract the tests pin.
const MOTIFS := ["crags", "clouds", "spires", "shoal", "open"]

## How much of the sky is OPEN (no features) — the world must breathe; a
## backdrop with something in every cell is wallpaper, not distance.
const OPEN_WEIGHT := 2   # "open" is rolled this many extra times

## The motif grid must NOT dilate with the parallax factor. A feature's motif
## is looked up at its VIRTUAL world anchor (lattice position ÷ factor), so a
## very slow layer would project one screenful across dozens of map cells and
## every silhouette would roll its own motif — "spire country" would dissolve
## into confetti. The lookup factor is floored here (the original far-layer
## value), which keeps a motif region roughly one map cell wide at every depth
## while the DRAWN speed goes as slow as we like. Purely a lookup clamp: a
## feature's anchor is still fixed forever, so nothing ever changes motif
## on-screen.
const MOTIF_FLOOR := 0.12


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()  # erasing is a redraw too (godot-quirks)


# --- The generative half: static and pure, so it is testable ---------------

## The motif of one MAP cell (MapDiscovery's grid). Pure in (seed, cell).
static func cell_motif(seed_v: int, cell: Vector2i) -> String:
	var roll := hash([seed_v, "backdrop", cell.x, cell.y])
	var table: Array = []
	for m in MOTIFS:
		table.append(m)
	for i in OPEN_WEIGHT:
		table.append("open")
	return table[absi(roll) % table.size()]


## The features one backdrop-LATTICE cell holds on one depth layer: an Array of
## {kind, off (0..1 within the cell), size (0..1 relative), tone (0..1)}.
## The kind comes from the MAP cell containing the feature's VIRTUAL world
## anchor (lattice pos ÷ parallax factor — where the feature "really is"), so
## motif regions are world regions and scroll coherently. Pure.
static func cell_features(seed_v: int, layer: int, cell: Vector2i,
		lattice_px: float, factor: float, map_cell_px: float) -> Array:
	var out: Array = []
	# The virtual world position this lattice cell projects to (motif lookup
	# only — floored so the region grid stays map-cell sized at any depth).
	var vworld := (Vector2(cell) + Vector2(0.5, 0.5)) * lattice_px / maxf(factor, MOTIF_FLOOR)
	var mc := Vector2i(floori(vworld.x / map_cell_px), floori(vworld.y / map_cell_px))
	var motif := cell_motif(seed_v, mc)
	if motif == "open":
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_v, "bfeat", layer, cell.x, cell.y])
	# One or two features per occupied cell — sparse on purpose.
	var n := 1 + (1 if rng.randf() < 0.35 else 0)
	for i in n:
		var kind := motif
		# A shoal is a mixed motif: mostly clouds with the odd crag among them.
		if motif == "shoal":
			kind = "clouds" if rng.randf() < 0.7 else "crags"
		out.append({
			"kind": kind,
			"off": Vector2(rng.randf(), rng.randf()),
			"size": 0.45 + rng.randf() * 0.55,
			"tone": rng.randf(),
		})
	return out


## The band palette at altitude fraction `a` (0 = floor, 1 = ceiling):
## [sky_top, sky_bottom, silhouette]. The three stops are the map's own band
## tints, saturated for a sky rather than a chart, and blended across the gap
## bands so flying through a gap is a sunrise, not a switch.
static func band_palette(a: float) -> Array:
	# Anchor palettes per band: [top of sky, bottom of sky, silhouette ink].
	var deep := [Color(0.13, 0.07, 0.09), Color(0.22, 0.10, 0.09), Color(0.30, 0.14, 0.15)]
	var mid := [Color(0.10, 0.14, 0.15), Color(0.14, 0.20, 0.17), Color(0.17, 0.26, 0.23)]
	var top := [Color(0.08, 0.09, 0.16), Color(0.13, 0.15, 0.24), Color(0.19, 0.22, 0.34)]
	var lo: Array
	var hi: Array
	var t: float
	if a < Airspace.DEEP_TOP:
		return deep
	elif a < Airspace.GAP_LOW_TOP:
		lo = deep
		hi = mid
		t = (a - Airspace.DEEP_TOP) / (Airspace.GAP_LOW_TOP - Airspace.DEEP_TOP)
	elif a < Airspace.MID_TOP:
		return mid
	elif a < Airspace.GAP_HIGH_TOP:
		lo = mid
		hi = top
		t = (a - Airspace.MID_TOP) / (Airspace.GAP_HIGH_TOP - Airspace.MID_TOP)
	else:
		return top
	var out: Array = []
	for i in 3:
		out.append((lo[i] as Color).lerp(hi[i] as Color, t))
	return out


## How far one depth layer scrolls, in screen px, for a camera that MOVED by
## `cam_step` under a live `zoom`, dialled by `strength` (F2 `backdrop_parallax`).
##
## The zoom is the whole point of this function existing. The world's own
## apparent motion on screen is `cam_step * zoom`; riding a FRACTION of that
## makes `factor` mean the same thing at every zoom, so pulling back at the helm
## no longer drags the backdrop forward. Pure, so the suite can pin the ratio.
##
## IT TAKES A STEP, NOT A POSITION, and that distinction is the owner's report
## (2026-08-30: *"zooming in/out should NOT affect parallax"*). The first version
## multiplied the camera's ABSOLUTE position by the zoom, which made the RATE
## zoom-invariant but not the OFFSET: change zoom without moving at all and
## `cam * factor * Δzoom` teleports the whole backdrop sideways — at a world
## y of −212,000 and factor 0.02, boarding a ship (zoom 0.9 → 0.69) lurched it
## nearly a thousand pixels. Integrating the step instead means zoom only ever
## affects how fast the scenery moves WHILE you move, which is what parallax is.
static func layer_step(cam_step: Vector2, factor: float, zoom: float,
		strength: float) -> Vector2:
	return cam_step * (factor * maxf(zoom, 0.01) * maxf(strength, 0.0))


## The alpha of one silhouette: `depth_t` is 0 at the farthest layer and 1 at
## the nearest, `tone` is the feature's own roll, `opacity` the F2 dial.
##
## CALM-DOWN (owner 2026-08-29: "too bright"). The first cut ran 0.35..0.85 —
## near-solid ink on a dark sky, which is a painting, not a distance. These
## numbers are a haze: present when you look for it, gone when you are flying.
static func feature_alpha(depth_t: float, tone: float, opacity: float) -> float:
	return clampf((0.10 + 0.10 * depth_t + 0.04 * tone) * maxf(opacity, 0.0),
		0.0, 1.0)


# --- The painting half ------------------------------------------------------

func _draw() -> void:
	if world == null or not world.has_method("backdrop_status"):
		return
	if Tunables.get_num("backdrop_enabled") == 0.0:
		return  # F2 kill-switch: back to the plain clear colour
	var st: Variant = world.call("backdrop_status")
	if st == null:
		return
	var d := st as Dictionary
	var cam := d["cam"] as Vector2
	var alt := float(d["alt"])
	var seed_v := int(d["seed"])
	var map_px := float(d["map_cell_px"])
	var zoom := float(d.get("zoom", 1.0))
	var strength := Tunables.get_num("backdrop_parallax")
	var opacity := Tunables.get_num("backdrop_opacity")
	var view := size
	if view.x <= 0.0 or view.y <= 0.0 or map_px <= 0.0:
		return

	# Integrate the camera's motion into each layer's own scroll. Absolute
	# position times zoom would jump the backdrop on every zoom change (see
	# `layer_step`); a step cannot.
	if not _primed:
		_primed = true
		_last_cam = cam
	var cam_step := cam - _last_cam
	_last_cam = cam
	for li in LAYERS.size():
		_scroll[li] += layer_step(cam_step, float(LAYERS[li]), zoom, strength)

	var pal := band_palette(alt)
	# The sky gradient: two stops, band-coloured. Cheap (a handful of strips)
	# and it carries most of the "you are somewhere" feeling on its own.
	var steps := 6
	for i in steps:
		var t0 := float(i) / float(steps)
		var col := (pal[0] as Color).lerp(pal[1] as Color, t0)
		draw_rect(Rect2(0.0, view.y * t0, view.x, view.y / float(steps) + 1.0), col)

	# The three parallax depths, far first so near draws over.
	for li in LAYERS.size():
		var factor := float(LAYERS[li])
		var lattice := float(LATTICE[li])
		# Depth fades a silhouette toward the sky (atmosphere): far is faint.
		var depth_t := float(li) / float(LAYERS.size() - 1)
		# Dimmer ink than the first cut, too: the silhouette now sits nearer the
		# sky's own colour, so depth reads as haze rather than as cut paper.
		var ink := (pal[1] as Color).lerp(pal[2] as Color, 0.15 + 0.45 * depth_t)
		# The layer's scroll: a fraction of the world's APPARENT motion, wrapped
		# on the lattice so only on-screen cells are ever generated.
		var scroll: Vector2 = _scroll[li]
		var first := Vector2i(floori(scroll.x / lattice) - 1, floori(scroll.y / lattice) - 1)
		var last := Vector2i(floori((scroll.x + view.x) / lattice) + 1,
			floori((scroll.y + view.y) / lattice) + 1)
		for cy in range(first.y, last.y + 1):
			for cx in range(first.x, last.x + 1):
				var cell := Vector2i(cx, cy)
				for f in _features_for(seed_v, li, cell, lattice, factor, map_px):
					var fd := f as Dictionary
					var at := (Vector2(cell) + (fd["off"] as Vector2)) * lattice - scroll
					var r := lattice * 0.32 * float(fd["size"]) * (0.55 + 0.45 * depth_t)
					var tone := float(fd["tone"])
					var col := Color(ink, feature_alpha(depth_t, tone, opacity))
					match String(fd["kind"]):
						"crags":
							_draw_crag(at, r, col)
						"clouds":
							_draw_cloud(at, r, col)
						"spires":
							_draw_spire(at, r, col)


## `cell_features`, remembered. Same answer, computed once per cell per world.
func _features_for(seed_v: int, layer: int, cell: Vector2i, lattice_px: float,
		factor: float, map_cell_px: float) -> Array:
	var key := "%d:%f" % [seed_v, map_cell_px]
	if key != _cache_key:
		_cache_key = key
		_features.clear()
	elif _features.size() > FEATURE_CACHE_MAX:
		_features.clear()   # scrolled far enough that the old window is dead
	var ck := Vector3i(layer, cell.x, cell.y)
	var hit: Variant = _features.get(ck)
	if hit != null:
		return hit as Array
	var made := cell_features(seed_v, layer, cell, lattice_px, factor, map_cell_px)
	_features[ck] = made
	return made


## A distant floating crag: a rough hull with a flat top — an island silhouette.
func _draw_crag(at: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(-r, 0.0), at + Vector2(-r * 0.55, -r * 0.38),
		at + Vector2(r * 0.35, -r * 0.42), at + Vector2(r, -r * 0.05),
		at + Vector2(r * 0.45, r * 0.75), at + Vector2(0.0, r * 1.05),
		at + Vector2(-r * 0.6, r * 0.55)]), col)


## A cloud bank: three soft overlapping strips.
func _draw_cloud(at: Vector2, r: float, col: Color) -> void:
	var c := Color(col, col.a * 0.7)
	draw_rect(Rect2(at + Vector2(-r, -r * 0.18), Vector2(r * 2.0, r * 0.36)), c)
	draw_rect(Rect2(at + Vector2(-r * 0.6, -r * 0.42), Vector2(r * 1.3, r * 0.3)), c)
	draw_rect(Rect2(at + Vector2(-r * 0.3, r * 0.14), Vector2(r * 1.5, r * 0.28)), c)


## A thin rock spire, the tall-country motif.
func _draw_spire(at: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(-r * 0.22, r * 1.2), at + Vector2(-r * 0.08, -r * 1.1),
		at + Vector2(r * 0.08, -r * 1.25), at + Vector2(r * 0.26, r * 1.2)]), col)
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(r * 0.34, r * 1.2), at + Vector2(r * 0.46, r * 0.1),
		at + Vector2(r * 0.6, r * 1.2)]), Color(col, col.a * 0.8))
