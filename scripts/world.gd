extends Node3D
## Builds the open world at startup: sky and lighting, terrain, the central Sanctum,
## scattered ruins and flora, and enemy camps whose danger grows with distance.

const CAMP_COUNT := 26
const CAMP_RESPAWN_TIME := 60.0
const WATER_LEVEL := -1.2  # keep in sync with Game.WATER_LEVEL

var _rng := RandomNumberGenerator.new()
var _camps: Array[Dictionary] = []
var _camp_check := 0.0
var _crystal: Heartstone
var _stone_mats: Array[StandardMaterial3D] = []
var _leaf_mats: Array[StandardMaterial3D] = []
var _bark: StandardMaterial3D
var _iron: StandardMaterial3D
var _rune_mat: StandardMaterial3D
var _deep_moss_mat: StandardMaterial3D
var _fire_mat: StandardMaterial3D
var _env: Environment
var _air_fog: Array = []
var _sun: DirectionalLight3D
var _sky_material: ProceduralSkyMaterial
var _moon: MeshInstance3D
var _stars: Node3D
var _underwater_blend := 0.0


func _ready() -> void:
	_rng.seed = 20261101
	if Game.story_start:
		Game.wake_point = _find_wake_point()
		_ring_spot = _fire_ring_spot(Game.wake_point)
	_make_materials()
	_build_environment()
	_build_terrain()
	_build_water()
	_build_grass()
	_build_sanctum()
	if Game.story_start:
		_build_forest(Game.wake_point)
	_scatter_props()
	if Game.ENEMIES_ENABLED:
		_create_camps()
	_place_starter_loot()
	_build_lake_ruin()
	_build_isle()
	_build_hill()

	var player := Player.new()
	player.name = "Player"
	player.position = Player.SPAWN_POINT
	var facing := 0.0
	if Game.story_start:
		# Lying at the foot of the great tree, head toward the trunk, facing
		# roughly toward the Sanctum.
		var to_sanctum := (Vector3.ZERO - Game.wake_point).normalized()
		to_sanctum.y = 0.0
		var spot := Game.wake_point + to_sanctum.rotated(Vector3.UP, 0.5) * 3.4
		spot.y = Game.ground_at(spot.x, spot.z) + 0.05
		player.position = spot
		player.spawn_point = spot + Vector3.UP
		facing = atan2(-to_sanctum.x, -to_sanctum.z) + 0.5
	if Game.has_shot_pos:
		player.position = Vector3(Game.shot_pos.x, Game.height_at(Game.shot_pos.x, Game.shot_pos.y) + 1.0, Game.shot_pos.y)
	if Game.shot_underwater:
		player.position = _deepest_point() + Vector3.UP * 0.5
	add_child(player)
	var hud := Hud.new()
	add_child(hud)
	hud.bind(player)
	_hud = hud
	if Game.story_start:
		# Where he's been, for the map: nowhere yet in a new life, or as saved.
		Game.explored = SaveGame.pending.get("explored", PackedByteArray())
		hud.set_map_base(_map_image())
	player.passed_out.connect(_on_passed_out)
	_birds = Birds.new()
	_birds.name = "Birds"
	add_child(_birds)
	_animals = Animals.new()
	_animals.name = "Animals"
	add_child(_animals)
	var pause := PauseMenu.new()
	add_child(pause)
	if Game.shot_help:
		get_tree().create_timer(1.0).timeout.connect(func():
			pause.open()
			pause._menu.visible = false
			pause._help.visible = true)
	if Game.story_start and not SaveGame.pending.is_empty():
		_resume(player, hud, SaveGame.pending)
		SaveGame.pending = {}
	elif Game.story_start:
		_start_wake(player, hud, facing)
	else:
		Game.notify("Welcome to the Sanctum. Take a dream tool, then head out.", Color(0.6, 0.95, 1.0))

	if Game.shot_demo and Game.ENEMIES_ENABLED:
		_spawn_demo_enemies(player)
	if Game.screenshot_mode:
		_take_screenshot()


# --- Story start -------------------------------------------------------------

const WAKE_DISTANCE := 95.0
var _sanctum_found := false
var _hum_timer := 3.0
## Memory Echoes already relived, by name ("aim", ...).
var _echoes: Array[String] = []


## A meadow spot well out from the Sanctum on dry, gentle ground.
func _find_wake_point() -> Vector3:
	var best := Vector3(0, 0, WAKE_DISTANCE)
	var best_score := -INF
	for i in 48:
		var a := TAU * i / 48.0
		var p := Vector3(cos(a), 0, sin(a)) * WAKE_DISTANCE
		p.y = Game.height_at(p.x, p.z)
		if p.y < 1.0 or p.y > 14.0:
			continue
		var slope := 0.0
		for k in 8:
			var q := p + Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0)) * 12.0
			slope = maxf(slope, absf(Game.height_at(q.x, q.z) - p.y))
		var score := -slope + (2.0 if Game.biome_at(p) == "meadow" else 0.0)
		if score > best_score:
			best_score = score
			best = p
	return best


var _birds: Birds
var _animals: Animals
var _fox: Companion
var _otter: Companion
var _fire_built := false
var _hud: Hud
var _food_at_start := 0
var _cooking_hinted := false
var _night_passed := false
var _settled := false  # food, idea and roof all done
var _fire_ring: Gatherable
var _ring_spot := Vector3(INF, 0, INF)


func _start_wake(player: Player, hud: Hud, facing: float) -> void:
	Game.backpack = ["Pocketknife", "Flint", "Canteen", "Dream journal", "Rune marble (humming)"]
	Game.inventory = {}
	Game.skills = {}
	Game.quests.clear()
	Game.ideas.clear()
	Game.food_found = 0
	Game.known.clear()
	Game.sparks.clear()
	Game.sparks_open = false  # the Otter's ideas wait until morning
	Game._held_sparks.clear()
	Game.rest_ready = false
	_hud = hud
	_connect_story()
	Game.hunger = 100.0
	Game.thirst = 100.0
	Game.warmth = 70.0  # a cold night on the forest floor
	Game.canteen_sips = 2
	hud.fade_in(Color(1, 1, 1), 4.0)
	player.begin_wake(facing)
	# The Fox and the Otter sleep curled up beside him.
	var right := Vector3(cos(facing), 0, -sin(facing))
	var fox_at := player.position + right * 1.3 + Vector3(0, 0, 0)
	var otter_at := player.position - right * 1.2
	_fox = Companion.create(self, Critter.fox(), "fox", fox_at, hud)
	_otter = Companion.create(self, Critter.otter(), "otter", otter_at, hud)
	player.woke_up.connect(func():
		hud.think([
			"Whoa... that was weird.",
			"It felt so real. A whole life... every bit of it.",
			"Where am I? How did I end up out here?",
			"...What am I supposed to do now?",
		], 3.6, func():
			_fox.wake(0.4, "Finally. You snore like a bear with a cold, you know.")
			_otter.wake(3.6, "Huh? Where ARE we? ...Whoa, it's so dark. And cold!")
			# One thing at a time: a beat to look around, the backpack, then the plan.
			get_tree().create_timer(9.0).timeout.connect(func():
				Game.notify("You check your backpack: a pocketknife, flint, a canteen, your dream journal... and a marble that hums.", Color(0.85, 0.9, 1.0)))
			get_tree().create_timer(16.0).timeout.connect(_fire_hint))
	, CONNECT_ONE_SHOT)


func _connect_story() -> void:
	Game.learned.connect(_on_learned)
	Game.sparked.connect(_on_sparked)
	Game.rest_requested.connect(_pass_the_night)
	Game.built.connect(_on_built)


# --- Saving and loading ------------------------------------------------------

## Whether now's a good moment to save: not mid-scene, not underwater.
func can_save() -> bool:
	var p := Game.player
	return Game.story_start and p != null and p.alive and not p.frozen and not p.knocked_out \
		and not Game.underwater and _fox != null and p.raft == null


func save_game() -> bool:
	if not can_save():
		return false
	return SaveGame.write(get_tree(), {
		"fire_built": _fire_built,
		"settled": _settled,
		"night_passed": _night_passed,
		"sanctum_found": _sanctum_found,
		"echoes": Array(_echoes),
		"woken": range(_buds.size()).filter(func(i): return _buds[i].awake),
		"home_step": _home_step,
		"lake_stage": _lake_stage,
		"isle_stage": _isle_stage,
		"hill_stage": _hill_stage,
		"food_at_start": _food_at_start,
		"cooking_hinted": _cooking_hinted,
		"fox": [_fox._tips_given, _fox._feelings],
		"otter": [_otter._tips_given, _otter._feelings],
	})



## A new morning saves the game by itself (waiting a bit if he's busy, say
## swimming, and giving up after a minute).
func _autosave(tries := 12) -> void:
	if save_game():
		Game.notify("Game saved.", Color(0.8, 0.9, 1.0))
	elif tries > 0:
		get_tree().create_timer(5.0).timeout.connect(_autosave.bind(tries - 1))


## Picks up a saved game: the hero where he was, both pets awake beside him,
## everything built, and the story carried on from the same place (any beat
## that was still on its way when you saved starts again here).
func _resume(player: Player, hud: Hud, data: Dictionary) -> void:
	_hud = hud
	_connect_story()
	SaveGame.restore_game(data)
	SaveGame.restore_player(data, player)
	SaveGame.restore_built(data, self)
	if not data.game.is_night:
		_make_dawn()
	var s: Dictionary = data.story
	_fire_built = s.fire_built
	_settled = s.settled
	_night_passed = s.night_passed
	_sanctum_found = s.sanctum_found
	_echoes.assign(s.get("echoes", []))
	for i in s.get("woken", []):
		if i < _buds.size():
			_buds[i].wake(false)
	_home_step = s.get("home_step", -1)
	if _woken() == _buds.size() and _home_step < 0:
		get_tree().create_timer(25.0).timeout.connect(_start_home)
	if _echoes.has("aim"):
		get_tree().create_timer(20.0).timeout.connect(_start_wake_quest)
	_lake_stage = s.get("lake_stage", -1)
	if _lake:
		if _lake_stage == 2:
			_lake.treasure.light_up()
		elif _lake_stage >= 3:
			_lake.treasure.queue_free()
	if _home_step >= HOME_STEPS.size() and _lake_stage < 0:
		get_tree().create_timer(25.0).timeout.connect(_start_lake)
	_isle_stage = s.get("isle_stage", -1)
	if _isle and _isle_stage == 1:
		_isle.page.light_up()
	if _lake_stage >= 3 and _isle_stage < 0:
		get_tree().create_timer(30.0).timeout.connect(_start_isle)
	_hill_stage = s.get("hill_stage", -1)
	if _hill:
		if _hill_stage == 2:
			_hill.page.light_up()
		elif _hill_stage >= 3:
			_hill.page.queue_free()
			_show_far_light()
	if _isle_stage >= 2 and _hill_stage < 0:
		get_tree().create_timer(40.0).timeout.connect(_start_hill)
	_food_at_start = s.food_at_start
	_cooking_hinted = s.cooking_hinted
	var right := Basis(Vector3.UP, player._yaw) * Vector3.RIGHT
	_fox = Companion.create(self, Critter.fox(), "fox", player.global_position + right * 1.6, hud)
	_otter = Companion.create(self, Critter.otter(), "otter", player.global_position - right * 1.4, hud)
	for pair in [[_fox, s.fox], [_otter, s.otter]]:
		var c: Companion = pair[0]
		if c._zzz:
			c._zzz.queue_free()
		c.body.rotation.z = 0.0
		c._tips_given = pair[1][0]
		c._feelings = pair[1][1]
		c.follow()
	hud.fade_in(Color.BLACK, 2.0)
	Game.notify("Welcome back.", Color(1.0, 0.9, 0.7))
	var later := func(t: float, f: Callable): get_tree().create_timer(t).timeout.connect(f)
	if not _fire_built:
		if Game.quest("fire").is_empty():
			later.call(4.0, _fire_hint)
		else:
			_update_fire_goal()
			Game.inventory_changed.connect(_update_fire_goal)
	elif not _settled and Game.quest("settle").is_empty():
		Game.start_quest("settle", "Settle In for the Night", ["Gather some food  0/3", "Ask the Otter how to stay safe (walk up, press E)", "Build a lean-to (Tab → Know-how)"], true, "Fox")
		_food_at_start = Game.food_found
	elif _settled and not _night_passed and Game.quest("night").is_empty():
		Game.start_quest("night", "The Long Night", ["Sit by the fire with the Fox and the Otter (E at the fire)"], true, "Fox")
		Game.rest_ready = true
	if _night_passed and not Game.known.has("map"):
		later.call(15.0, _suggest_map)
	elif Game.known.has("map") and not Game.has_map() and Game.quest("map").is_empty():
		_start_map_quest()
	if _night_passed:
		if not _sanctum_found and Game.quest("hum").is_empty() and Game.quest("sanctum").is_empty():
			later.call(5.0, func(): Game.start_quest("hum", "The Humming Marble", ["Follow the hum (it chimes when you face the right way)"], true, "Fox"))
		if not Game.sparks_open:
			later.call(30.0, Game.open_sparks)


## The pets come up with the first plan: the Otter is cold, the Fox spots
## an old fire ring to learn from. Their idea becomes the first quest.
func _fire_hint() -> void:
	_otter.say(["Brrr... I'm SO cold. Can we make a fire? Pleeease?"])
	get_tree().create_timer(3.6).timeout.connect(func():
		_fox.say(["Somebody camped here before us. See that old fire ring?", "Over here. Come look. Maybe you'll learn something. For once."])
		if is_instance_valid(_fire_ring):
			_fox.show_spot(_fire_ring.global_position)
		Game.start_quest("fire", "A Fire in the Dark", ["Look at the old fire ring", "Gather sticks", "Gather stones", "Build a campfire (Tab → Know-how)"], true, "Otter")
		_update_fire_goal()
		Game.inventory_changed.connect(_update_fire_goal))


## Figuring something out: the hero thinks it through, and for the fire the
## Fox chimes in with where to find the makings.
func _on_learned(id: String, thought: Array) -> void:
	if not thought.is_empty():
		_hud.think(thought, 3.4)
	if id == "campfire":
		_update_fire_goal()
		get_tree().create_timer(7.5).timeout.connect(func():
			_fox.say(["Pale sticks, round rocks. They're all over. Grab 'em with E."]))


func _update_fire_goal() -> void:
	if _fire_built:
		return
	var sticks: int = Game.inventory.get("Sticks", 0)
	var stones: int = Game.inventory.get("Stones", 0)
	Game.set_step("fire", 0, "Look at the old fire ring", Game.known.has("campfire"))
	Game.set_step("fire", 1, "Gather sticks  %d/5" % mini(sticks, 5), sticks >= 5)
	Game.set_step("fire", 2, "Gather stones  %d/3" % mini(stones, 3), stones >= 3)


func _on_fire_built() -> void:
	_fire_built = true
	Game.complete_quest("fire")
	_otter.say(["A fire! Ooh, it's so warm. You did it!"])
	get_tree().create_timer(3.2).timeout.connect(func():
		_fox.say(["Look at you. Making fire. Very caveman. I'm proud."]))
	# They just woke up, so nobody wants to sleep yet: settle in instead.
	get_tree().create_timer(8.0).timeout.connect(func():
		_fox.say(["Okay. Fire: check. Food: NOT check. I'll go sniff around.", "And you. Ask the little genius how we don't get eaten tonight."])
		Game.start_quest("settle", "Settle In for the Night", ["Gather some food  0/3", "Ask the Otter how to stay safe (walk up, press E)", "Build a lean-to (Tab → Know-how)"], true, "Fox")
		_food_at_start = Game.food_found
		get_tree().create_timer(7.0).timeout.connect(func(): _fox.request_food()))


## Food, the Otter's idea, and a roof. When all three are done, the marble's
## hum takes over.
func _update_settle() -> void:
	if Game.quest("settle").is_empty():
		return
	var food := mini(Game.food_found - _food_at_start, 3)
	Game.set_step("settle", 0, "Gather some food  %d/3" % food, food >= 3)
	Game.set_step("settle", 1, "Ask the Otter how to stay safe (walk up, press E)", Game.known.has("lean_to"))
	var built := not get_tree().get_nodes_in_group("shelters").is_empty()
	Game.set_step("settle", 2, "Build a lean-to (Tab → Know-how)", built)
	if food >= 3 and built:
		Game.complete_quest("settle")
		_settled = true
		_otter.say(["Ta-da! Our first house!", "...Okay, it's a house for ants. But it's OURS."])
		# Nobody's sleepy (they just woke up), so they sit up by the fire instead.
		get_tree().create_timer(8.0).timeout.connect(func():
			_otter.say(["I'm not sleepy. Like, at ALL."])
			get_tree().create_timer(3.4).timeout.connect(func():
				_fox.say(["Same. Let's just sit by the fire for a while.", "Watch the stars. Be lazy. My favorite."])
				Game.start_quest("night", "The Long Night", ["Sit by the fire with the Fox and the Otter (E at the fire)"], true, "Fox")
				Game.rest_ready = true))


## The Fox notices you're about to eat something raw with a fire right there.
func _update_cooking_hint() -> void:
	if _cooking_hinted or not _fire_built or Game.known.has("cooking"):
		return
	for raw in Game.COOKS:
		if Game.has_items(raw):
			_cooking_hinted = true
			get_tree().create_timer(2.5).timeout.connect(func():
				_fox.say(["Wait. You're gonna eat that RAW?", "We have a FIRE. Hold it over the fire. Walk up and press E.", "Honestly. What would you do without me."])
				get_tree().create_timer(9.0).timeout.connect(func():
					Game.learn("cooking", ["Cook it first. Of course.", "That fox is smarter than he lets on."], "Fox")))
			return


## Found something the Otter can turn into an idea: the hero thinks it over,
## then the Otter wants to see.
func _on_sparked(_id: String, thought: Array) -> void:
	_hud.think(thought, 3.2)
	get_tree().create_timer(6.8).timeout.connect(func():
		_otter.say(["Ooh! What's that? Show me, show me!", "(Walk up to me and press E.)"]))


## Sitting by the fire with the boys until morning: they get comfy, talk a
## little, the screen fades, and the sky's pink when it comes back.
func _pass_the_night() -> void:
	if _night_passed:
		return
	var fire: Node3D = null
	for f in get_tree().get_nodes_in_group("campfires"):
		if fire == null or (f as Node3D).global_position.distance_to(Game.player.global_position) < fire.global_position.distance_to(Game.player.global_position):
			fire = f
	if fire == null:
		return
	_night_passed = true
	Game.rest_ready = false
	var p := Game.player
	var center := fire.global_position
	var away := p.global_position - center
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3.BACK
	p.seated = false  # the night passes before anyone gets up
	var seat := center + away * 1.8
	p.global_position = Vector3(seat.x, Game.ground_at(seat.x, seat.z), seat.z)
	p.sit_facing(center)
	_fox.rest_at(center + away.rotated(Vector3.UP, 1.4) * 1.5, center)
	_otter.rest_at(center + away.rotated(Vector3.UP, -1.4) * 1.4, center)
	var talk := [
		[_otter, "Do you think the stars can see us?"],
		[_fox, "Only the nosy ones."],
		[_otter, "...I'm glad we're all together."],
		[_fox, "Yeah. Me too.", "Don't make it weird."],
	]
	var t := 1.0
	for line in talk:
		var who: Companion = line[0]
		var words: Array = line.slice(1)
		get_tree().create_timer(t).timeout.connect(func(): who.say(words))
		t += 3.6 * words.size()
	get_tree().create_timer(t).timeout.connect(func():
		_hud.think(["Me too. Both of you."], 3.4))
	get_tree().create_timer(t + 4.0).timeout.connect(func():
		_hud.fade_through(Color.BLACK, 3.0, 2.5, 3.5, func():
			_make_dawn()
			Game.warmth = 100.0
			Game.hunger = maxf(30.0, Game.hunger - 20.0)
			Game.thirst = maxf(30.0, Game.thirst - 20.0)
			Game.notify("The night passes by the fire.", Color(1.0, 0.85, 0.7)))
		get_tree().create_timer(10.0).timeout.connect(_morning))


