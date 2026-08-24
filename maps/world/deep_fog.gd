class_name DeepFog
extends Control

## The deep haze (owner + WORLD_SPEC "Core of Cordeus": thick yellow/brown EMBER
## FOG from the lower levels — the kraken's murk above the lava core). A screen-
## space atmospheric wash that FADES IN as you descend: nothing in the breathable
## bands, thickening through the deep band to a warm murk at the floor. Purely a
## view effect — it never touches gameplay — and it sits UNDER the HUD (health,
## cues, map stay readable) but OVER the world. The density is a pure function the
## world exposes (fog_density), so it is testable and the render can't drift from it.

## Fog begins at the deep band's top and thickens to the floor. Read from Airspace
## so map, sim and haze share the one band model.
const FADE_TOP_FRAC := Airspace.DEEP_TOP    ## 0.34 — no haze above here
const MAX_ALPHA := 0.52                      ## the murk never fully blinds you
const HAZE := Color(0.52, 0.40, 0.16)        ## yellow/brown ember tint
const EMBERS := 46

var world: Node2D
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()   # cheap; erasing is a redraw too (godot-quirks)


## Fog density 0..1 at altitude fraction `a` (0 = floor, 1 = ceiling): 0 at/above
## the deep-band top, ramping to 1 at the floor. Eased (quadratic) so the deep
## reads clear-ish and the murk gathers near the core. Pure — tests pin it.
static func density_at(a: float) -> float:
	if a >= FADE_TOP_FRAC or FADE_TOP_FRAC <= 0.0:
		return 0.0
	var lin := clampf((FADE_TOP_FRAC - a) / FADE_TOP_FRAC, 0.0, 1.0)
	return lin * lin


func _draw() -> void:
	if world == null:
		return
	var d := float(world.call("fog_density"))
	if d <= 0.0:
		return
	var vp := size
	# The base wash — denser toward the bottom of the screen (down = deeper).
	var top_a := MAX_ALPHA * d * 0.55
	var bot_a := MAX_ALPHA * d
	# Two stacked rects approximate a vertical gradient without a shader.
	draw_rect(Rect2(0, 0, vp.x, vp.y * 0.5), Color(HAZE, top_a))
	draw_rect(Rect2(0, vp.y * 0.5, vp.x, vp.y * 0.5), Color(HAZE, (top_a + bot_a) * 0.5))
	draw_rect(Rect2(0, vp.y * 0.75, vp.x, vp.y * 0.25), Color(HAZE, bot_a))

	# Rising embers — more of them, brighter, the deeper you are. Deterministic
	# columns cycling upward; a handful of cheap circles, gated by density.
	var n := int(EMBERS * d)
	for i in n:
		var fx := float((i * 13 + 5) % 100) / 100.0
		var phase := fposmod(_t * 0.22 + float(i) * 0.161, 1.0)
		var ex := fx * vp.x + sin(_t * 0.6 + float(i)) * 12.0
		var ey := vp.y * (1.0 - phase)             # drift up the screen
		var a := (1.0 - phase) * 0.5 * d
		draw_circle(Vector2(ex, ey), 1.5 + 1.5 * d, Color(1.0, 0.55, 0.18, a))
