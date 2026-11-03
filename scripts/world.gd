extends Node3D
## Builds the open world at startup: sky and lighting, terrain, the central Sanctum,
## scattered ruins and flora, and enemy camps whose danger grows with distance.

const CAMP_COUNT := 26
const CAMP_RESPAWN_TIME := 60.0
const WATER_LEVEL := -1.2  # keep in sync with Game.WATER_LEVEL

var _rng := RandomNumberGenerator.new()
var _camps: Array[Dictionary] = []
var _camp_check := 0.0
var _crystal: Node3D
var _stone_mats: Array[StandardMaterial3D] = []
var _leaf_mats: Array[StandardMaterial3D] = []
var _bark: StandardMaterial3D
var _obsidian: StandardMaterial3D
var _iron: StandardMaterial3D
var _rune_mat: StandardMaterial3D
var _gold_rune_mat: StandardMaterial3D
var _fire_mat: StandardMaterial3D
var _env: Environment
var _air_fog: Array = []
var _underwater_blend := 0.0


func _ready() -> void:
	_rng.seed = 20261101
	if Game.story_start:
		Game.wake_point = _find_wake_point()
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
	var pause := PauseMenu.new()
	add_child(pause)
	if Game.shot_help:
		get_tree().create_timer(1.0).timeout.connect(func():
			pause.open()
			pause._menu.visible = false
			pause._help.visible = true)
	if Game.story_start:
		_start_wake(player, hud, facing)
	else:
		Game.notify("Welcome to the Sanctum. Pick a weapon, then head out.", Color(0.6, 0.95, 1.0))

	if Game.shot_demo and Game.ENEMIES_ENABLED:
		_spawn_demo_enemies(player)
	if Game.screenshot_mode:
		_take_screenshot()


# --- Story start -------------------------------------------------------------

const WAKE_DISTANCE := 95.0
var _sanctum_found := false
var _hum_timer := 3.0


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


var _fox: Companion
var _otter: Companion
var _fire_built := false
var _hud: Hud
var _food_at_start := 0


func _start_wake(player: Player, hud: Hud, facing: float) -> void:
	Game.backpack = ["Pocketknife", "Flint", "Canteen", "Dream journal", "Rune marble (humming)"]
	Game.inventory = {}
	Game.skills = {}
	Game.quests.clear()
	Game.ideas.clear()
	Game.food_found = 0
	Game.known.clear()
	_hud = hud
	Game.learned.connect(_on_learned)
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
			get_tree().create_timer(8.0).timeout.connect(func():
				Game.notify("You check your backpack: a pocketknife, flint, a canteen, your dream journal... and a marble that hums.", Color(0.85, 0.9, 1.0))
				_fire_hint()))
	, CONNECT_ONE_SHOT)


