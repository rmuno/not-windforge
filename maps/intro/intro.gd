class_name IntroScene
extends Node2D

## THE INTRO — its own scene, and that is the point (owner 2026-08-30: "I think
## we're just gonna need a new scene for the intro screen honestly. don't just
## reuse the existing world").
##
## The old intro was a camera state bolted onto a live game world, and it showed:
## it inherited the health bar, the inventory strip, the edge markers pointing at
## things, and a helm politely offering itself to a player who did not exist.
## Every one of those was a separate bug with a separate fix. Here there is no
## player, no terrain, no HUD and no gameplay at all, so none of them is possible
## to have.
##
## What it shows is a CURATED PROCESSION, the owner's own running order: the
## whale varieties one at a time, then the little critters, then your ship and a
## bandit trading fire. The camera pans right at a constant rate and the cast
## drifts left past it; when an act falls off the left it is moved to the back of
## the queue, so the procession never ends and there is no cut, no fade and no
## wrap to hide. A title screen can sit here all night.
##
## The bodies are the REAL `Ship` class loading the REAL `.ship` blueprints, so
## the intro can never advertise a silhouette the game does not have — it just
## freezes them (the same `freeze` a nest uses) and moves them itself. The
## gunfire is drawn by this scene rather than fired: a tracer that cannot damage
## anything needs no damage rules turned off.

## How fast the camera pans right, px/s at scale 1.
const PAN_SPEED := 34.0
## THE CAST IS BUILT AT 1x, AND THAT COSTS NOTHING VISUALLY (owner 2026-08-30:
## "the game is still super laggy when loading it... Is the title screen a small
## scene? (it should be)"). It was not: the intro built all thirteen bodies
## UPSCALED 8x, which is **358,016 blocks** — measured — and around eleven
## seconds of work before the first frame. That is the loading lag, and it is
## paid again every time you quit to the title, because that reloads this scene.
##
## `ShipLayout.upscale_cells` multiplies a blueprint's GRANULARITY, never its
## shape: an 8x whale is the same silhouette made of 64x as many cells. The
## world needs that granularity so an 8x player fits through an authored door
## and mining takes bites out of a hull. **An intro needs none of it** — nothing
## walks, mines, collides or is shot here, and at this camera pull-back one 8x
## cell was 0.88 screen pixels. So the cast is authored-scale, the camera zoom is
## multiplied by the same factor to keep the framing identical, and the
## silhouettes are pixel-for-pixel what they were.
const SCALE := 1
## What the cast WOULD have been built at. The zoom is divided by this, so the
## framing is unchanged from the 8x version — change one and the picture moves.
const SHIPPED_SCALE := 8
## Gap between acts along the procession, px at SHIPPED_SCALE.
##
## SHRUNK 2600 -> 900 (owner 2026-08-30: "I only see one whale going around in
## the title screen, then it goes away. It's a little slow for another whale to
## come in, but I'd just want something going on in the screen"). The gap was
## 20,800 px against a closing speed of 480 px/s — **forty-three seconds of empty
## sky between acts.** At 900 the procession overlaps: something is always
## entering as something else leaves.
const ACT_GAP := 250.0
## How far above and below the eye line the procession spreads, px at SCALE.
##
## The cast used to fly in SINGLE FILE at y = 0, which is why the only way to
## get "something going on in the screen" was to close the gaps until the acts
## queued up nose to tail. Spread them vertically and three or four fit in frame
## without ever touching — a sky with things in it rather than a parade.
const ACT_SPREAD_Y := 620.0
## A slow bob, so nothing on screen is ever perfectly still. Amplitude in px at
## SCALE, period in seconds.
const BOB_PX := 55.0
const BOB_PERIOD := 7.0
## How far behind the camera an act may fall before it is sent to the back.
const RECYCLE_BEHIND := 3400.0
## Camera pull-back, expressed at SHIPPED_SCALE and corrected for the scale the
## cast is actually built at — so the framing is a constant.
const ZOOM := 0.055

var fleet: Fleet
var camera: Camera2D

var _title: TitleScreen
var _acts: Array = []          ## [{node, drift, span}] in procession order
var _tail_x := 0.0             ## world x the next recycled act is placed at
var _t := 0.0
var _bolts: Array = []         ## cosmetic tracers: {from, to, t, life}
var _duel: Array = []          ## [mine, theirs] — the two hulls that trade fire
var _bolt_clock := 0.0


