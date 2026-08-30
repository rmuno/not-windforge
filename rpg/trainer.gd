class_name Trainer
extends Node2D

## A trainer station: the place you spend money to raise a stat and sell your
## salvage (Sprint 5, the economy). Deliberately minimal — a world marker with a
## reach check, reusing the same "are you close enough?" idiom as helms and doors.
## The actual buy/sell logic is data (rpg/training.gd, rpg/economy.gd); the actual
## UI is the toggled character sheet (maps/world/character_sheet.gd). This node is
## just WHERE in the world the exchange happens.
##
## Every town has trainers in the source (owner memory); for now the throwaway
## harness world plants one near spawn so the loop is reachable and testable.
## Real trainers belong to towns (Phase 6) — a seam, noted in BACKLOG.

## How close (world px) the player must stand to use this trainer. Set by the
## world at spawn so it scales with the world like every other reach.
var reach := 48.0

## The stats this trainer can raise. Empty == all four (the simple default; the
## source's per-town specialisation, where most cap at 60 and one master trains a
## single stat to 100, is a Phase-6 seam). Kept as data so specialisation later
## needs no code change here.
var trains: Array = []

## Coat colour. The Dive's outposts reuse this node as a QUARTERMASTER — same
## person-shaped figure, same reach idiom, different trade — and the coat is what
## tells the two apart at a glance without a second body to draw.
var coat := Color(0.38, 0.52, 0.66)


func in_reach(from: Vector2) -> bool:
	return global_position.distance_to(from) <= reach


## Does this trainer teach `stat`? True for all four unless a specific set was set.
func teaches(stat: int) -> bool:
	return trains.is_empty() or trains.has(stat)


## The player's body, for the NPC to match. Player.SIZE is a `var` (scale_body
## multiplies it), so it cannot be read as a constant here — this is the same
## 10×18 the player's collider is built from, and the two are meant to agree.
const BODY := Vector2(10.0, 18.0)


func _draw() -> void:
	# Placeholder art (like every _draw here until the art pass). It used to be a
	# POST WITH A BANNER, which read as signage rather than as somebody standing
	# there — the owner's 2026-08-29 note. It is now a PERSON in the player's own
	# idiom: the same little rectangle body, at the same size, plus a head, so an
	# NPC reads as the same kind of thing you are. A different palette (slate coat
	# against the player's khaki) keeps the two apart at a glance, and the small
	# ledger under the arm is what says this particular person TRADES.
	#
	# Scale is baked into `reach` upstream; draw relative to it so the figure
	# tracks the world scale like every other reach in the game.
	var s := reach / 48.0
	var body := Rect2(-BODY.x * 0.5 * s, -BODY.y * 0.5 * s, BODY.x * s, BODY.y * s)
	draw_rect(body, coat)
	draw_rect(body, coat.darkened(0.45), false, maxf(1.0, s))
	# Head: a plain circle above the shoulders — one shape, and the figure stops
	# being a crate.
	var head := Vector2(0.0, -(BODY.y * 0.5 + 3.6) * s)
	draw_circle(head, 3.6 * s, Color(0.86, 0.74, 0.60))
	draw_arc(head, 3.6 * s, 0.0, TAU, 14, Color(0.42, 0.32, 0.24), maxf(1.0, s))
	# The ledger: the trade sign, kept from the old banner's blue so the station
	# is still findable as a shop rather than as scenery with a face.
	var ledger := Rect2((BODY.x * 0.5 - 1.0) * s, -3.0 * s, 7.0 * s, 9.0 * s)
	draw_rect(ledger, Color(0.30, 0.55, 0.72))
	draw_rect(ledger, Color(0.12, 0.20, 0.28), false, maxf(1.0, s))
