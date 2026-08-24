class_name HudCues
extends RefCounted

## Pure contextual-cue logic for the decluttered HUD (owner 2026-08-22: "the
## screen is CLUTTERED with text and FYIs, keys, etc — take a BROADER approach").
##
## Instead of a standing wall of key hints, the world shows only the actions that
## are USABLE right now, near the reticle. This module decides WHICH cues are
## active from plain state — no nodes, no Labels, no mouse — so the decision is
## unit-testable on its own. The world formats each active cue into text and the
## HUD draws it; nothing here touches the scene.

enum Cue { HELM, MINE, HARVEST, PLACE, CRAFT, TRAINER }

## Given the player's situation, the cues to show. State keys (all optional,
## default false):
##   piloting    — at the helm: your hands fly the ship, so foot actions are out.
##   near_helm   — a helm (or door) is within interact reach.
##   mineable    — aiming at a solid terrain cell in reach.
##   harvestable — aiming at a carcass flesh cell in reach.
##   placeable   — aiming at an empty, in-reach cell with a stocked held material.
##   craftable   — the selected recipe's inputs are all present.
##   near_trainer — a trainer station is within reach (open the sheet to trade).
##
## Mine / harvest / place are cursor-driven and mutually exclusive by nature (a
## cell is either solid, a corpse, or empty), so at most one of them is ever
## active — the elif chain enforces it rather than trusting the caller. Helm and
## craft are independent of the cursor. While piloting, only the step-off helm
## cue applies.
static func active(state: Dictionary) -> Array:
	var out: Array = []
	if bool(state.get("piloting", false)):
		out.append(Cue.HELM)   # rendered as "[F] step off"
		return out
	if bool(state.get("near_helm", false)):
		out.append(Cue.HELM)
	if bool(state.get("mineable", false)):
		out.append(Cue.MINE)
	elif bool(state.get("harvestable", false)):
		out.append(Cue.HARVEST)
	elif bool(state.get("placeable", false)):
		out.append(Cue.PLACE)
	if bool(state.get("craftable", false)):
		out.append(Cue.CRAFT)
	if bool(state.get("near_trainer", false)):
		out.append(Cue.TRAINER)
	return out
