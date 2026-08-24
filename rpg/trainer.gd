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


func in_reach(from: Vector2) -> bool:
	return global_position.distance_to(from) <= reach


## Does this trainer teach `stat`? True for all four unless a specific set was set.
func teaches(stat: int) -> bool:
	return trains.is_empty() or trains.has(stat)


func _draw() -> void:
	# Placeholder art (like every _draw here until the art pass): a small post
	# with a banner, so the station reads as a place, not a stray block. Scale is
	# baked into `reach` upstream; draw relative to it so the mark tracks size.
	var s := reach / 48.0
	var post := Rect2(-3.0 * s, -22.0 * s, 6.0 * s, 30.0 * s)
	draw_rect(post, Color(0.42, 0.34, 0.24))
	var banner := Rect2(3.0 * s, -22.0 * s, 20.0 * s, 12.0 * s)
	draw_rect(banner, Color(0.30, 0.55, 0.72))
	draw_rect(banner, Color(0.12, 0.20, 0.28), false, 1.0)