## THE RUNNING ORDER, as data (owner: "showing the whale varieties slowly … then
## critters, then the player+ship and an enemy"). Static and pure so the suite
## can check the procession without booting a scene.
static func cast_plan() -> Array:
	var out: Array = []
	for plan in WhaleSpawn.PLANS:
		var p := plan as Dictionary
		out.append({"kind": "whale", "path": String(p["path"]),
			"tint": p["tint"], "drift": -26.0})
	for i in 3:
		out.append({"kind": "critter", "path": "res://ships/critter.ship",
			"tint": Color(1, 1, 1), "drift": -40.0})
	out.append({"kind": "duel", "path": "res://ships/starter.ship",
		"tint": Color(1, 1, 1), "drift": -8.0})
	return out


func _ready() -> void:
	name = "Intro"
	fleet = Fleet.new()
	fleet.name = "Fleet"
	add_child(fleet)

	var back := CanvasLayer.new()
	back.layer = -1
	var backdrop := Backdrop.new()
	backdrop.world = self          # duck-typed: it only wants backdrop_status()
	back.add_child(backdrop)
	add_child(back)

	camera = Camera2D.new()
	# The cast is built at SCALE but framed as though it were at SHIPPED_SCALE.
	var z := ZOOM * float(SHIPPED_SCALE) / float(SCALE)
	camera.zoom = Vector2(z, z)
	add_child(camera)
	camera.make_current()

	_build_cast()

	var layer := CanvasLayer.new()
	_title = TitleScreen.new()
	_title.world = self             # duck-typed: it only calls choose_mode()
	layer.add_child(_title)
	add_child(layer)
	_title.open()


# --- The procession ---------------------------------------------------------

func _build_cast() -> void:
	var x := 0.0
	var i := 0
	for entry in cast_plan():
		var e := entry as Dictionary
		# Deterministic vertical spread — a fixed irrational stride so
		# consecutive acts never share a lane and the pattern never repeats
		# inside one pass of the cast.
		var lane := fposmod(float(i) * 0.618, 1.0) * 2.0 - 1.0
		var node := _spawn_act(e, x, lane * ACT_SPREAD_Y * float(SCALE))
		i += 1
		if node == null:
			continue
		# `solid_bounds` is ALREADY world px at whatever scale the body was built
		# at — the scale lives in the CELL COUNT, never in the node (CODEMAP; the
		# eightfold bug). Multiplying it by SCALE here made every act's span 64x
		# its real width at the old SCALE=8, which is most of why the procession
		# had a minute of empty sky in it. Only the AUTHORED constants below
		# carry the scale.
		var span: float = maxf(node.solid_bounds.size.x, 600.0 * float(SCALE))
		_acts.append({"node": node, "drift": float(e["drift"]), "span": span,
			"base_y": node.global_position.y,
			"phase": fposmod(float(i) * 2.399, TAU)})
		x += span + ACT_GAP * float(SCALE)
	_tail_x = x


## One act. A duel is two hulls facing each other; everything else is one body.
func _spawn_act(e: Dictionary, x: float, y: float) -> Ship:
	var at := Vector2(x, y)
	var ship := _spawn_body(String(e["path"]), at, 0)
	if ship == null:
		return null
	if String(e["kind"]) == "whale":
		ship.creature_kind = "whale"
		ship.body_tint = e["tint"]
		ship.shared_health_max = 1000.0
		ship.shared_health = 1000.0
		ship.rebuild()
	elif String(e["kind"]) == "critter":
		ship.creature_kind = "critter"
		ship.shared_health_max = 200.0
		ship.shared_health = 200.0
		ship.rebuild()
	elif String(e["kind"]) == "duel":
		# Your ship, and a bandit off its bow. They shoot at each other for the
		# whole procession and neither of them can be hurt, because the bolts
		# are drawn (see _draw_bolts), not fired.
		var foe := _spawn_body("res://ships/hulk.ship",
			at + Vector2(ship.solid_bounds.size.x * 1.5,   # already world px
				-260.0 * float(SCALE)), 1)
		_duel = [ship, foe]
	return ship


func _spawn_body(path: String, at: Vector2, faction: int) -> Ship:
	var cells := ShipLayout.upscale_cells(ShipLayout.load_cells(path), SCALE)
	if cells.is_empty():
		return null
	var ship := fleet.spawn_ship_from_cells(cells, at, 0, 0.0, float(SCALE), faction)
	if ship == null:
		return null
	# Held, not flown: an intro is a picture that moves, and a live RigidBody2D
	# with lift would climb out of frame inside a minute (the launch deck learned
	# this the hard way). Kinematic so moving it every frame is expected.
	ship.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	ship.freeze = true
	return ship


