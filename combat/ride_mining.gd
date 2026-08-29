class_name RideMining
extends RefCounted

## The ridden-whale MINING geometry (Sprint 5 taming payoff): while the player
## rides a whale and drives it into terrain, the whale eats through the terrain —
## a swath of cells at the whale's leading edge, along its travel, is dug and
## credited to the RIDER (world.ride_mine_pulse). This is the whole reward: a
## tamed whale mines far faster and broader than hand-mining, and carries you to
## the deep.
##
## Pure logic (a RefCounted, no tree — the world passes the whale's geometry in),
## so the front-cell probe is unit-testable without booting the world. The world
## owns the actual dig (Terrain.net_dig) and the immunity flag (Ship.ridden_mining);
## this only answers "which cells are at the whale's mining front".
##
## Terrain sits at the world origin (terrain/terrain.gd), so a world point maps to
## a cell by floor(point / cell_px) — the same floori the terrain's world_to_cell
## uses, so the cells here and the terrain's agree.

## The cells at the mining front of a creature whose solid bounds have world
## CENTRE `center` and local half-extents `half`, driving in direction `dir`,
## with the body rotated `rot` radians (its node rotation — the pose tilt).
##
##   * `cell_px`   — terrain cell size in px (Terrain.cell_px()).
##   * `depth`     — how many cell-layers deep AHEAD of the leading edge to dig
##                   in one pulse (the reach lever). Clamped to >= 1.
##   * `breadth_pad` — extra cells dug on EACH side beyond the whale's own
##                   cross-section (the breadth lever). 0 = exactly the whale's
##                   width; the swath is always at least as wide as the whale so
##                   it clears a body-sized tunnel.
##   * `rot`       — the body's world rotation. 0 keeps the old axis-aligned
##                   arithmetic exactly.
##
## Returns de-duplicated cell coords. Empty if `dir` is ~zero (no travel, no
## front) or `cell_px` is non-positive.
##
## WHY `rot` EXISTS (owner 2026-08-29: "nowhere near where the actual whale is
## — perhaps an improperly rotated collider?"): close — an UNROTATED front. The
## pose tilt is a REAL node rotation (up to ±31°, Ship.POSE_MAX), and the first
## cut projected the body's LOCAL half-extents against the WORLD travel axis as
## if the body never rotated. A whale is long and thin, so on a pitched whale
## the swath was sized off the unrotated cross-section and missed where the
## nose visibly was by up to the tilt's full vertical throw (~1,300 px on the
## shipped body). The fix is the support function of the ROTATED box: rotate
## the travel axis into the body's frame before projecting. The swath then
## matches the body's true world profile perpendicular to its motion — exactly
## the tunnel the body needs to fit through.
static func front_cells(center: Vector2, half: Vector2, dir: Vector2,
		cell_px: float, depth: int, breadth_pad: int, rot := 0.0) -> Array:
	var out: Array = []
	if cell_px <= 0.0 or dir.length() < 0.001:
		return out
	var d := dir.normalized()
	var perp := Vector2(-d.y, d.x)
	# The body's extent projected onto the travel axis (how far the leading edge
	# is from centre) and onto the perpendicular (its half-width there) — the
	# support function of the box AS ROTATED, so both agree with where the body
	# actually is. (The visual-facing mirror never matters here: a box reflected
	# about its own centre keeps the same support extents.)
	var ld := d.rotated(-rot)
	var lp := perp.rotated(-rot)
	var ext_along := absf(ld.x) * half.x + absf(ld.y) * half.y
	var ext_perp := absf(lp.x) * half.x + absf(lp.y) * half.y
	var half_cells := int(ceil(ext_perp / cell_px)) + maxi(breadth_pad, 0)
	var seen := {}
	for layer in range(maxi(depth, 1)):
		# The cell-centre of this layer, one cell deep per step beyond the edge.
		var along := ext_along + cell_px * (float(layer) + 0.5)
		for s in range(-half_cells, half_cells + 1):
			var p := center + d * along + perp * (float(s) * cell_px)
			var cell := Vector2i(floori(p.x / cell_px), floori(p.y / cell_px))
			if not seen.has(cell):
				seen[cell] = true
				out.append(cell)
	return out
