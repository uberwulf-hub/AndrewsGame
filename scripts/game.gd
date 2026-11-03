extends Node
## Global game state (autoload "Game"): input bindings, shared RNG, terrain height
## lookup, notifications, and command-line options used for automated screenshots.

signal notified(text: String, color: Color)

const WORLD_RADIUS := 205.0
const TERRAIN_SIZE := 440.0
const TERRAIN_CELLS := 220
const WATER_LEVEL := -1.2
const BIOME_NAMES := {
	"sanctum": "The Sanctum",
	"meadow": "Whispering Meadows",
	"shore": "Glasswater Shore",
	"highlands": "Frostspine Highlands",
}

var rng := RandomNumberGenerator.new()
var player: Player
## True while the camera is below the water surface (drives view and sound changes).
var underwater := false
var terrain_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()


## Story start (set when the dream ends): wake unarmed under the great tree
## instead of at the Sanctum with a rifle.
var story_start := false
var wake_point := Vector3.ZERO
## What's in the backpack (names shown on the character sheet).
var backpack: Array[String] = []

# --- Survival: inventory, use-based skills and needs ---------------------------

signal inventory_changed
signal skill_leveled(skill: String, level: int)

const ENEMIES_ENABLED := false  # hostile camps are off while the opening is built
const SKILLS := ["Foraging", "Woodcraft", "Firecraft", "Survival", "Swimming"]
const SKILL_MAX := 50

## What each food is worth when eaten (raw, for now), out of 100 hunger.
const FOODS := {
	"Berries": 12.0, "Grubs": 6.0, "Mushrooms": 8.0, "Bird eggs": 12.0,
	"Fish": 18.0, "Crayfish": 10.0, "Clams": 9.0,
}
## The pets' knacks: they get better at finding food the more they do it.
const PET_KNACKS := {"fox": "Fox: Sniffing", "otter": "Otter: Fishing"}

## Item counts by name (sticks, stones, berries, ...).
var inventory := {}
## Skill XP by name; level comes from xp_to_level().
var skills := {}
## Needs from 0 (empty) to 100 (full).
var warmth := 100.0
var hunger := 100.0
var thirst := 100.0
var canteen_sips := 0


func add_item(item: String, count := 1) -> void:
	inventory[item] = inventory.get(item, 0) + count
	inventory_changed.emit()


func has_items(item: String, count := 1) -> bool:
	return inventory.get(item, 0) >= count


func take_items(item: String, count := 1) -> bool:
	if not has_items(item, count):
		return false
	inventory[item] -= count
	if inventory[item] <= 0:
		inventory.erase(item)
	inventory_changed.emit()
	return true


func skill_level(skill: String) -> int:
	return xp_to_level(skills.get(skill, 0.0))


static func xp_to_level(xp: float) -> int:
	# Fast early levels, slower later: 10, 25, 45, 70... XP per level.
	return mini(SKILL_MAX, 1 + int(sqrt(xp / 5.0)))


static func level_floor_xp(level: int) -> float:
	return 5.0 * pow(level - 1, 2)


## Practice makes perfect: doing something raises the skill behind it.
func practice(skill: String, xp := 1.0) -> void:
	var before := skill_level(skill)
	skills[skill] = skills.get(skill, 0.0) + xp
	var after := skill_level(skill)
	if after > before:
		notify("%s improved to %d" % [skill, after], Color(0.7, 1.0, 0.6))
		skill_leveled.emit(skill, after)


# --- Know-how ------------------------------------------------------------------
# Things the hero has figured out how to make. Nothing is known at the start:
# each one is discovered by noticing something in the world (an old fire ring
# teaches the campfire) or taught by the Otter, then shows up on the Know-how
# tab of the backpack.

signal learned(id: String, thought: Array)

const KNOW_HOW := {
	"campfire": {"name": "Campfire", "needs": {"Sticks": 5, "Stones": 3},
		"about": "Sticks in the middle, a ring of stones around. Warmth and light."},
	"lean_to": {"name": "Lean-to", "needs": {"Sticks": 6, "Ferns": 5},
		"about": "Sticks leaned on a pole, ferns on top. Rest under it and the cold creeps in slower."},
}

var known: Array[String] = []
## Food items picked up so far (for "gather some food" goals).
var food_found := 0