## Out of air: he floats up limp, the Otter shoots out to him with the Fox
## paddling after, they tow him in by the arms, the screen fades as one of
## them scolds him, and he comes to on the bank with them fussing over him.
func _on_passed_out() -> void:
	var p := Game.player
	var shore := _nearest_shore(p.global_position)
	var pull := shore - p.global_position
	pull.y = 0.0
	pull = pull.normalized() if pull.length() > 0.1 else Vector3.FORWARD
	var side := pull.cross(Vector3.UP)
	var pets := [_otter, _fox].filter(func(c): return c != null)
	var later := func(t: float, f: Callable): get_tree().create_timer(t).timeout.connect(f)
	if _otter:
		later.call(0.8, func():
			_otter.say(["Uh oh. He's not swimming. He's NOT swimming!"])
			_otter.rescue(-side * 0.75 + pull * 0.45, pull))
	if _fox:
		later.call(2.2, func():
			_fox.say(["Hang on! I got this arm! You get that one!"])
			_fox.rescue(side * 0.8 + pull * 0.45, pull))
	later.call(4.5, func(): p.tow = pull * 1.6)
	later.call(6.5, func():
		if _otter:
			_otter.say(["You can't hold your breath THAT long, silly! You're not an otter!"])
		_hud.fade_through(Color.BLACK, 3.5, 2.0, 3.0, func():
			# Up on the bank: him lying there, the two of them dripping beside him.
			var spot := shore + pull * 1.2
			spot.y = Game.ground_at(spot.x, spot.z) + 0.05
			p.wake_on_shore(spot, atan2(-pull.x, -pull.z))
			p.health = maxf(25.0, p.health - 10.0)
			Game.warmth = maxf(0.0, Game.warmth - 20.0)
			var head := spot - pull * 0.2
			if _otter:
				_otter.rest_at(head - side * 0.9 + pull * 0.9, head)
			if _fox:
				_fox.rest_at(head + side * 1.0 + pull * 0.9, head)
			for c in pets:
				c.wet = 1.0
				c.in_water = false
				c.body.swimming = false))
	# The screen comes back (6.5 + 3.5 + 2.0 + 3.0 s): he blinks, gets up, they fuss.
	later.call(15.0, func():
		p.begin_wake(atan2(-pull.x, -pull.z))
		if _otter:
			_otter.say(["You're awake! You're AWAKE! You scared me SO bad!"]))
	later.call(18.6, func():
		if _fox:
			_fox.say(["Rule two of the wild: keep breathing.", "Air goes in. Air goes out. It's a whole thing."]))
	later.call(19.5, func():
		for c in pets:
			c.shake(false))
	later.call(25.8, func():
		_hud.think(["Note to self... I am not a fish."], 3.0)
		for c in pets:
			c.follow())
	later.call(29.0, func():
		Game.notify("Watch your air when you dive. Come up for a breath with Space.", Color(0.6, 0.85, 1.0)))


## The closest dry ground to `from`, searching outward in rings.
func _nearest_shore(from: Vector3) -> Vector3:
	for r in range(2, 80, 2):
		var best := Vector3.INF
		for k in 24:
			var a := TAU * k / 24.0
			var q := from + Vector3(cos(a), 0.0, sin(a)) * r
			if Game.ground_at(q.x, q.z) > Game.WATER_LEVEL + 0.15:
				best = q
				break
		if best != Vector3.INF:
			return Vector3(best.x, Game.ground_at(best.x, best.z), best.z)
	return Game.player.spawn_point


func _morning() -> void:
	Game.complete_quest("night")
	_otter.say(["Look! The sky's all pink!"])
	get_tree().create_timer(3.4).timeout.connect(func():
		_fox.say(["Morning already? I wasn't asleep.", "I was resting my eyes. Loudly."]))
	get_tree().create_timer(5.0).timeout.connect(func():
		Game.player.stand_up()
		_fox.follow()
		_otter.follow())
	get_tree().create_timer(12.0).timeout.connect(func():
		_fox.say(["Hey. That marble of yours won't stop humming.", "It gets louder when you face a certain way. Just saying."])
		Game.start_quest("hum", "The Humming Marble", ["Follow the hum (it chimes when you face the right way)"], true, "Fox"))
	get_tree().create_timer(40.0).timeout.connect(Game.open_sparks)
	get_tree().create_timer(26.0).timeout.connect(_suggest_map)
	get_tree().create_timer(14.0).timeout.connect(_autosave)


## After the fire, the marble chimes when you face the Sanctum, louder as you
## get close; reaching the Sanctum completes the quest.
func _update_story(delta: float) -> void:
	var p := Game.player
	if not Game.story_start or p == null or p.frozen:
		return
	if not _fire_built and not get_tree().get_nodes_in_group("campfires").is_empty():
		_on_fire_built()
	_update_settle()
	_update_cooking_hint()
	_update_map_goal()
	_update_lake(delta)
	_update_isle()
	_update_hill(delta)
	var dist :=Vector2(p.global_position.x, p.global_position.z).length()
	if not _sanctum_found:
		if dist < 22.0 and not Game.quest("hum").is_empty():
			_sanctum_found = true
			Game.notify("The Sanctum... somehow, you've been here before.", Color(0.6, 0.95, 1.0))
			Game.complete_quest("hum")
			Game.start_quest("sanctum", "The Sanctum", ["See what rests on the old stone"])
			return
		_hum_timer -= delta
		if _hum_timer <= 0.0 and not Game.quest("hum").is_empty():
			_hum_timer = 2.4
			var look := -p.camera.global_transform.basis.z
			var to := (Vector3.ZERO - p.global_position)
			look.y = 0.0
			to.y = 0.0
			if look.normalized().dot(to.normalized()) > 0.9:
				Audio.play("ui_notify", null, lerpf(-4.0, -14.0, clampf(dist / 120.0, 0.0, 1.0)), 1.9)
	elif p.weapon and not Game.quest("sanctum").is_empty():
		Game.complete_quest("sanctum")
		Game.start_quest("family", "Finding Home", ["Touch the heartstone (E at the altar)", "Find out what happened to your family"])
		get_tree().create_timer(6.0).timeout.connect(func():
			if _heartstone_ready() and _otter:
				_otter.say(["That little stone on the altar keeps glowing at you.", "Like it wants to say hi. Go on, touch it!"]))


# --- Memory Echoes -------------------------------------------------------------
# The heartstone gives back one memory of the dream: a short scene, then a
# skill remembered. Later ones will wait at other old stones.

var _echo_playing := false


func _heartstone_ready() -> bool:
	var p := Game.player
	return not _echo_playing and not _echoes.has("aim") and p != null and p.weapon != null \
		and not Game.quest("family").is_empty()


## The lake's heartstone, once you've followed the hum there.
func _lake_stone_ready() -> bool:
	return not _echo_playing and _lake_stage == 1 and not _echoes.has("dive")


func _update_heartstone() -> void:
	_set_usable(_crystal, _heartstone_ready())
	if _lake:
		_set_usable(_lake.heartstone, _lake_stone_ready())
	if _hill:
		_set_usable(_hill.heartstone, _hill_stone_ready())


func _set_usable(node: Node, ready: bool) -> void:
	if ready != node.is_in_group("usables"):
		if ready:
			node.add_to_group("usables")
		else:
			node.remove_from_group("usables")


func _on_lake_stone_touched() -> void:
	if _lake_stone_ready():
		play_echo("dive")


func _on_heartstone_touched() -> void:
	if not _heartstone_ready():
		return
	play_echo("aim")


func play_echo(which: String) -> void:
	_echo_playing = true
	var p := Game.player
	p.frozen = true
	Audio.play("level_up", null, -10.0, 0.7)
	var stone: Node3D = _crystal
	if which == "dive":
		stone = _lake.heartstone
	elif which == "run":
		stone = _hill.heartstone
	var flare := create_tween()
	flare.tween_property(stone.get_child(1), "omni_range", 16.0, 1.4)
	flare.tween_property(stone.get_child(1), "omni_range", 7.0, 2.0).set_delay(16.0)
	create_tween().tween_property(Audio, "dim", 0.0, 1.5)
	MemoryEcho.play(self, which).finished.connect(_after_echo.bind(which))


func _after_echo(_skipped: bool, which: String) -> void:
	_echo_playing = false
	_echoes.append(which)
	Game.player.frozen = false
	create_tween().tween_property(Audio, "dim", 1.0, 3.0)
	match which:
		"aim":
			Game.skills["Aim"] = Game.skills.get("Aim", 0.0)
			Game.notify("A memory comes back to you: Aim", Color(1.0, 0.9, 0.6))
			get_tree().create_timer(2.5).timeout.connect(func():
				Game.notify("Your dream tools fly truer the more you use them.", Color(0.85, 0.85, 0.75)))
			var q := Game.quest("family")
			for i in q.get("steps", []).size():
				if (q.steps[i].text as String).begins_with("Touch the heartstone"):
					Game.set_step("family", i, "Touch the heartstone", true)
			if _otter and _fox:
				get_tree().create_timer(3.5).timeout.connect(func():
					_otter.say(["You went all quiet and glowy for a second.", "Are you okay? You were smiling."]))
				get_tree().create_timer(10.0).timeout.connect(func():
					_fox.say(["\"Steady hands. Breathe out. Let go.\"", "...Huh. Why do I know that one?"]))
				get_tree().create_timer(22.0).timeout.connect(func():
					_fox.say(["See those sleepy little lights on top of the stones?", "Bet you can't wake all eight with that thing. Go on. Prove me wrong."])
					_start_wake_quest())
		"dive":
			Game.skills["Diving"] = Game.skills.get("Diving", 0.0)
			Game.notify("A memory comes back to you: Diving", Color(1.0, 0.9, 0.6))
			get_tree().create_timer(2.5).timeout.connect(func():
				Game.notify("You can hold your breath much longer now, and dive faster (C).", Color(0.85, 0.85, 0.75)))
			_finish_family_step("Touch the heartstone by the lake", "Touch the heartstone by the lake")
			if _otter and _fox:
				get_tree().create_timer(3.5).timeout.connect(func():
					_otter.say(["You did the glowy thing again!", "You were laughing this time. That was a good one, huh?"]))
				get_tree().create_timer(10.0).timeout.connect(func():
					_fox.say(["\"Big breath... hold it...\"", "\"...and come back up smiling.\" Okay. I DEFINITELY know that one."]))
				get_tree().create_timer(20.0).timeout.connect(_lake_dare)
		"run":
			_after_run_echo()
	get_tree().create_timer(12.0).timeout.connect(_autosave)


# --- The lake ------------------------------------------------------------------
# Once the Sanctum is home, the marble hums again, toward the water. Old stones
# at the lake's edge hold a second heartstone (the rainy-day echo: Diving),
# and then the Otter dares you to bring back what's glowing on the bottom.

var _lake: LakeRuin
## -1 not yet, 0 following the hum, 1 at the lake, 2 the dare, 3 found it.
var _lake_stage := -1
var _lake_hum := 2.0


func _build_lake_ruin() -> void:
	var spot := LakeRuin.find_spot(Game.wake_point if Game.story_start else Vector3(INF, 0, INF))
	if spot.is_empty():
		push_warning("No shore found for the lake ruin")
		return
	_lake = LakeRuin.build(self, spot, _stone_mats)
	_lake.heartstone.touched.connect(_on_lake_stone_touched)
	_lake.treasure_taken.connect(_on_lake_treasure)


func _start_lake() -> void:
	if _lake_stage >= 0 or _otter == null or _lake == null:
		return
	_lake_stage = 0
	Audio.play("ui_notify", null, -6.0, 1.9)
	_otter.say(["Hey! Your marble's humming again!", "It sounds kind of... splashy? I think it wants us to go to the water!"])
	get_tree().create_timer(7.0).timeout.connect(func():
		_fox.say(["Translation: he wants to go swimming.", "He ALWAYS wants to go swimming."]))
	_add_family_step("Follow the marble's hum to the water (it chimes when you face the right way)")


## A new step on the main quest, just before the last open one ("find out
## what happened to your family" stays at the bottom).
func _add_family_step(text: String) -> void:
	var q := Game.quest("family")
	if q.is_empty():
		Game.start_quest("family", "Finding Home", [text, "Find out what happened to your family"])
		return
	var at: int = q.steps.size()
	if at > 0 and (q.steps[-1].text as String).begins_with("Find out what happened"):
		at -= 1
	q.steps.insert(at, {"text": text, "done": false})
	Game.quests_changed.emit()


func _finish_family_step(starts: String, text: String) -> void:
	var q := Game.quest("family")
	for i in q.get("steps", []).size():
		if (q.steps[i].text as String).begins_with(starts):
			Game.set_step("family", i, text, true)


func _update_lake(delta: float) -> void:
	if _lake == null or _lake_stage != 0:
		return
	var p := Game.player
	var to := _lake.heartstone.global_position - p.global_position
	to.y = 0.0
	if to.length() < 12.0:
		_lake_stage = 1
		Game.notify("Old stones at the water's edge... and another heartstone.", Color(0.6, 0.85, 1.0))
		_finish_family_step("Follow the marble's hum", "Follow the hum to the lake")
		_add_family_step("Touch the heartstone by the lake (E)")
		if _otter:
			_otter.say(["ANOTHER glowy stone! And it's right next to WATER!", "Best. Day. Ever."])
		return
	_lake_hum -= delta
	if _lake_hum <= 0.0:
		_lake_hum = 2.4
		var look := -p.camera.global_transform.basis.z
		look.y = 0.0
		if look.normalized().dot(to.normalized()) > 0.9:
			Audio.play("ui_notify", null, lerpf(-4.0, -14.0, clampf(to.length() / 120.0, 0.0, 1.0)), 1.9)


## After the echo: the stone on the lake bed lights up, and the Otter dares you.
func _lake_dare() -> void:
	if _lake_stage >= 2 or _lake == null:
		return
	_lake_stage = 2
	_lake.treasure.light_up()
	if _otter and _fox:
		_otter.say(["Look! Something's glowing at the bottom, out past the stones!", "I dare you to dive down and get it. Big breath!"])
		get_tree().create_timer(7.0).timeout.connect(func():
			_fox.say(["I'll wait up here. Staying dry.", "Like a genius."]))
	Game.start_quest("lakebed", "The Bottom of the Lake", ["Dive for what's glowing (C to dive)"], false, "Otter")


func _on_lake_treasure() -> void:
	_lake_stage = 3
	Game.complete_quest("lakebed")
	Game.ideas.erase("The Bottom of the Lake")
	Game.backpack.append("River stone (a little house scratched on it)")
	Game.practice("Diving", 4.0)
	_add_family_step("A clue: a river stone with a little house scratched on it")
	_finish_family_step("A clue:", "A clue: a river stone with a little house scratched on it")
	_hud.think([
		"A river stone, worn smooth...",
		"Someone scratched a little house into it. A door, and a round window.",
		"...Like the house in my dream.",
	], 3.6)
	if _otter and _fox:
		get_tree().create_timer(12.0).timeout.connect(func():
			_fox.say(["Someone was here before us.", "Someone who missed home too."]))
		get_tree().create_timer(19.0).timeout.connect(func():
			_otter.say(["We're keeping it. It's going right on the hearth.", "...Can I hold it first?"]))
	get_tree().create_timer(14.0).timeout.connect(_autosave)
	get_tree().create_timer(45.0).timeout.connect(_start_isle)


# --- The little house on the water ---------------------------------------------
# The stone's little house, with its round window, is out on a tiny island in
# the lake. The Otter wants to build a raft to get there (the Fox is NOT
# swimming); inside, a page from someone else's dream journal.

var _isle: IsleHouse
## -1 not yet, 0 building the raft and getting there, 1 at the house, 2 read the page.
var _isle_stage := -1
const DRIFTWOOD_NEEDED := 4


func _build_isle() -> void:
	if _lake == null:
		return
	var spot := IsleHouse.find_spot(_lake.global_position)
	if spot.is_empty():
		push_warning("No island found for the little house")
		return
	_isle = IsleHouse.build(self, spot, _stone_mats)
	_isle.page_read.connect(_on_page_read)
	_spawn_driftwood()
	Game.inventory_changed.connect(_update_driftwood_step)


## Bleached logs washed up along the shore near the old stones.
func _spawn_driftwood() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6262
	var placed: Array[Vector3] = []
	var from := _lake.global_position
	for tries in 600:
		if placed.size() >= 8:
			break
		var a := rng.randf() * TAU
		var r := rng.randf_range(5.0, 42.0)
		var p := from + Vector3(cos(a), 0, sin(a)) * r
		p.y = Game.ground_at(p.x, p.z)
		if p.y < WATER_LEVEL - 0.05 or p.y > WATER_LEVEL + 0.6 or Vector2(p.x - Game.ISLE.x, p.z - Game.ISLE.y).length() < 12.0:
			continue
		if placed.any(func(q): return q.distance_to(p) < 4.0):
			continue
		placed.append(p)
		Gatherable.spawn(self, p, "driftwood", rng)


func _driftwood_step() -> String:
	return "Gather driftwood along the shore  %d/%d" % [mini(Game.inventory.get("Driftwood", 0), DRIFTWOOD_NEEDED), DRIFTWOOD_NEEDED]


func _update_driftwood_step() -> void:
	var q := Game.quest("isle")
	if q.is_empty() or q.steps[0].done:
		return
	Game.set_step("isle", 0, _driftwood_step(), Game.has_items("Driftwood", DRIFTWOOD_NEEDED))


func _start_isle() -> void:
	if _isle_stage >= 0 or _isle == null or _otter == null:
		return
	_isle_stage = 0
	_otter.say(["I keep looking at the little house on the stone...", "Wait. LOOK! Out on the water! There's a little house! With a ROUND window!"])
	get_tree().create_timer(7.5).timeout.connect(func():
		_fox.say(["Great. It's on an island.", "Which means swimming. Which means no."]))
	get_tree().create_timer(14.0).timeout.connect(func():
		_otter.say(["We could build a RAFT! Driftwood floats, and there's lots along the shore.", "Tie it up with vines, push it out... and the Fox stays dry!"])
		Game.learn("raft", [], "Otter")
		Game.start_quest("isle", "The House on the Water", [_driftwood_step(), "Build a raft on the water (Tab → Know-how)",
			"Paddle out to the little house (E on the raft)"], false, "Otter")
		_update_driftwood_step())


func _on_raft_built() -> void:
	var q := Game.quest("isle")
	if q.is_empty():
		return
	Game.set_step("isle", 0, "Gather driftwood along the shore", true)
	Game.set_step("isle", 1, "Build a raft on the water", true)
	if _fox and _otter:
		get_tree().create_timer(1.5).timeout.connect(func():
			_otter.say(["It floats! It FLOATS!", "Everybody on! Captain Otter says GO!"]))
		get_tree().create_timer(7.0).timeout.connect(func():
			_fox.say(["I call the front.", "Somebody has to be the lookout. And stay dry."]))


func _update_isle() -> void:
	if _isle == null or _isle_stage != 0 or not Game.known.has("raft"):
		return
	var p := Game.player
	var to := _isle.global_position - p.global_position
	if Vector2(to.x, to.z).length() > 5.5 or p.raft or p.global_position.y < _isle.floor_y - 0.4:
		return
	_isle_stage = 1
	var q := Game.quest("isle")
	if not q.is_empty():
		for i in q.steps.size():
			if not q.steps[i].done:
				Game.set_step("isle", i, (q.steps[i].text as String).get_slice(" (", 0).get_slice("  ", 0), true)
		q.steps.append({"text": "Look inside the little house", "done": false})
		Game.quests_changed.emit()
	_isle.page.light_up()
	Game.notify("Someone lived here once.", Color(0.9, 0.85, 0.7))
	if _fox and _otter:
		_otter.say(["It's a REAL house! With a round window, just like on the stone!", "Hello? ...Anybody home?"])
		get_tree().create_timer(6.0).timeout.connect(func():
			_fox.say(["Nobody's home.", "There's something on the table, though. Glowing. Naturally."]))


func _on_page_read() -> void:
	_isle_stage = 2
	Game.complete_quest("isle")
	Game.ideas.erase("The House on the Water")
	Game.backpack.append("A journal page (someone else's)")
	Game.practice("Survival", 3.0)
	_add_family_step("A clue: a page from someone else's dream journal")
	_finish_family_step("A clue: a page", "A clue: a page from someone else's dream journal")
	_hud.think([
		"A page from a dream journal... but not mine. It says:",
		"I woke up under a big tree, and everyone was gone.",
		"All I had was a little marble that hums. I followed it here.",
		"I built this house so I'd have somewhere to come back to.",
		"If you're reading this, you're not the first. And you're not alone.",
		"Keep following the hum. It knows the way home.",
		"...Someone else. Someone just like me.",
	], 4.2)
	if _otter and _fox:
		get_tree().create_timer(31.0).timeout.connect(func():
			_otter.say(["Somebody else had a marble too?", "Do you think they found their way home?"]))
		get_tree().create_timer(38.0).timeout.connect(func():
			_fox.say(["Only one way to find out.", "...We follow the hum. Obviously."]))
		get_tree().create_timer(46.0).timeout.connect(func():
			_otter.say(["And the bed in here is still comfy!", "We could stay over sometimes. A home away from home!"]))
	get_tree().create_timer(30.0).timeout.connect(_autosave)
	get_tree().create_timer(70.0).timeout.connect(_start_hill)


# --- The lookout on the hill ---------------------------------------------------
# After the page, the marble hums once more, uphill this time: the other
# dreamer's lookout, with a third heartstone (the beach-run echo: Running) and
# another page, which points out a thin light far off in the mountains.

var _hill: HillLookout
## -1 not yet, 0 following the hum, 1 at the lookout, 2 remembered (page lit), 3 read it.
var _hill_stage := -1
var _hill_hum := 2.0
var _far_light: Node3D


