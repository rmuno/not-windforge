extends SceneTree

## Ship blueprint previewer — the iteration loop for authoring ships.
##
##   godot --headless --path . --script tools/ship_preview.gd -- ships/hulk.ship [out.svg]
##
## Output defaults to docs/previews/<name>.svg — that folder carries a
## .gdignore so Godot never imports the pictures as textures, and the
## .svgs themselves are gitignored (regenerate at will).
##
## Headless and GPU-free: parses the .ship through the REAL parser and
## derives everything through a REAL Ship (mass, lift, power, prop axes,
## component clusters), so an authoring trap shows up here exactly as it
## would in-game — this tool exists because the hulk's hull row was being
## parsed as a comment and nobody could see it. Writes an SVG picture
## (open it in any browser / image pane) and prints a stats + lint report
## to stdout. Edit the .ship, re-run, look — that is the whole loop.

const PX := 24.0      ## svg pixels per authored cell
const MARGIN := 24.0
const FOOTER_LINE := 18.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: godot --headless --path . --script tools/ship_preview.gd -- <file.ship> [out.svg]")
		return quit(2)
	var in_path: String = args[0]
	if not in_path.begins_with("res://") and not in_path.is_absolute_path():
		in_path = "res://" + in_path.replace("\\", "/")
	var out_path: String = args[1] if args.size() > 1 else \
		ProjectSettings.globalize_path(
			"res://docs/previews/" + in_path.get_file().get_basename() + ".svg")

	var cells := ShipLayout.load_cells(in_path)
	if cells.is_empty():
		print("FAIL: no cells parsed from %s" % in_path)
		return quit(1)

	# A real Ship, so every derived number is the game's own.
	var ship := Ship.new()
	for cell in cells:
		ship.blocks[cell] = {"type": cells[cell], "hp": BlockDB.max_hp(cells[cell])}
	ship.gravity_scale = 0.0
	root.add_child(ship)
	ship.rebuild()

	var report := _report(ship, in_path)
	for line in report:
		print(line)

	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		print("FAIL: cannot write %s" % out_path)
		return quit(1)
	f.store_string(_svg(ship, report))
	f.close()
	print("\nwrote %s" % out_path)
	quit(0)


# --- Stats + lint ---------------------------------------------------------

func _report(ship: Ship, path: String) -> Array[String]:
	var full_draw := 0.0
	var idle_draw := 0.0
	var doors := 0
	var helm_floor := true
	for cell in ship.blocks:
		var def := BlockDB.get_def(ship.blocks[cell]["type"])
		full_draw += def["draw"]
		if def["thrust"] <= 0.0:
			idle_draw += def["draw"]  # turrets scan even when parked
		var t: int = ship.blocks[cell]["type"]
		if t == BlockDB.Type.DOOR or t == BlockDB.Type.DOOR_CLOSED:
			doors += 1
		if t == BlockDB.Type.HELM:
			# Multi-row helms (4×7 at 8×) stack on their own cells; only
			# the component's bottom row needs a solid floor beneath it.
			var below: Vector2i = cell + Vector2i.DOWN
			if not (ship.blocks.has(below)
					and ship.blocks[below]["type"] == BlockDB.Type.HELM):
				var ok: bool = ship.blocks.has(below) \
					and BlockDB.get_def(ship.blocks[below]["type"])["solid"]
				helm_floor = helm_floor and ok

	var lines: Array[String] = []
	lines.append("%s — %d cells" % [path.get_file(), ship.blocks.size()])
	lines.append("mass %.0f   lift capacity %.0f   lift/weight %.2f (%s)" %
		[ship.mass, ship._total_lift, ship.lift_ratio(),
		"floats" if ship.lift_ratio() >= 1.0 else "SINKS"])
	lines.append("power %.0f supply / %.0f full draw / %.0f idle draw%s" %
		[ship.power_supply(), full_draw, idle_draw,
		"  (BROWNOUT under way)" if full_draw > ship.power_supply() else ""])

	var warn: Array[String] = []
	if not ship.has_helm():
		warn.append("no helm — unpilotable until one is built")
	if ship.lift_ratio() < 1.0:
		warn.append("lift below weight — this ship is doomed to fall")
	if ship.power_supply() <= 0.0 and full_draw > 0.0:
		warn.append("powered components but no engine — props and guns are inert")
	if not helm_floor:
		warn.append("no solid floor under the helm — the crew has nowhere to stand")
	if doors == 0 and ship.has_helm():
		warn.append("no doors — an enclosed crew can never leave (layout audit rule)")
	for w in warn:
		lines.append("WARN: " + w)
	return lines


