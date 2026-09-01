class_name CreatureLog
extends RefCounted

## THE CREATURE LOG — a persistent "have you met it" record over the game's
## authored creatures. Step 1 of the owner's title-screen WORKSHOP ask ("the
## discovered creature(s) log"), and the recommended first step because it is
## mostly data the game already has plus a met-flag, and it is the one entry that
## rewards PLAYING rather than being an editor bolted to the menu.
##
## Pure data + logic: the ROSTER of varieties, the map from a spawn `.ship` path
## to a variety id, and a discovered-set that encodes to / from a plain dict for
## the profile (save/profile.gd). No nodes, no autoloads — so the whole thing is
## unit-testable without booting the world, and it is SAFE TO NAME AS A TYPE IN A
## TEST FILE (the class-cache trap in CODEMAP §4 only bites a class that reaches
## an autoload before they exist; this one reaches nothing).
##
## GRANULARITY: one row per authored SILHOUETTE (variety), not per coarse
## `creature_kind` — the owner chose "varieties (~18)". A body carries its variety
## on `Ship.variety`, set at spawn from its `.ship` path (world._spawn_one_*);
## discovery reads that. `variety_from_path` is the single source of that id, so a
## row's `id` is literally the `.ship` basename and a spawn tags exactly the id a
## row carries — the parity the suite pins.
##
## EASTER EGGS ARE NOT ROSTER ENTRIES on purpose: the ghost whale (Pale Wanderer)
## and the Deep Sovereign kraken are cosmetic tint overrides, hidden by design and
## catalogued in the Secret Log. The bestiary must not spoil them, so it lists the
## honest creatures only and an egg simply logs as its underlying variety.

## The coarse families — used only to GROUP the bestiary and to hint at an
## undiscovered row ("a whale you have not met yet") without naming it.
const KIND_WHALE := "whale"
const KIND_KRAKEN := "kraken"
const KIND_BASILISK := "basilisk"
const KIND_CRITTER := "critter"

## The order kinds are shown in the bestiary, with their section headers.
const KIND_ORDER := [KIND_WHALE, KIND_KRAKEN, KIND_BASILISK, KIND_CRITTER]
const KIND_HEADERS := {
	KIND_WHALE: "WHALES", KIND_KRAKEN: "KRAKENS",
	KIND_BASILISK: "BASILISKS", KIND_CRITTER: "CRITTERS",
}

## The roster, in display order within a kind. Each `id` == the `.ship` basename
## (see variety_from_path), so it matches what a spawn writes onto Ship.variety.
## Names come straight from the authored bodies' own descriptions in the source
## (WhaleSpawn.PLANS comments; world's kraken plans).
const ROSTER := [
	{"id": "whale",           "name": "Blue Whale",         "kind": KIND_WHALE},
	{"id": "whale_bull",      "name": "Bull Whale",         "kind": KIND_WHALE},
	{"id": "whale_humpback",  "name": "Humpback Whale",     "kind": KIND_WHALE},
	{"id": "whale_sleek",     "name": "Sleek Whale",        "kind": KIND_WHALE},
	{"id": "whale_bowhead",   "name": "Bowhead Whale",      "kind": KIND_WHALE},
	{"id": "whale_manta",     "name": "Manta Whale",        "kind": KIND_WHALE},
	{"id": "whale_narwhal",   "name": "Narwhal",            "kind": KIND_WHALE},
	{"id": "whale_leviathan", "name": "Leviathan",          "kind": KIND_WHALE},
	{"id": "whale_city",      "name": "Leviathan Arcology", "kind": KIND_WHALE},
	{"id": "kraken_c",        "name": "Ammonite Conch",     "kind": KIND_KRAKEN},
	{"id": "kraken_b",        "name": "Giant Squid",        "kind": KIND_KRAKEN},
	{"id": "kraken_urchin",   "name": "Urchin Kraken",      "kind": KIND_KRAKEN},
	{"id": "kraken_angler",   "name": "Anglerfish Kraken",  "kind": KIND_KRAKEN},
	{"id": "kraken_nautilus", "name": "Nautilus Kraken",    "kind": KIND_KRAKEN},
	{"id": "basilisk",        "name": "Basilisk",           "kind": KIND_BASILISK},
	{"id": "critter",         "name": "Sky Critter",        "kind": KIND_CRITTER},
]