func _build_hill() -> void:
	var avoid: Array = [Vector3.ZERO]
	if Game.story_start:
		avoid.append(Game.wake_point)
	if _lake:
		avoid.append(_lake.global_position)
	var at := HillLookout.find_spot(avoid)
	if at == Vector3.INF:
		push_warning("No hilltop found for the lookout")
		return
	_hill = HillLookout.build(self, at, _stone_mats)
	_hill.heartstone.touched.connect(_on_hill_stone_touched)
	_hill.page.read.connect(_on_hill_page_read)


func _start_hill() -> void:
	if _hill_stage >= 0 or _hill == null or _otter == null:
		return
	_hill_stage = 0
	Audio.play("ui_notify", null, -6.0, 1.9)
	_fox.say(["Your marble's at it again.", "...It's pointing UPHILL. Of course it is."])
	get_tree().create_timer(7.0).timeout.connect(func():
		_otter.say(["Maybe the person who wrote the page went up there!", "Come on, come on! Before it stops humming!"]))
	_add_family_step("Follow the hum again (it chimes when you face the right way)")


func _update_hill(delta: float) -> void:
	if _hill == null or _hill_stage != 0:
		return
	var p := Game.player
	var to := _hill.heartstone.global_position - p.global_position
	to.y = 0.0
	if to.length() < 12.0:
		_hill_stage = 1
		Game.notify("A lookout on the hilltop... and another heartstone.", Color(1.0, 0.85, 0.6))
		_finish_family_step("Follow the hum again", "Follow the hum up the hill")
		_add_family_step("Touch the heartstone at the lookout (E)")
		if _otter and _fox:
			_otter.say(["Somebody had a campfire up here!", "And look, ANOTHER glowy stone!"])
			get_tree().create_timer(6.0).timeout.connect(func():
				_fox.say(["Nice view.", "Whoever it was, they liked a good view."]))
		return
	_hill_hum -= delta
	if _hill_hum <= 0.0:
		_hill_hum = 2.4
		var look := -p.camera.global_transform.basis.z
		look.y = 0.0
		if look.normalized().dot(to.normalized()) > 0.9:
			Audio.play("ui_notify", null, lerpf(-4.0, -14.0, clampf(to.length() / 120.0, 0.0, 1.0)), 1.9)


func _hill_stone_ready() -> bool:
	return not _echo_playing and _hill_stage == 1 and not _echoes.has("run")


func _on_hill_stone_touched() -> void:
	if _hill_stone_ready():
		play_echo("run")


func _after_run_echo() -> void:
	Game.skills["Running"] = Game.skills.get("Running", 0.0)
	Game.notify("A memory comes back to you: Running", Color(1.0, 0.9, 0.6))
	get_tree().create_timer(2.5).timeout.connect(func():
		Game.notify("The more you run (Shift), the faster you get.", Color(0.85, 0.85, 0.75)))
	_finish_family_step("Touch the heartstone at the lookout", "Touch the heartstone at the lookout")
	_hill_stage = 2
	if _otter and _fox:
		get_tree().create_timer(3.5).timeout.connect(func():
			_otter.say(["The glowy thing again! You were RUNNING in your sleep!", "Your legs were going like this!"]))
		get_tree().create_timer(10.0).timeout.connect(func():
			_fox.say(["\"Last one to the ship...\"", "...is a rotten egg. I won. I always won. I'm sure of it."]))
		get_tree().create_timer(18.0).timeout.connect(func():
			if _hill_stage != 2:
				return
			_hill.page.light_up()
			_otter.say(["Hey, there's paper stuck in that pile of rocks!", "It's glowing like the page in the little house!"])
			_add_family_step("Look at the page in the pile of stones"))
	else:
		_hill.page.light_up()


func _on_hill_page_read() -> void:
	_hill_stage = 3
	Game.backpack.append("Another journal page (from the lookout)")
	Game.practice("Survival", 3.0)
	_finish_family_step("Look at the page in the pile", "Read the other dreamer's second page")
	_add_family_step("A clue: a light far off in the mountains")
	_finish_family_step("A clue: a light", "A clue: a light far off in the mountains")
	_hud.think([
		"Another page, in the same handwriting:",
		"From up here you can see it. A thin light, far off in the mountains.",
		"My marble hums loudest when I face it.",
		"I think that's the way home. I'm going to find out.",
		"...A light in the mountains.",
	], 4.2)
	get_tree().create_timer(9.0).timeout.connect(_show_far_light.bind(true))
	if _otter and _fox:
		get_tree().create_timer(22.0).timeout.connect(func():
			_otter.say(["THERE! I see it! Way, way out there!", "Is that where they went?"]))
		get_tree().create_timer(29.0).timeout.connect(func():
			_fox.say(["That's a long walk.", "We're gonna need snacks. Lots of snacks."]))
	get_tree().create_timer(30.0).timeout.connect(_autosave)


func _show_far_light(fade := false) -> void:
	if _far_light or _hill == null:
		return
	_far_light = HillLookout.make_far_light(self, _hill.far_light_at())
	if fade:
		Audio.play("level_up", null, -14.0, 0.6)
		_far_light.scale = Vector3(0.02, 0.02, 0.02)
		create_tween().tween_property(_far_light, "scale", Vector3.ONE, 4.0).set_trans(Tween.TRANS_SINE)


# --- Waking the stones ---------------------------------------------------------
# Each standing stone has a sleepy light on top. Once Aim is remembered, a
# dream tool's shot wakes one into a warm glow, and the Sanctum lights up one
# stone at a time. Before then they just stir.

var _buds: Array[WispBud] = []


func _woken() -> int:
	return _buds.filter(func(b): return b.awake).size()


func _wake_step() -> String:
	return "Wake the sleepy lights on the stones (shoot them)  %d/%d" % [_woken(), _buds.size()]


func _start_wake_quest() -> void:
	if _woken() < _buds.size():
		Game.start_quest("wake", "Wake the Stones", [_wake_step()], false, "Fox")


func _on_bud_shot(bud: WispBud) -> void:
	if bud.awake:
		return
	if not _echoes.has("aim"):
		bud.stir()
		return
	bud.wake(true, 0.8 + 0.07 * _woken())
	Game.practice("Aim", 1.0)
	Game.set_step("wake", 0, _wake_step(), false)
	if _woken() < _buds.size():
		return
	Game.complete_quest("wake")
	Game.practice("Aim", 4.0)
	if _otter and _fox:
		get_tree().create_timer(2.0).timeout.connect(func():
			_otter.say(["Look! The stones are all lit up!", "It feels kind of... cozy here now. Like it could be home."]))
		get_tree().create_timer(9.0).timeout.connect(func():
			_fox.say(["Not bad. You only missed, what, forty times?", "Kidding. ...Mostly."]))
		get_tree().create_timer(18.0).timeout.connect(_start_home)
	get_tree().create_timer(12.0).timeout.connect(_autosave)


# --- Making it home ------------------------------------------------------------
# Once the stones are lit, the Otter wants to make the Sanctum home. One idea
# at a time: a hearth, then a bedroll (and a nap on it), a storage chest and a
# rain cover, each built inside the stone circle. Each one done, the next idea.

const HOME_STEPS := [
	["hearth", "Build a hearth in the Sanctum (Tab → Know-how)", "otter",
		["What if we made this place our HOME? Like, for real?", "First, a proper hearth! Big stones, right here in the circle."]],
	["sleep", "Make a bedroll in the Sanctum and sleep on it", "otter",
		["Ooh, it's so warm! Now we need somewhere to sleep.", "A bedroll! Ferns for squishy, vines to tie it up."]],
	["chest", "Build a storage chest in the Sanctum", "fox",
		["Your pockets are bulging. It's honestly embarrassing.", "Build a chest. Put your sticks in it like a civilized person."]],
	["rain_cover", "Put up a rain cover in the Sanctum", "otter",
		["Last idea, I promise! A roof, for when it rains.", "Four poles and lots of ferns. Over the hearth would be SO cozy."]],
]
const TEACHES := {"hearth": "hearth", "sleep": "bedroll", "chest": "chest", "rain_cover": "rain_cover"}
const SANCTUM_REACH := 13.0  # "in the Sanctum": inside the stone circle, give or take

## Which home step is next (-1 before it starts, HOME_STEPS.size() when done).
var _home_step := -1
var _told_inside := false


func _start_home() -> void:
	if _home_step >= 0 or _otter == null:
		return
	_home_step = 0
	Game.start_quest("home", "Make It Home", [HOME_STEPS[0][1]], false, "Otter")
	_suggest_home(0)


## The pet whose idea it is says it, and the hero learns how.
func _suggest_home(step: int) -> void:
	var s: Array = HOME_STEPS[step]
	var pet: Companion = _otter if s[2] == "otter" else _fox
	pet.say(s[3])
	Game.learn(TEACHES[s[0]], [], "Otter" if s[2] == "otter" else "Fox")


func _on_built(id: String, at: Vector3) -> void:
	if id == "raft":
		_on_raft_built()
		return
	if _home_step < 0 or _home_step >= HOME_STEPS.size() or HOME_STEPS[_home_step][0] != id:
		return
	if Vector2(at.x, at.z).length() > SANCTUM_REACH:
		if not _told_inside and _otter:
			_told_inside = true
			_otter.say(["Ooh, nice! But I meant in the stone circle,", "so everything's together. Home, you know?"])
		return
	var q := Game.quest("home")
	if not q.is_empty():
		Game.set_step("home", q.steps.size() - 1, q.steps[-1].text, true)
	_home_step += 1
	if _home_step < HOME_STEPS.size():
		if not q.is_empty():
			q.steps.append({"text": HOME_STEPS[_home_step][1], "done": false})
			Game.quests_changed.emit()
		get_tree().create_timer(4.0).timeout.connect(_suggest_home.bind(_home_step))
	else:
		Game.complete_quest("home")
		Game.notify("The Sanctum is home now.", Color(1.0, 0.9, 0.6))
		if _otter and _fox:
			get_tree().create_timer(2.5).timeout.connect(func():
				_otter.say(["We did it! It's a real home now!", "Hearth, beds, a chest, a roof... we should get a welcome mat."]))
			get_tree().create_timer(9.0).timeout.connect(func():
				_fox.say(["Not bad. I give it four tails out of five.", "...Okay, five. Don't let it go to your head."]))
		get_tree().create_timer(40.0).timeout.connect(_start_lake)
	get_tree().create_timer(10.0).timeout.connect(_autosave)


func _process(delta: float) -> void:
	if _crystal:
		# The little stone on the altar glows brighter and dimmer, slow as breathing,
		# and brighter still when it has a memory to give back.
		for stone in [_crystal, _lake.heartstone if _lake else null]:
			if stone == null:
				continue
			var waiting: bool = stone.is_in_group("usables")
			var breath := 0.5 + 0.5 * sin(Time.get_ticks_msec() * (0.0024 if waiting else 0.0012))
			(stone.get_child(1) as OmniLight3D).light_energy = lerpf(0.4, 1.0, breath) * (1.8 if waiting else 1.0)
		_update_heartstone()
	_update_underwater_view(delta)
	_update_story(delta)
	_update_explored(delta)
	_camp_check -= delta
	if _camp_check <= 0.0:
		_camp_check = 1.0
		_update_camps()


# --- The map -----------------------------------------------------------------

var _explore_timer := 0.0


## The land as the map draws it, sketched in charcoal and washes: water,
## meadow, forest, rock, with faint height lines. Only the parts he's seen
## ever show.
func _map_image() -> Image:
	var n := 384
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var paper := Color(0.84, 0.76, 0.6)
	for j in n:
		for i in n:
			var x := (i + 0.5) / n * Game.TERRAIN_SIZE - Game.TERRAIN_SIZE * 0.5
			var z := (j + 0.5) / n * Game.TERRAIN_SIZE - Game.TERRAIN_SIZE * 0.5
			var h := Game.height_at(x, z)
			var c := paper.lerp(Color(0.62, 0.68, 0.42), 0.5)  # meadow
			if h < WATER_LEVEL:
				c = Color(0.52, 0.66, 0.72).lerp(Color(0.36, 0.5, 0.62), clampf((WATER_LEVEL - h) / 2.0, 0.0, 1.0))
			elif h < WATER_LEVEL + 0.5:
				c = paper.lerp(Color(0.8, 0.72, 0.52), 0.6)  # shore
			else:
				if Game.story_start:
					c = c.lerp(Color(0.3, 0.42, 0.24), _forest_amount(x, z) * 0.85)
				if h > 14.0:
					c = c.lerp(Color(0.55, 0.5, 0.44), clampf((h - 14.0) / 10.0, 0.0, 1.0))
				if fposmod(h, 3.0) < 0.3:
					c = c.darkened(0.18)  # height lines
			if Vector2(x, z).length() < 16.0:
				c = c.lerp(Color(0.7, 0.68, 0.6), 0.6)  # the Sanctum's stone floor
			img.set_pixel(i, j, c)
	return img


## Marks the ground around him as seen, a couple of times a second.
func _update_explored(delta: float) -> void:
	var p := Game.player
	if not Game.story_start or p == null:
		return
	_explore_timer -= delta
	if _explore_timer <= 0.0:
		_explore_timer = 0.5
		Game.explore_at(p.global_position)


## The morning after the long night, heading out: the Fox worries they'll get
## lost, and the Otter has the idea.
func _suggest_map() -> void:
	if Game.known.has("map") or _fox == null:
		return
	_fox.say(["Heading out into all THAT? We'll be lost in five minutes.", "Four, if you're leading."])
	get_tree().create_timer(7.6).timeout.connect(func():
		_otter.say(["Ooh! Ooh! We make a MAP!", "Charcoal from the fire to draw with. Birch bark to draw on!", "Then we always know where we've been. And how to get home."]))
	get_tree().create_timer(19.0).timeout.connect(func():
		Game.learn("map", ["A map. Charcoal from the fire, bark to draw on.", "Then we never get lost."], "Otter")
		_start_map_quest())


func _start_map_quest() -> void:
	Game.start_quest("map", "Draw a Map", ["Get charcoal from the campfire (E at the fire)", "Peel birch bark  0/2", "Make the map (Tab → Know-how)"], false, "Otter")


func _update_map_goal() -> void:
	if Game.quest("map").is_empty():
		return
	if Game.has_map():
		Game.complete_quest("map")
		return
	var bark: int = Game.inventory.get("Birch bark", 0)
	Game.set_step("map", 0, "Get charcoal from the campfire (E at the fire)", Game.has_items("Charcoal"))
	Game.set_step("map", 1, "Peel birch bark  %d/2" % mini(bark, 2), bark >= 2)


# --- Look & feel -------------------------------------------------------------

func _make_materials() -> void:
	for c in [Color(0.55, 0.52, 0.47), Color(0.47, 0.45, 0.42), Color(0.64, 0.6, 0.52)]:
		_stone_mats.append(MeshKit.mat(c, 0.95))
	for c in [Color(0.24, 0.5, 0.3), Color(0.34, 0.58, 0.26), Color(0.86, 0.5, 0.2), Color(0.2, 0.46, 0.42)]:
		_leaf_mats.append(MeshKit.mat(c, 0.9))
	_leaf_mats.append(MeshKit.glow(Color(0.55, 0.42, 1.0), 0.9))
	_bark = MeshKit.mat(Color(0.33, 0.24, 0.17), 0.95)
	_iron = MeshKit.mat(Color(0.22, 0.22, 0.25), 0.4, 0.8)
	# The old carvings have long since grown over: moss in the grooves, and
	# here and there a crust of golden lichen.
	_rune_mat = MeshKit.mat(Color(0.3, 0.45, 0.2), 0.95)
	_deep_moss_mat = MeshKit.mat(Color(0.22, 0.36, 0.16), 0.95)
	_fire_mat = MeshKit.glow(Color(1.0, 0.5, 0.15), 6.0)


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.42, 0.78)
	sky_mat.sky_horizon_color = Color(0.78, 0.72, 0.66)
	sky_mat.ground_bottom_color = Color(0.2, 0.22, 0.2)
	sky_mat.ground_horizon_color = Color(0.7, 0.66, 0.6)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	env.ssao_intensity = 1.6
	env.ssil_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.76, 0.84)
	env.fog_density = 0.0018
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.2
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0025
	env.volumetric_fog_albedo = Color(0.9, 0.88, 0.85)
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.06
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	_env = env
	_air_fog = [env.fog_light_color, env.fog_density, env.volumetric_fog_albedo, env.volumetric_fog_density, env.adjustment_saturation]

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -40.0, 0.0)
	sun.light_color = Color(1.0, 0.93, 0.82)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	sun.light_volumetric_fog_energy = 1.5
	add_child(sun)
	_sun = sun
	_sky_material = sky_mat
	Game.is_night = Game.story_start
	if Game.story_start:
		_make_night(env, sky_mat, sun)
		_air_fog = [env.fog_light_color, env.fog_density, env.volumetric_fog_albedo, env.volumetric_fog_density, env.adjustment_saturation]


## Moonlit night: deep blue sky, a cool moon light raking through the trees,
## blue mist that catches the moonbeams, a moon and stars overhead.
func _make_night(env: Environment, sky_mat: ProceduralSkyMaterial, moon_light: DirectionalLight3D) -> void:
	sky_mat.sky_top_color = Color(0.015, 0.025, 0.07)
	sky_mat.sky_horizon_color = Color(0.06, 0.08, 0.15)
	sky_mat.ground_horizon_color = Color(0.04, 0.05, 0.08)
	sky_mat.ground_bottom_color = Color(0.01, 0.012, 0.02)
	sky_mat.sun_angle_max = 2.0
	sky_mat.sun_curve = 0.02
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.4, 0.62)
	env.ambient_light_energy = 0.5
	env.fog_light_color = Color(0.07, 0.09, 0.16)
	env.fog_density = 0.008
	env.fog_sky_affect = 0.6
	env.volumetric_fog_density = 0.016
	env.volumetric_fog_albedo = Color(0.55, 0.65, 0.9)
	env.volumetric_fog_emission = Color(0.01, 0.015, 0.03)
	env.adjustment_saturation = 0.85
	env.glow_intensity = 1.0
	env.glow_hdr_threshold = 0.7
	moon_light.rotation_degrees = Vector3(-42.0, 150.0, 0.0)
	moon_light.light_color = Color(0.62, 0.72, 1.0)
	moon_light.light_energy = 0.55
	moon_light.light_volumetric_fog_energy = 3.0
	# The moon sits where the light comes from.
	var toward_moon := moon_light.global_transform.basis.z if moon_light.is_inside_tree() else Basis.from_euler(moon_light.rotation).z
	_moon = MeshKit.part(self, MeshKit.sphere(14.0, -1.0, 24, 12), _sky_mat(Color(0.92, 0.95, 1.0), 6.0), toward_moon * 520.0)
	_moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var stars := MultiMesh.new()
	stars.transform_format = MultiMesh.TRANSFORM_3D
	stars.mesh = MeshKit.sphere(0.9, -1.0, 4, 2)
	stars.mesh.surface_set_material(0, _sky_mat(Color(0.85, 0.9, 1.0), 4.0))
	stars.instance_count = 900
	for i in stars.instance_count:
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.12, 1.0), _rng.randf_range(-1, 1)).normalized()
		var s := _rng.randf_range(0.4, 1.5)
		stars.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * s), dir * 540.0))
	var star_node := MultiMeshInstance3D.new()
	star_node.multimesh = stars
	star_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(star_node)
	_stars = star_node


## Early morning after the first night: a pink-gold sky, low warm sun through
## the trees, soft peach mist. (Swapped in while the screen is black.)
func _make_dawn() -> void:
	Game.is_night = false
	_moon.visible = false
	_stars.visible = false
	_sky_material.sky_top_color = Color(0.36, 0.52, 0.8)
	_sky_material.sky_horizon_color = Color(0.98, 0.7, 0.58)
	_sky_material.ground_horizon_color = Color(0.62, 0.52, 0.46)
	_sky_material.ground_bottom_color = Color(0.16, 0.15, 0.14)
	_sky_material.sun_angle_max = 25.0
	_sky_material.sun_curve = 0.15
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 1.0
	_env.fog_light_color = Color(0.86, 0.7, 0.62)
	_env.fog_density = 0.004
	_env.fog_sky_affect = 0.3
	_env.volumetric_fog_density = 0.01
	_env.volumetric_fog_albedo = Color(1.0, 0.86, 0.76)
	_env.volumetric_fog_emission = Color(0, 0, 0)
	_env.adjustment_saturation = 1.08
	_env.glow_intensity = 0.8
	_env.glow_hdr_threshold = 0.9
	_sun.rotation_degrees = Vector3(-16.0, -70.0, 0.0)
	_sun.light_color = Color(1.0, 0.78, 0.58)
	_sun.light_energy = 1.15
	_sun.light_volumetric_fog_energy = 2.0
	_air_fog = [_env.fog_light_color, _env.fog_density, _env.volumetric_fog_albedo, _env.volumetric_fog_density, _env.adjustment_saturation]


func _sky_mat(color: Color, energy: float) -> StandardMaterial3D:
	var m := MeshKit.glow(color, energy)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_fog = true
	return m


