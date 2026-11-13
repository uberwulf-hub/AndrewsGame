extends Node3D
## Title screen: "Finding Home", a moonlit forest campfire with the hero sitting
## on a mossy log, the Fox and the Otter beside him, and Play / Options /
## Load Game / Quit. Play fades out into the dream.

const NEXT_SCENE := "res://scenes/dream.tscn"
const GAME_SCENE := "res://scenes/main.tscn"
const CREAM := Color(0.97, 0.9, 0.74)
const WOOD := Color(0.42, 0.26, 0.15)
const WOOD_DARK := Color(0.24, 0.14, 0.08)

var _camera: Camera3D
var _fire_light: OmniLight3D
var _fade: ColorRect
var _options: PanelContainer
var _help: PanelContainer
var _t := 0.0
var _leaving := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_scene()
	_build_ui()
	var music := AudioStreamPlayer.new()
	music.bus = "Music"
	music.volume_db = 2.0
	if ResourceLoader.exists("res://audio/music/sanctum.wav"):
		music.stream = load("res://audio/music/sanctum.wav")
	add_child(music)
	music.play()
	if Game.screenshot_mode:
		if Game.shot_help:
			_on_help()
		await get_tree().create_timer(Game.screenshot_delay).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(Game.screenshot_path)
		get_tree().quit()


func _process(delta: float) -> void:
	_t += delta
	# Firelight flicker and a slow breathing drift of the camera.
	_fire_light.light_energy = 2.6 + sin(_t * 13.0) * 0.25 + sin(_t * 7.3) * 0.35 + sin(_t * 23.0) * 0.12
	_camera.position = Vector3(sin(_t * 0.17) * 0.15, 1.45 + sin(_t * 0.23) * 0.05, 5.6)
	_camera.look_at(Vector3(0.1, 1.15, 0))


# --- Scene -------------------------------------------------------------------

