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
## THE SHIPYARD (owner arc: the in-game ship builder, 2026-09-01): a quiet boot
## — no ecology, sandbox loadout — where your ship is the canvas and the F2
## EXPORT writes the .ship file the Loft and the game both speak.
const BUILDER := "builder"

## What the next world should open as. Cleared by the world once it has applied
## it, so a later reset or reload does not silently re-enter a mode.
static var pending := EXPEDITION


static func is_known(name: String) -> bool:
	return name in [EXPEDITION, SANDBOX, DIVE, BUILDER]


## Take the pending choice, leaving EXPEDITION behind. One reader, once.
static func take() -> String:
	var chosen := pending if is_known(pending) else EXPEDITION
	pending = EXPEDITION
	return chosen