## Below the surface the world turns into thick blue-green murk; the HUD adds the
## wobble and tint on top of this.
func _update_underwater_view(delta: float) -> void:
	_underwater_blend = move_toward(_underwater_blend, 1.0 if Game.underwater else 0.0, delta * 5.0)
	var u := _underwater_blend
	_env.fog_light_color = (_air_fog[0] as Color).lerp(Color(0.04, 0.24, 0.3), u)
	_env.fog_density = lerpf(_air_fog[1], 0.09, u)
	_env.volumetric_fog_albedo = (_air_fog[2] as Color).lerp(Color(0.2, 0.6, 0.65), u)
	_env.volumetric_fog_density = lerpf(_air_fog[3], 0.05, u)
	_env.adjustment_saturation = lerpf(_air_fog[4], 0.8, u)


# --- Terrain -----------------------------------------------------------------

func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells := Game.TERRAIN_CELLS
	var step := Game.TERRAIN_SIZE / cells
	var half := Game.TERRAIN_SIZE * 0.5
	for zi in cells + 1:
		for xi in cells + 1:
			var x := -half + xi * step
			var z := -half + zi * step
			var h := Game.height_at(x, z)
			st.set_color(_terrain_color(x, z, h))
			st.set_uv(Vector2(xi, zi) * 0.25)
			st.add_vertex(Vector3(x, h, z))
	var row := cells + 1
	for zi in cells:
		for xi in cells:
			var i := zi * row + xi
			st.add_index(i)
			st.add_index(i + 1)
			st.add_index(i + row)
			st.add_index(i + 1)
			st.add_index(i + row + 1)
			st.add_index(i + row)
	st.generate_normals()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("noise_large", _noise_texture(301, 0.012, 4, false))
	mat.set_shader_parameter("noise_med", _noise_texture(302, 0.05, 3, false))
	mat.set_shader_parameter("noise_fine", _noise_texture(303, 0.2, 2, false))
	mat.set_shader_parameter("noise_normal", _noise_texture(304, 0.08, 4, true))
	st.set_material(mat)
	var mesh := st.commit()

	var body := StaticBody3D.new()
	body.name = "Terrain"
	add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)


func _noise_texture(noise_seed: int, frequency: float, octaves: int, as_normal: bool) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.as_normal_map = as_normal
	tex.bump_strength = 4.0
	tex.noise = noise
	return tex


func _terrain_color(x: float, z: float, h: float) -> Color:
	var e := 1.0
	var slope := Vector2(Game.height_at(x + e, z) - Game.height_at(x - e, z),
		Game.height_at(x, z + e) - Game.height_at(x, z - e)).length() / (2.0 * e)
	var n := Game.detail_noise.get_noise_2d(x, z) * 0.5 + 0.5
	var grass := Color(0.2, 0.44, 0.13).lerp(Color(0.42, 0.55, 0.15), n)
	var sand := Color(0.74, 0.67, 0.48)
	var c := grass
	if h < -0.5:
		c = sand
	elif h < 0.2:
		c = sand.lerp(grass, (h + 0.5) / 0.7)
	if slope > 0.55:
		c = c.lerp(Color(0.42, 0.4, 0.38), clampf((slope - 0.55) * 3.0, 0.0, 1.0))
	if h > 28.0:
		c = c.lerp(Color(0.92, 0.94, 0.98), clampf((h - 28.0) / 6.0, 0.0, 1.0))
	var d := Vector2(x, z).length()
	if d < 16.0:
		c = c.lerp(Color(0.58, 0.55, 0.49), smoothstep(16.0, 12.0, d))
	if Game.story_start:
		# Forest floor: dark loam and needle litter in uneven patches.

		var soil := Color(0.17, 0.13, 0.09).lerp(Color(0.24, 0.2, 0.12), n)
		c = c.lerp(soil, _forest_amount(x, z) * (0.7 + 0.3 * n))
	return c


func _build_water() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mat.set_shader_parameter("ripple_a", _ripple_texture(11, 0.02))
	mat.set_shader_parameter("ripple_b", _ripple_texture(23, 0.035))
	var plane := PlaneMesh.new()
	plane.size = Vector2(Game.TERRAIN_SIZE, Game.TERRAIN_SIZE)
	plane.subdivide_width = 200
	plane.subdivide_depth = 200
	var mi := MeshKit.part(self, plane, mat, Vector3(0, WATER_LEVEL, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _ripple_texture(noise_seed: int, frequency: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = frequency
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 6.0
	tex.noise = noise
	return tex


## Grass grows in uneven patches (a noise field decides where it's thick, thin
## or bare), as clumps of curved blades with varied height, lean and color that
## sway in the wind. Under the forest it thins out to scattered tufts.
func _build_grass() -> void:
	var patches := FastNoiseLite.new()
	patches.seed = 4242
	patches.frequency = 0.06
	patches.fractal_octaves = 3
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass.gdshader")
	var meshes: Array[ArrayMesh] = [NatureKit.grass_clump(7, 5), NatureKit.grass_clump(5, 9), NatureKit.grass_clump(9, 17)]
	var buckets: Array = [[], [], []]
	for i in 110000:
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * 160.0
		var x := cos(a) * d
		var z := sin(a) * d
		var h := Game.ground_at(x, z)
		if d < 15.0 or h < -0.2 or h > 24.0 or _on_isle(x, z):
			continue
		var density := patches.get_noise_2d(x, z) * 0.5 + 0.5
		var in_forest := 0.0
		if Game.story_start:
			in_forest = _forest_amount(x, z)
		if _rng.randf() > lerpf(0.3 + density * 1.1, 0.12, in_forest):
			continue
		var s := _rng.randf_range(0.55, 1.35) * lerpf(0.7, 1.25, density)
		var squash := Vector3(s * _rng.randf_range(0.8, 1.3), s * _rng.randf_range(0.7, 1.3), s * _rng.randf_range(0.8, 1.3))
		var basis := (Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(-0.15, 0.15))).scaled(squash)
		var n := Game.detail_noise.get_noise_2d(x, z) * 0.5 + 0.5
		var green := Color(0.16, 0.42, 0.1).lerp(Color(0.48, 0.58, 0.16), n * _rng.randf_range(0.5, 1.3))
		if _rng.randf() < 0.08:
			green = green.lerp(Color(0.62, 0.56, 0.28), 0.6)  # dry straw blades here and there
		green = green.lerp(Color(0.12, 0.2, 0.08), in_forest * 0.6)
		var bucket := _rng.randi() % 3
		if not _near_ring(x, z):
			buckets[bucket].append([Transform3D(basis, Vector3(x, h - 0.02, z)), green])
	for k in meshes.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = meshes[k]
		mm.instance_count = buckets[k].size()
		for i in buckets[k].size():
			mm.set_instance_transform(i, buckets[k][i][0])
			mm.set_instance_color(i, buckets[k][i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


# --- Landmarks ---------------------------------------------------------------

func _build_sanctum() -> void:
	var body := StaticBody3D.new()
	body.name = "Sanctum"
	add_child(body)
	# An old stone circle, older than anyone remembers: a worn, mossy floor,
	# standing stones (one long fallen), and a low altar stone in the middle
	# with a small pale stone on it that glows, faintly, like it's breathing.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1771
	var worn := MeshKit.mat(Color(0.56, 0.55, 0.48), 0.95)
	var moss := MeshKit.mat(Color(0.3, 0.44, 0.2), 0.95)
	var deep_moss := MeshKit.mat(Color(0.22, 0.36, 0.16), 0.95)
	_add_cylinder(body, 11.0, 11.5, 0.8, Vector3(0, 0.3, 0), worn, 14)
	_add_cylinder(body, 6.0, 6.3, 0.4, Vector3(0, 0.85, 0), _stone_mats[1], 12)
	# Moss creeping over the floor.
	for k in 14:
		var a := rng.randf() * TAU
		var r := rng.randf_range(3.0, 10.0)
		var s := rng.randf_range(0.8, 2.0)
		var y := 1.07 if r < 6.0 else 0.72
		var patch := MeshKit.part(body, MeshKit.cyl(s, s * 1.1, 0.04, 9), moss if k % 3 else deep_moss, Vector3(cos(a) * r, y, sin(a) * r))
		patch.scale = Vector3(1.0, 1.0, rng.randf_range(0.5, 1.0))
		patch.rotation.y = rng.randf() * TAU
	# The standing stones, rough and leaning a little, each with a mossy cap.
	for i in 9:
		var a := TAU * i / 9.0 + rng.randf_range(-0.08, 0.08)
		var base := Vector3(cos(a) * 8.6, 0.7, sin(a) * 8.6)
		var size := Vector3(rng.randf_range(1.0, 1.4), rng.randf_range(2.4, 4.2), rng.randf_range(0.6, 0.85))
		if i == 6:
			# This one fell long ago and lies in the grass.
			_add_box(body, Vector3(size.x, size.z, size.y), base + Vector3(0, size.z * 0.5 - 0.05, 0), Vector3(0, -a + 0.3, 0.05), _stone_mats[0])
			MeshKit.part(body, MeshKit.box(Vector3(size.x * 0.9, 0.06, size.y * 0.7)), moss, base + Vector3(0, size.z - 0.02, 0), Vector3(0, -a + 0.3, 0.05))
			continue
		# Rough and tapering, wider than deep, leaning a little.
		var lean := Vector3(rng.randf_range(-0.07, 0.07), PI / 2 - a + rng.randf_range(-0.2, 0.2), rng.randf_range(-0.07, 0.07))
		var flat := Vector3(size.x, 1.0, size.z) / 0.9
		var stone := MeshKit.part(body, MeshKit.cyl(0.3, 0.45, size.y, 6), _stone_mats[rng.randi() % 3], base + Vector3(0, size.y * 0.5 - 0.1, 0), lean)
		stone.scale = flat
		var cap := MeshKit.part(body, MeshKit.sphere(0.33, 0.22, 7, 3), moss, base + Vector3(0, size.y - 0.12, 0), lean)
		cap.scale = flat
		# A sleepy light curled up on top, waiting to be woken.
		var bud := WispBud.new()
		bud.position = base + Vector3(0, size.y + 0.1, 0)
		bud.shot.connect(_on_bud_shot)
		add_child(bud)
		_buds.append(bud)
		# Moss climbing up from the ground.
		var foot := MeshKit.part(body, MeshKit.cyl(0.43, 0.47, size.y * 0.22, 6), deep_moss, base + Vector3(0, size.y * 0.11 - 0.1, 0), lean)
		foot.scale = flat
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(size.x * 0.85, size.y, size.z * 0.85)
		shape.shape = box
		shape.position = base + Vector3(0, size.y * 0.5 - 0.1, 0)
		shape.rotation = lean
		body.add_child(shape)
	# The altar stone.
	_add_box(body, Vector3(1.8, 0.6, 1.1), Vector3(0, 1.35, 0), Vector3.ZERO, _stone_mats[0])
	_add_box(body, Vector3(2.1, 0.16, 1.3), Vector3(0, 1.72, 0), Vector3(0, 0.04, 0), _stone_mats[2])
	MeshKit.part(body, MeshKit.box(Vector3(0.9, 0.04, 0.6)), moss, Vector3(-0.5, 1.81, 0.25), Vector3(0, 0.3, 0))

	_crystal = Heartstone.new()
	_crystal.touched.connect(_on_heartstone_touched)
	_crystal.position = Vector3(0, 1.96, -0.38)
	add_child(_crystal)
	MeshKit.part(_crystal, MeshKit.sphere(0.2, 0.3, 7, 4), MeshKit.glow(Color(0.75, 0.95, 0.9), 1.6))
	var light := OmniLight3D.new()
	light.light_color = Color(0.75, 0.95, 0.9)
	light.light_energy = 0.8
	light.omni_range = 7.0
	light.position.y = 0.3
	_crystal.add_child(light)
	Audio.attach_loop(_crystal, "loop_crystal", -10.0, 16.0, 4.0)


## One plain tool waiting on the altar stone, as if left there for him: an
## oak sling. Fancier things come later.
func _place_starter_loot() -> void:
	var sling := WeaponData.generate(1, Game.rng, 0.0, "Hand Cannon", 0)
	sling.element = WeaponData.Element.KINETIC
	sling.perks.clear()
	sling.display_name = "Old Oak Sling"
	LootDrop.spawn(self, sling, Vector3(0, 1.2, 0.1), false)


const FOREST_RADIUS := 125.0
const GLADE_RADIUS := 7.5
const SANCTUM_CLEARING := 36.0  # the forest stops short of the Sanctum
const FOREST_TREES := 1300


## How much of the forest covers (x, z): 1 deep in the woods, 0 in the open
## (beyond its edge or in the Sanctum's clearing).
func _forest_amount(x: float, z: float) -> float:
	if not Game.story_start:
		return 0.0
	var from_wake := Vector2(x - Game.wake_point.x, z - Game.wake_point.z).length()
	var from_sanctum := Vector2(x, z).length()
	return smoothstep(FOREST_RADIUS + 12.0, FOREST_RADIUS - 10.0, from_wake) * smoothstep(SANCTUM_CLEARING - 6.0, SANCTUM_CLEARING + 8.0, from_sanctum)


## The forest you wake in: the great tree from the dream in a small glade,
## surrounded by a big forest of pines and broadleaf trees scattered unevenly
## (thick in places, with gaps and clearings), fallen logs, things to gather,
## and a forest floor of leaf litter, twigs, pebbles, ferns and mushrooms.
func _build_forest(center: Vector3) -> void:
	Animal.trunks.clear()
	_great_tree(Vector3(center.x, Game.ground_under(center.x, center.z, 1.4) - 0.3, center.z))
	var clumps := FastNoiseLite.new()
	clumps.seed = 99
	clumps.frequency = 0.05
	clumps.fractal_octaves = 3
	var prefabs := _tree_prefabs()
	var buckets: Array = []
	for i in prefabs.size():
		buckets.append([])
	var trunks := StaticBody3D.new()
	trunks.name = "ForestTrunks"
	add_child(trunks)
	var placed := 0
	var tries := 0
	while placed < FOREST_TREES and tries < FOREST_TREES * 8:
		tries += 1
		var a := _rng.randf() * TAU
		var d := lerpf(GLADE_RADIUS + 1.5, FOREST_RADIUS, sqrt(_rng.randf()))
		var p := center + Vector3(cos(a), 0, sin(a)) * d
		p.y = Game.height_at(p.x, p.z)
		if p.y < WATER_LEVEL + 0.5 or p.y > 22.0 or _on_isle(p.x, p.z):
			continue
		var keep := (clumps.get_noise_2d(p.x, p.z) * 0.5 + 0.62) * _forest_amount(p.x, p.z)
		if _rng.randf() > keep:
			continue
		placed += 1
		var s := _rng.randf_range(0.8, 1.5)
		var k := _rng.randi() % prefabs.size()
		var base := Vector3(p.x, Game.ground_under(p.x, p.z, 0.35 * s) - 0.2, p.z)
		var basis := (Basis(Vector3.UP, _rng.randf() * TAU) * Basis.from_euler(Vector3(_rng.randf_range(-0.04, 0.04), 0, _rng.randf_range(-0.04, 0.04)))).scaled(Vector3.ONE * s)
		var leaf := Color(0.08, 0.2, 0.11).lerp(Color(0.18, 0.28, 0.12), _rng.randf())
		buckets[k].append([Transform3D(basis, base), leaf])
		Animal.trunks.append([base, 0.3 * s])
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.3 * s
		cyl.height = 4.0
		shape.shape = cyl
		shape.position = base + Vector3(0, 2.0, 0)
		trunks.add_child(shape)
	var bark := _root_bark(_bark)
	var leaves := StandardMaterial3D.new()
	leaves.vertex_color_use_as_albedo = true
	leaves.roughness = 0.95
	for k in prefabs.size():
		_multimesh_of(prefabs[k][0], bark, buckets[k], false)
		_multimesh_of(prefabs[k][2], bark, buckets[k], false)
		_multimesh_of(prefabs[k][1], leaves, buckets[k], true)
	for i in 34:
		var a := _rng.randf() * TAU
		var p := center + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(GLADE_RADIUS, FOREST_RADIUS - 10.0)
		if _forest_amount(p.x, p.z) > 0.5:
			_fallen_log(p)
	_forest_floor(center)
	_place_gatherables(center)


## A few tree shapes at unit size, each as [trunk-with-roots mesh, canopy mesh];
## the forest draws hundreds of copies of each with MultiMesh.
func _tree_prefabs() -> Array:
	var out := []
	var shape_rng := RandomNumberGenerator.new()
	shape_rng.seed = 777
	for v in 6:
		var trunk := SurfaceTool.new()
		trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
		var canopy := SurfaceTool.new()
		canopy.begin(Mesh.PRIMITIVE_TRIANGLES)
		var roots := SurfaceTool.new()
		roots.begin(Mesh.PRIMITIVE_TRIANGLES)
		roots.append_from(NatureKit.root_flare(shape_rng.randi_range(4, 6), 60 + v), 0, Transform3D(Basis().scaled(Vector3.ONE * 0.36), Vector3(0, 0.2, 0)))
		if v < 3:
			# Tall pine: long bare trunk, stacked uneven cones.
			var h: float = [7.5, 9.0, 10.5][v]
			trunk.append_from(MeshKit.cyl(0.14, 0.32, h, 7), 0, Transform3D(Basis(), Vector3(0, h * 0.5, 0)))
			var tiers := 4 + v
			for j in tiers:
				var t := float(j) / tiers
				var cone_h := lerpf(2.6, 1.5, t)
				var cone := MeshKit.cyl(0.0, lerpf(1.9, 0.7, t) * shape_rng.randf_range(0.85, 1.15), cone_h, 8)
				canopy.append_from(cone, 0, Transform3D(Basis(Vector3.UP, shape_rng.randf() * TAU),
					Vector3(shape_rng.randf_range(-0.15, 0.15), h * lerpf(0.42, 0.95, t) + cone_h * 0.3, shape_rng.randf_range(-0.15, 0.15))))
		else:
			# Broadleaf: crooked trunk with a branch, lopsided cluster of blobs.
			var h: float = [5.5, 6.5, 7.5][v - 3]
			trunk.append_from(MeshKit.cyl(0.18, 0.38, h, 7), 0, Transform3D(Basis(), Vector3(0, h * 0.5, 0)))
			trunk.append_from(MeshKit.cyl(0.06, 0.12, 2.2, 6), 0, Transform3D(Basis.from_euler(Vector3(0, shape_rng.randf() * TAU, -0.7)), Vector3(0.5, h * 0.7, 0)))
			for j in shape_rng.randi_range(5, 7):
				var r := shape_rng.randf_range(1.3, 2.3)
				var blob := MeshKit.sphere(r, r * shape_rng.randf_range(1.0, 1.5), 8, 5)
				canopy.append_from(blob, 0, Transform3D(Basis(), Vector3(0, h, 0) + Vector3(shape_rng.randf_range(-1.6, 1.6), shape_rng.randf_range(-0.6, 1.6), shape_rng.randf_range(-1.6, 1.6))))
		out.append([trunk.commit(), canopy.commit(), roots.commit()])
	return out


func _multimesh_of(mesh: Mesh, material: Material, items: Array, colored: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colored
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		if colored:
			mm.set_instance_color(i, items[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material
	add_child(mmi)
## Sticks, stones and berry bushes: just a couple in sight of the great tree,
## a few more nearby, and the rest scattered thin through the woods.
## Sticks, stones and berry bushes: a handful right around the great tree so
## the first fire is quick, more scattered through the woods.
func _place_gatherables(center: Vector3) -> void:
	# The first few lie in plain sight just past where the hero wakes, so the
	# fire goal never starts with a search.
	var ahead := (Vector3.ZERO - center).normalized().rotated(Vector3.UP, 0.5)
	ahead.y = 0.0
	var side := ahead.cross(Vector3.UP)
	_fire_ring = Gatherable.spawn(self, Vector3(_ring_spot.x, Game.ground_at(_ring_spot.x, _ring_spot.z) - 0.02, _ring_spot.z), "fire_ring", _rng)
	var tilt := Quaternion(Vector3.UP, _ground_normal(_ring_spot.x, _ring_spot.z))
	_fire_ring.basis = Basis(tilt) * _fire_ring.basis  # lying along the slope
	var starter := [["sticks", 6.0, -1.8], ["stones", 8.5, 2.2]]
	for s in starter:
		var p: Vector3 = center + ahead * float(s[1]) + side * float(s[2])
		p.y = Game.ground_at(p.x, p.z)
		Gatherable.spawn(self, p, s[0], _rng)
	# Right around camp: only what the fire needs. Everything else is a short
	# walk out, so the first minutes are just sticks and stones.
	var near := [["sticks", 5, 6.0, 16.0], ["stones", 4, 6.0, 16.0], ["berries", 2, 24.0, 40.0], ["ferns", 4, 24.0, 40.0], ["vines", 2, 28.0, 45.0], ["bark", 2, 28.0, 45.0]]
	for entry in near:
		for i in entry[1]:
			var a := _rng.randf() * TAU
			var p := center + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(entry[2], entry[3])
			p.y = Game.ground_at(p.x, p.z)
			Gatherable.spawn(self, p, entry[0], _rng)
	var far := [["sticks", 70], ["stones", 40], ["berries", 30], ["ferns", 45], ["vines", 30], ["bark", 25]]
	for entry in far:
		var placed := 0
		var tries := 0
		while placed < entry[1] and tries < 2000:
			tries += 1
			var a := _rng.randf() * TAU
			var p := center + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(10.0 if entry[0] in ["sticks", "stones"] else 24.0, FOREST_RADIUS)
			p.y = Game.ground_at(p.x, p.z)
			if p.y < WATER_LEVEL + 0.2 or _forest_amount(p.x, p.z) < 0.3 or _on_isle(p.x, p.z):
				continue
			placed += 1
			Gatherable.spawn(self, p, entry[0], _rng)


## Same tree as in the dream: broad trunk, roots, a huge canopy, fireflies.
func _great_tree(at: Vector3) -> void:
	var body := _static_at(at, 0.0)
	var bark := MeshKit.mat(Color(0.3, 0.22, 0.16), 0.95)
	_add_cylinder(body, 0.75, 1.35, 9.0, Vector3(0, 4.5, 0), bark, 12)
	var roots := MeshKit.part(body, NatureKit.root_flare(8, 21), _root_bark(bark), Vector3(0, 0.25, 0))
	roots.scale = Vector3.ONE * 1.3
	var leaves := MeshKit.mat(Color(0.14, 0.3, 0.16), 0.95)
	for b in [[Vector3(0, 10.5, 0), 5.8], [Vector3(-3.6, 9.2, 1.2), 4.0], [Vector3(3.3, 9.6, -1.0), 4.2], [Vector3(0.6, 13.2, 0.4), 3.8], [Vector3(-1.5, 11.0, -3.0), 3.5]]:
		var r: float = b[1]
		MeshKit.part(body, MeshKit.sphere(r, r * 1.35, 10, 6), leaves, b[0])
	var firefly := MeshKit.glow(Color(1.0, 0.9, 0.45), 6.0)
	var flies := CPUParticles3D.new()
	var fly_mesh := MeshKit.sphere(0.035, -1.0, 4, 2)
	fly_mesh.material = firefly
	flies.mesh = fly_mesh
	flies.amount = 60
	flies.lifetime = 7.0
	flies.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	flies.emission_box_extents = Vector3(9, 2.5, 9)
	flies.direction = Vector3.UP
	flies.spread = 180.0
	flies.initial_velocity_min = 0.05
	flies.initial_velocity_max = 0.3
	flies.gravity = Vector3.ZERO
	flies.position = Vector3(0, 2.0, 0)
	body.add_child(flies)


var _root_meshes: Array[ArrayMesh] = []
var _root_mat: StandardMaterial3D


func _root_bark(bark: StandardMaterial3D) -> StandardMaterial3D:
	var m := bark.duplicate() as StandardMaterial3D
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## A few shared root flare shapes, so each tree adds one mesh for its roots.
func _roots_for(body: Node3D, trunk_radius: float) -> void:
	if _root_meshes.is_empty():
		for k in 4:
			_root_meshes.append(NatureKit.root_flare(_rng.randi_range(4, 6), 40 + k))
	if _root_mat == null:
		_root_mat = _root_bark(_bark)
	var roots := MeshKit.part(body, _root_meshes[_rng.randi() % _root_meshes.size()], _root_mat, Vector3(0, 0.2, 0))
	roots.scale = Vector3.ONE * trunk_radius
	roots.rotation.y = _rng.randf() * TAU


func _fallen_log(p: Vector3) -> void:
	var length := _rng.randf_range(3.0, 6.0)
	var r := _rng.randf_range(0.22, 0.4)
	var body := _static_at(_seated(p, length * 0.4, -r * 0.7), _rng.randf() * TAU)
	var mesh := MeshKit.part(body, MeshKit.cyl(r * 0.85, r, length, 8), _bark, Vector3.ZERO, Vector3(0, 0, PI / 2))
	mesh.rotation.x = _rng.randf_range(-0.05, 0.05)
	var moss := MeshKit.mat(Color(0.18, 0.32, 0.12), 1.0)
	MeshKit.part(body, MeshKit.box(Vector3(length * 0.7, 0.06, r * 1.2)), moss, Vector3(_rng.randf_range(-0.4, 0.4), r * 0.92, 0))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(length, r * 2.0, r * 2.0)
	shape.shape = box
	body.add_child(shape)


## Leaf litter, twigs, pebbles, ferns and mushrooms, thick under the trees and
## trailing off into the meadow, never in neat rows.
func _forest_floor(center: Vector3) -> void:
	var leaf_colors := [Color(0.42, 0.26, 0.12), Color(0.55, 0.36, 0.14), Color(0.32, 0.22, 0.12), Color(0.5, 0.45, 0.2), Color(0.25, 0.3, 0.12)]
	_scatter(NatureKit.leaf(), center, FOREST_RADIUS + 6.0, 40000, func(_p: Vector3) -> Array:
		var basis := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(-0.3, 0.3))
		return [basis.scaled(Vector3.ONE * _rng.randf_range(0.7, 1.6)), leaf_colors[_rng.randi() % leaf_colors.size()].darkened(_rng.randf_range(0.0, 0.3))])
	_scatter(NatureKit.twig(), center, FOREST_RADIUS + 4.0, 6000, func(_p: Vector3) -> Array:
		var basis := Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.FORWARD, _rng.randf_range(-0.12, 0.12))
		return [basis.scaled(Vector3.ONE * _rng.randf_range(0.6, 1.8)), Color(0.36, 0.27, 0.19).darkened(_rng.randf_range(0.0, 0.4))])
	_scatter(NatureKit.pebble(), center, FOREST_RADIUS + 10.0, 4000, func(_p: Vector3) -> Array:
		var s := _rng.randf_range(0.4, 2.2)
		var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf() * TAU, _rng.randf_range(-0.5, 0.5)))
		return [basis.scaled(Vector3(s * _rng.randf_range(0.8, 1.4), s * _rng.randf_range(0.5, 1.0), s)), Color(0.42, 0.41, 0.4).lerp(Color(0.3, 0.33, 0.25), _rng.randf())])
	_scatter(NatureKit.fern(), center, FOREST_RADIUS, 2600, func(_p: Vector3) -> Array:
		var s := _rng.randf_range(0.6, 1.5)
		return [Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.8, 1.3), s)), Color(0.18, 0.4, 0.14).lerp(Color(0.3, 0.45, 0.16), _rng.randf())])
	_scatter(NatureKit.mushroom(), center, FOREST_RADIUS - 6.0, 900, func(_p: Vector3) -> Array:
		var s := _rng.randf_range(0.7, 2.0)
		var cap: Color = [Color(0.85, 0.3, 0.2), Color(0.8, 0.66, 0.45), Color(0.95, 0.92, 0.85), Color(0.6, 0.4, 0.3)][_rng.randi() % 4]
		return [Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), cap])