## The pets come up with the first plan: the Otter is cold, the Fox spots
## an old fire ring to learn from. Their idea becomes the first quest.
func _fire_hint() -> void:
	_otter.say(["Brrr... I'm SO cold. Can we make a fire? Pleeease?"])
	get_tree().create_timer(3.6).timeout.connect(func():
		_fox.say(["Somebody camped here before us. See that old fire ring?", "Go look. Maybe you'll learn something. For once."])
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
		_otter.say(["Ta-da! Our first house!", "...Okay, it's a house for ants. But it's OURS."])
		get_tree().create_timer(8.0).timeout.connect(func():
			_fox.say(["Hey. That marble of yours won't stop humming.", "It gets louder when you face a certain way. Just saying."])
			Game.start_quest("hum", "The Humming Marble", ["Warm up by the fire", "Follow the hum (it chimes when you face the right way)"], true, "Fox"))


## After the fire, the marble chimes when you face the Sanctum, louder as you
## get close; reaching the Sanctum completes the quest.
func _update_story(delta: float) -> void:
	var p := Game.player
	if not Game.story_start or p == null or p.frozen:
		return
	if not _fire_built and not get_tree().get_nodes_in_group("campfires").is_empty():
		_on_fire_built()
	_update_settle()
	if not Game.quest("hum").is_empty() and Game.warmth > 90.0:
		Game.set_step("hum", 0, "Warm up by the fire", true)
	var dist := Vector2(p.global_position.x, p.global_position.z).length()
	if not _sanctum_found:
		if dist < 22.0 and not Game.quest("hum").is_empty():
			_sanctum_found = true
			Game.notify("The Sanctum... somehow, you've been here before.", Color(0.6, 0.95, 1.0))
			Game.complete_quest("hum")
			Game.start_quest("sanctum", "The Sanctum", ["Take a weapon from the altar"])
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
		Game.start_quest("family", "Finding Home", ["Find out what happened to your family"])


func _process(delta: float) -> void:
	if _crystal:
		_crystal.rotate_y(delta * 0.6)
		_crystal.position.y = 4.4 + sin(Time.get_ticks_msec() * 0.001) * 0.25
	_update_underwater_view(delta)
	_update_story(delta)
	_camp_check -= delta
	if _camp_check <= 0.0:
		_camp_check = 1.0
		_update_camps()


# --- Look & feel -------------------------------------------------------------

func _make_materials() -> void:
	for c in [Color(0.55, 0.52, 0.47), Color(0.47, 0.45, 0.42), Color(0.64, 0.6, 0.52)]:
		_stone_mats.append(MeshKit.mat(c, 0.95))
	for c in [Color(0.24, 0.5, 0.3), Color(0.34, 0.58, 0.26), Color(0.86, 0.5, 0.2), Color(0.2, 0.46, 0.42)]:
		_leaf_mats.append(MeshKit.mat(c, 0.9))
	_leaf_mats.append(MeshKit.glow(Color(0.55, 0.42, 1.0), 0.9))
	_bark = MeshKit.mat(Color(0.33, 0.24, 0.17), 0.95)
	_obsidian = MeshKit.mat(Color(0.14, 0.14, 0.19), 0.25, 0.6)
	_iron = MeshKit.mat(Color(0.22, 0.22, 0.25), 0.4, 0.8)
	_rune_mat = MeshKit.glow(Color(0.35, 0.9, 1.0), 4.0)
	_gold_rune_mat = MeshKit.glow(Color(1.0, 0.75, 0.3), 3.0)
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
	var moon := MeshKit.part(self, MeshKit.sphere(14.0, -1.0, 24, 12), _sky_mat(Color(0.92, 0.95, 1.0), 6.0), toward_moon * 520.0)
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
		if d < 15.0 or h < -0.2 or h > 24.0:
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
		buckets[_rng.randi() % 3].append([Transform3D(basis, Vector3(x, h - 0.02, z)), green])
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
	_add_cylinder(body, 11.0, 11.5, 0.8, Vector3(0, 0.3, 0), _stone_mats[2], 32)
	_add_cylinder(body, 6.0, 6.3, 0.4, Vector3(0, 0.85, 0), _stone_mats[0], 32)
	var rune_ring := TorusMesh.new()
	rune_ring.inner_radius = 5.3
	rune_ring.outer_radius = 5.55
	rune_ring.rings = 64
	MeshKit.part(body, rune_ring, _rune_mat, Vector3(0, 1.06, 0))
	for i in 8:
		var a := TAU * i / 8.0
		var base := Vector3(cos(a) * 9.0, 0.7, sin(a) * 9.0)
		var h := 6.0 if i % 2 == 0 else 3.5
		_add_cylinder(body, 0.55, 0.65, h, base + Vector3(0, h * 0.5, 0), _stone_mats[1], 10)
		MeshKit.part(body, MeshKit.cyl(0.62, 0.62, 0.15, 10), _rune_mat, base + Vector3(0, h * 0.6, 0))
		if i % 2 == 0:
			_add_box(body, Vector3(1.6, 0.4, 1.6), base + Vector3(0, h + 0.2, 0), Vector3(0, a, 0), _stone_mats[2])

	_crystal = Node3D.new()
	_crystal.position = Vector3(0, 4.4, 0)
	add_child(_crystal)
	MeshKit.part(_crystal, MeshKit.sphere(0.9, 3.2, 6, 2), MeshKit.glow(Color(0.4, 0.9, 1.0), 3.0))
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 0.9, 1.0)
	light.light_energy = 2.5
	light.omni_range = 20.0
	_crystal.add_child(light)
	Audio.attach_loop(_crystal, "loop_crystal", 0.0, 28.0, 8.0)

	var title := Label3D.new()
	title.text = "THE SANCTUM"
	title.font_size = 72
	title.outline_size = 16
	title.pixel_size = 0.008
	title.modulate = Color(0.75, 0.95, 1.0)
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.position = Vector3(0, 7.2, 0)
	add_child(title)


func _place_starter_loot() -> void:
	var picks := [["Hand Cannon", 1, Vector3(-3.2, 1.05, 1.6)], ["Scattergun", 1, Vector3(0, 1.05, 3.0)], ["Rune SMG", 2, Vector3(3.2, 1.05, 1.6)]]
	for pick in picks:
		LootDrop.spawn(self, WeaponData.generate(1, Game.rng, 0.0, pick[0], pick[1]), pick[2], false)


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
		if p.y < WATER_LEVEL + 0.5 or p.y > 22.0:
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
	Gatherable.spawn(self, _seated(center + ahead * 4.6 + side * 2.8, 0.7, 0.0), "fire_ring", _rng)
	var starter := [["sticks", 6.0, -1.8], ["stones", 8.5, 2.2], ["ferns", 10.0, -3.8]]
	for s in starter:
		var p: Vector3 = center + ahead * float(s[1]) + side * float(s[2])
		p.y = Game.ground_at(p.x, p.z)
		Gatherable.spawn(self, p, s[0], _rng)
	var near := [["sticks", 4], ["stones", 3], ["berries", 1], ["ferns", 3]]
	for entry in near:
		for i in entry[1]:
			var a := _rng.randf() * TAU
			var p := center + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(9.0, 22.0)
			p.y = Game.ground_at(p.x, p.z)
			Gatherable.spawn(self, p, entry[0], _rng)
	var far := [["sticks", 70], ["stones", 40], ["berries", 30], ["ferns", 45]]
	for entry in far:
		var placed := 0
		var tries := 0
		while placed < entry[1] and tries < 2000:
			tries += 1
			var a := _rng.randf() * TAU
			var p := center + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(10.0, FOREST_RADIUS)
			p.y = Game.ground_at(p.x, p.z)
			if p.y < WATER_LEVEL + 0.2 or _forest_amount(p.x, p.z) < 0.3:
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
		if h < WATER_LEVEL + 0.1 or _forest_amount(p.x, p.z) < 0.1:
			continue
		if _rng.randf() > (clusters.get_noise_2d(p.x, p.z) * 0.5 + 0.55) * smoothstep(radius, radius * 0.6, d):
			continue
		var look: Array = style.call(p)
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