# --- Drawing ---------------------------------------------------------------

func _svg(ship: Ship, report: Array[String]) -> String:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for cell in ship.blocks:
		lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
		hi = Vector2i(maxi(hi.x, cell.x), maxi(hi.y, cell.y))
	var cols := hi.x - lo.x + 1
	var rows := hi.y - lo.y + 1
	var w := cols * PX + MARGIN * 2.0
	var h := rows * PX + MARGIN * 2.0 + FOOTER_LINE * (report.size() + 1)

	var out := PackedStringArray()
	out.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">' % [w, h])
	out.append('<rect width="100%" height="100%" fill="#1a2028"/>')

	for cell in ship.blocks:
		out.append(_cell_svg(ship, cell, lo))

	# One label per component cluster, exactly as the game letters them.
	for cluster in ship._glyph_clusters:
		var key: String = cluster["key"]
		if key == "G":
			continue  # balloons are a silent mass of colour in-game too
		var label := key
		match key:
			"PV": label = "V"
			"PH": label = "P"
		var r: Rect2 = cluster["rect"]
		var c := _to_svg(r.get_center(), lo)
		out.append(('<text x="%.1f" y="%.1f" font-family="monospace" ' +
			'font-size="%.0f" fill="#10131a" text-anchor="middle" ' +
			'dominant-baseline="central">%s</text>') % [c.x, c.y, PX * 0.66, label])

	var y := rows * PX + MARGIN * 2.0
	for line in report:
		var color := "#e8a04a" if line.begins_with("WARN") else "#c8d2e0"
		out.append(('<text x="%.1f" y="%.1f" font-family="monospace" ' +
			'font-size="12" fill="%s">%s</text>') %
			[MARGIN * 0.5, y, color, line.xml_escape()])
		y += FOOTER_LINE
	out.append('</svg>')
	return "\n".join(out)


## Authored-cell centre -> svg coordinates (from Ship-local px).
func _to_svg(local_px: Vector2, lo: Vector2i) -> Vector2:
	return (local_px / Ship.CELL - Vector2(lo)) * PX + Vector2(MARGIN, MARGIN) \
		+ Vector2(PX, PX) * 0.5


func _cell_svg(ship: Ship, cell: Vector2i, lo: Vector2i) -> String:
	var type: int = ship.blocks[cell]["type"]
	var def := BlockDB.get_def(type)
	var color: Color = def["color"]
	var p := Vector2(cell - lo) * PX + Vector2(MARGIN, MARGIN)

	# Match the game's reading: struts are poles, platforms are planks.
	if type == BlockDB.Type.STRUT:
		return _rect(p + Vector2(PX * 0.36, 0), Vector2(PX * 0.28, PX), color)
	if def["platform"]:
		return _rect(p, Vector2(PX, PX * 0.25), color)
	return _rect(p, Vector2(PX, PX), color)


func _rect(pos: Vector2, size: Vector2, c: Color) -> String:
	return ('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" ' +
		'fill="#%s" fill-opacity="%.2f" stroke="#%s" stroke-width="1"/>') % [
		pos.x, pos.y, size.x, size.y,
		c.to_html(false), c.a, c.darkened(0.35).to_html(false)]