## Scatters a mesh around `center` with MultiMesh. `style` returns [basis, color]
## for each instance. Clusters come from rejecting spots in sparse noise areas.
func _scatter(mesh: Mesh, center: Vector3, radius: float, count: int, style: Callable) -> void:
	var clusters := FastNoiseLite.new()
	clusters.seed = _rng.randi()
	clusters.frequency = 0.12
	var items := []
	var tries := 0
	while items.size() < count and tries < count * 4:
		tries += 1
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * radius
		var p := center + Vector3(cos(a), 0, sin(a)) * d
		var h := Game.ground_at(p.x, p.z)
		if h < WATER_LEVEL + 0.1 or _forest_amount(p.x, p.z) < 0.1 or _on_isle(p.x, p.z):
			continue
		if _rng.randf() > (clusters.get_noise_2d(p.x, p.z) * 0.5 + 0.55) * smoothstep(radius, radius * 0.6, d):
			continue
		var look: Array = style.call(p)
		if not _near_ring(p.x, p.z):
			items.append([Transform3D(look[0], Vector3(p.x, h, p.z)), look[1]])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_color(i, items[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = NatureKit.tinted()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _near_wake(p: Vector3, margin: float) -> bool:
	return Game.story_start and Vector2(p.x - Game.wake_point.x, p.z - Game.wake_point.z).length() < margin


## On (or just off) the little island: nothing grows or gets scattered there.
## It's checked where the island's ground would otherwise pass for dry land,
## so the rest of the world comes out the same as before the island was raised.
func _on_isle(x: float, z: float) -> bool:
	return Vector2(x - Game.ISLE.x, z - Game.ISLE.y).length() < 10.5


## Where the old fire ring sits: in plain sight, a few steps from where he
## wakes, on the flattest bit of ground thereabouts so none of it sinks in.
func _fire_ring_spot(center: Vector3) -> Vector3:
	var ahead := (Vector3.ZERO - center).normalized().rotated(Vector3.UP, 0.5)
	ahead.y = 0.0
	var planned := center + ahead * 4.6 + ahead.cross(Vector3.UP) * 2.8
	var best := planned
	var best_slope := INF
	for ring in [0.0, 0.8, 1.6, 2.4]:
		for k in 8:
			var q: Vector3 = planned + Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 8.0) * ring
			if Vector2(q.x - center.x, q.z - center.z).length() < 3.5:
				continue  # not on top of the sleepers
			var slope: float = absf(Game.ground_at(q.x + 1.0, q.z) - Game.ground_at(q.x - 1.0, q.z)) + absf(Game.ground_at(q.x, q.z + 1.0) - Game.ground_at(q.x, q.z - 1.0)) + ring * 0.05
			if slope < best_slope:
				best_slope = slope
				best = q
	return best


## The ground's tilt at a spot, for laying flat things along it.
func _ground_normal(x: float, z: float) -> Vector3:
	return Vector3(Game.ground_at(x - 0.8, z) - Game.ground_at(x + 0.8, z), 1.6, Game.ground_at(x, z - 0.8) - Game.ground_at(x, z + 0.8)).normalized()


## Kept bare around the old fire ring (no grass, ferns or leaves), so it stands out.
func _near_ring(x: float, z: float) -> bool:
	return Vector2(x - _ring_spot.x, z - _ring_spot.z).length() < 1.9


func _scatter_props() -> void:
	var placed := 0
	var attempts := 0
	while placed < 340 and attempts < 3000:
		attempts += 1
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * 160.0 + 20.0
		var p := Vector3(cos(a) * d, 0.0, sin(a) * d)
		p.y = Game.height_at(p.x, p.z)
		if p.y < WATER_LEVEL + 0.4 or _near_wake(p, GLADE_RADIUS + 5.0) or _on_isle(p.x, p.z):
			continue
		placed += 1
		var r := _rng.randf()
		if r < 0.5:
			_tree(p)
		elif r < 0.75:
			_rock(p)
		elif r < 0.94:
			_ruin(p)
		else:
			_monolith(p)


func _tree(p: Vector3) -> void:
	var s := _rng.randf_range(0.8, 1.6)
	var body := _static_at(_seated(p, 0.3 * s, 0.15), _rng.randf() * TAU)
	_roots_for(body, 0.28 * s)
	var trunk_h := 2.6 * s
	_add_cylinder(body, 0.16 * s, 0.28 * s, trunk_h, Vector3(0, trunk_h * 0.5, 0), _bark, 6)
	var leaves: StandardMaterial3D = _leaf_mats[4] if _rng.randf() < 0.08 else _leaf_mats[_rng.randi() % 4]
	if _rng.randf() < 0.4:
		for j in 3:
			var cone_h := 1.8 * s
			MeshKit.part(body, MeshKit.cyl(0.0, (1.4 - j * 0.32) * s, cone_h, 7), leaves,
				Vector3(0, trunk_h * 0.55 + j * 0.95 * s + cone_h * 0.5, 0))
	else:
		for j in 3:
			var r := (1.5 - j * 0.35) * s
			var offset := Vector3(_rng.randf_range(-0.3, 0.3), trunk_h + j * 0.85 * s - 0.2, _rng.randf_range(-0.3, 0.3))
			MeshKit.part(body, MeshKit.sphere(r, r * 1.5, 7, 4), leaves, offset)


func _rock(p: Vector3) -> void:
	var r := _rng.randf_range(0.5, 2.2)
	var body := _static_at(_seated(p, r * 0.8, r * 0.1), _rng.randf() * TAU)
	body.rotation.x = _rng.randf_range(-0.3, 0.3)
	body.rotation.z = _rng.randf_range(-0.3, 0.3)
	var stone: StandardMaterial3D = _stone_mats[_rng.randi() % _stone_mats.size()]
	MeshKit.part(body, MeshKit.sphere(r, r * _rng.randf_range(1.0, 1.5), 6, 4), stone)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = r * 0.85
	shape.shape = sphere
	body.add_child(shape)


## Old ruins, weathered and mossy: a broken column, a crumbling wall, or an
## arch. (Draws from _rng exactly as the older version did, so the world's
## layout doesn't shift; the extra details roll their own dice.)
func _ruin(p: Vector3) -> void:
	var stone: StandardMaterial3D = _stone_mats[_rng.randi() % _stone_mats.size()]
	var moss := _rune_mat  # moss green since the mythic restyle
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(p.x * 10.0), roundi(p.z * 10.0))) + 7
	match _rng.randi() % 3:
		0:
			# A column snapped off partway, moss on the break, a fallen piece beside it.
			var body := _static_at(_seated(p, 0.7, 0.1), _rng.randf() * TAU)
			body.rotation.z = _rng.randf_range(-0.2, 0.2) * 0.4
			var h := _rng.randf_range(2.5, 6.5) * 0.7
			_add_cylinder(body, 0.42, 0.56, h, Vector3(0, h * 0.5 - 0.3, 0), stone, 6)
			MeshKit.part(body, MeshKit.sphere(0.46, 0.25, 6, 3), moss, Vector3(0, h - 0.32, 0)).rotation.z = rng.randf_range(-0.3, 0.3)
			MeshKit.part(body, MeshKit.cyl(0.55, 0.6, 0.5, 6), _deep_moss_mat, Vector3(0, -0.1, 0))
			if _rng.randf() < 0.5:
				var drum := rng.randf_range(0.8, 1.4)
				MeshKit.part(body, MeshKit.cyl(0.44, 0.44, drum, 6), stone, Vector3(1.3, 0.1, rng.randf_range(-0.5, 0.5)), Vector3(0, rng.randf() * TAU, PI / 2))
		1:
			# A stretch of old wall, its top worn ragged and grown over.
			var w := _rng.randf_range(3.0, 7.0)
			var body := _static_at(_seated(p, w * 0.5, 0.0), _rng.randf() * TAU)
			var h := _rng.randf_range(1.5, 3.5)
			_add_box(body, Vector3(w, h, 0.7), Vector3(0, h * 0.5 - 0.3, 0), Vector3.ZERO, stone)
			_add_box(body, Vector3(w * 0.4, h * 0.6, 0.7), Vector3(w * 0.3, h - 0.3 + h * 0.3, 0), Vector3.ZERO, stone)
			MeshKit.part(body, MeshKit.box(Vector3(w * 0.6, 0.1, 0.78)), moss, Vector3(-w * 0.2, h - 0.27, 0))
			MeshKit.part(body, MeshKit.box(Vector3(w * 0.42, 0.1, 0.78)), moss, Vector3(w * 0.3, h * 1.6 - 0.27, 0))
			MeshKit.part(body, MeshKit.box(Vector3(w + 0.1, 0.45, 0.8)), _deep_moss_mat, Vector3(0, -0.12, 0))
			_rng.randf()  # was the old stripe's colour roll; kept so the layout holds
			for k in rng.randi_range(2, 4):  # rubble at the foot
				MeshKit.part(body, MeshKit.sphere(0.25, 0.3, 6, 3), stone,
					Vector3(rng.randf_range(-w * 0.5, w * 0.5), 0.0, rng.randf_range(0.6, 1.1) * (1.0 if k % 2 else -1.0)))
		_:
			# An arch still standing, moss along the lintel.
			var span := _rng.randf_range(3.0, 4.5)
			var body := _static_at(_seated(p, span * 0.5 + 0.5, 0.0), _rng.randf() * TAU)
			var h := _rng.randf_range(3.5, 5.0)
			for side in [-1.0, 1.0]:
				_add_box(body, Vector3(0.8, h, 0.8), Vector3(span * 0.5 * side, h * 0.5 - 0.2, 0), Vector3.ZERO, stone)
				MeshKit.part(body, MeshKit.box(Vector3(0.9, 0.5, 0.9)), _deep_moss_mat, Vector3(span * 0.5 * side, 0.0, 0))
			_add_box(body, Vector3(span + 1.4, 0.7, 1.0), Vector3(0, h, 0), Vector3.ZERO, stone)
			MeshKit.part(body, MeshKit.box(Vector3(span + 1.2, 0.1, 0.9)), moss, Vector3(0, h + 0.38, 0))


## A lone standing stone out in the wilds, like the Sanctum's but taller and
## older: rough, tapering, leaning a little, moss on its head and climbing up
## from its foot. Sometimes a smaller one stands beside it.
func _monolith(p: Vector3) -> void:
	# Its own dice, so the rest of the world lays out exactly as it always has
	# (this draws from _rng just as many times as the old monolith did).
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(p.x * 10.0), roundi(p.z * 10.0)))
	var yaw := _rng.randf() * TAU
	_rng.randf()
	var moss := MeshKit.mat(Color(0.3, 0.44, 0.2), 0.95)
	var deep_moss := MeshKit.mat(Color(0.22, 0.36, 0.16), 0.95)
	var body := _static_at(_seated(p, 0.8, 0.2), yaw)
	var stones := [[Vector3.ZERO, rng.randf_range(4.0, 6.0), 1.0]]
	if rng.randf() < 0.4:
		stones.append([Vector3(rng.randf_range(1.4, 1.9), 0, rng.randf_range(-0.4, 0.4)), rng.randf_range(1.8, 2.8), 0.75])
	for s in stones:
		var at: Vector3 = s[0]
		var h: float = s[1]
		var w: float = s[2]
		var lean := Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.08, 0.08))
		var flat := Vector3(1.5 * w, 1.0, 0.8 * w)
		var stone: StandardMaterial3D = _stone_mats[rng.randi() % _stone_mats.size()]
		MeshKit.part(body, MeshKit.cyl(0.3, 0.48, h, 6), stone, at + Vector3(0, h * 0.5 - 0.2, 0), lean).scale = flat
		MeshKit.part(body, MeshKit.sphere(0.33, 0.24, 7, 3), moss, at + Vector3(0, h - 0.3, 0), lean).scale = flat
		MeshKit.part(body, MeshKit.cyl(0.46, 0.5, h * 0.2, 6), deep_moss, at + Vector3(0, h * 0.1 - 0.2, 0), lean).scale = flat
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.8 * w, h, 0.5 * w)
		shape.shape = box
		shape.position = at + Vector3(0, h * 0.5 - 0.2, 0)
		shape.rotation = lean
		body.add_child(shape)


# --- Camps -------------------------------------------------------------------

func _create_camps() -> void:
	var attempts := 0
	while _camps.size() < CAMP_COUNT and attempts < 600:
		attempts += 1
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(40.0, 165.0)
		var pos := Vector3(cos(a) * d, 0.0, sin(a) * d)
		pos.y = Game.height_at(pos.x, pos.z)
		if pos.y < 0.0 or _near_wake(pos, FOREST_RADIUS + 8.0):
			continue
		var too_close := false
		for c in _camps:
			if pos.distance_to(c["pos"]) < 28.0:
				too_close = true
				break
		if too_close:
			continue
		var camp := {"pos": pos, "level": Game.enemy_level_at(pos), "enemies": [], "cleared": false, "respawn": 0.0}
		_camps.append(camp)
		_decorate_camp(pos)
		_spawn_camp(camp)


## Camp pieces are placed relative to an unrotated body, so local offsets line up
## with the world positions used to look up the ground under each one.
func _decorate_camp(camp_pos: Vector3) -> void:
	var pos := _seated(camp_pos, 0.6, 0.1)
	var body := _static_at(pos, 0.0)
	_add_cylinder(body, 0.55, 0.4, 0.9, Vector3(0, 0.35, 0), _iron, 8)
	MeshKit.part(body, MeshKit.sphere(0.35, 0.8, 6, 3), _fire_mat, Vector3(0, 1.0, 0))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 2.5
	light.omni_range = 12.0
	light.position = Vector3(0, 1.6, 0)
	body.add_child(light)
	var crackle := Audio.attach_loop(body, "loop_fire", 0.0, 22.0, 4.0)
	if crackle:
		crackle.position.y = 1.0
	for i in 4:
		var a := TAU * i / 4.0 + _rng.randf_range(-0.3, 0.3)
		var p := Vector3(cos(a) * 8.0, 0.0, sin(a) * 8.0)
		var world := pos + p
		var local_y := Game.ground_under(world.x, world.z, 0.5) - pos.y
		var h := _rng.randf_range(2.0, 4.5)
		_add_cylinder(body, 0.4, 0.5, h, Vector3(p.x, local_y + h * 0.5 - 0.3, p.z), _stone_mats[1], 8)
	MeshKit.part(body, MeshKit.cyl(0.05, 0.05, 4.0, 6), _iron, Vector3(1.2, 2.0, 0))
	MeshKit.part(body, MeshKit.box(Vector3(0.9, 1.4, 0.04)), MeshKit.mat(Color(0.55, 0.12, 0.1)), Vector3(1.65, 3.2, 0))