## Learns something new. `thought` is what the hero thinks as it clicks;
## `teacher` names who showed him (the Otter), if anyone.
func learn(id: String, thought: Array = [], teacher := "") -> void:
	if known.has(id):
		return
	known.append(id)
	var how := ("The %s taught you: " % teacher) if teacher != "" else "You figured something out: "
	notify(how + KNOW_HOW[id].name + "  (Tab → Know-how)", Color(1.0, 0.84, 0.45))
	Audio.play("level_up", null, -10.0, 1.5)
	learned.emit(id, thought)


# --- Quests ---------------------------------------------------------------------
# Kept deliberately small: one main quest at a time and at most MAX_SIDE side
# quests on the tracker. Anything else the companions suggest waits in the
# dream journal as an idea instead of piling up on screen.

signal quests_changed
signal quest_completed(title: String)

const MAX_SIDE := 2

## Active quests: {id, title, main, giver, steps: [{text, done}]}. Main first.
var quests: Array[Dictionary] = []
## Suggestions that didn't fit on the tracker, kept for the journal.
var ideas: Array[String] = []


## Starts a quest. Side quests beyond the cap become journal ideas instead
## (returns false). A new main quest replaces the old one.
func start_quest(id: String, title: String, steps: Array, main := true, giver := "") -> bool:
	if quest(id):
		return true
	if not main and quests.filter(func(q): return not q.main).size() >= MAX_SIDE:
		if not ideas.has(title):
			ideas.append(title)
		quests_changed.emit()
		return false
	var q := {"id": id, "title": title, "main": main, "giver": giver, "steps": []}
	for s in steps:
		q.steps.append({"text": s, "done": false})
	if main:
		quests = quests.filter(func(o): return not o.main)
		quests.push_front(q)
	else:
		quests.append(q)
	ideas.erase(title)
	notify(("New quest: " if main else "Side quest: ") + title, Color(1.0, 0.84, 0.45))
	quests_changed.emit()
	return true


func quest(id: String) -> Dictionary:
	for q in quests:
		if q.id == id:
			return q
	return {}


## Updates one step's text and whether it's done.
func set_step(id: String, index: int, text: String, done: bool) -> void:
	var q := quest(id)
	if q.is_empty() or index >= q.steps.size():
		return
	var step: Dictionary = q.steps[index]
	if step.text == text and step.done == done:
		return
	step.text = text
	step.done = done
	quests_changed.emit()


func complete_quest(id: String) -> void:
	var q := quest(id)
	if q.is_empty():
		return
	quests.erase(q)
	notify("Quest complete: " + q.title, Color(0.7, 1.0, 0.6))
	Audio.play("level_up", null, -8.0, 1.2)
	quest_completed.emit(q.title)
	quests_changed.emit()


## The lowest need, used by the player to decide whether health recovers.
func lowest_need() -> float:
	return minf(warmth, minf(hunger, thirst))

# Screenshot mode: run with `-- --screenshot=path.png [--shot-delay=4] [--shot-yaw=deg] [--shot-pos=x,z] [--shot-demo]`
var screenshot_mode := false
var screenshot_path := ""
var screenshot_delay := 4.0
var shot_yaw := 0.0
var shot_pos := Vector2.ZERO
var has_shot_pos := false
var shot_demo := false
var shot_underwater := false
var dream_shots: Array[float] = []
var shot_speed := 1.0
var shot_inventory := false
var shot_tab := "Backpack"
var shot_punch := false
var shot_place := false
var shot_forage := false
var shot_settle := false
var shot_help := false


func _ready() -> void:
	rng.randomize()
	terrain_noise.seed = 7331
	terrain_noise.frequency = 0.0055
	terrain_noise.fractal_octaves = 4
	detail_noise.seed = 99
	detail_noise.frequency = 0.03
	_setup_input()
	_parse_args()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_F11:
		var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)


func notify(text: String, color := Color.WHITE) -> void:
	notified.emit(text, color)


## Terrain height at a world position. Flat plaza at the center, rolling hills,
## shallow lakes, and a ring of mountains that bounds the playable area.
func height_at(x: float, z: float) -> float:
	var h := terrain_noise.get_noise_2d(x, z) * 16.0
	if h < -3.0:
		h = -3.0 + (h + 3.0) * 0.3
	var d := Vector2(x, z).length()
	h = lerpf(0.6, h, smoothstep(16.0, 40.0, d))
	var edge := clampf((d - 165.0) / 45.0, 0.0, 1.0)
	h += edge * edge * 40.0
	return h