func _build_scene() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.02, 0.03, 0.08)
	sky_mat.sky_horizon_color = Color(0.07, 0.1, 0.18)
	sky_mat.ground_bottom_color = Color(0.01, 0.01, 0.02)
	sky_mat.ground_horizon_color = Color(0.05, 0.06, 0.1)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.38, 0.6)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 1.1
	env.glow_hdr_threshold = 0.7
	env.glow_bloom = 0.15
	env.ssao_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.08, 0.15)
	env.fog_density = 0.03
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.03
	env.volumetric_fog_albedo = Color(0.55, 0.65, 0.95)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-38, 160, 0)
	moon.light_color = Color(0.6, 0.72, 1.0)
	moon.light_energy = 0.6
	moon.light_volumetric_fog_energy = 4.0
	moon.shadow_enabled = true
	add_child(moon)
	var moon_disc := MeshKit.part(self, MeshKit.sphere(3.0, -1.0, 20, 10), _unshaded(Color(0.95, 0.97, 1.0), 5.0), Vector3(1.8, 15.0, -40.0))
	moon_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_camera = Camera3D.new()
	_camera.fov = 50.0
	add_child(_camera)
	_camera.current = true

	var ground := MeshKit.part(self, MeshKit.cyl(40.0, 40.0, 0.1, 40), MeshKit.mat(Color(0.12, 0.1, 0.07)), Vector3(0, -0.05, 0))
	ground.name = "Ground"
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bark := MeshKit.mat(Color(0.26, 0.19, 0.14), 0.95)
	var moss := MeshKit.mat(Color(0.2, 0.34, 0.14), 1.0)
	var leaves := MeshKit.mat(Color(0.08, 0.17, 0.12), 0.95)
	# Two huge trunks framing the shot, then rows of trees fading into the mist.
	for side in [-1.0, 1.0]:
		var x: float = 4.6 * side
		MeshKit.part(self, MeshKit.cyl(0.85, 1.25, 14.0, 12), bark, Vector3(x, 7.0, -0.5))
		MeshKit.part(self, MeshKit.box(Vector3(0.12, 3.0, 1.0)), moss, Vector3(x - 0.75 * side, 3.0, 0.1), Vector3(0, 0, 0.05 * side))
	for i in 46:
		var p := Vector3(rng.randf_range(-16, 16), 0, rng.randf_range(-30, -4))
		if absf(p.x) < 2.5 and p.z > -10.0:
			continue
		var h := rng.randf_range(9.0, 16.0)
		MeshKit.part(self, MeshKit.cyl(0.18, 0.4, h, 7), bark, p + Vector3(0, h * 0.5, 0))
		for k in 3:
			var r := rng.randf_range(1.4, 2.6)
			MeshKit.part(self, MeshKit.sphere(r, r * 1.3, 8, 5), leaves, p + Vector3(rng.randf_range(-1, 1), h * rng.randf_range(0.6, 1.0), rng.randf_range(-1, 1)))

	# Mossy log seat.
	var log_mesh := MeshKit.part(self, MeshKit.cyl(0.32, 0.36, 3.0, 10), bark, Vector3(0.4, 0.3, -0.2), Vector3(0, 0.15, PI / 2))
	log_mesh.name = "Log"
	MeshKit.part(self, MeshKit.box(Vector3(2.2, 0.08, 0.5)), moss, Vector3(0.6, 0.62, -0.2), Vector3(0, 0.15, 0))

	# Campfire: ring of stones, crossed logs, flames, embers and warm light.
	var fire_at := Vector3(-1.9, 0, 1.4)
	var stone := MeshKit.mat(Color(0.42, 0.4, 0.38), 0.9)
	for k in 9:
		var a := TAU * k / 9.0
		var s := MeshKit.part(self, MeshKit.sphere(0.2, 0.26, 7, 4), stone, fire_at + Vector3(cos(a) * 0.62, 0.08, sin(a) * 0.62))
		s.scale = Vector3(rng.randf_range(0.9, 1.3), 1.0, rng.randf_range(0.9, 1.3))
	for k in 4:
		var log := MeshKit.part(self, MeshKit.cyl(0.07, 0.08, 0.9, 6), MeshKit.mat(Color(0.3, 0.2, 0.12)), fire_at + Vector3(0, 0.18, 0), Vector3(0.9, TAU * k / 4.0, 0))
		log.name = "FireLog"
	var flame := CPUParticles3D.new()
	var flame_mesh := MeshKit.sphere(0.12, 0.32, 6, 3)
	flame_mesh.material = MeshKit.glow(Color(1.0, 0.55, 0.15), 6.0, true)
	flame.mesh = flame_mesh
	flame.amount = 46
	flame.lifetime = 0.7
	flame.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flame.emission_sphere_radius = 0.2
	flame.direction = Vector3.UP
	flame.spread = 12.0
	flame.initial_velocity_min = 0.8
	flame.initial_velocity_max = 1.6
	flame.gravity = Vector3(0, 0.5, 0)
	flame.scale_amount_min = 0.6
	flame.scale_amount_max = 1.3
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0))
	flame.scale_amount_curve = shrink
	flame.color = Color(1.0, 0.75, 0.35)
	flame.position = fire_at + Vector3(0, 0.25, 0)
	add_child(flame)
	var embers := CPUParticles3D.new()
	var ember_mesh := MeshKit.sphere(0.015, -1.0, 4, 2)
	ember_mesh.material = MeshKit.glow(Color(1.0, 0.6, 0.2), 8.0)
	embers.mesh = ember_mesh
	embers.amount = 30
	embers.lifetime = 2.5
	embers.direction = Vector3.UP
	embers.spread = 25.0
	embers.initial_velocity_min = 0.6
	embers.initial_velocity_max = 1.4
	embers.gravity = Vector3(0.2, 0.1, 0)
	embers.position = fire_at + Vector3(0, 0.4, 0)
	add_child(embers)
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.6, 0.28)
	_fire_light.omni_range = 9.0
	_fire_light.shadow_enabled = true
	_fire_light.position = fire_at + Vector3(0, 0.7, 0)
	add_child(_fire_light)
	var crackle := Node3D.new()
	crackle.position = fire_at
	add_child(crackle)
	Audio.attach_loop(crackle, "loop_fire", 0.0, 20.0, 4.0)

	# The hero on the log, the Fox on the log beside him, the Otter in front.
	# Figures face -Z; the camera is at +Z, so turn them around to face it.
	var hero := Figure.hero()
	hero.position = Vector3(0.0, 0.0, 0.25)
	hero.rotation.y = PI - 0.2
	add_child(hero)
	if hero._rig and hero._rig.has_state("sit"):
		hero._rig.play("sit", 1.0, 0.0)
		hero.set_process(false)  # keep the pose instead of the walk/idle picker
		hero.position = Vector3(0.0, 0.18, -0.05)
		_seat_on_log.call_deferred(hero)
	var fox := Critter.fox()
	fox.position = Vector3(1.2, 0.64, -0.25)
	fox.rotation.y = PI - 0.6
	fox.scale = Vector3.ONE * 1.25
	add_child(fox)
	var otter := Critter.otter()
	otter.position = Vector3(1.7, 0.0, 0.9)
	otter.rotation.y = PI - 0.9
	otter.scale = Vector3.ONE * 1.35
	add_child(otter)

	# Leaves and pebbles on the ground.
	var leaf_mesh := NatureKit.leaf()
	var leaf_mats: Array[StandardMaterial3D] = []
	for c in [Color(0.45, 0.27, 0.12), Color(0.55, 0.38, 0.15), Color(0.3, 0.22, 0.12)]:
		var m := MeshKit.mat(c, 0.9)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		leaf_mats.append(m)
	for k in 220:
		var l := MeshKit.part(self, leaf_mesh, leaf_mats[k % 3], Vector3(rng.randf_range(-6, 6), 0.01, rng.randf_range(-3, 4)), Vector3(0, rng.randf() * TAU, 0))
		l.scale = Vector3.ONE * rng.randf_range(1.0, 2.2)
	var fireflies := CPUParticles3D.new()
	var fly_mesh := MeshKit.sphere(0.03, -1.0, 4, 2)
	fly_mesh.material = MeshKit.glow(Color(1.0, 0.92, 0.5), 6.0)
	fireflies.mesh = fly_mesh
	fireflies.amount = 40
	fireflies.lifetime = 8.0
	fireflies.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fireflies.emission_box_extents = Vector3(7, 2, 4)
	fireflies.spread = 180.0
	fireflies.initial_velocity_min = 0.05
	fireflies.initial_velocity_max = 0.25
	fireflies.gravity = Vector3.ZERO
	fireflies.position = Vector3(0, 2.2, -1.5)
	add_child(fireflies)