func _spawn_camp(camp: Dictionary) -> void:
	var lvl: int = camp["level"]
	var enemies: Array = camp["enemies"]
	var count := 3 + mini(int(lvl * 0.5), 4)
	for i in count:
		var kind := Enemy.Kind.HUSK
		if _rng.randf() < 0.3:
			kind = Enemy.Kind.SENTINEL
		if i == 0 and lvl >= 3 and _rng.randf() < 0.6:
			kind = Enemy.Kind.BRUTE
		var e := Enemy.new()
		e.setup(kind, lvl, camp["pos"])
		var p: Vector3 = camp["pos"] + Vector3(_rng.randf_range(-6.0, 6.0), 0.0, _rng.randf_range(-6.0, 6.0))
		p.y = Game.height_at(p.x, p.z) + (1.8 if kind == Enemy.Kind.SENTINEL else 0.3)
		e.position = p
		add_child(e)
		enemies.append(e)


func _update_camps() -> void:
	for camp in _camps:
		var alive: Array = camp["enemies"].filter(func(e): return is_instance_valid(e) and not e.dead)
		camp["enemies"] = alive
		if not alive.is_empty():
			continue
		if not camp["cleared"]:
			camp["cleared"] = true
			camp["respawn"] = CAMP_RESPAWN_TIME
			Game.notify("Camp cleared", Color(1.0, 0.8, 0.4))
			Audio.play("camp_cleared", null, 0.0, 1.0, 0.0)
			continue
		camp["respawn"] -= 1.0
		var far := Game.player == null or Game.player.global_position.distance_to(camp["pos"]) > 50.0
		if camp["respawn"] <= 0.0 and far:
			camp["cleared"] = false
			_spawn_camp(camp)


func _spawn_demo_enemies(player: Player) -> void:
	var forward := Basis(Vector3.UP, Game.shot_yaw) * Vector3.FORWARD
	var kinds := [Enemy.Kind.HUSK, Enemy.Kind.SENTINEL, Enemy.Kind.BRUTE]
	for i in kinds.size():
		var e := Enemy.new()
		var p := player.position + forward * 14.0 + forward.cross(Vector3.UP) * (i - 1) * 4.0
		e.setup(kinds[i], 2, p)
		p.y = Game.height_at(p.x, p.z) + (1.8 if kinds[i] == Enemy.Kind.SENTINEL else 0.3)
		e.position = p
		add_child(e)


# --- Helpers -----------------------------------------------------------------

## Moves a position down onto the lowest ground under a footprint of `radius`,
## then sinks it a little further so the base never shows a gap.
func _seated(p: Vector3, radius: float, sink: float) -> Vector3:
	return Vector3(p.x, Game.ground_under(p.x, p.z, radius) - sink, p.z)


func _static_at(pos: Vector3, yaw: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = yaw
	add_child(body)
	return body


func _add_cylinder(body: Node3D, top: float, bottom: float, height: float, pos: Vector3, material: Material, sides := 8) -> void:
	MeshKit.part(body, MeshKit.cyl(top, bottom, height, sides), material, pos)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = maxf(top, bottom)
	cyl.height = height
	shape.shape = cyl
	shape.position = pos
	body.add_child(shape)


func _add_box(body: Node3D, size: Vector3, pos: Vector3, rot: Vector3, material: Material) -> void:
	MeshKit.part(body, MeshKit.box(size), material, pos, rot)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	shape.rotation = rot
	body.add_child(shape)


func _deepest_point() -> Vector3:
	var best := Vector3(0, 99.0, 0)
	for x in range(-160, 161, 4):
		for z in range(-160, 161, 4):
			var h := Game.height_at(x, z)
			if h < best.y:
				best = Vector3(x, h, z)
	return best


func _take_screenshot() -> void:
	await get_tree().create_timer(Game.screenshot_delay).timeout
	if Game.shot_bloom:
		# Bloom (Q) as it opens, spreads and settles, in daylight on the grass.
		var pl := Game.player
		pl.global_position = Vector3(30.0, Game.ground_at(30.0, 30.0) + 0.3, 30.0)
		pl._yaw = 0.6
		pl._pitch = -0.5
		pl.zoom = 5.0
		await get_tree().create_timer(1.5).timeout
		pl._nova()
		var t := 0.0
		for at in [0.2, 0.5, 1.0]:
			await get_tree().create_timer(at - t).timeout
			t = at
			get_viewport().get_texture().get_image().save_png("%s_bloom_%.1f.png" % [Game.screenshot_path.get_basename(), at])
		get_tree().quit()
		return
	if Game.shot_lake:
		_test_lake()
		return
	if Game.shot_hill:
		_test_hill()
		return
	if Game.shot_isle:
		_test_isle()
		return
	if Game.shot_hero:
		_test_hero()
		return
	if Game.shot_home:
		# Make It Home, start to finish: each piece placed on the Sanctum floor
		# the way the player would, a nap on the bedroll, the chest used.
		var pl := Game.player
		pl._end_wake()
		await get_tree().create_timer(36.0).timeout  # through the opening lines
		for c in [_fox, _otter]:
			if c._zzz:
				c._zzz.queue_free()
			c.body.rotation.z = 0.0
			c.follow()
			c._forage_timer = 999.0
		for item in ["Stones", "Sticks", "Ferns", "Vines"]:
			Game.add_item(item, 40)
		_start_home()
		var put := func(id: String, x: float, z: float) -> void:
			pl.global_position = Vector3(x, 3.0, z)
			pl.velocity = Vector3.ZERO
			pl._yaw = 0.0
			pl._pitch = -0.3
			await get_tree().create_timer(0.8).timeout
			var ok := pl.begin_placing(id)
			await get_tree().create_timer(0.3).timeout
			var spot := pl._placer.global_position if ok else Vector3.ZERO
			var valid := ok and pl._placer.valid
			print("%s: known %s, preview at %s valid %s (terrain %.2f)" % [id, Game.known.has(id), spot.snapped(Vector3.ONE * 0.01), valid, Game.ground_at(spot.x, spot.z)])
			if valid:
				pl._build(id, spot, pl._placer.rotation.y)
			pl.cancel_placing()
			await get_tree().create_timer(5.0).timeout  # the next idea comes after a moment
			print("  -> home step %d, quest %s" % [_home_step, Game.quest("home").get("steps", "done")])
		await put.call("hearth", 0.0, 7.8)
		await put.call("bedroll", -3.0, 5.5)
		var bed := get_tree().get_first_node_in_group("bedrolls") as Bedroll
		if bed:
			bed.use(pl)
			await get_tree().create_timer(5.5).timeout
		print("after nap: rested %.0f s, frozen %s, home step %d" % [Game.rested, pl.frozen, _home_step])
		await get_tree().create_timer(5.0).timeout  # the Fox's idea
		await put.call("chest", 3.2, 5.3)
		Game.stash_all()
		print("stashed: %s, pockets sticks %d" % [Game.stash, Game.inventory.get("Sticks", 0)])
		Game.unstash_all()
		await put.call("rain_cover", 0.0, 7.6)
		print("covered at hearth: %s, done %s, quest left %s" % [Shelter.covers(get_tree(), Vector3(0, 0, 5.0)), _home_step, not Game.quest("home").is_empty()])
		pl.global_position = Vector3(5.5, 3.0, 12.5)
		pl._yaw = 0.42
		pl._pitch = -0.3
		await get_tree().create_timer(2.0).timeout
		get_viewport().get_texture().get_image().save_png(Game.screenshot_path.get_basename() + "_home.png")
		pl.global_position = Vector3(-2.5, 3.0, 9.5)
		pl._yaw = -0.35
		pl._pitch = -0.45
		await get_tree().create_timer(1.5).timeout
		get_viewport().get_texture().get_image().save_png(Game.screenshot_path.get_basename() + "_home2.png")
		get_tree().quit()
		return
	if Game.shot_pets_eat:
		# Hungry pets: they snack on food lying nearby, then eat their own
		# find instead of bringing it back; a fed pet still brings his back.
		var pl := Game.player
		pl._end_wake()
		await get_tree().create_timer(36.0).timeout  # through the opening lines
		for c in [_fox, _otter]:
			if c._zzz:
				c._zzz.queue_free()
			c.body.rotation.z = 0.0
			c.follow()
			c._forage_timer = 999.0
			c.hunger = 20.0
		var at := pl.global_position + Vector3(4.0, 0, 1.0)
		var grubs := Gatherable.spawn(self, Vector3(at.x, Game.ground_at(at.x, at.z), at.z), "grubs", _rng)
		var at2 := pl.global_position + Vector3(-3.0, 0, 3.0)
		var clams := Gatherable.spawn(self, Vector3(at2.x, Game.ground_at(at2.x, at2.z), at2.z), "clams", _rng)
		await get_tree().create_timer(12.0).timeout
		print("snacks: fox hunger %.0f, otter hunger %.0f, grubs left %s, clams left %s" % [_fox.hunger, _otter.hunger, is_instance_valid(grubs), is_instance_valid(clams)])
		var count_food := func() -> int:
			return get_tree().get_nodes_in_group("gatherables").filter(func(g): return Companion.SNACK_KINDS.has(g.kind)).size()
		_fox.hunger = 20.0
		var before: int = count_food.call()
		_fox._start_run(pl, false)
		await get_tree().create_timer(16.0).timeout
		print("hungry run: fox hunger %.0f, food on ground %d -> %d, state %d" % [_fox.hunger, before, count_food.call(), _fox.state])
		_fox.hunger = 90.0
		_otter.hunger = 90.0
		before = count_food.call()
		_fox._start_run(pl, false)
		await get_tree().create_timer(16.0).timeout
		print("fed run: fox hunger %.0f, food on ground %d -> %d" % [_fox.hunger, before, count_food.call()])
		get_tree().quit()
		return
	if Game.shot_wisps:
		# Stand by the altar and shoot each stone's sleepy light: before the
		# echo they only stir, after it they wake one by one.
		var pl := Game.player
		pl.global_position = Vector3(0, Game.ground_at(0, 3.0) + 0.2, 3.0)
		await get_tree().create_timer(0.5).timeout
		var shoot_at := func(bud: WispBud) -> void:
			for k in 6:
				var f := -pl.camera.global_basis.z
				var d := (bud.global_position - pl.camera.global_position).normalized()
				pl._yaw += angle_difference(atan2(-f.x, -f.z), atan2(-d.x, -d.z))
				pl._pitch += asin(d.y) - asin(f.y)
				await get_tree().process_frame
				await get_tree().process_frame
			pl._fire_timer = 0.0
			pl.ammo = maxi(pl.ammo, 1)
			pl._try_fire()
			await get_tree().create_timer(0.4).timeout
		await shoot_at.call(_buds[0])
		print("before echo: woken %d" % _woken())
		_echoes.append("aim")
		Game.skills["Aim"] = 0.0
		_start_wake_quest()
		var base := Game.screenshot_path.get_basename()
		for i in _buds.size():
			await shoot_at.call(_buds[i])
			print("bud %d awake %s, step: %s" % [i, _buds[i].awake, Game.quest("wake").get("steps", [{}])[0].get("text", "(quest done)")])
			if i == 3:
				get_viewport().get_texture().get_image().save_png(base + "_half.png")
		print("woken %d/%d, wake quest left %s, aim xp %.1f" % [_woken(), _buds.size(), not Game.quest("wake").is_empty(), Game.skills.get("Aim", 0.0)])
		# The lit circle at night, from a little way out.
		_make_night(_env, _sky_material, _sun)
		pl.global_position = Vector3(0, Game.ground_at(0, 17.0) + 0.2, 17.0)
		pl._yaw = 0.0
		pl._pitch = -0.2
		await get_tree().create_timer(2.5).timeout
		get_viewport().get_texture().get_image().save_png(base + "_lit.png")
		get_tree().quit()
		return
	if Game.shot_echo:
		# Walk up to the altar with a tool in hand, touch the heartstone, and
		# watch the echo play and hand back.
		var pl := Game.player
		Game.start_quest("family", "Finding Home", ["Touch the heartstone (E at the altar)", "Find out what happened to your family"])
		pl.global_position = Vector3(0, Game.ground_at(0, 2.4) + 0.2, 2.4)
		pl._yaw = 0.0
		pl._pitch = -0.35
		await get_tree().create_timer(1.0).timeout
		print("weapon %s, ready %s, usable %s, focused %s, prompt %s" % [pl.weapon != null, _heartstone_ready(),
			_crystal.is_in_group("usables"), pl.focused == _crystal, _crystal.use_prompt()])
		var base := Game.screenshot_path.get_basename()
		get_viewport().get_texture().get_image().save_png(base + "_altar.png")
		_crystal.use(pl)
		var t := 0.0
		for at in [1.2, 4.6, 6.4, 7.5, 12.6, 17.0]:
			await get_tree().create_timer(at - t).timeout
			t = at
			get_viewport().get_texture().get_image().save_png("%s_echo_%.1f.png" % [base, at])
			print("t %.1f frozen %s dim %.2f" % [at, pl.frozen, Audio.dim])
		await get_tree().create_timer(6.0).timeout
		get_viewport().get_texture().get_image().save_png(base + "_after.png")
		print("after: frozen %s, echoes %s, aim %s (lv %d), steady %.2f, quest %s, usable %s, dim %.2f" % [pl.frozen, _echoes,
			Game.skills.has("Aim"), Game.skill_level("Aim"), pl.aim_steadiness(), Game.quest("family").steps, _crystal.is_in_group("usables"), Audio.dim])
		get_tree().quit()
		return
	if Game.shot_tools:
		# The five dream tools in a row, and the hero holding the wand.
		var pl := Game.player
		var at := Vector3(40.0, 0.0, 40.0)
		at.y = Game.ground_at(at.x, at.z)
		var k := 0
		for kind in WeaponData.ARCHETYPES:
			var w := WeaponData.generate(1, Game.rng, 0.0, kind, k % 5)
			var x := at.x + (k - 2) * 1.3
			LootDrop.spawn(self, w, Vector3(x, Game.ground_at(x, at.z) - 0.2, at.z), false)
			print("%s -> %s" % [kind, w.display_name])
			k += 1
		pl.global_position = at + Vector3(0, 0.1, 4.2)
		pl._yaw = 0.0
		pl._pitch = -0.15
		pl.zoom = 0.0
		pl.visible = false
		await get_tree().create_timer(2.0).timeout
		get_viewport().get_texture().get_image().save_png(Game.screenshot_path.replace(".png", "_tools.png"))
		pl.visible = true
		pl.global_position = at + Vector3(0, 0.1, 8.0)
		pl._yaw = 0.9
		pl.zoom = 2.5
		await get_tree().create_timer(1.5).timeout
		get_viewport().get_texture().get_image().save_png(Game.screenshot_path.replace(".png", "_held.png"))
		get_tree().quit()
		return
	if Game.shot_sit:
		await _test_sit()
		get_tree().quit()
		return
	if Game.shot_burn:
		await _test_burns()
		get_tree().quit()
		return
	if Game.shot_drown:
		await _test_drown()
		get_tree().quit()
		return
	if Game.shot_birds:
		await _test_birds()
		get_tree().quit()
		return
	if Game.shot_animals:
		await _test_animals()
		get_tree().quit()
		return
	if Game.shot_save:
		await _test_save()
		return
	if Game.shot_map:
		await _test_map()
		get_tree().quit()
		return
	if Game.shot_ring:
		# The old fire ring, from a few steps away, as you first see it.
		var pl := Game.player
		pl._end_wake()
		var ring := _fire_ring.global_position
		var from := (pl.global_position - ring)
		from.y = 0.0
		pl.global_position = ring + from.normalized() * 3.0 + Vector3.UP * 0.5
		pl._yaw = atan2(from.x, from.z)
		pl._pitch = -0.45
		pl.visible = false
		pl.zoom = 0.0
		await get_tree().create_timer(1.5).timeout
		get_viewport().get_texture().get_image().save_png(Game.screenshot_path.replace(".png", "_ring.png"))
		# Building a campfire right on it: the old ring makes way.
		var fire := Campfire.build(self, ring)
		await get_tree().create_timer(1.0).timeout
		print("old ring still there after building on it: %s" % is_instance_valid(_fire_ring))
		get_viewport().get_texture().get_image().save_png(Game.screenshot_path.replace(".png", "_ring_built.png"))
		fire.queue_free()
		# Then the pets settling down while he stands still, and pointing the
		# dot at things.
		var snap := func(tag: String):
			get_viewport().get_texture().get_image().save_png(Game.screenshot_path.replace(".png", "_%s.png" % tag))
		pl.visible = true
		pl.zoom = 3.4
		await get_tree().create_timer(36.0).timeout  # through the opening lines
		for c in [_fox, _otter]:
			if c._zzz:
				c._zzz.queue_free()
			c.body.rotation.z = 0.0
			c.follow()
		pl._pitch = -0.6
		await get_tree().create_timer(14.0).timeout
		snap.call("resting")
		print("lounging: fox %s otter %s" % [_fox.body.lounging, _otter.body.lounging])
		print("otter body lift %.2f (should stay under 0.6), fox rig %s" % [_otter.body._body.position.y, _fox.body._rig.position if _fox.body._rig else Vector3.ZERO])
		print("fox states: %s" % [_fox.body._rig.states() if _fox.body._rig else []])
		# A fire right where the pets like to lie: the next spot they pick
		# must keep clear of it.
		var fire_at := pl.global_position + Vector3(cos(pl._yaw), 0, -sin(pl._yaw)) * 3.0
		Campfire.build(self, Vector3(fire_at.x, Game.ground_at(fire_at.x, fire_at.z), fire_at.z))
		var near_fire := 0
		for k in 40:
			for c in [_fox, _otter]:
				c._wander_timer = 0.0
				c._antsy(0.0, pl)
				if Vector2(c._wander_point.x - fire_at.x, c._wander_point.z - fire_at.z).length() < 2.2:
					near_fire += 1
		print("lounge spots inside the fire's reach: %d of 80" % near_fire)
		# A close look at the Fox lying on his side.
		_fox._wander_timer = 999.0
		_fox._wander_point = _fox.body.position
		_fox.body.lounging = true
		var fx: Vector3 = _fox.body.position
		pl.global_position = Vector3(fx.x + 2.2, Game.ground_at(fx.x + 2.2, fx.z) + 0.1, fx.z)
		pl._yaw = PI / 2
		pl._pitch = -0.35
		pl.zoom = 2.0
		pl.visible = false
		await get_tree().create_timer(2.5).timeout
		snap.call("fox_lying")
		print("fox lying: rig %s roll %.2f" % [_fox.body._rig.position if _fox.body._rig else Vector3.ZERO, _fox.body._rig.rotation.z if _fox.body._rig else 0.0])
		pl.visible = true
		print("aiming at ring: focused %s" % pl.focused)
		print("frozen %s, fox state %d" % [pl.frozen, _fox.state])
		for target in [_fox, _otter]:
			var found := false
			for k in 72:
				pl._yaw = TAU * k / 72.0
				for pitch in [-0.3, -0.5, -0.7]:
					pl._pitch = pitch
					await get_tree().process_frame
					await get_tree().process_frame
					if pl.focused == target:
						found = true
						break
				if found:
					break
			print("pointing at %s: %s" % [target.who, found])
			if found:
				snap.call("point_" + target.who)
		get_tree().quit()
		return
	if Game.shot_camp or Game.shot_dawn:
		var pl := Game.player
		pl._end_wake()
		for c in [_fox, _otter]:
			c.state = Companion.State.FOLLOWING
			if c._zzz:
				c._zzz.queue_free()
			c.body.rotation.z = 0.0
		var fwd := pl._aim_flat()
		var fire_at := pl.global_position + fwd * 2.4 + fwd.cross(Vector3.UP) * 1.6
		fire_at.y = Game.ground_at(fire_at.x, fire_at.z)
		Campfire.build(self, fire_at)
		var shot := func(tag: String):
			get_viewport().get_texture().get_image().save_png(Game.screenshot_path.replace(".png", "_%s.png" % tag))
		if Game.shot_camp:
			# The Fox's cooking idea, the fire menu, a find for the Otter, and the new builds.
			await get_tree().create_timer(9.0).timeout
			Game.add_item("Fish", 2)
			Game.add_item("Grubs", 3)
			await get_tree().create_timer(13.0).timeout
			var to_fire := fire_at - pl.global_position
			pl.global_position = fire_at - to_fire.normalized() * 1.6
			_hud._open_fire(get_tree().get_nodes_in_group("campfires")[0])
			await get_tree().create_timer(0.5).timeout
			shot.call("fire")
			_hud._talk.close()
			pl.cook("Fish", get_tree().get_nodes_in_group("campfires")[0])
			var vine_at := pl.global_position + fwd * 1.2
			vine_at.y = Game.ground_at(vine_at.x, vine_at.z)
			var vines := Gatherable.spawn(self, vine_at, "vines", _rng)
			await get_tree().create_timer(1.0).timeout
			shot.call("vines")
			vines.gather(_rng)
			Game.add_item("Birch bark", 3)
			Game.spark("rain_catcher")
			await get_tree().create_timer(8.0).timeout
			_otter.body.global_position = pl.global_position + fwd * 1.5
			_hud._talk.open(_otter)
			await get_tree().create_timer(0.5).timeout
			shot.call("otter")
			_hud._talk.close()
			_otter._teach_spark()
			await get_tree().create_timer(13.0).timeout
			_otter._teach_spark()
			await get_tree().create_timer(13.0).timeout
			Game.add_item("Sticks", 10)
			Game.add_item("Vines", 2)
			pl._yaw += 2.2
			for id in ["torch_post", "rain_catcher"]:
				pl._yaw -= 0.5
				pl.begin_placing(id)
				await get_tree().create_timer(0.4).timeout
				pl._build(id, pl._placer.global_position, pl._placer.rotation.y)
				pl.cancel_placing()
			await get_tree().create_timer(1.0).timeout
			shot.call("built")
			_hud._inventory._tab = "Know-how"
			_hud._inventory.open()
			await get_tree().create_timer(0.6).timeout
			shot.call("knowhow")
		else:
			# Sitting up with the boys, the fade, and morning.
			await get_tree().create_timer(2.0).timeout
			Game.rest_ready = true
			Game.rest_requested.emit()
			for t in [6.0, 14.0, 20.0, 12.0]:
				await get_tree().create_timer(t).timeout
				shot.call("%d" % int(Time.get_ticks_msec() / 1000))
		get_tree().quit()
		return
	if Game.shot_settle:
		# After the fire: the new quest, talking to the Otter, and a lean-to.
		var pl := Game.player
		pl._end_wake()
		for c in [_fox, _otter]:
			c.state = Companion.State.FOLLOWING
			if c._zzz:
				c._zzz.queue_free()
			c.body.rotation.z = 0.0
		var fwd := pl._aim_flat()
		var fire_at := pl.global_position + fwd * 2.4 + fwd.cross(Vector3.UP) * 1.6
		fire_at.y = Game.ground_at(fire_at.x, fire_at.z)
		Campfire.build(self, fire_at)
		await get_tree().create_timer(9.0).timeout
		_otter.body.global_position = pl.global_position + fwd * 1.5
		_hud._talk.open(_otter)
		await get_tree().create_timer(0.5).timeout
		get_viewport().get_texture().get_image().save_png(Game.screenshot_path.replace(".png", "_talk.png"))
		_hud._talk.close()
		_otter.talk_options()[0][1].call()
		await get_tree().create_timer(12.0).timeout
		Game.add_item("Sticks", 6)
		Game.add_item("Ferns", 5)
		pl._yaw += 0.9
		pl.begin_placing("lean_to")
		await get_tree().create_timer(0.6).timeout
		get_viewport().get_texture().get_image().save_png(Game.screenshot_path.replace(".png", "_ghost.png"))
		pl._build("lean_to", pl._placer.global_position, pl._placer.rotation.y)
		pl.cancel_placing()
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png(Game.screenshot_path.replace(".png", "_built.png"))
		# Walk at it from behind: the roof should stop him.
		var lean: Node3D = get_tree().get_nodes_in_group("shelters")[0]
		var d := lean.global_basis * Vector3.BACK
		pl.global_position = lean.global_transform * Vector3(0, 0, -Shelter.DEPTH - 1.5) + Vector3.UP * 0.5
		pl._yaw = atan2(-d.x, -d.z)
		await get_tree().create_timer(0.5).timeout
		Input.action_press("move_forward")
		await get_tree().create_timer(3.0).timeout
		Input.action_release("move_forward")
		print("walked into lean-to: local z %.2f (through if > 0)" % (lean.global_transform.affine_inverse() * pl.global_position).z)
		get_viewport().get_texture().get_image().save_png(Game.screenshot_path.replace(".png", "_blocked.png"))
		get_tree().quit()
		return
	if Game.shot_forage:
		# A food run: the Fox digging, then back with the find.
		Game.player._end_wake()
		_fox.state = Companion.State.FOLLOWING
		if _fox._zzz:
			_fox._zzz.queue_free()
		_fox.body.rotation.z = 0.0
		_fox._forage_timer = 0.01
		for t in [2.6, 5.5]:
			await get_tree().create_timer(t).timeout
			get_viewport().get_texture().get_image().save_png(Game.screenshot_path.replace(".png", "_%.1f.png" % t))
		get_tree().quit()
		return
	if Game.shot_place:
		# The build preview: blue on open ground, then red against the great tree.
		var pl := Game.player
		pl._end_wake()
		Game.learn("campfire")
		Game.add_item("Sticks", 5)
		Game.add_item("Stones", 3)
		pl.begin_placing("campfire")
		for i in 2:
			if i == 1:
				pl._yaw += PI
				pl.says.emit(["I don't think I can build that there.", "Should find a different spot."])
			await get_tree().create_timer(1.2).timeout
			get_viewport().get_texture().get_image().save_png(Game.screenshot_path.replace(".png", "_%d.png" % i))
		get_tree().quit()
		return
	if Game.shot_punch:
		# Two punches in a row, caught at full reach, seen from the side.
		var p := Game.player
		p._end_wake()
		var side_cam := Camera3D.new()
		add_child(side_cam)
		var fwd := p._aim_flat()
		var right := fwd.cross(Vector3.UP)
		side_cam.look_at_from_position(p.global_position + right * 2.6 + fwd * 0.6 + Vector3(0, 1.5, 0), p.global_position + fwd * 0.5 + Vector3(0, 1.2, 0))
		side_cam.make_current()
		var lamp := OmniLight3D.new()
		lamp.position = side_cam.position
		lamp.omni_range = 6.0
		add_child(lamp)
		for i in 2:
			await get_tree().create_timer(0.7).timeout
			p._punch()
			await get_tree().create_timer(0.14).timeout
			get_viewport().get_texture().get_image().save_png(Game.screenshot_path.replace(".png", "_%d.png" % i))
		get_tree().quit()
		return
	var image := get_viewport().get_texture().get_image()
	image.save_png(Game.screenshot_path)
	get_tree().quit()


## Test hook (--shot-burn): the hero, the Fox and the Otter each step into a
## campfire, and the hero brushes a torch.
func _test_burns() -> void:
	var pl := Game.player
	pl._end_wake()
	for c in [_fox, _otter]:
		c.state = Companion.State.FOLLOWING
		if c._zzz:
			c._zzz.queue_free()
		c.body.rotation.z = 0.0
	var fwd := pl._aim_flat()
	var fire_at := pl.global_position - fwd * 4.0 + fwd.cross(Vector3.UP) * 2.0
	fire_at.y = Game.ground_at(fire_at.x, fire_at.z)
	Campfire.build(self, fire_at)
	var shot := func(tag: String):
		get_viewport().get_texture().get_image().save_png(Game.screenshot_path.replace(".png", "_%s.png" % tag))
	await get_tree().create_timer(9.0).timeout
	var h0 := pl.health
	pl.global_position = fire_at - fwd * 0.3 + Vector3.UP * 0.1
	await get_tree().create_timer(0.35).timeout
	shot.call("hero")
	await get_tree().create_timer(1.6).timeout
	print("hero health %.1f -> %.1f, distance from fire %.2f" % [h0, pl.health, Vector2(pl.global_position.x - fire_at.x, pl.global_position.z - fire_at.z).length()])
	shot.call("hero_after")
	# Look at the hero from the fire side to see the smudge on the shin.
	pl._yaw += PI
	await get_tree().create_timer(0.6).timeout
	shot.call("hero_mark")
	pl._yaw -= PI
	pl.global_position = fire_at - fwd * 3.5
	await get_tree().create_timer(2.0).timeout
	for c in [_fox, _otter]:
		c._careless = true
		c.body.global_position = fire_at + fwd.cross(Vector3.UP) * 0.3
		await get_tree().create_timer(0.4).timeout
		shot.call(c.who)
		await get_tree().create_timer(4.0).timeout
	shot.call("pets_after")
	var torch_at := pl.global_position + fwd.cross(Vector3.UP) * 2.0
	torch_at.y = Game.ground_at(torch_at.x, torch_at.z)
	TorchPost.build(self, torch_at)
	await get_tree().create_timer(4.0).timeout
	var h1 := pl.health
	pl.global_position = torch_at + Vector3(0.1, 0.05, 0)
	await get_tree().create_timer(0.4).timeout
	shot.call("torch")
	print("torch: health %.1f -> %.1f" % [h1, pl.health])


## Test hook (--shot-sit): sit down by a fire with the pets, roast a fish
## (flip included), feed the Otter, then get up.
func _test_sit() -> void:
	var pl := Game.player
	pl._end_wake()
	for c in [_fox, _otter]:
		c.state = Companion.State.FOLLOWING
		if c._zzz:
			c._zzz.queue_free()
		c.body.rotation.z = 0.0
	var fwd := pl._aim_flat()
	var fire_at := pl.global_position - fwd * 4.0 + fwd.cross(Vector3.UP) * 2.0
	fire_at.y = Game.ground_at(fire_at.x, fire_at.z)
	var fire := Campfire.build(self, fire_at)
	var shot := func(tag: String):
		get_viewport().get_texture().get_image().save_png(Game.screenshot_path.replace(".png", "_%s.png" % tag))
	await get_tree().create_timer(9.0).timeout
	Game.learn("cooking")
	Game.add_item("Fish", 2)
	pl.global_position = fire_at + fwd * 2.0
	await get_tree().create_timer(0.5).timeout
	pl.sit_by_fire(fire)
	await get_tree().create_timer(4.0).timeout
	shot.call("sit")
	pl._yaw += 1.3
	await get_tree().create_timer(0.5).timeout
	shot.call("sit_side")
	pl._yaw -= 1.3
	pl.cook("Fish", fire)
	await get_tree().create_timer(2.3).timeout
	shot.call("cook_flip")
	pl.cook_needs_flip = false
	pl._cook_flipped = true
	await get_tree().create_timer(2.5).timeout
	print("after one: fish %d, roast %d" % [Game.inventory.get("Fish", 0), Game.inventory.get("Roast fish", 0)])
	pl.stop_cooking()
	_otter.hunger = 30.0
	_hud._talk.open(_otter)
	await get_tree().create_timer(0.4).timeout
	shot.call("otter_menu")
	_hud._talk.close()
	_otter.feed("Roast fish")
	await get_tree().create_timer(1.0).timeout
	shot.call("fed")
	print("otter hunger %.0f" % _otter.hunger)
	pl.get_up()
	await get_tree().create_timer(3.0).timeout
	print("seated %s frozen %s fox state %d" % [pl.seated, pl.frozen, _fox.state])
	shot.call("up")


## Test hook (--shot-lake): the second echo, start to finish. The hum toward
## the water, the ruin, the heartstone and the rainy-day echo, then the dare
## and a dive to the glowing stone on the lake bed.
func _test_lake() -> void:
	var pl := Game.player
	pl._end_wake()
	var base := Game.screenshot_path.get_basename()
	var shot := func(tag: String):
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [base, tag])
	await get_tree().create_timer(55.0).timeout  # through the opening lines and the fire quest
	for c in [_fox, _otter]:
		if c._zzz:
			c._zzz.queue_free()
		c.body.rotation.z = 0.0
		c.follow()
		c._forage_timer = 999.0
	print("lake ruin at %s, out %s, treasure at %s (water depth %.2f)" % [_lake.global_position.snapped(Vector3.ONE * 0.1), _lake.out.snapped(Vector3.ONE * 0.01),
		_lake.treasure.global_position.snapped(Vector3.ONE * 0.1), WATER_LEVEL - _lake.treasure.global_position.y])
	Game.start_quest("family", "Finding Home", ["Touch the heartstone", "Find out what happened to your family"])
	Game.set_step("family", 0, "Touch the heartstone", true)
	_home_step = HOME_STEPS.size()
	_start_lake()
	await get_tree().create_timer(1.0).timeout
	print("stage %d, steps %s" % [_lake_stage, Game.quest("family").steps])
	var look_out := func(local: Vector3, pitch: float):
		pl.global_position = _lake.to_global(local) + Vector3.UP * 2.0
		pl.global_position.y = Game.ground_at(pl.global_position.x, pl.global_position.z) + 0.3
		pl.velocity = Vector3.ZERO
		pl._yaw = _lake.rotation.y
		pl._pitch = pitch
	look_out.call(Vector3(2.5, 0, 9.0), -0.2)
	await get_tree().create_timer(2.5).timeout
	shot.call("ruin")
	look_out.call(Vector3(0.3, 0, 3.4), -0.3)
	await get_tree().create_timer(1.5).timeout
	print("arrived: stage %d, usable %s, focused %s, steps %s" % [_lake_stage, _lake.heartstone.is_in_group("usables"),
		pl.focused == _lake.heartstone, Game.quest("family").steps])
	shot.call("stone")
	_lake.heartstone.use(pl)
	var t := 0.0
	for at in [2.0, 3.6, 5.5, 7.5, 9.5, 11.2, 12.6]:
		await get_tree().create_timer(at - t).timeout
		t = at
		shot.call("echo_%.1f" % at)
	await get_tree().create_timer(34.0).timeout
	print("after echo: echoes %s, diving %s, air time %.0f, stage %d, side %s" % [_echoes, Game.skills.has("Diving"), pl.air_time(), _lake_stage, Game.quest("lakebed")])
	look_out.call(Vector3(0.5, 0, 0.5), -0.35)
	await get_tree().create_timer(1.5).timeout
	shot.call("dare")
	# Down to the bottom.
	var tr := _lake.treasure.global_position
	pl.global_position = tr + _lake.out * -0.7 + Vector3.UP * 0.5
	Input.action_press("swim_down")
	pl.velocity = Vector3.ZERO
	pl._yaw = _lake.rotation.y
	pl._pitch = -0.4
	await get_tree().create_timer(1.5).timeout
	print("on the bed: swimming %s, under %s, usable %s, focused %s, air %.2f" % [pl.swimming, pl.head_under(), _lake.treasure.is_in_group("usables"), pl.focused == _lake.treasure, pl.air])
	shot.call("lakebed")
	Input.action_release("swim_down")
	pl._interact()
	await get_tree().create_timer(3.0).timeout
	print("found: stage %d, backpack %s, side %s, steps %s, diving %.1f" % [_lake_stage, Game.backpack, Game.quest("lakebed"), Game.quest("family").steps, Game.skills.get("Diving", 0.0)])
	get_tree().quit()