## Height of the rendered terrain surface. The mesh is a grid of flat triangles, so
## between grid points it can sit below height_at(); use this to place things on it.
func ground_at(x: float, z: float) -> float:
	var step := TERRAIN_SIZE / TERRAIN_CELLS
	var gx := (x + TERRAIN_SIZE * 0.5) / step
	var gz := (z + TERRAIN_SIZE * 0.5) / step
	var x0 := floorf(gx)
	var z0 := floorf(gz)
	var u := gx - x0
	var v := gz - z0
	var wx := -TERRAIN_SIZE * 0.5 + x0 * step
	var wz := -TERRAIN_SIZE * 0.5 + z0 * step
	var h01 := height_at(wx, wz + step)
	var h10 := height_at(wx + step, wz)
	# Same split as the mesh: triangles (00, 10, 01) and (10, 11, 01).
	if u + v <= 1.0:
		var h00 := height_at(wx, wz)
		return h00 + u * (h10 - h00) + v * (h01 - h00)
	var h11 := height_at(wx + step, wz + step)
	return h11 + (1.0 - u) * (h01 - h11) + (1.0 - v) * (h10 - h11)


## Lowest ground under a circular footprint, so wide objects never overhang a slope.
func ground_under(x: float, z: float, radius: float) -> float:
	var lowest := ground_at(x, z)
	for k in 8:
		var a := TAU * k / 8.0
		lowest = minf(lowest, ground_at(x + cos(a) * radius, z + sin(a) * radius))
	return lowest


## Biome at a position, used for music, ambience, footsteps and the HUD.
func biome_at(pos: Vector3) -> String:
	var d := Vector2(pos.x, pos.z).length()
	if d < 22.0:
		return "sanctum"
	if height_at(pos.x, pos.z) > 16.0 or d > 172.0:
		return "highlands"
	for k in 8:
		var a := TAU * k / 8.0
		if height_at(pos.x + cos(a) * 14.0, pos.z + sin(a) * 14.0) < WATER_LEVEL:
			return "shore"
	return "meadow"


## Danger grows the further you travel from the Sanctum.
func enemy_level_at(pos: Vector3) -> int:
	return 1 + int(Vector2(pos.x, pos.z).length() / 24.0)


func _setup_input() -> void:
	_bind_key("move_forward", KEY_W)
	_bind_key("move_back", KEY_S)
	_bind_key("move_left", KEY_A)
	_bind_key("move_right", KEY_D)
	_bind_key("jump", KEY_SPACE)
	_bind_key("sprint", KEY_SHIFT)
	_bind_key("reload", KEY_R)
	_bind_key("ability_nova", KEY_Q)
	_bind_key("ability_dash", KEY_F)
	_bind_key("swim_down", KEY_C)
	_bind_key("swim_down", KEY_CTRL)
	_bind_key("interact", KEY_E)
	_bind_key("character", KEY_TAB)
	_bind_key("pause", KEY_ESCAPE)
	_bind_key("volume_down", KEY_MINUS)
	_bind_key("volume_up", KEY_EQUAL)
	_bind_mouse("fire", MOUSE_BUTTON_LEFT)
	_bind_mouse("aim", MOUSE_BUTTON_RIGHT)


func _bind_key(action: StringName, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _bind_mouse(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var key := arg.get_slice("=", 0)
		var value := arg.get_slice("=", 1)
		match key:
			"--screenshot":
				screenshot_path = value
			"--shot-delay":
				screenshot_delay = value.to_float()
			"--shot-yaw":
				shot_yaw = deg_to_rad(value.to_float())
			"--shot-pos":
				var parts := value.split(",")
				shot_pos = Vector2(parts[0].to_float(), parts[1].to_float())
				has_shot_pos = true
			"--shot-demo":
				shot_demo = true
			"--shot-underwater":
				shot_underwater = true
			"--shot-dream":
				for t in value.split(","):
					dream_shots.append(t.to_float())
			"--shot-speed":
				shot_speed = value.to_float()
			"--shot-inventory":
				shot_inventory = true
				if value != "":
					shot_tab = value
			"--shot-help":
				shot_help = true
			"--shot-settle":
				shot_settle = true
			"--shot-forage":
				shot_forage = true
			"--shot-place":
				shot_place = true
			"--shot-punch":
				shot_punch = true
			"--shot-wake":
				story_start = true
	screenshot_mode = screenshot_path != ""
	if screenshot_mode:
		# Test captures: keep the window off-screen and never take keyboard focus,
		# so it doesn't cover what you're doing or catch your typing. (Minimizing
		# would stop it drawing.)
		get_window().set_flag(Window.FLAG_NO_FOCUS, true)
		get_window().position = Vector2i(-5000, -5000)