func _unshaded(color: Color, energy: float) -> StandardMaterial3D:
	var m := MeshKit.glow(color, energy)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_fog = true
	return m


# --- Menu --------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)

	var title_font := SystemFont.new()
	title_font.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Book Antiqua", "Times New Roman", "serif"])
	title_font.font_weight = 800
	var title := _text("FINDING HOME", title_font, 112, CREAM)
	title.add_theme_color_override("font_outline_color", Color(0.3, 0.17, 0.08))
	title.add_theme_constant_override("outline_size", 22)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("shadow_offset_y", 8)
	_anchor(title, Vector2(0.5, 0.0), Vector2(-700, 40), Vector2(1400, 140))
	root.add_child(title)
	var sub := _text("A Whispering Woods Adventure", title_font, 44, CREAM)
	sub.add_theme_color_override("font_outline_color", Color(0.3, 0.17, 0.08))
	sub.add_theme_constant_override("outline_size", 12)
	_anchor(sub, Vector2(0.5, 0.0), Vector2(-500, 170), Vector2(1000, 60))
	root.add_child(sub)

	var play := _wood_button("▶  PLAY", 46, Vector2(360, 96))
	_anchor(play, Vector2(0.5, 1.0), Vector2(-180, -230), Vector2(360, 96))
	play.pressed.connect(_on_play)
	root.add_child(play)
	var row := [["OPTIONS", _on_options], ["HELP", _on_help], ["LOAD GAME", _on_load], ["QUIT", func(): get_tree().quit()]]
	for i in row.size():
		var b := _wood_button(row[i][0], 26, Vector2(230, 60))
		_anchor(b, Vector2(0.5, 1.0), Vector2(-512 + i * 265, -112), Vector2(230, 60))
		b.pressed.connect(row[i][1])
		root.add_child(b)
		if row[i][0] == "LOAD GAME":
			b.tooltip_text = ("Saved " + SaveGame.saved_when()) if SaveGame.exists() else "No saved games yet"
	play.grab_focus()

	_options = _build_options()
	root.add_child(_options)
	_options.visible = false
	_help = _build_help()
	root.add_child(_help)
	_help.visible = false

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 1.6)