## Test hook (--shot-isle): the little house on the water, start to finish:
## the Otter's raft idea, driftwood, building the raft on the water, paddling
## out with the pets aboard, hopping off at the deck and reading the page.
func _test_isle() -> void:
	var pl := Game.player
	pl._end_wake()
	var base := Game.screenshot_path.get_basename()
	var shot := func(tag: String):
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [base, tag])
	await get_tree().create_timer(55.0).timeout  # through the opening lines and the fire quest
	for c in [_fox, _otter]:
		if c._zzz:
			c._zzz.queue_free()
		c.body.rotation.z = 0.0
		c.follow()
		c._forage_timer = 999.0
	print("isle house at %s, floor %.2f, facing ruin at %s" % [_isle.global_position.snapped(Vector3.ONE * 0.1), _isle.floor_y, _lake.global_position.snapped(Vector3.ONE * 0.1)])
	print("driftwood: %d pieces" % get_tree().get_nodes_in_group("gatherables").filter(func(g): return g.kind == "driftwood").size())
	Game.start_quest("family", "Finding Home", ["Touch the heartstone", "Find out what happened to your family"])
	_home_step = HOME_STEPS.size()
	_lake_stage = 3
	_lake.treasure.queue_free()
	# Stand on the shore by the old stones, looking out at the house.
	var shore := _lake.to_global(Vector3(0, 0, -1.6))
	pl.global_position = Vector3(shore.x, Game.ground_at(shore.x, shore.z) + 0.3, shore.z)
	var look := func(at: Vector3, pitch: float):
		var d := at - pl.global_position
		pl._yaw = atan2(-d.x, -d.z)
		pl._pitch = pitch
	look.call(_isle.global_position, -0.05)
	for c in [_fox, _otter]:
		c.body.position = pl.global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	_start_isle()
	await get_tree().create_timer(15.0).timeout
	print("knows raft %s, quest %s" % [Game.known.has("raft"), Game.quest("isle")])
	shot.call("view")
	# Gather one driftwood for real, then the rest.
	var wood: Array = get_tree().get_nodes_in_group("gatherables").filter(func(g): return g.kind == "driftwood")
	if not wood.is_empty():
		print("gathered: ", wood[0].gather(Game.rng))
	Game.add_item("Driftwood", 3)
	Game.add_item("Vines", 3)
	await get_tree().process_frame
	print("steps after wood: %s" % [Game.quest("isle").steps])
	# Build it on the water, just out from the steps.
	look.call(_lake.to_global(Vector3(0, 0, -12)), -0.3)
	pl.begin_placing("raft")
	await get_tree().create_timer(0.3).timeout
	print("placer valid %s at %s" % [pl._placer.valid, pl._placer.global_position.snapped(Vector3.ONE * 0.1)])
	shot.call("place")
	if not pl._placer.valid:
		# Try a step further out.
		pl.global_position = _lake.to_global(Vector3(0, 0, -3.0))
		pl.global_position.y = Game.ground_at(pl.global_position.x, pl.global_position.z) + 0.3
		await get_tree().create_timer(0.5).timeout
		print("placer valid (further out) %s" % pl._placer.valid)
	pl._build("raft", pl._placer.global_position, pl._placer.rotation.y)
	pl.cancel_placing()
	await get_tree().create_timer(2.0).timeout
	var raft: Raft = get_tree().get_nodes_in_group("rafts")[0]
	print("raft built at %s, steps %s, driftwood left %d" % [raft.global_position.snapped(Vector3.ONE * 0.1), Game.quest("isle").steps, Game.inventory.get("Driftwood", 0)])
	for c in [_fox, _otter]:
		c.body.position = pl.global_position + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
		c.body.position.y = Game.ground_at(c.body.position.x, c.body.position.z)
	pl.focused_usable = raft
	raft.use(pl)
	await get_tree().create_timer(1.0).timeout
	print("aboard %s, fox %s, otter %s" % [pl.raft == raft, Companion.State.keys()[_fox.state], Companion.State.keys()[_otter.state]])
	shot.call("aboard")
	# Paddle toward the deck.
	var landing: Vector3 = get_tree().get_nodes_in_group("landings")[0].global_position
	Input.action_press("move_forward")
	var t := 0.0
	var shots := [6.0, 14.0]
	while t < 60.0:
		look.call(landing, -0.25)
		await get_tree().create_timer(0.25).timeout
		t += 0.25
		if not shots.is_empty() and t >= shots[0]:
			shot.call("paddle_%.0f" % shots.pop_front())
		if Vector2(raft.global_position.x - landing.x, raft.global_position.z - landing.z).length() < 4.5 or (t > 8.0 and raft._speed < 0.05):
			break
	Input.action_release("move_forward")
	print("after %.1fs: raft at %s, %.1f m from the deck landing, pets on %s" % [t, raft.global_position.snapped(Vector3.ONE * 0.1),
		Vector2(raft.global_position.x - landing.x, raft.global_position.z - landing.z).length(), _fox.body.position.distance_to(raft.global_position) < 2.0])
	shot.call("arrive")
	pl.leave_raft()
	await get_tree().create_timer(2.0).timeout
	print("hopped off to %s (floor %.2f), isle stage %d, fox at y %.2f, quest %s" % [pl.global_position.snapped(Vector3.ONE * 0.01), _isle.floor_y, _isle_stage, _fox.body.position.y, Game.quest("isle").steps])
	pl._yaw = _isle.rotation.y + PI
	pl._pitch = -0.15
	await get_tree().create_timer(1.0).timeout
	shot.call("deck")
	# Inside, at the table.
	var table := _isle.page.global_position
	pl.global_position = _isle.to_global(Vector3(-0.6, _isle.floor_y + 0.1, -0.3))
	look.call(table, -0.6)
	pl.zoom = 1.5
	await get_tree().create_timer(1.5).timeout
	print("inside: on floor y %.2f, page usable %s, focused %s" % [pl.global_position.y, _isle.page.is_in_group("usables"), pl.focused == _isle.page])
	shot.call("inside")
	_isle.page.use(pl)
	await get_tree().create_timer(3.0).timeout
	print("read: stage %d, backpack %s, side %s, family %s" % [_isle_stage, Game.backpack, Game.quest("isle"), Game.quest("family").steps])
	# From out on the water, the round window.
	pl.global_position = _isle.to_global(Vector3(-2.0, 0, -9.0))
	pl.global_position.y = WATER_LEVEL - 1.4
	look.call(_isle.global_position + Vector3.UP * (_isle.floor_y + 1.4), 0.05)
	pl.zoom = 3.0
	await get_tree().create_timer(2.0).timeout
	shot.call("house")
	get_tree().quit()


