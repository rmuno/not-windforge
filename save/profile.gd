class_name Profile
extends RefCounted

## THE PLAYER PROFILE — persistent progress that outlives a single session save.
## The store a TITLE-SCREEN log needs: the title is its own scene (maps/intro) with
## no world and no loaded save, so a "creatures you have met" list shown there has
## to read from something that is always on disk and not tied to one expedition.
##
## Deliberately SEPARATE from user://saves/*.json: a save is ONE run of the world;
## this is everything you have ever met, across every save and every Dive. Today it
## holds exactly one thing — the CreatureLog's discovered set (the bestiary, step 1
## of the workshop). More of the workshop (unlocked blueprints, a records board)
## would land here beside it.
##
## FORMAT — human-inspectable JSON at user://profile.json, versioned like SaveGame
## and read with the same graceful-failure discipline: a missing, unreadable,
## corrupt, or wrong-format file is a CLEAN EMPTY profile, never a crash and never
## a half-load. Pure of autoloads (FileAccess/JSON only), so it is safe to name as a
## type in a test file (CODEMAP §4).

const PATH := "user://profile.json"
## Bump when the shape changes and migrate in `from_dict`; an unrecognised format
## loads as empty (the same graceful gate SaveGame uses).
const FORMAT_VERSION := 1

## The met-creatures record. Always present (a fresh CreatureLog for a new player).
var creatures := CreatureLog.new()


## Read the profile off disk. Returns a clean empty profile on ANY failure — no
## file yet, an unreadable handle, malformed JSON, or an unsupported format — so a
## first-run or corrupt profile is simply "nothing met yet".
static func load() -> Profile:
	if not FileAccess.file_exists(PATH):
		return Profile.new()
	var f := FileAccess.open(PATH, FileAccess.READ)
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
	return p


func to_dict() -> Dictionary:
	return {"format": FORMAT_VERSION, "creatures": creatures.to_dict()}


## Write the profile to disk (pretty-printed). Returns false if the file could not
## be opened — never throws. Called when a creature is newly met, so it is a small
## write on a rare event.
func save() -> bool:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	return true
