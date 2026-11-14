class_name SaveGame
extends RefCounted
## One save slot on disk: what's in your pockets and backpack, what you know,
## your quests, where you are, the time of day, and everything you've built.
## The world itself is the same every time (it's grown from a fixed seed), so
## only what you changed needs keeping. The story's own place is kept by the
## World (see World.story_state()).

const PATH := "user://save.dat"
const TEST_PATH := "user://save_test.dat"  # test runs never touch the real save
const VERSION := 1

## Filled in from the title screen's Load Game; the World picks it up on start.
static var pending: Dictionary = {}


static func _path() -> String:
	return TEST_PATH if Game.screenshot_mode else PATH


static func exists() -> bool:
	return FileAccess.file_exists(_path())


## When the save was made, for the title screen ("" if there isn't one).
static func saved_when() -> String:
	var data := read()
	return data.get("when", "")


static func read() -> Dictionary:
	if not exists():
		return {}
	var f := FileAccess.open(_path(), FileAccess.READ)
	if f == null:
		return {}
	var data = f.get_var()
	if typeof(data) != TYPE_DICTIONARY or data.get("version", 0) != VERSION:
		return {}
	return data


## Writes everything to disk. `story` is the World's own record of where the
## story's got to.
static func write(tree: SceneTree, story: Dictionary) -> bool:
	var p := Game.player
	var built := []
	for c in tree.get_nodes_in_group("campfires"):
		built.append(["hearth" if c is Hearth else "campfire", (c as Node3D).global_position, (c as Node3D).rotation.y])
	for group in [["bedrolls", "bedroll"], ["chests", "chest"], ["dream_catchers", "dream_catcher"], ["rain_covers", "rain_cover"], ["rafts", "raft"]]:
		for n in tree.get_nodes_in_group(group[0]):
			built.append([group[1], (n as Node3D).global_position, (n as Node3D).rotation.y])
	for s in tree.get_nodes_in_group("shelters"):
		built.append(["lean_to", (s as Node3D).global_position, (s as Node3D).rotation.y])
	for t in tree.get_nodes_in_group("torches"):
		built.append(["torch_post", (t as Node3D).global_position, 0.0])
	for r in tree.get_nodes_in_group("rain_catchers"):
		built.append(["rain_catcher", (r as Node3D).global_position, (r as Node3D).rotation.y])
	var data := {
		"version": VERSION,
		"when": Time.get_datetime_string_from_system(false, true),
		"game": {
			"inventory": Game.inventory.duplicate(true),
			"skills": Game.skills.duplicate(true),
			"known": Array(Game.known),
			"sparks": Array(Game.sparks),
			"sparks_open": Game.sparks_open,
			"held_sparks": Game._held_sparks.duplicate(true),
			"quests": Array(Game.quests).duplicate(true),
			"ideas": Array(Game.ideas),
			"food_found": Game.food_found,
			"warmth": Game.warmth,
			"hunger": Game.hunger,
			"thirst": Game.thirst,
			"canteen_sips": Game.canteen_sips,
			"backpack": Array(Game.backpack),
			"is_night": Game.is_night,
			"rest_ready": Game.rest_ready,
			"stash": Game.stash.duplicate(),
			"rested": Game.rested,
		},
		"player": {
			"pos": p.global_position,
			"yaw": p._yaw,
			"health": p.health,
			"max_health": p.max_health,
			"level": p.level,
			"xp": p.xp,
			"wet": p.wet,
		},
		"built": built,
		"explored": Game.explored,
		"story": story,
	}
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(data)
	return true


## Puts the saved pockets, needs and quests back into Game.
static func restore_game(data: Dictionary) -> void:
	var g: Dictionary = data.game
	Game.inventory = g.inventory.duplicate(true)
	Game.skills = g.skills.duplicate(true)
	Game.known.assign(g.known)
	Game.sparks.assign(g.sparks)
	Game.sparks_open = g.sparks_open
	Game._held_sparks = g.held_sparks.duplicate(true)
	Game.quests.assign(g.quests.duplicate(true))
	Game.ideas.assign(g.ideas)
	Game.food_found = g.food_found
	Game.warmth = g.warmth
	Game.hunger = g.hunger
	Game.thirst = g.thirst
	Game.canteen_sips = g.canteen_sips
	Game.backpack.assign(g.backpack)
	Game.rest_ready = g.rest_ready
	Game.stash = g.get("stash", {}).duplicate()
	Game.rested = g.get("rested", 0.0)
	Game.inventory_changed.emit()
	Game.quests_changed.emit()


## Puts the hero back where he was.
static func restore_player(data: Dictionary, p: Player) -> void:
	var d: Dictionary = data.player
	p.global_position = d.pos + Vector3.UP * 0.1
	p.spawn_point = d.pos + Vector3.UP
	p._yaw = d.yaw
	p.max_health = d.max_health
	p.health = d.health
	p.level = d.level
	p.xp = d.xp
	p.wet = d.wet


## Rebuilds the campfires, lean-tos, torches and rain catchers.
static func restore_built(data: Dictionary, parent: Node) -> void:
	for b in data.built:
		var at: Vector3 = b[1]
		match b[0]:
			"campfire":
				Campfire.build(parent, at)
			"lean_to":
				Shelter.build(parent, at, b[2])
			"torch_post":
				TorchPost.build(parent, at)
			"rain_catcher":
				RainCatcher.build(parent, at).rotation.y = b[2]
			"hearth":
				Hearth.build_hearth(parent, at, b[2])
			"bedroll":
				Bedroll.build(parent, at, b[2])
			"chest":
				StorageChest.build(parent, at, b[2])
			"dream_catcher":
				DreamCatcher.build(parent, at, b[2])
			"rain_cover":
				RainCover.build(parent, at, b[2])
			"raft":
				Raft.build(parent, at, b[2])
