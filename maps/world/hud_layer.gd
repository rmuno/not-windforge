class_name HudLayer
extends Control

## The calm, always-on HUD (owner 2026-08-22: declutter — "a calm screen: the
## world, a reticle, a couple of contextual cues, a small status corner").
##
## Draws three light things in screen space and nothing else:
##   * a subtle RETICLE at the cursor (the aim point for mine / place / build);
##   * a clean INVENTORY STRIP bottom-left — colour swatches + counts, not
##     sentences (ItemDB.color_of + count), shown only when you carry something;
##   * a CONTEXTUAL CUE bar bottom-centre — the one or two actions usable right
##     now (HudCues), and nothing when none apply.
## Everything heavier (the full controls list, ship stats, the map) lives on a
## toggle or appears only in context, handled by the world. All the decisions are
## made in the world (inventory_swatches / contextual_cue_lines); this only paints
## them, the same split WorldOverlay uses — so nothing here can touch a ship.

var world: Node2D

## Wind-cue particle positions, in screen space (see _draw_wind). Kept between
## frames and advanced in _process; _draw is otherwise stateless.
var _wind_particles: Array[Vector2] = []

## The HUD is SCREEN-space chrome, so its size must NOT track world_scale — that
## was the bug behind "some UIs are far too large" (owner 2026-08-23): at the
## shipped 8× the character sheet, air warning and swatches were drawn 8× oversize
## and ran off the screen. The camera zoom already sizes the WORLD; the HUD sits
## on the glass in front of it and should stay a comfortable fixed size, gently
## bumped only on genuinely hi-dpi displays (never by the world zoom). Derived
## from the viewport height, capped so it can never explode.
func _scale() -> int:
	var vh := get_viewport_rect().size.y
	return clampi(int(round(vh / 900.0)), 1, 3)


func _ready() -> void:
	# Fill the viewport; never eat mouse events (the game reads the raw cursor).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_advance_wind(delta)
	queue_redraw()  # erasing is a redraw too (godot-quirks)


func _draw() -> void:
	if world == null:
		return
	# THE INTRO IS A PICTURE, NOT A COCKPIT (owner 2026-08-30). Everything this
	# layer paints is about the player — their aim, their health, their pack,
	# what they could do right now — and none of it means anything over the title
	# screen. One ask, and the whole glass goes dark.
	if world.has_method("hud_quiet") and bool(world.call("hud_quiet")):
		return
	_draw_wind()
	_draw_reticle()
	_draw_health()
	_draw_money()
	_draw_inventory_strip()
	_draw_cue_bar()
	_draw_depth_warning()


## A minimal always-on health readout, top-left — the one vital the owner asked to
## always see (2026-08-23: "a MINIMAL character hud showing current health"). A
## short bar (green→amber→red as it drops) with a small numeric, or nothing at all
## when there is no player. Deliberately tiny and cornered: the character sheet (K)
## still holds the full picture; this is just "am I hurt right now?".
func _draw_health() -> void:
	var v: Variant = world.call("player_vitals")
	if v == null:
		return
	var vd := v as Dictionary
	var maxh := float(vd.get("max", 0.0))
	if maxh <= 0.0:
		return
	var hp := clampf(float(vd.get("health", 0.0)), 0.0, maxh)
	var frac := hp / maxh
	var font := ThemeDB.fallback_font
	var s := _scale()
	var fs := 12 * s
	var pad := 8.0 * s
	var bw := 120.0 * s          # bar width
	var bh := 9.0 * s            # bar height
	var x := pad
	var y := pad
	# Colour ramps green (full) → amber (half) → red (near death).
	var col: Color
	if frac > 0.5:
		col = Color(0.45, 0.85, 0.45).lerp(Color(0.90, 0.80, 0.35), (1.0 - frac) * 2.0)
	else:
		col = Color(0.90, 0.80, 0.35).lerp(Color(0.90, 0.30, 0.28), (0.5 - frac) * 2.0)
	draw_rect(Rect2(x, y, bw, bh), Color(0.05, 0.07, 0.10, 0.6))
	draw_rect(Rect2(x, y, bw * frac, bh), col)
	draw_rect(Rect2(x, y, bw, bh), Color(0, 0, 0, 0.5), false, 1.0)
	draw_string(font, Vector2(x + bw + 6.0 * s, y + bh),
		"%d/%d" % [roundi(hp), roundi(maxh)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.86, 0.90, 0.96))


## Advance the wind-cue particles one frame in the prevailing wind direction. State
## lives here (screen positions) so the drift reads as motion; _draw only paints.
## A calm direction (ZERO) parks them — no motion, so a dead band reads as dead.
func _advance_wind(delta: float) -> void:
	if world == null:
		return
	var dir: Variant = world.call("wind_status")
	var wind := (dir as Vector2) if dir is Vector2 else Vector2.ZERO
	var vp := get_viewport_rect().size
	if _wind_particles.is_empty() and vp.x > 0.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = 20260823
		for i in 28:
			_wind_particles.append(Vector2(
				rng.randf() * vp.x, rng.randf() * vp.y))
	if wind == Vector2.ZERO:
		return
	# ~1/8 of the screen height per second — a light, unhurried drift.
	var speed := vp.y * 0.12
	var step := wind.normalized() * speed * delta
	for i in _wind_particles.size():
		var p := _wind_particles[i] + step
		# Wrap around the screen so the field is endless.
		p.x = fposmod(p.x, vp.x)
		p.y = fposmod(p.y, vp.y)
		_wind_particles[i] = p


