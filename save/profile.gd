class_name Profile
extends RefCounted

## THE PLAYER PROFILE — persistent progress that outlives a single session save.
## The store a TITLE-SCREEN log needs: the title is its own scene (maps/intro) with
## no world and no loaded save, so a "creatures you have met" list shown there has
## to read from something that is always on disk and not tied to one expedition.
##
## Deliberately SEPARATE from user://saves/*.json: a save is ONE run of the world;
## this is everything you have ever met, across every save and every Dive. Two
## logs today, both of them workshop pages: the CreatureLog's discovered set (the
## bestiary) and the DiveCards taken set (the card gallery). More of the workshop
## (unlocked blueprints, a records board) would land here beside them.
##
## FORMAT — human-inspectable JSON at user://profile.json, versioned like SaveGame
## and read with the same graceful-failure discipline: a missing, unreadable,
## corrupt, or wrong-format file is a CLEAN EMPTY profile, never a crash and never
## a half-load. Pure of autoloads (FileAccess/JSON only), so it is safe to name as a
## type in a test file (CODEMAP §4).

const PATH := "user://profile.json"

## Where load/save actually point. THE SUITES REDIRECT THIS to a scratch file
## in their _initialize — every full run used to WIPE the owner's real
## bestiary + card gallery (the creature-log check and the F2 forget buttons
## write through the live path), which on a machine where the assistant runs
## run_all constantly meant the profile never survived a working session. A
## `static var` so a test can point it away; the game never touches it.
static var path := PATH
## Bump when the shape changes and migrate in `from_dict`; an unrecognised format
## loads as empty (the same graceful gate SaveGame uses).
const FORMAT_VERSION := 1

## The met-creatures record. Always present (a fresh CreatureLog for a new player).
var creatures := CreatureLog.new()

## The taken-cards record (owner 2026-09-01: the title's card screen shows what
## YOU have actually drafted). Always present; empty for a new player, and empty
## for every profile written before this key existed — which is why the FORMAT
## VERSION DID NOT MOVE. A bump would send every existing profile through the
## migration gate below and wipe the bestiary that is already on the owner's disk;
## an ADDED key needs no bump, because `from_dict` defaults it to empty.
var cards := DiveCards.new()


## Read the profile off disk. Returns a clean empty profile on ANY failure — no
## file yet, an unreadable handle, malformed JSON, or an unsupported format — so a
## first-run or corrupt profile is simply "nothing met yet".
static func load() -> Profile:
	if not FileAccess.file_exists(path):
		return Profile.new()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return Profile.new()
	var text := f.get_as_text()
	f.close()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return Profile.new()   # corrupt / truncated — refuse gracefully
	var data: Variant = parser.data
	if typeof(data) != TYPE_DICTIONARY:
		return Profile.new()
	return from_dict(data as Dictionary)


## Rebuild a profile from a parsed dict. An absent or unrecognised `format` yields
## a fresh empty profile (the migration gate). Pure — no disk — so the suite can
## round-trip it without touching user://.
static func from_dict(data: Dictionary) -> Profile:
	var p := Profile.new()
	if int(data.get("format", -1)) != FORMAT_VERSION:
		return p
	p.creatures = CreatureLog.from_dict(data.get("creatures", {}) as Dictionary)
	# Absent on every profile written before the card log existed — an empty log,
	# never a failed load (the graceful rule applies per key, not just per file).
	p.cards = DiveCards.from_dict(data.get("cards", {}) as Dictionary)
	return p


func to_dict() -> Dictionary:
	return {
		"format": FORMAT_VERSION,
		"creatures": creatures.to_dict(),
		"cards": cards.to_dict(),
	}


## Write the profile to disk (pretty-printed). Returns false if the file could not
## be opened — never throws. Called when a creature is newly met or a card is
## taken for the first time, so it is a small write on a rare event.
func save() -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	return true