# --- The roster (pure statics) ---------------------------------------------

## The variety id for a `.ship` resource path — its basename without directory or
## extension. "res://ships/whale_bowhead.ship" -> "whale_bowhead". This is the ONE
## place a path becomes an id, so a spawn and a roster row cannot drift in how
## they spell it.
static func variety_from_path(path: String) -> String:
	var base := path.get_file()           # "whale_bowhead.ship"
	return base.get_basename()            # "whale_bowhead"


## Total number of authored varieties (the denominator of "met X of Y").
static func total() -> int:
	return ROSTER.size()


## Every roster row for a coarse kind, in display order.
static func of_kind(kind: String) -> Array:
	var out: Array = []
	for row in ROSTER:
		if String((row as Dictionary)["kind"]) == kind:
			out.append(row)
	return out


static func is_known_id(id: String) -> bool:
	for row in ROSTER:
		if String((row as Dictionary)["id"]) == id:
			return true
	return false


## The display name for a variety id (the id itself if it is not a roster row —
## should never happen, but never crash for a missing name).
static func name_of(id: String) -> String:
	for row in ROSTER:
		if String((row as Dictionary)["id"]) == id:
			return String((row as Dictionary)["name"])
	return id


# --- The discovered set (an instance) --------------------------------------

## Discovered variety ids, as a set (id -> true). A Dictionary rather than an
## Array so `has` and `mark` are O(1) and JSON round-trips cleanly.
var discovered := {}


## Record that variety `id` has been met. Returns true only when this is a NEW
## discovery of a KNOWN roster id — the signal the world uses to notify + persist.
## An unknown id (a body with no variety, or a `.ship` with no roster row) is
## dropped: the parity test guarantees every spawn maps to a row, so a drop means
## a creature was added without a bestiary entry, and the suite reddens.
func mark(id: String) -> bool:
	if id == "" or not is_known_id(id) or discovered.has(id):
		return false
	discovered[id] = true
	return true


func has(id: String) -> bool:
	return discovered.has(id)


## How many DISTINCT roster varieties have been met (ignores any stale id that is
## no longer in the roster, so a removed creature cannot inflate the count).
func count() -> int:
	var n := 0
	for row in ROSTER:
		if discovered.has(String((row as Dictionary)["id"])):
			n += 1
	return n


# --- Persistence (plain dict, for save/profile.gd) -------------------------

## The discovered set as a JSON-safe dict {id: true}. Only KNOWN ids are written,
## so an old profile carrying a since-removed creature is quietly cleaned on save.
func to_dict() -> Dictionary:
	var out := {}
	for row in ROSTER:
		var id := String((row as Dictionary)["id"])
		if discovered.has(id):
			out[id] = true
	return out


static func from_dict(data: Dictionary) -> CreatureLog:
	var log := CreatureLog.new()
	for key in data.keys():
		var id := String(key)
		if is_known_id(id) and bool(data[key]):
			log.discovered[id] = true
	return log


# --- The bestiary page text (pure, so the suite can assert it) -------------

## The whole bestiary panel body for a discovered set (id -> true). Grouped by
## kind; a met creature shows its name, an unmet one shows "???" under its kind's
## header — so the log tells you WHAT FAMILY you are missing without spoiling the
## name. `met_count` is computed against the roster, not the set, so a stale id
## cannot skew the header.
static func bestiary_text(discovered_set: Dictionary) -> String:
	var met := 0
	for row in ROSTER:
		if discovered_set.has(String((row as Dictionary)["id"])):
			met += 1
	var lines: Array = [
		"",
		"  A E R O N A U T ' S   B E S T I A R Y  ",
		"",
		"  Met %d of %d creatures  " % [met, total()],
		"",
	]
	for kind in KIND_ORDER:
		var rows := of_kind(kind)
		if rows.is_empty():
			continue
		lines.append("  %s  " % String(KIND_HEADERS.get(kind, kind)))
		for row in rows:
			var r := row as Dictionary
			if discovered_set.has(String(r["id"])):
				lines.append("    ✓ %s  " % String(r["name"]))
			else:
				lines.append("    · ???  ")
		lines.append("")
	return "\n".join(lines)