func _physics_process(delta: float) -> void:
	_t += delta
	var s := float(SCALE)
	camera.global_position += Vector2(PAN_SPEED * s * delta, 0.0)
	# Everyone drifts against the pan, so the procession sweeps past rather than
	# merely being passed. An act that falls behind goes to the back of the
	# queue — that is the whole loop, and it has no seam to hide.
	var behind := camera.global_position.x - RECYCLE_BEHIND * s
	for act in _acts:
		var a := act as Dictionary
		var node: Ship = a["node"]
		if not is_instance_valid(node):
			continue
		var step := Vector2(float(a["drift"]) * s * delta, 0.0)
		node.global_position += step
		_shift_duel(node, step)
		# The bob is an absolute y, not an accumulation, so recycling an act
		# cannot drift it off its lane over a long night on the title screen.
		var bob := sin(_t * TAU / BOB_PERIOD + float(a["phase"])) * BOB_PX * s
		var lift := float(a["base_y"]) + bob - node.global_position.y
		node.global_position.y += lift
		_shift_duel(node, Vector2(0.0, lift))
		if node.global_position.x + float(a["span"]) < behind:
			var jump := Vector2(_tail_x - node.global_position.x, 0.0)
			node.global_position += jump
			_shift_duel(node, jump)
			_tail_x += float(a["span"]) + ACT_GAP * s
	_advance_bolts(delta)
	queue_redraw()


## The duel's second hull rides with the first, so recycling the act keeps the
## pair together.
func _shift_duel(lead: Ship, by: Vector2) -> void:
	if _duel.size() < 2 or lead != _duel[0]:
		return
	var foe: Ship = _duel[1]
	if is_instance_valid(foe):
		foe.global_position += by


# --- The gunfire, which is a drawing ----------------------------------------

const BOLT_LIFE := 0.42
const BOLT_EVERY := 0.33

func _advance_bolts(delta: float) -> void:
	for b in _bolts:
		(b as Dictionary)["t"] = float((b as Dictionary)["t"]) + delta
	_bolts = _bolts.filter(func(b: Dictionary) -> bool:
		return float(b["t"]) < BOLT_LIFE)
	if _duel.size() < 2:
		return
	_bolt_clock -= delta
	if _bolt_clock > 0.0:
		return
	_bolt_clock = BOLT_EVERY
	var mine: Ship = _duel[0]
	var theirs: Ship = _duel[1]
	if not is_instance_valid(mine) or not is_instance_valid(theirs):
		return
	# Alternate who is shooting, and MISS on purpose — the bolts pass wide, so
	# nothing on screen ever looks like it is losing.
	var out := (int(_t / BOLT_EVERY) % 2) == 0
	var from: Vector2 = (mine if out else theirs).global_position
	var to: Vector2 = (theirs if out else mine).global_position
	var wide := Vector2(0.0, (260.0 if out else -260.0) * float(SCALE))
	_bolts.append({"from": from, "to": to + wide, "t": 0.0})


func _draw() -> void:
	for b in _bolts:
		var d := b as Dictionary
		var k: float = clampf(float(d["t"]) / BOLT_LIFE, 0.0, 1.0)
		var from: Vector2 = d["from"]
		var to: Vector2 = d["to"]
		var head: Vector2 = from.lerp(to, k)
		var tail: Vector2 = from.lerp(to, maxf(0.0, k - 0.12))
		draw_line(tail, head, Color(1.0, 0.86, 0.5, 1.0 - k * 0.5),
			26.0 * float(SCALE))


# --- What the Backdrop asks for (the same plain-values seam the world uses) --

func backdrop_status() -> Variant:
	if camera == null or not is_instance_valid(camera):
		return null
	return {"cam": camera.global_position, "alt": 0.62,
		"seed": IslandGen.DEFAULT_SEED, "map_cell_px": 4096.0,
		"zoom": camera.zoom.x}


# --- The doors --------------------------------------------------------------

## The title screen calls this. Remembers the choice across the scene change and
## opens the world — the one place the intro hands over.
##
## The scene change is DEFERRED by Godot (it lands at the end of the frame), so
## everything after the call still runs against a live tree. That is exactly the
## window the crash lived in, so nothing is done after it: record, hand over,
## return.
func choose_mode(mode: String) -> void:
	if not GameMode.is_known(mode):
		mode = GameMode.EXPEDITION
	GameMode.pending = mode
	var err := get_tree().change_scene_to_file("res://maps/world/world.tscn")
	if err != OK:
		push_error("Intro: could not open the world (%d)" % err)
