class_name GameMode
extends RefCounted

## WHICH MODE THE WORLD SHOULD OPEN IN.
##
## The intro (maps/intro/intro.tscn) is the game's main scene now, and choosing
## a door there loads maps/world/world.tscn. That scene change throws away every
## node, so the choice has to survive it — and a `static var` on a class does,
## for the whole process, without adding a second autoload to a project that has
## deliberately kept exactly one (`Net`).
##
## Deliberately tiny and deliberately NOT a mode object. The modes themselves are
## rules inside `world.gd` (`dive_style()`, `sandbox_mode`, `DiveRun`); this only
## carries which one was picked across the scene boundary. If the modes ever grow
## into real objects, this is the seam they would hang from.

const EXPEDITION := "expedition"
const SANDBOX := "sandbox"
const DIVE := "dive"
## THE DRAFTING TABLE (owner arc Q-Q): the native ship builder. NOT a world
## boot — the intro routes this straight to maps/editor/ship_editor.tscn (the
## mid-air Shipyard world-mode was retired 2026-09-01: "the midair shipyard is
## ridiculous"), so `pending` never carries it and the world never sees it.
const BUILDER := "builder"
## THE MAP ROOM (owner arc, 2026-09-01: "this way I can look at the full Dive
## mode map, for example, and SEE the entire thing there"). Another workshop
## SCREEN, like the drafting table — no world, no run, no physics.
const MAPROOM := "maproom"

## What the next world should open as. Cleared by the world once it has applied
## it, so a later reset or reload does not silently re-enter a mode.
static var pending := EXPEDITION


static func is_known(name: String) -> bool:
	return name in [EXPEDITION, SANDBOX, DIVE, BUILDER, MAPROOM]


## Is this a SCREEN rather than a world? Screens are their own scenes with no
## `world.gd` in them at all, so nothing may be left in `pending` on their
## account — there is no world booting to consume it.
static func is_screen(name: String) -> bool:
	return name in [BUILDER, MAPROOM]


## WHICH SCENE A DOOR OPENS. Pure, and pure on purpose: the intro's routing used
## to be a chain of special cases inside `choose_mode`, which meant the only way
## to test "does [1] open the Dive" was to actually change scenes in a headless
## suite. One table, asserted directly.
##
## THE DIVE HAS ITS OWN SCENE NOW (maps/dive/dive.tscn — a dive-native world.gd,
## see its `dive_native` export), so the Dive door does not need `pending` at
## all. It is still set, harmlessly, because `world.tscn` + pending is the path
## F2's in-expedition dive and the startup suites still walk.
static func scene_for(name: String) -> String:
	match name:
		BUILDER: return "res://maps/editor/ship_editor.tscn"
		MAPROOM: return "res://maps/maproom/map_room.tscn"
		DIVE: return "res://maps/dive/dive.tscn"
	return "res://maps/world/world.tscn"


## Take the pending choice, leaving EXPEDITION behind. One reader, once.
static func take() -> String:
	var chosen := pending if is_known(pending) else EXPEDITION
	pending = EXPEDITION
	return chosen