func _build_options() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _plank(WOOD_DARK.lerp(Color.BLACK, 0.2), 0.95))
	_anchor(panel, Vector2(0.5, 0.5), Vector2(-260, -150), Vector2(520, 300))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	var heading := _text("Options", null, 34, CREAM)
	box.add_child(heading)
	var vol_label := _text("Volume  %d%%" % roundi(Audio.master_volume * 100.0), null, 22, CREAM)
	box.add_child(vol_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Audio.master_volume
	slider.custom_minimum_size = Vector2(440, 30)
	slider.value_changed.connect(func(v: float):
		Audio.set_master_volume(v)
		vol_label.text = "Volume  %d%%" % roundi(v * 100.0))
	box.add_child(slider)
	var full := CheckButton.new()
	full.text = "Fullscreen"
	full.add_theme_font_size_override("font_size", 22)
	full.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	full.toggled.connect(func(on: bool):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED))
	box.add_child(full)
	var back := _wood_button("BACK", 22, Vector2(160, 50))
	back.pressed.connect(func(): panel.visible = false)
	box.add_child(back)
	return panel


func _on_play() -> void:
	if _leaving:
		return
	_leaving = true
	Audio.play("ui_notify", null, -6.0, 0.8)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 1.2)
	tw.tween_callback(func(): get_tree().change_scene_to_file(NEXT_SCENE))


func _build_help() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _plank(WOOD_DARK.lerp(Color.BLACK, 0.2), 0.95))
	_anchor(panel, Vector2(0.5, 0.5), Vector2(-330, -215), Vector2(660, 520))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	box.add_child(_text("Controls", null, 34, CREAM))
	box.add_child(Hud.controls_grid(CREAM, 17, 1))
	var back := _wood_button("BACK", 22, Vector2(160, 50))
	back.pressed.connect(func(): panel.visible = false)
	box.add_child(back)
	return panel


func _on_options() -> void:
	_help.visible = false
	_options.visible = not _options.visible


func _on_help() -> void:
	_options.visible = false
	_help.visible = not _help.visible


func _on_load() -> void:
	var data := SaveGame.read()
	if data.is_empty() or _leaving:
		Audio.play("dry_fire", null, -10.0, 1.4)
		return
	_leaving = true
	SaveGame.pending = data
	Game.story_start = true
	Audio.play("ui_notify", null, -6.0, 0.8)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 1.2)
	tw.tween_callback(func(): get_tree().change_scene_to_file(GAME_SCENE))


func _text(s: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = s
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if font:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A chunky wooden plank button with a cream label, lighter on hover.
func _wood_button(label: String, size: int, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", Color(1, 0.97, 0.85))
	b.add_theme_color_override("font_outline_color", WOOD_DARK)
	b.add_theme_constant_override("outline_size", 6)
	b.add_theme_stylebox_override("normal", _plank(WOOD, 1.0))
	b.add_theme_stylebox_override("hover", _plank(WOOD.lightened(0.15), 1.0))
	b.add_theme_stylebox_override("pressed", _plank(WOOD.darkened(0.15), 1.0))
	b.add_theme_stylebox_override("focus", _plank(WOOD.lightened(0.1), 1.0, Color(0.95, 0.85, 0.55)))
	return b


func _plank(color: Color, alpha: float, border := Color(0.6, 0.6, 0.58)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(color, alpha)
	s.border_color = border
	s.set_border_width_all(5)
	s.set_corner_radius_all(18)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 8
	s.content_margin_left = 20
	s.content_margin_right = 20
	return s


func _anchor(c: Control, anchor: Vector2, offset: Vector2, box_size: Vector2) -> void:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + box_size.x
	c.offset_bottom = offset.y + box_size.y


## Sits the hero's hips on top of the log, whatever rig he is (each model's sit
## pose puts the hips at a different height), once the pose has been applied.
func _seat_on_log(hero: Node3D) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var sk: Skeleton3D = hero._rig.skeleton
	var hips := CharacterRig.find_bone(sk, "hips")
	if hips < 0:
		return
	var at := sk.global_transform * sk.get_bone_global_pose(hips).origin
	# The log's top is at about y 0.66 and its middle at z -0.2: hips just above
	# the bark, a touch in front of the middle.
	hero.global_position += Vector3(0.0, 0.6 - at.y, -0.12 - at.z)