func _scatter_props() -> void:
	var placed := 0
	var attempts := 0
	while placed < 340 and attempts < 3000:
		attempts += 1
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * 160.0 + 20.0
		var p := Vector3(cos(a) * d, 0.0, sin(a) * d)
		p.y = Game.height_at(p.x, p.z)
		if p.y < WATER_LEVEL + 0.4 or _near_wake(p, GLADE_RADIUS + 5.0):
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


func _ruin(p: Vector3) -> void:
	var stone: StandardMaterial3D = _stone_mats[_rng.randi() % _stone_mats.size()]
	match _rng.randi() % 3:
		0:
			var body := _static_at(_seated(p, 0.7, 0.1), _rng.randf() * TAU)
			body.rotation.z = _rng.randf_range(-0.2, 0.2)
			var h := _rng.randf_range(2.5, 6.5)
			_add_cylinder(body, 0.45, 0.55, h, Vector3(0, h * 0.5 - 0.3, 0), stone, 8)
			if _rng.randf() < 0.5:
				MeshKit.part(body, MeshKit.cyl(0.5, 0.5, 0.12, 8), _rune_mat, Vector3(0, h * 0.55, 0))
		1:
			var w := _rng.randf_range(3.0, 7.0)
			var body := _static_at(_seated(p, w * 0.5, 0.0), _rng.randf() * TAU)
			var h := _rng.randf_range(1.5, 3.5)
			_add_box(body, Vector3(w, h, 0.7), Vector3(0, h * 0.5 - 0.3, 0), Vector3.ZERO, stone)
			_add_box(body, Vector3(w * 0.4, h * 0.6, 0.7), Vector3(w * 0.3, h - 0.3 + h * 0.3, 0), Vector3.ZERO, stone)
			var strip: StandardMaterial3D = _gold_rune_mat if _rng.randf() < 0.3 else _rune_mat
			MeshKit.part(body, MeshKit.box(Vector3(w * 0.8, 0.08, 0.72)), strip, Vector3(0, h * 0.6, 0))
		_:
			var span := _rng.randf_range(3.0, 4.5)
			var body := _static_at(_seated(p, span * 0.5 + 0.5, 0.0), _rng.randf() * TAU)
			var h := _rng.randf_range(3.5, 5.0)
			for side in [-1.0, 1.0]:
				_add_box(body, Vector3(0.8, h, 0.8), Vector3(span * 0.5 * side, h * 0.5 - 0.2, 0), Vector3.ZERO, stone)
			_add_box(body, Vector3(span + 1.4, 0.7, 1.0), Vector3(0, h, 0), Vector3.ZERO, stone)
			MeshKit.part(body, MeshKit.box(Vector3(span * 0.6, 0.12, 1.02)), _rune_mat, Vector3(0, h, 0))


func _monolith(p: Vector3) -> void:
	var body := _static_at(_seated(p, 0.8, 0.2), _rng.randf() * TAU)
	_add_box(body, Vector3(1.4, 7.0, 0.7), Vector3(0, 3.2, 0), Vector3.ZERO, _obsidian)
	for k in 4:
		MeshKit.part(body, MeshKit.box(Vector3(1.0 - k * 0.15, 0.08, 0.72)), _rune_mat, Vector3(0, 1.5 + k * 1.3, 0))
	MeshKit.part(body, MeshKit.box(Vector3(0.08, 5.5, 0.72)), _rune_mat, Vector3(0, 3.6, 0))
	MeshKit.part(body, MeshKit.sphere(0.4, 1.2, 4, 2), _rune_mat, Vector3(0, 8.0, 0))
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 0.9, 1.0)
	light.light_energy = 1.5
	light.omni_range = 9.0
	light.position = Vector3(0, 4.0, 1.0)
	body.add_child(light)
	var hum := Audio.attach_loop(body, "loop_crystal", -8.0, 16.0, 3.0)
	if hum:
		hum.position.y = 4.0
		hum.pitch_scale = _rng.randf_range(0.7, 0.9)


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
