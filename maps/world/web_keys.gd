class_name WebKeys
extends RefCounted

## Browser-safe aliases for the F-row UI toggles.
##
## WHY: the game ships to GitHub Pages as a web export, and the browser eats the
## F-row before the canvas ever sees it — F5 RELOADS THE PAGE (so "quicksave"
## threw the session away), F1 opens browser help, F3 opens find-in-page. The
## keys are not ours to bind on that platform, and there is no export-preset
## switch that takes them back (the page can only preventDefault what the
## browser lets it, and F5 is not on that list in every browser). So on web we
## additionally accept a plain letter for each reserved toggle; world._input
## matches BOTH, so a browser that DOES let an F-key through still works, and
## desktop is untouched (remap is the identity there).
##
## The mapping is DATA (one dict) so the test can assert its properties rather
## than re-walking a switch: identity off-web, the four reserved keys on-web,
## and the no-collision property (no target is itself a source).
##
## Target choice — every alias had to be a key nothing else in the game reads.
## After the 2026-08-25 consolidation (one place key, one cycle key, E to use):
## A/B/C/D/E/M/N/Q/R/S/T/W/X/Z are bound in project.godot's action map;
## H/J/K/Tab and the 1-4/0 trainer row are raw keys read in world.gd
## (0 SELLS SALVAGE — so the number row is taken too). F/G/U/V/Y fell free in
## that consolidation, but the aliases STAY on I, L, O, P — web players have
## muscle memory on them, and reshuffling working keys buys nothing.

## Reserved F-key -> browser-safe alias. Sources are keys the browser steals;
## targets are verified-unused keys (see the class doc).
const WEB_ALIASES: Dictionary = {
	KEY_F1: KEY_I,  # help panel
	KEY_F3: KEY_L,  # whale/collision diagnostic (L for the log it writes)
	KEY_F5: KEY_P,  # quicksave — the one F5 actively destroyed
	KEY_F9: KEY_O,  # saves panel
}


## True when running inside a browser (the GitHub Pages build).
static func is_web() -> bool:
	return OS.has_feature("web")


## Pure form, so the headless suite can test both platforms — OS.has_feature
## cannot be faked in a test.
static func remap_for(keycode: int, web: bool) -> int:
	if not web:
		return keycode
	return int(WEB_ALIASES.get(keycode, keycode))


## Platform-resolved remap: identity on desktop, aliased in a browser.
static func remap(keycode: int) -> int:
	return remap_for(keycode, is_web())


## The reverse fold: the reserved key an alias stands in for, identity for
## anything else (and always identity off-web). world._input runs the pressed
## key through this BEFORE its match, so on web the F-key AND its alias both
## reach the same toggle — a browser that lets F1 through keeps working.
static func unalias_for(keycode: int, web: bool) -> int:
	if not web:
		return keycode
	var source: Variant = WEB_ALIASES.find_key(keycode)
	return keycode if source == null else int(source)


## Platform-resolved reverse fold: identity on desktop.
static func unalias(keycode: int) -> int:
	return unalias_for(keycode, is_web())


## The alias the help panel should advertise for a reserved key on this
## platform — used to print "I help" in the browser and "F1 help" on desktop.
static func label_for(keycode: int, web: bool) -> String:
	return OS.get_keycode_string(remap_for(keycode, web))