## Test hook (--shot-drown): a swim with the pets, then a dive held too long:
## the low-air view, passing out, the tow, waking on the bank, the shake.
func _test_drown() -> void:
	var pl := Game.player
	pl._end_wake()
	for c in [_fox, _otter]:
		c.state = Companion.State.FOLLOWING
		if c._zzz:
			c._zzz.queue_free()
		c.body.rotation.z = 0.0
	var shot := func(tag: String):
		get_viewport().get_texture().get_image().save_png(Game.screenshot_path.replace(".png", "_%s.png" % tag))
	await get_tree().create_timer(36.0).timeout  # let the opening lines play out
	for c in [_fox, _otter]:
		c.follow()
	var deep := _deepest_point()
	pl.global_position = Vector3(deep.x, Game.WATER_LEVEL - Player.FLOAT_DEPTH, deep.z)
	var fwd := pl._aim_flat()
	_fox.body.position = pl.global_position + fwd * 2.5 + fwd.cross(Vector3.UP) * 1.2
	_otter.body.position = pl.global_position + fwd * 2.2 - fwd.cross(Vector3.UP) * 1.2
	await get_tree().create_timer(4.0).timeout
	shot.call("swim")
	Input.action_press("swim_down")
	await get_tree().create_timer(2.5).timeout
	shot.call("dive")
	pl.air = 0.4
	await get_tree().create_timer(7.0).timeout
	print("air %.2f under %s" % [pl.air, pl.head_under()])
	shot.call("low_air")
	await get_tree().create_timer(5.5).timeout
	Input.action_release("swim_down")
	print("knocked out %s" % pl.knocked_out)
	await get_tree().create_timer(3.0).timeout
	shot.call("out")
	await get_tree().create_timer(4.0).timeout
	shot.call("tow")
	await get_tree().create_timer(4.5).timeout
	shot.call("fading")
	await get_tree().create_timer(6.0).timeout
	shot.call("wake")
	await get_tree().create_timer(4.0).timeout
	shot.call("shake")
	print("hero wet %.2f" % pl.wet)
	print("on shore y %.2f ground %.2f, fox wet %.2f state %d" % [pl.global_position.y, Game.ground_at(pl.global_position.x, pl.global_position.z), _fox.wet, _fox.state])
	await get_tree().create_timer(8.0).timeout
	print("frozen %s, fox state %d" % [pl.frozen, _fox.state])
	shot.call("after")


## Test hook (--shot-birds): by day, a flock lands nearby and a crow circles;
## then the hero walks at the flock and it scatters.
func _test_birds() -> void:
	var pl := Game.player
	pl._end_wake()
	_make_dawn()
	Game.is_night = false
	var shot := func(tag: String):
		get_viewport().get_texture().get_image().save_png(Game.screenshot_path.replace(".png", "_%s.png" % tag))
	await get_tree().create_timer(5.0).timeout
	var fwd := pl._aim_flat()
	var spot := pl.global_position + fwd * 9.0
	_birds.spawn_flock(pl.global_position, "cardinal", spot)
	_birds.spawn_flock(pl.global_position, "bluebird", spot + fwd.cross(Vector3.UP) * 3.0)
	_birds.spawn_soarer("crow", pl.global_position)
	await get_tree().create_timer(6.0).timeout
	shot.call("arriving")
	await get_tree().create_timer(8.0).timeout
	var grounded := _birds.get_children().filter(func(b): return b.mode == Bird.Mode.GROUND).size()
	print("birds %d, on the ground %d" % [_birds.get_child_count(), grounded])
	Bird.fearless = true
	var perched: Array = _birds.get_children().filter(func(b): return b.mode == Bird.Mode.GROUND)
	if not perched.is_empty():
		var bird: Node3D = perched[0]
		bird.global_position = pl.global_position - fwd * 1.6
		pl._yaw += PI
		bird.global_position.y = Game.ground_at(bird.global_position.x, bird.global_position.z)
		pl._pitch = -0.45
		pl.zoom = 0.0
	await get_tree().create_timer(0.4).timeout
	shot.call("ground")
	pl.zoom = 3.4
	Bird.fearless = false
	pl._pitch = 0.5
	await get_tree().create_timer(0.8).timeout
	shot.call("sky")
	pl._pitch = -0.12
	pl.global_position = spot - fwd * 4.0
	await get_tree().create_timer(0.7).timeout
	shot.call("scatter")
	await get_tree().create_timer(4.0).timeout
	grounded = _birds.get_children().filter(func(b): return b.mode == Bird.Mode.GROUND).size()
	print("after scare: birds %d, on the ground %d" % [_birds.get_child_count(), grounded])


## Test hook (--shot-animals): all the forest animals in a row in front of the
## hero, a close-up of the little ones, then the hero runs at them.
func _test_animals() -> void:
	var pl := Game.player
	pl._end_wake()
	_make_dawn()
	Game.is_night = false
	var shot := func(tag: String):
		get_viewport().get_texture().get_image().save_png(Game.screenshot_path.replace(".png", "_%s.png" % tag))
	await get_tree().create_timer(5.0).timeout
	Animal.fearless = true
	pl._yaw += PI
	await get_tree().create_timer(0.3).timeout
	var fwd := pl._aim_flat()
	pl.global_position += fwd * 6.0
	pl.global_position.y = Game.ground_at(pl.global_position.x, pl.global_position.z) + 0.1
	var right := fwd.cross(Vector3.UP)
	var kinds := ["stag", "deer", "rabbit", "squirrel", "chipmunk", "skunk", "frog"]
	for i in kinds.size():
		var at: Vector3 = pl.global_position + fwd * 7.0 + right * (i - 3) * 1.6
		_animals.spawn(pl.global_position, kinds[i], at)
	for a in _animals.get_children():
		a.rotation.y = atan2(fwd.x, fwd.z)  # all looking at the camera
		a._timer = 30.0
	pl._pitch = -0.2
	await get_tree().create_timer(1.5).timeout
	shot.call("lineup")
	var home := pl.global_position
	var all := _animals.get_children()
	for a in all:
		var near := 7.0 if a.kind in ["deer", "stag"] else 2.2
		for b in all:
			b.visible = b == a
		var keep: Vector3 = a.global_position
		var at := home + fwd * near
		a.global_position = Vector3(at.x, Game.ground_at(at.x, at.z), at.z)
		a.rotation.y = pl._yaw + PI / 2  # nose should point screen-left
		a.set_process(false)
		pl._pitch = -0.2 if near > 3.0 else -0.5
		pl.zoom = 0.0
		pl.visible = false
		await get_tree().create_timer(0.5).timeout
		shot.call("k_" + a.kind)
		a.global_position = keep
		a.set_process(true)
	for b in all:
		b.visible = true
	pl.visible = true
	pl.global_position = home
	for a in _animals.get_children():
		print("%s mode %d at %.1f m" % [a.kind, a.mode, a.global_position.distance_to(pl.global_position)])
	pl.zoom = 3.4
	pl._pitch = -0.15
	# Back in a row ahead on dry ground, grazing; then the hero walks straight at them.
	var found := false
	for ring in [0.0, 10.0, 20.0, 30.0]:
		for j in 12:
			var c: Vector3 = home + Vector3.FORWARD.rotated(Vector3.UP, TAU * j / 12.0) * ring
			for k in 24:
				var d := Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 24.0)
				var dry := true
				for t in range(-8, 18, 2):
					var q: Vector3 = c + d * t
					if Game.ground_at(q.x, q.z) < Game.WATER_LEVEL + 0.4:
						dry = false
				if dry and not found:
					found = true
					home = Vector3(c.x, Game.ground_at(c.x, c.z), c.z)
					fwd = d
					right = fwd.cross(Vector3.UP)
					pl._yaw = atan2(-d.x, -d.z)
	print("dry spot found: %s" % found)
	var kinds_left := _animals.get_children()
	for i in kinds_left.size():
		var a: Animal = kinds_left[i]
		var at: Vector3 = home + fwd * (12.0 if a.kind in ["deer", "stag"] else 9.0) + right * (i - kinds_left.size() / 2.0) * 1.4
		a.global_position = Vector3(at.x, Game.ground_at(at.x, at.z), at.z)
		a._idle()
	pl.global_position = home - fwd * 6.0
	await get_tree().create_timer(0.6).timeout
	Animal.fearless = false
	shot.call("grazing")
	var walked := 0.0
	while walked < 5.0:
		await get_tree().process_frame
		var step := 3.0 * get_process_delta_time()
		walked += step
		pl.global_position += fwd * step
		pl.velocity = fwd * 3.0
	shot.call("alert")
	await get_tree().create_timer(1.2).timeout
	shot.call("scatter")
	await get_tree().create_timer(2.5).timeout
	shot.call("after")
	for a in _animals.get_children():
		print("after: %s mode %d at %.1f m, up %.1f" % [a.kind, a.mode, a.global_position.distance_to(pl.global_position), a._climb])


## Test hook (--shot-save): play a little (wake the pets, pick things up,
## build a fire and a lean-to, wander off), save, load it back into a fresh
## world, and check it all came back.
func _test_save() -> void:
	var shot := func(tag: String):
		get_viewport().get_texture().get_image().save_png(Game.screenshot_path.replace(".png", "_%s.png" % tag))
	var pl := Game.player
	if Game.shot_save_loaded:
		await get_tree().create_timer(4.0).timeout
		shot.call("loaded")
		print("loaded: sticks %d stones %d, known %s, quests %s, warmth %.0f" % [Game.inventory.get("Sticks", 0), Game.inventory.get("Stones", 0), Game.known, Game.quests.map(func(q): return q.id), Game.warmth])
		print("loaded: hero at %s, fires %d, lean-tos %d, fox state %d, night %s" % [pl.global_position.round(), get_tree().get_nodes_in_group("campfires").size(), get_tree().get_nodes_in_group("shelters").size(), _fox.state, Game.is_night])
		get_tree().quit()
		return
	pl._end_wake()
	await get_tree().create_timer(30.0).timeout  # through the opening lines
	for c in [_fox, _otter]:
		c.follow()
	var fwd := pl._aim_flat()
	Game.known.append("campfire")
	Game.add_item("Sticks", 7)
	Game.add_item("Stones", 4)
	pl._build("campfire", pl.global_position + fwd * 3.0, 0.0)
	Game.add_item("Sticks", 6)
	Game.add_item("Ferns", 5)
	pl._build("lean_to", pl.global_position + fwd.rotated(Vector3.UP, 1.2) * 4.0, pl._yaw)
	Game.warmth = 63.0
	await get_tree().create_timer(12.0).timeout  # the fire's done; settle starts
	pl.global_position += fwd.rotated(Vector3.UP, -1.0) * 5.0
	await get_tree().create_timer(1.0).timeout
	print("can save: %s" % can_save())
	print("saved: %s" % save_game())
	print("before: sticks %d stones %d, known %s, quests %s, warmth %.0f" % [Game.inventory.get("Sticks", 0), Game.inventory.get("Stones", 0), Game.known, Game.quests.map(func(q): return q.id), Game.warmth])
	print("before: hero at %s" % pl.global_position.round())
	shot.call("saved")
	# Muddle things up, then load into a fresh world.
	Game.inventory.clear()
	Game.warmth = 10.0
	SaveGame.pending = SaveGame.read()
	Game.shot_save_loaded = true
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## Test hook (--shot-map): a walk through the woods, a campfire, the map idea,
## making it, then the little map in the corner and the big one unfolded.
func _test_map() -> void:
	var shot := func(tag: String):
		get_viewport().get_texture().get_image().save_png(Game.screenshot_path.replace(".png", "_%s.png" % tag))
	var pl := Game.player
	pl._end_wake()
	await get_tree().create_timer(36.0).timeout  # through the opening lines
	for c in [_fox, _otter]:
		c.follow()
	var fwd := pl._aim_flat()
	pl._build("campfire", pl.global_position + fwd * 3.0, 0.0)
	# A wander: out toward the Sanctum and round, marking what he sees.
	var start := pl.global_position
	for k in 40:
		var a := k / 40.0 * TAU
		var spot := start.lerp(Vector3.ZERO, 0.5 * sin(a * 0.5)) + Vector3(cos(a) * 25.0, 0, sin(a) * 25.0)
		Game.explore_at(Vector3(spot.x, 0, spot.z))
	_suggest_map()
	await get_tree().create_timer(20.0).timeout
	print("map known %s, quest %s" % [Game.known.has("map"), not Game.quest("map").is_empty()])
	Game.add_item("Charcoal", 1)
	Game.add_item("Birch bark", 2)
	pl.make("map")
	print("has map %s" % Game.has_map())
	await get_tree().create_timer(1.0).timeout
	shot.call("mini")
	_hud.open_map()
	print("frozen while open %s" % pl.frozen)
	await get_tree().create_timer(0.8).timeout
	shot.call("full")
	_hud.close_map()
	await get_tree().create_timer(0.6).timeout
	print("frozen after close %s, map quest left %s" % [pl.frozen, not Game.quest("map").is_empty()])


## The hero model in the world: standing, running, aiming a tool, sitting and
## swimming, each held for a picture from the usual camera.
func _test_hero() -> void:
	var pl := Game.player
	pl._end_wake()
	await get_tree().create_timer(2.0).timeout
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	pl.equip(WeaponData.generate(1, rng))
	pl.global_position = Vector3(30.0, Game.ground_at(30.0, 30.0) + 0.3, 30.0)
	pl._yaw = 2.4
	pl._pitch = -0.25
	await get_tree().create_timer(1.0).timeout
	print("rig %s, states %d" % [pl._rig.name if pl._rig else "none", pl._rig.states().size() if pl._rig else 0])
	var base := Game.screenshot_path.get_basename()
	for state in ["idle", "run", "aim_idle", "sit", "attack"]:
		pl.set_physics_process(false)
		pl._legs.rotation.y = pl._yaw
		pl._torso.rotation.y = pl._yaw
		pl._rig.rotation.y = pl._yaw
		pl._rig.current = ""
		pl._rig.play(state, 1.0, 0.0)
		await get_tree().create_timer(0.6).timeout
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [base, state])
	# From the side, to see the tool in hand.
	pl._rig.current = ""
	pl._rig.play("aim_idle", 1.0, 0.0)
	pl._yaw += 1.3
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png("%s_side.png" % base)
	pl.set_physics_process(true)
	# The real moves, as the game triggers them, caught partway through,
	# out on the open Sanctum floor and seen a little from the side.
	pl.global_position = Vector3(2.0, Game.ground_at(2.0, 3.0) + 0.3, 3.0)
	pl._legs.rotation.y = 0.0
	pl._yaw = 0.9
	pl.zoom = 4.6
	var snap := func(label: String, wait: float) -> void:
		await get_tree().create_timer(wait).timeout
		print("%s: rig %s, action %.2f" % [label, pl._rig.current, pl._action_time])
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [base, label])
	await get_tree().create_timer(0.8).timeout
	pl._try_fire()
	await snap.call("act_shoot", 0.12)
	pl._nova()
	await snap.call("act_cast", 0.35)
	await get_tree().create_timer(0.6).timeout
	pl._dash(Vector3.ZERO)
	await snap.call("act_dodge", 0.2)
	await get_tree().create_timer(0.8).timeout
	pl._hurt_sound_cooldown = 0.0
	pl.take_damage(5.0)
	await snap.call("act_hit", 0.15)
	await get_tree().create_timer(0.6).timeout
	var held := pl.weapon
	pl.weapon = null
	pl._punch_cooldown = 0.0
	for i in 3:
		pl._punch()
		await snap.call("act_punch_%d" % i, 0.2)
		await get_tree().create_timer(0.5).timeout
		pl._punch_cooldown = 0.0
	pl.equip(held)
	pl.take_damage(1000.0)
	await snap.call("act_death", 0.9)
	await get_tree().create_timer(4.5).timeout
	print("respawned alive %s, model visible %s, rig %s" % [pl.alive, pl._model.visible, pl._rig.current])
	# Swim: out in the lake, moving.
	pl.global_position = Vector3(-56.0, Game.WATER_LEVEL - 0.6, -45.0)
	Input.action_press("move_forward")
	await get_tree().create_timer(2.5).timeout
	print("swimming %s, rig state %s" % [pl.swimming, pl._rig.current])
	get_viewport().get_texture().get_image().save_png("%s_swim.png" % base)
	Input.action_release("move_forward")
	get_tree().quit()


## --shot-hill: after the page in the little house, the hum leads up to the
## lookout; the heartstone's beach-run echo gives back Running, the cairn's
## page is read, and the far light rises in the mountains.
func _test_hill() -> void:
	var pl := Game.player
	pl._end_wake()
	var base := Game.screenshot_path.get_basename()
	var shot := func(tag: String):
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [base, tag])
	var look := func(at: Vector3, pitch: float):
		var d := at - pl.global_position
		pl._yaw = atan2(-d.x, -d.z)
		pl._pitch = pitch
	var put := func(at: Vector3):
		pl.global_position = Vector3(at.x, Game.ground_at(at.x, at.z) + 0.3, at.z)
		pl.velocity = Vector3.ZERO
		for c in [_fox, _otter]:
			c.body.position = pl.global_position + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
			c.body.position.y = Game.ground_at(c.body.position.x, c.body.position.z)
	await get_tree().create_timer(30.0).timeout
	for c in [_fox, _otter]:
		if c._zzz:
			c._zzz.queue_free()
		c.body.rotation.z = 0.0
		c.follow()
		c._forage_timer = 999.0
	if _hill == null:
		print("NO HILL")
		get_tree().quit()
		return
	var top := _hill.heartstone.global_position
	print("lookout at %s (height %.1f, %.0f m from the Sanctum), far light at %s" % [_hill.global_position.snapped(Vector3.ONE * 0.1), top.y, Vector2(top.x, top.z).length(), _hill.far_light_at().snapped(Vector3.ONE)])
	Game.start_quest("family", "Finding Home", ["Touch the heartstone", "Find out what happened to your family"])
	Game.set_step("family", 0, "Touch the heartstone", true)
	_home_step = HOME_STEPS.size()
	_lake_stage = 3
	_isle_stage = 2
	# Partway there, looking up at the hill.
	put.call(top - _hill.out * 30.0)
	look.call(top, 0.05)
	_start_hill()
	await get_tree().create_timer(3.0).timeout
	print("hum: stage %d, steps %s" % [_hill_stage, Game.quest("family").steps])
	shot.call("approach")
	# Up at the lookout.
	put.call(_hill.to_global(Vector3(0.4, 0, 2.6)))
	look.call(top, -0.25)
	await get_tree().create_timer(1.5).timeout
	print("arrived: stage %d, stone usable %s, focused %s, steps %s" % [_hill_stage, _hill.heartstone.is_in_group("usables"), pl.focused == _hill.heartstone, Game.quest("family").steps])
	shot.call("arrive")
	_hill.heartstone.use(pl)
	for t in [5.0, 4.0, 4.0]:
		await get_tree().create_timer(t).timeout
		shot.call("echo_%d" % Time.get_ticks_msec())
	await get_tree().create_timer(10.0).timeout
	print("after echo: echoes %s, running %s, stage %d, frozen %s" % [_echoes, Game.skills.has("Running"), _hill_stage, pl.frozen])
	await get_tree().create_timer(18.0).timeout
	print("page usable %s, steps %s" % [_hill.page.is_in_group("usables"), Game.quest("family").steps])
	put.call(_hill.to_global(Vector3(-1.0, 0, 1.8)))
	look.call(_hill.page.global_position, -0.5)
	await get_tree().create_timer(1.0).timeout
	shot.call("cairn")
	_hill.page.use(pl)
	await get_tree().create_timer(15.0).timeout
	print("read: stage %d, backpack %s, far light %s, steps %s" % [_hill_stage, Game.backpack, _far_light != null, Game.quest("family").steps])
	put.call(_hill.to_global(Vector3(2.2, 0, 3.0)))
	look.call(_hill.far_light_at() + Vector3.UP * 30.0, 0.0)
	await get_tree().create_timer(2.0).timeout
	shot.call("far_light")
	# From back at the Sanctum, can it still be seen?
	put.call(Vector3(6, 0, 6))
	look.call(_hill.far_light_at() + Vector3.UP * 40.0, 0.08)
	await get_tree().create_timer(2.0).timeout
	shot.call("far_from_home")
	# Running: a sprint on the flat.
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await get_tree().create_timer(2.0).timeout
	print("running: speed %.2f (story run %.1f), Running xp %.2f" % [Vector2(pl.velocity.x, pl.velocity.z).length(), Player.STORY_RUN_SPEED, Game.skills.get("Running", 0.0)])
	Input.action_release("sprint")
	Input.action_release("move_forward")
	get_tree().quit()