## Very light drifting particles showing which way the wind blows at the player's
## altitude — the owner's "visual outside the map for wind going in a direction"
## (2026-08-23). Faint streaks trailing the drift direction; nothing at all in a
## calm band (ZERO wind) so it never adds noise where there is no wind to show.
func _draw_wind() -> void:
	if _wind_particles.is_empty():
		return
	var dir: Variant = world.call("wind_status")
	var wind := (dir as Vector2) if dir is Vector2 else Vector2.ZERO
	if wind == Vector2.ZERO:
		return
	var s := _scale()
	var tail := wind.normalized() * (7.0 * s)
	var col := Color(0.75, 0.85, 0.95, 0.10)
	for p in _wind_particles:
		draw_line(p - tail, p, col, maxf(1.0, float(s)))


## A tiny money indicator, bottom-left just above the inventory swatches. Shown
## only when the player has money — an unobtrusive coin readout, not a panel
## (the calm screen; the full breakdown lives on the K character sheet).
func _draw_money() -> void:
	var money := int(world.call("player_money"))
	if money <= 0:
		return
	var font := ThemeDB.fallback_font
	var s := _scale()
	var fs := 12 * s
	var pad := 8.0 * s
	var sw := 14.0 * s
	# Sit one swatch-row above the inventory strip's row.
	var y := size.y - pad - sw - (fs + 6.0 * s)
	draw_string(font, Vector2(pad, y + fs), "$%d" % money,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.86, 0.45))


## A small, quiet crosshair at the cursor — the reticle the calm screen is built
## around. Deliberately faint so it frames the aim point without shouting.
func _draw_reticle() -> void:
	var m := get_viewport().get_mouse_position()
	var r := 7.0
	var col := Color(0.92, 0.95, 1.0, 0.35)
	draw_line(m + Vector2(-r, 0), m + Vector2(-2, 0), col, 1.0)
	draw_line(m + Vector2(2, 0), m + Vector2(r, 0), col, 1.0)
	draw_line(m + Vector2(0, -r), m + Vector2(0, -2), col, 1.0)
	draw_line(m + Vector2(0, 2), m + Vector2(0, r), col, 1.0)


## Inventory as colour swatches + counts, bottom-left. Reads plain [color, name,
## count] rows from the world; empty inventory draws nothing at all (calm screen).
func _draw_inventory_strip() -> void:
	var rows: Variant = world.call("inventory_swatches")
	if rows == null or (rows as Array).is_empty():
		return
	var font := ThemeDB.fallback_font
	var s := _scale()
	var fs := 12 * s
	var sw := 14.0 * s          # swatch edge
	var pad := 8.0 * s
	var gap := 6.0 * s
	var y := size.y - pad - sw
	var x := pad
	for row in rows as Array:
		var col := (row as Array)[0] as Color
		var count := int((row as Array)[2])
		draw_rect(Rect2(x, y, sw, sw), col)
		draw_rect(Rect2(x, y, sw, sw), Color(0, 0, 0, 0.5), false, 1.0)
		var label := "%d" % count
		var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(x + sw + 4.0 * s, y + sw * 0.85),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.90, 0.93, 0.98))
		x += sw + 4.0 * s + tw + gap


## The deep-air warning, top-centre — shown ONLY while the local body is in the
## deep band's unbreathable air (world.depth_status), nothing otherwise (the calm
## screen). Unprotected: a slow RED pulse — "ascend or craft life-support" — so the
## danger reads without an obnoxious flash. Protected: a quiet cyan "air holding",
## the reassurance that the Aether Lung is doing its job. This is the deep-air
## feedback the gate needs: the band reads as dangerous the moment you enter it.
func _draw_depth_warning() -> void:
	var st: Variant = world.call("depth_status")
	if st == null or not bool((st as Dictionary).get("deep", false)):
		return
	var protected := bool((st as Dictionary).get("protected", false))
	var font := ThemeDB.fallback_font
	var s := _scale()
	var fs := 15 * s
	var text := "LIFE-SUPPORT — air holding" if protected \
		else "UNBREATHABLE AIR — ascend or craft an Aether Lung"
	var col: Color
	if protected:
		col = Color(0.55, 0.82, 0.95, 0.85)
	else:
		# A slow pulse (~0.4 Hz), never a strobe — danger, not a seizure.
		var pulse := 0.55 + 0.45 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 380.0))
		col = Color(1.0, 0.35, 0.30, pulse)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := (size.x - tw) * 0.5
	var y := 44.0 * s
	draw_string(font, Vector2(x + 1, y + fs + 1), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6))
	draw_string(font, Vector2(x, y + fs), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## The one or two contextual cues, bottom-centre, stacked. Only what is usable
## right now; nothing when nothing applies. The world builds the strings from
## HudCues; this just centres and paints them.
func _draw_cue_bar() -> void:
	var lines: Variant = world.call("contextual_cue_lines")
	if lines == null or (lines as Array).is_empty():
		return
	var font := ThemeDB.fallback_font
	var s := _scale()
	var fs := 13 * s
	var line_h := fs + 6 * s
	var n := (lines as Array).size()
	var y := size.y - 12.0 * s - float(n) * line_h
	for line in lines as Array:
		var text := line as String
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := (size.x - tw) * 0.5
		# A faint shadow so the cue reads over any background.
		draw_string(font, Vector2(x + 1, y + fs + 1), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6))
		draw_string(font, Vector2(x, y + fs), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.95, 0.75))
		y += line_h
