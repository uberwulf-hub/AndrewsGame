class_name WeaponData
extends RefCounted
## A generated dream tool (wand, sling, horn, jar of fireflies, moonbow):
## archetype base stats scaled by item level and rarity, an optional element,
## and rarity-dependent perks. The archetype keys are the old internal names;
## `kind` is what the player sees.

enum Element { KINETIC, FIRE, SHOCK, FROST }

const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Mythic"]
const RARITY_COLORS := [Color(0.82, 0.82, 0.82), Color(0.35, 0.9, 0.4), Color(0.3, 0.6, 1.0), Color(0.75, 0.35, 1.0), Color(1.0, 0.62, 0.15)]
const RARITY_WEIGHTS := [55.0, 26.0, 12.0, 5.5, 1.5]
const ELEMENT_NAMES := ["Wild", "Ember", "Storm", "Frost"]
const ELEMENT_COLORS := [Color(1.0, 0.85, 0.55), Color(1.0, 0.42, 0.12), Color(0.6, 0.55, 1.0), Color(0.5, 1.0, 0.95)]
const ELEMENT_DESCRIPTIONS := [
	"",
	"Ember: hits set foes smouldering for 3s",
	"Storm: hits leap to a nearby foe for 50% damage",
	"Frost: hits slow foes by 50%",
]

## What each archetype is in the dream.
const KINDS := {
	"Rifle": "Wisp Wand", "Hand Cannon": "Oak Sling", "Scattergun": "Seed Horn",
	"Rune SMG": "Firefly Jar", "Sky Lance": "Moonbow",
}

const ARCHETYPES := {
	"Rifle": {"damage": 14.0, "fire_rate": 8.0, "mag": 30, "reload": 1.8, "spread": 0.012, "pellets": 1, "auto": true, "crit": 0.05},
	"Hand Cannon": {"damage": 48.0, "fire_rate": 2.2, "mag": 8, "reload": 1.6, "spread": 0.004, "pellets": 1, "auto": false, "crit": 0.15},
	"Scattergun": {"damage": 11.0, "fire_rate": 1.4, "mag": 6, "reload": 2.2, "spread": 0.07, "pellets": 8, "auto": false, "crit": 0.05},
	"Rune SMG": {"damage": 8.0, "fire_rate": 14.0, "mag": 40, "reload": 1.5, "spread": 0.025, "pellets": 1, "auto": true, "crit": 0.03},
	"Sky Lance": {"damage": 120.0, "fire_rate": 0.8, "mag": 4, "reload": 2.6, "spread": 0.0, "pellets": 1, "auto": false, "crit": 0.25},
}

const PERKS := {
	"explosive": "Puffball: hits pop for 40% damage nearby",
	"vampiric": "Heartsap: hits heal 3% of damage dealt",
	"overcharge": "Quickbloom: wins cut Bloom's wait by 2s",
	"keen": "True Aim: +15% crit chance",
	"deep_mag": "Deep Pouch: +50% shots before refilling",
	"executioner": "Last Light: +60% damage to foes below 30% health",
	"momentum": "Tailwind: wins quicken your shots 30% for 4s",
}

const NAME_PREFIXES := [
	["Mossy", "Rootbound", "Old-Wood", "Willow"],
	["Ember", "Sunlit", "Hearth", "Fox-Fire"],
	["Stormcall", "Thunder", "Skyfork", "Rainsong"],
	["Rimeglass", "Winter", "Snowberry", "Hoarfrost"],
]
const MYTHIC_SUFFIXES := ["of the Great Tree", "of the Hollow Moon", "of the First Dream", "of the Nine Groves"]

var archetype := "Rifle"
var display_name := ""
var rarity := 0
var level := 1
var element: int = Element.KINETIC
var damage := 10.0
var fire_rate := 1.0
var mag_size := 10
var reload_time := 1.5
var spread := 0.0
var pellets := 1
var automatic := false
var crit_chance := 0.05
var perks: Array[String] = []

var kind: String:
	get:
		return KINDS.get(archetype, archetype)

var color: Color:
	get:
		return RARITY_COLORS[rarity]


func has_perk(id: String) -> bool:
	return perks.has(id)


func dps() -> float:
	return damage * pellets * fire_rate * (1.0 + crit_chance)


static func roll_rarity(rng: RandomNumberGenerator, bonus := 0.0) -> int:
	var weights := RARITY_WEIGHTS.duplicate()
	for i in range(1, weights.size()):
		weights[i] *= 1.0 + bonus * i
	var total := 0.0
	for w in weights:
		total += w
	var roll := rng.randf() * total
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			return i
	return 0


static func generate(item_level: int, rng: RandomNumberGenerator, rarity_bonus := 0.0, forced_archetype := "", forced_rarity := -1) -> WeaponData:
	var w := WeaponData.new()
	w.level = maxi(1, item_level)
	w.rarity = forced_rarity if forced_rarity >= 0 else roll_rarity(rng, rarity_bonus)
	var names := ARCHETYPES.keys()
	w.archetype = forced_archetype if forced_archetype != "" else names[rng.randi() % names.size()]
	var base: Dictionary = ARCHETYPES[w.archetype]
	var level_mult := pow(1.13, w.level - 1)
	var rarity_mult := 1.0 + 0.12 * w.rarity
	w.damage = base["damage"] * level_mult * rarity_mult * rng.randf_range(0.9, 1.1)
	w.fire_rate = base["fire_rate"] * rng.randf_range(0.9, 1.12)
	w.mag_size = base["mag"]
	w.reload_time = base["reload"] * rng.randf_range(0.85, 1.1)
	w.spread = base["spread"] * rng.randf_range(0.8, 1.2)
	w.pellets = base["pellets"]
	w.automatic = base["auto"]
	w.crit_chance = base["crit"] + 0.01 * w.rarity

	var element_chance: float = [0.1, 0.35, 0.6, 0.85, 1.0][w.rarity]
	if rng.randf() < element_chance:
		w.element = 1 + rng.randi() % 3

	var perk_count: int = [0, 1, 1, 2, 3][w.rarity]
	var pool := PERKS.keys()
	pool.shuffle()
	for i in perk_count:
		w.perks.append(pool[i])
	if w.has_perk("deep_mag"):
		w.mag_size = int(w.mag_size * 1.5)
	if w.has_perk("keen"):
		w.crit_chance += 0.15

	var prefixes: Array = NAME_PREFIXES[w.element]
	w.display_name = "%s %s" % [prefixes[rng.randi() % prefixes.size()], w.kind]
	if w.rarity == 4:
		w.display_name += " " + MYTHIC_SUFFIXES[rng.randi() % MYTHIC_SUFFIXES.size()]
	return w
