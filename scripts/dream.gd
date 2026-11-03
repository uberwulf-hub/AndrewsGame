extends Node3D
## The opening dream: a ~90 second in-engine cutscene of the life the player dreamed.
## Meeting their mate, adventures, raising a family with their two pets (the Fox and
## the Otter), a rainy season, then the dream softly fading away at dusk. Nearly
## wordless on purpose: it should feel half-remembered, and blame no one. Ends
## with "Wake up." and loads the world. Any key skips.
##
## Scene timings match the dream score in MusicThemes._dream().

const NEXT_SCENE := "res://scenes/main.tscn"
const MEADOW := Vector3(0, 0, 0)
const CLIFF := Vector3(160, 0, 0)
const HOME := Vector3(700, 0, 0)  # far enough that its hills never block the cliff's sea view
const HOME2 := Vector3(1200, 0, 0)
const HOME3 := Vector3(1700, 0, 0)
const GARDEN := Vector3(-450, 0, 0)
const PATH_TOP := 0.065  # top of the garden's paths, so feet stand on them

const MOODS := {
	"warm": [Color(0.42, 0.56, 0.9), Color(1.0, 0.8, 0.65), Color(1.0, 0.85, 0.65), 1.3, Color(1.0, 0.88, 0.78), 0.006, Color(1.0, 0.96, 0.88), 1.1, 0.3],
	"sunset": [Color(0.35, 0.35, 0.72), Color(1.0, 0.55, 0.35), Color(1.0, 0.6, 0.35), 1.7, Color(1.0, 0.68, 0.5), 0.004, Color(1.05, 0.93, 0.82), 1.2, 0.35],
	"golden": [Color(0.45, 0.58, 0.88), Color(1.0, 0.82, 0.6), Color(1.0, 0.82, 0.55), 1.5, Color(1.0, 0.85, 0.68), 0.005, Color(1.05, 0.97, 0.85), 1.15, 0.32],
	"gloom": [Color(0.28, 0.32, 0.42), Color(0.5, 0.53, 0.6), Color(0.65, 0.7, 0.85), 0.45, Color(0.48, 0.52, 0.6), 0.02, Color(0.82, 0.9, 1.0), 0.55, 0.15],
	"dusk": [Color(0.3, 0.32, 0.55), Color(0.86, 0.64, 0.62), Color(0.88, 0.76, 0.9), 0.65, Color(0.62, 0.56, 0.72), 0.012, Color(0.97, 0.94, 1.03), 0.8, 0.32],
	"white": [Color(1, 1, 1), Color(1.0, 0.97, 0.92), Color(1.0, 0.98, 0.94), 2.2, Color(1.0, 0.97, 0.92), 0.018, Color(1.1, 1.08, 1.02), 0.6, 0.5],
}

var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _camera: Camera3D
var _look := Vector3.ZERO
var _overlay: ShaderMaterial
var _caption: Label
var _caption_tween: Tween
var _fade: ColorRect
var _music: AudioStreamPlayer
var _rain: CPUParticles3D
var _rain_audio: AudioStreamPlayer
var _motes: CPUParticles3D
var _window_mats: Array[StandardMaterial3D] = []
var _window_lights: Array[OmniLight3D] = []
var _door: Node3D
var _circlers: Array = []
var _leaving := false

var _hero: Figure
var _mate: Figure
var _fox: Critter
var _otter: Critter


func _ready() -> void:
	if Game.screenshot_mode and Game.dream_shots.is_empty():
		get_tree().change_scene_to_file.call_deferred(NEXT_SCENE)
		return
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_build_environment()
	_build_ui()
	_build_meadow()
	_build_cliff()
	_build_garden()
	_build_home()
	_build_home2()
	_build_home3()
	_build_cast()
	_build_weather()
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.volume_db = 8.0
	if ResourceLoader.exists("res://audio/music/dream.wav"):
		var stream := load("res://audio/music/dream.wav") as AudioStreamWAV
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
		_music.stream = stream
	add_child(_music)
	if Game.screenshot_mode:
		_schedule_screenshots()
	_play()


func _play() -> void:
	_music.play()
	await _meeting()
	await _adventures()
	await _family()
	await _growing()
	await _struggles()
	await _fading()
	await _searching()
	await _waking()
	_finish()


# --- Scenes ------------------------------------------------------------------

func _meeting() -> void:
	_set_sun(Vector3(-25, -35, 0))
	_mood("warm", 0.0)
	_show([_hero, _mate])
	# They come around the inner ring path from either side and meet on the main walk.
	var ring := 7.1
	var on_ring := func(deg: float) -> Vector3:
		return GARDEN + Vector3(sin(deg_to_rad(deg)) * ring, PATH_TOP, cos(deg_to_rad(deg)) * ring)
	_place(_hero, on_ring.call(-75.0), 0.0)
	_place(_mate, on_ring.call(75.0), 0.0)
	_shot(GARDEN + Vector3(0, 2.6, 34), GARDEN + Vector3(2.2, 1.75, 12.4), GARDEN + Vector3(0, 2.6, 20), GARDEN + Vector3(0, 1.55, 7.1), 12.0)
	_fade_to(0.0, 2.5)
	_at(0.8, func(): _say("You dreamed you lived a whole life.", 3.6))
	_at(1.5, func():
		_hero.walk_to(on_ring.call(-45.0), 2.4)
		_mate.walk_to(on_ring.call(45.0), 2.4)
	)
	_at(3.9, func():
		_hero.walk_to(on_ring.call(-18.0), 2.2)
		_mate.walk_to(on_ring.call(18.0), 2.2)
	)
	_at(6.1, func():
		_hero.walk_to(GARDEN + Vector3(-0.6, PATH_TOP, ring), 1.9)
		_mate.walk_to(GARDEN + Vector3(0.6, PATH_TOP, ring), 1.9)
	)
	_at(8.3, func():
		_hero.face(_mate.position)
		_mate.face(_hero.position)
		_hero.raise_arms(0.0, 0.7)
		_mate.raise_arms(0.7, 0.0)
	)
	_at(9.0, func(): FX.burst(GARDEN + Vector3(0, 2.0, ring), Color(1.0, 0.45, 0.55), 40, 3.5, 0.06))
	await _wait(12.0)


func _adventures() -> void:
	await _cut(func():
		_set_sun(Vector3(-8, 90, 0))
		_mood("sunset", 0.0)
		_hero.raise_arms(0, 0, 0.01)
		_mate.raise_arms(0, 0, 0.01)
		_hero.position = CLIFF + Vector3(-10, 0, -0.6)
		_mate.position = CLIFF + Vector3(-10, 0, 0.6)
		_shot(CLIFF + Vector3(-17, 3.0, 5.0), CLIFF + Vector3(4, 2.4, 3.5), CLIFF + Vector3(10, 1.0, 0), CLIFF + Vector3(40, -2.0, 0), 11.6)
	)
	_hero.walk_to(CLIFF + Vector3(12.5, 0, -0.5), 5.5)
	_mate.walk_to(CLIFF + Vector3(12.5, 0, 0.5), 5.5)
	_at(4.0, _lanterns)
	_at(5.8, func(): _hero.raise_arms(0.0, 1.9))
	await _wait(11.65)


func _family() -> void:
	await _cut(func():
		_set_sun(Vector3(-35, -25, 0))
		_mood("golden", 0.0)
		_place(_hero, HOME + Vector3(-0.6, 0.2, 3.7), PI)
		_place(_mate, HOME + Vector3(0.6, 0.2, 3.7), PI)
		_hero.raise_arms(0.0, 0.25, 0.01)
		_mate.raise_arms(0.25, 0.0, 0.01)
		_show([_fox, _otter])
		var yard := HOME + Vector3(-3.5, 0, 8.0)
		_circle(_fox, yard, 2.4, 1.5, PI * 0.45)
		_circle(_otter, yard, 1.6, 1.5, PI * 1.45)
		_shot(HOME + Vector3(-11, 3.2, 15), HOME + Vector3(-2, 3.4, 15), HOME + Vector3(-2, 1.0, 6), HOME + Vector3(0, 1.4, 4.5), 7.6)
	)
	await _wait(7.65)


## The second home: the best years, the Fox and the Otter tumbling in the yard.
func _growing() -> void:
	await _cut(func():
		_stop_circling()
		_place(_hero, HOME2 + Vector3(-1.2, 0, 6.2), 0.4)
		_place(_mate, HOME2 + Vector3(-0.5, 0, 6.3), 0.4)
		_hero.raise_arms(0.0, 0.0, 0.01)
		_mate.raise_arms(0.0, 0.0, 0.01)
		var yard := HOME2 + Vector3(-3.6, 0, 8.4)
		_circle(_fox, yard, 2.8, 1.5, PI * 0.45)
		_circle(_otter, yard, 1.5, 1.5, PI * 1.45)
		_shot(HOME2 + Vector3(-12, 3.0, 17), HOME2 + Vector3(-1, 3.2, 17.5), HOME2 + Vector3(-3, 1.0, 7), HOME2 + Vector3(-1.5, 1.4, 6), 7.6)
	)
	_at(3.8, func(): _say("Those were the best years.", 3.2))
	await _wait(7.65)


func _struggles() -> void:
	await _cut(func():
		_mood("gloom", 0.0)
		_set_rain(true)
		_motes.emitting = false
		_stop_circling()
		_place(_fox, HOME2 + Vector3(-2.2, 0.2, 4.2), PI)
		_place(_otter, HOME2 + Vector3(0.1, 0.2, 4.2), PI)
		_place(_hero, HOME2 + Vector3(-1.4, 0.2, 3.9), PI)
		_place(_mate, HOME2 + Vector3(-0.6, 0.2, 3.8), PI)
		_hero.raise_arms(0, 0, 0.01)
		_mate.raise_arms(0, 0, 0.01)
		_set_windows(Color(1.0, 0.75, 0.4), 0.6, 0.01)
		_shot(HOME2 + Vector3(-6, 2.2, 17), HOME2 + Vector3(-4.5, 2.0, 14.5), HOME2 + Vector3(-2.5, 1.5, 9), HOME2 + Vector3(-1, 1.5, 6), 11.6)
	)
	await _wait(11.65)


## The last home at dusk. The Fox and the Otter play in the yard, she waves
## from the warm doorway. Then the dream thins like mist and she softly
## dissolves into light; the windows stay warm. Nobody leaves anybody; the
## dream just ends.
func _fading() -> void:
	await _cut(func():
		_set_rain(false)
		_motes.emitting = true
		_mood("golden", 0.0)
		_set_sun(Vector3(-12, -30, 0))
		_show([_mate, _fox, _otter])
		_place(_hero, HOME3 + Vector3(-2.8, 0, 10.6), -0.25)
		_place(_mate, HOME3 + Vector3(0.5, 0.2, 3.8), PI)
		_hero.raise_arms(0, 0, 0.01)
		_mate.raise_arms(0, 0, 0.01)
		_door.rotation.y = -1.2
		var yard := HOME3 + Vector3(0.6, 0, 7.6)
		_circle(_fox, yard, 2.7, 1.4, PI * 0.45)
		_circle(_otter, yard, 1.3, 1.4, PI * 1.45)
		_set_windows(Color(1.0, 0.78, 0.45), 1.4, 0.01)
		_shot(HOME3 + Vector3(-9, 2.4, 19), HOME3 + Vector3(-6.5, 2.1, 16.5), HOME3 + Vector3(0, 1.4, 6), HOME3 + Vector3(0.3, 1.3, 4.6), 13.6)
	)
	_mood("dusk", 11.0)
	_at(3.0, func():
		_stop_circling()
		_fox.move_to(HOME3 + Vector3(-3.7, 0, 11.0), 2.0)
		_otter.move_to(HOME3 + Vector3(-1.9, 0, 11.2), 2.2)
	)
	_at(5.6, func():
		_mate.face(_hero.position)
		_mate.raise_arms(0.0, 0.9)
		_hero.raise_arms(0.0, 0.7)
	)
	_at(7.4, func():
		var tw := create_tween().set_parallel()
		tw.tween_property(_env, "fog_density", 0.06, 4.0)
		tw.tween_property(_overlay, "shader_parameter/haze", 0.65, 4.0)
	)
	# She fades into soft light, the way people do in dreams.
	_at(9.6, func():
		FX.burst(_mate.position + Vector3.UP * 1.0, Color(1.0, 0.92, 0.75), 36, 1.1, 0.05)
		_hide([_mate]))
	_at(11.0, func(): _hero.raise_arms(0, 0, 1.2))
	await _wait(13.65)


## Twilight on the road. The house still glows. He looks back once, and
## walks on with the Fox and the Otter: finding home is what comes next.
func _searching() -> void:
	await _cut(func():
		_mood("dusk", 0.0)
		_hide([_mate])
		_place(_hero, HOME3 + Vector3(0, 0, 9.0), 0.0)
		_place(_fox, HOME3 + Vector3(-1.0, 0, 9.6), 0.0)
		_place(_otter, HOME3 + Vector3(1.0, 0, 9.4), 0.0)
		_hero.raise_arms(0, 0, 0.01)
		_door.rotation.y = -0.6
		_set_windows(Color(1.0, 0.78, 0.45), 1.6, 0.01)
		_shot(HOME3 + Vector3(6, 1.8, 26), HOME3 + Vector3(3, 2.2, 21), HOME3 + Vector3(0, 1.4, 8), HOME3 + Vector3(0, 1.4, 15), 13.6)
	)
	_at(1.0, func():
		var road := HOME3 + Vector3(0, 0, 30)
		_hero.face(road)
		_fox.face(road)
		_otter.face(road))
	_at(1.4, func():
		_hero.walk_to(HOME3 + Vector3(0, 0, 20), 6.0)
		_fox.move_to(HOME3 + Vector3(-1.0, 0, 20.4), 6.0)
		_otter.move_to(HOME3 + Vector3(1.0, 0, 20.2), 6.2))
	_at(7.6, func(): _hero.face(HOME3))  # one look back
	_at(8.0, func(): _say("Find your way home.", 4.0))
	_at(10.2, func(): _set_windows(Color(1.0, 0.78, 0.45), 0.25, 3.0))
	_at(10.6, func():
		_hero.face(HOME3 + Vector3(0, 0, 40))
		_hero.walk_to(HOME3 + Vector3(0, 0, 27), 3.0)
		_fox.move_to(HOME3 + Vector3(-1.0, 0, 27.4), 3.0)
		_otter.move_to(HOME3 + Vector3(1.0, 0, 27.2), 3.1))
	await _wait(13.65)


func _waking() -> void:
	await _cut(func():
		_set_rain(false)
		_motes.emitting = true
		_set_sun(Vector3(-25, -35, 0))
		_mood("white", 7.0)
		_hide([_mate])
		_place(_hero, MEADOW + Vector3(0, 0, 14), 0.0)
		_place(_fox, MEADOW + Vector3(-1.0, 0, 14.5), 0.0)
		_place(_otter, MEADOW + Vector3(1.0, 0, 14.3), 0.0)
		_shot(MEADOW + Vector3(2.5, 2.2, 22), MEADOW + Vector3(1.5, 2.6, 15), MEADOW + Vector3(0, 3, -10), MEADOW + Vector3(0, 5, -16), 8.0)
	)
	_hero.walk_to(MEADOW + Vector3(0, 0, -10), 9.0)
	_fox.move_to(MEADOW + Vector3(-1.0, 0, -9.5), 9.0)
	_otter.move_to(MEADOW + Vector3(1.0, 0, -9.7), 9.0)
	_at(4.2, func(): _fade_to(1.0, 3.0))
	_at(5.2, func(): _say("Wake up.", 3.0, Color(0.25, 0.25, 0.32), 46))
	await _wait(8.8)


# --- Direction helpers -------------------------------------------------------

func _process(_delta: float) -> void:
	if _camera and _camera.position.distance_to(_look) > 0.01:
		_camera.look_at(_look)
	for c in _circlers:
		var node: Node3D = c[0]
		c[4] += _delta * c[3]
		var angle: float = c[4]
		node.position = c[1] + Vector3(cos(angle), 0.0, sin(angle)) * c[2]
		var tangent := Vector3(-sin(angle), 0.0, cos(angle))
		node.rotation.y = atan2(-tangent.x, -tangent.z)


func _timer(seconds: float) -> Timer:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = maxf(seconds, 0.001)
	add_child(timer)
	timer.start()
	timer.timeout.connect(timer.queue_free)
	return timer


func _wait(seconds: float) -> void:
	await _timer(seconds).timeout


func _at(seconds: float, action: Callable) -> void:
	_timer(seconds).timeout.connect(action)


## A quick white flash between scenes; `setup` runs while the screen is white.
func _cut(setup: Callable) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.35)
	await tw.finished
	setup.call()
	_fade_to(0.0, 0.6)


func _fade_to(alpha: float, duration: float) -> void:
	create_tween().tween_property(_fade, "color:a", alpha, duration)


func _shot(from: Vector3, to: Vector3, look_from: Vector3, look_to: Vector3, duration: float) -> void:
	_camera.position = from
	_look = look_from
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_camera, "position", to, duration)
	tw.tween_property(self, "_look", look_to, duration)


func _say(text: String, hold: float, color := Color(1.0, 0.96, 0.9), size := 30) -> void:
	if _caption_tween:
		_caption_tween.kill()
	_caption.text = text
	_caption.add_theme_color_override("font_color", color)
	_caption.add_theme_font_size_override("font_size", size)
	_caption.modulate.a = 0.0
	_caption_tween = create_tween()
	_caption_tween.tween_property(_caption, "modulate:a", 1.0, 0.9)
	_caption_tween.tween_interval(hold)
	_caption_tween.tween_property(_caption, "modulate:a", 0.0, 0.9)


func _mood(mood: String, duration: float) -> void:
	var m: Array = MOODS[mood]
	var tw := create_tween().set_parallel()
	var d := maxf(duration, 0.01)
	tw.tween_property(_sky, "sky_top_color", m[0], d)
	tw.tween_property(_sky, "sky_horizon_color", m[1], d)
	tw.tween_property(_sky, "ground_horizon_color", m[1], d)
	tw.tween_property(_sky, "ground_bottom_color", (m[1] as Color).darkened(0.5), d)
	tw.tween_property(_sun, "light_color", m[2], d)
	tw.tween_property(_sun, "light_energy", m[3], d)
	tw.tween_property(_env, "fog_light_color", m[4], d)
	tw.tween_property(_env, "fog_density", m[5], d)
	tw.tween_property(_overlay, "shader_parameter/tint", m[6], d)
	tw.tween_property(_overlay, "shader_parameter/saturation", m[7], d)
	tw.tween_property(_overlay, "shader_parameter/haze", m[8], d)


func _set_sun(rotation_deg: Vector3) -> void:
	_sun.rotation_degrees = rotation_deg


func _set_rain(on: bool) -> void:
	_rain.emitting = on
	if on and not _rain_audio.playing:
		_rain_audio.play()
	create_tween().tween_property(_rain_audio, "volume_db", Audio.MIX["loop_rain"] if on else -60.0, 1.5)


func _set_windows(color: Color, energy: float, duration: float) -> void:
	var tw := create_tween().set_parallel()
	for m in _window_mats:
		tw.tween_property(m, "albedo_color", color, duration)
		tw.tween_property(m, "emission", color, duration)
		tw.tween_property(m, "emission_energy_multiplier", energy, duration)
	for l in _window_lights:
		tw.tween_property(l, "light_color", color, duration)
		tw.tween_property(l, "light_energy", energy, duration)



func _lanterns() -> void:
	var glow := MeshKit.glow(Color(1.0, 0.65, 0.3), 5.0)
	for k in 18:
		var lantern := MeshKit.part(self, MeshKit.sphere(0.18, 0.3, 6, 3), glow,
			CLIFF + Vector3(randf_range(14, 40), randf_range(-24, -10), randf_range(-16, 16)))
		var tw := lantern.create_tween()
		tw.tween_property(lantern, "position", lantern.position + Vector3(randf_range(-3, 3), randf_range(24, 34), randf_range(-3, 3)), randf_range(8.0, 11.0))


func _place(node: Node3D, pos: Vector3, yaw: float) -> void:
	if node.has_method("halt"):
		node.halt()
	node.position = pos
	node.rotation.y = yaw
	node.visible = true


func _show(nodes: Array) -> void:
	for n in nodes:
		n.visible = true


func _hide(nodes: Array) -> void:
	for n in nodes:
		n.visible = false


func _circle(node: Node3D, center: Vector3, radius: float, speed: float, phase: float) -> void:
	_circlers.append([node, center, radius, speed, phase])
	if node is Figure:
		node.walking = true
	elif node is Critter:
		node.moving = true


func _stop_circling() -> void:
	for c in _circlers:
		var node: Node3D = c[0]
		if node is Figure:
			node.walking = false
		elif node is Critter:
			node.moving = false
	_circlers.clear()


# --- Skipping & ending -------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _leaving or Game.screenshot_mode:
		return
	var key := event is InputEventKey and event.is_pressed() and not event.is_echo()
	var click := event is InputEventMouseButton and event.is_pressed()
	if key or click:
		_leaving = true
		Game.story_start = true
		var tw := create_tween().set_parallel()
		tw.tween_property(_fade, "color:a", 1.0, 0.6)
		tw.tween_property(_music, "volume_db", -60.0, 0.6)
		tw.chain().tween_callback(func(): get_tree().change_scene_to_file(NEXT_SCENE))


func _finish() -> void:
	if _leaving:
		return
	_leaving = true
	Game.story_start = true
	get_tree().change_scene_to_file(NEXT_SCENE)


func _schedule_screenshots() -> void:
	Engine.time_scale = Game.shot_speed
	var last := 0.0
	for i in Game.dream_shots.size():
		var t: float = Game.dream_shots[i]
		var path := "%s_%d.png" % [Game.screenshot_path.get_basename(), i]
		_at(t, func(): get_viewport().get_texture().get_image().save_png(path))
		last = maxf(last, t)
	_at(last + 0.2, func(): get_tree().quit())


# --- Building the sets -------------------------------------------------------

func _build_environment() -> void:
	_sky = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = _sky
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.glow_enabled = true
	_env.glow_intensity = 1.0
	_env.glow_bloom = 0.25
	_env.glow_hdr_threshold = 0.8
	_env.ssao_enabled = true
	_env.fog_enabled = true
	_env.fog_aerial_perspective = 0.4
	_env.fog_sky_affect = 0.4
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 80.0
	add_child(_sun)
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_camera.far = 900.0
	add_child(_camera)
	_camera.current = true
	_motes = CPUParticles3D.new()
	var mote := MeshKit.sphere(0.03, -1.0, 6, 3)
	mote.material = MeshKit.glow(Color(1.0, 0.92, 0.7), 4.0)
	_motes.mesh = mote
	_motes.amount = 140
	_motes.lifetime = 6.0
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_motes.emission_box_extents = Vector3(12, 4, 12)
	_motes.direction = Vector3.UP
	_motes.spread = 180.0
	_motes.initial_velocity_min = 0.1
	_motes.initial_velocity_max = 0.4
	_motes.gravity = Vector3(0, 0.05, 0)
	_motes.local_coords = false
	_motes.position = Vector3(0, 0, -8)
	_camera.add_child(_motes)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay = ShaderMaterial.new()
	_overlay.shader = load("res://shaders/dream.gdshader")
	_overlay.set_shader_parameter("tint", Color(1.0, 0.96, 0.88))
	_overlay.set_shader_parameter("saturation", 1.1)
	_overlay.set_shader_parameter("haze", 0.3)
	overlay.material = _overlay
	layer.add_child(overlay)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = 0.0 if top else 1.0
		bar.offset_top = 0.0 if top else -96.0
		bar.offset_bottom = 96.0 if top else 0.0
		layer.add_child(bar)
	_fade = ColorRect.new()
	_fade.color = Color(1, 1, 1, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_caption = Label.new()
	_caption.anchor_right = 1.0
	_caption.anchor_top = 1.0
	_caption.anchor_bottom = 1.0
	_caption.offset_top = -92.0
	_caption.offset_bottom = -6.0
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.modulate.a = 0.0
	layer.add_child(_caption)
	var hint := Label.new()
	hint.text = "Press any key to skip"
	hint.anchor_left = 1.0
	hint.anchor_right = 1.0
	hint.offset_left = -260.0
	hint.offset_right = -24.0
	hint.offset_top = 34.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	hint.add_theme_font_size_override("font_size", 16)
	layer.add_child(hint)
	hint.create_tween().tween_property(hint, "modulate:a", 0.0, 2.0).set_delay(6.0)


func _build_meadow() -> void:
	MeshKit.part(self, _plane(260.0), MeshKit.mat(Color(0.42, 0.62, 0.3)), MEADOW)
	_hills(MEADOW, Color(0.38, 0.55, 0.32))
	_flowers(MEADOW + Vector3(0, 0, 2), 40.0, 2600)
	_great_tree(MEADOW + Vector3(0, 0, -16))


## Where they met: a circular rose garden behind a fieldstone gate, with
## concentric rose beds, a cross of concrete paths, a white-roofed pavilion in
## the middle and an iron fence all around. The gate faces +Z.
func _build_garden() -> void:
	var g := GARDEN
	MeshKit.part(self, _plane(300.0), MeshKit.mat(Color(0.62, 0.58, 0.42)), g)
	_hills(g, Color(0.55, 0.52, 0.4))
	var dirt := MeshKit.mat(Color(0.42, 0.32, 0.24))
	var gravel := MeshKit.mat(Color(0.74, 0.65, 0.5))
	var concrete := MeshKit.mat(Color(0.83, 0.81, 0.77))

	# Rings drawn from the outside in: beds (dirt) alternate with gravel paths.
	var rings := [[22.8, gravel], [21.6, dirt], [19.8, gravel], [18.4, dirt], [13.8, gravel], [12.4, dirt], [7.8, gravel], [6.4, dirt]]
	for i in rings.size():
		MeshKit.part(self, MeshKit.cyl(rings[i][0], rings[i][0], 0.02, 64), rings[i][1], g + Vector3(0, 0.01 + i * 0.004, 0))
	for rot in [0.0, PI / 2]:
		MeshKit.part(self, MeshKit.box(Vector3(2.2, 0.06, 45.6)), concrete, g + Vector3(0, 0.03, 0), Vector3(0, rot, 0))
	MeshKit.part(self, MeshKit.box(Vector3(2.6, 0.06, 9.0)), concrete, g + Vector3(0, 0.03, 26.5))
	MeshKit.part(self, MeshKit.cyl(4.2, 4.2, 0.1, 6), concrete, g + Vector3(0, 0.05, 0))
	_rose_beds(g, [[1.4, 6.3], [7.9, 12.3], [13.9, 18.3], [19.9, 21.5]])

	# Pavilion: brown posts under a white standing-seam hip roof.
	var post := MeshKit.mat(Color(0.36, 0.24, 0.18))
	var tin := MeshKit.mat(Color(0.9, 0.92, 0.92), 0.4, 0.5)
	for k in 6:
		var a := TAU * k / 6.0
		MeshKit.part(self, MeshKit.box(Vector3(0.22, 2.7, 0.22)), post, g + Vector3(cos(a) * 3.4, 1.4, sin(a) * 3.4))
	MeshKit.part(self, MeshKit.cyl(3.65, 3.65, 0.18, 6), post, g + Vector3(0, 2.8, 0))
	MeshKit.part(self, MeshKit.cyl(0.25, 4.3, 1.5, 6), tin, g + Vector3(0, 3.6, 0))
	for k in 6:
		var a := TAU * (k + 0.5) / 6.0
		var hip := MeshKit.part(self, MeshKit.box(Vector3(0.08, 0.06, 4.0)), tin, g + Vector3(cos(a) * 2.0, 3.62, sin(a) * 2.0))
		hip.look_at_from_position(hip.position, g + Vector3(0, 4.35, 0), Vector3.UP)
	var wood := MeshKit.mat(Color(0.45, 0.32, 0.22))
	for z in [-1.0, 1.0]:
		MeshKit.part(self, MeshKit.box(Vector3(2.0, 0.08, 0.8)), wood, g + Vector3(0, 0.75, z))
		MeshKit.part(self, MeshKit.box(Vector3(2.0, 0.06, 0.3)), wood, g + Vector3(0, 0.45, z * 1.7))
	MeshKit.part(self, MeshKit.cyl(0.3, 0.27, 0.9, 10), MeshKit.mat(Color(0.12, 0.42, 0.3)), g + Vector3(2.2, 0.45, 4.6))

	# Wrought-iron fence around the edge, open at the gate.
	var iron := MeshKit.mat(Color(0.1, 0.09, 0.09), 0.5, 0.6)
	var fence_r := 23.0
	var steps := 120
	for k in steps:
		var a := TAU * (k + 0.5) / steps
		var gate_gap := absf(angle_difference(a, PI / 2)) < 0.11
		if gate_gap:
			continue
		var p := Vector3(cos(a) * fence_r, 0, sin(a) * fence_r)
		MeshKit.part(self, MeshKit.box(Vector3(0.05, 1.9, 0.05)), iron, g + p + Vector3(0, 0.95, 0))
		var seg := TAU * fence_r / steps
		for y in [0.25, 1.75]:
			MeshKit.part(self, MeshKit.box(Vector3(0.05, 0.05, seg)), iron, g + p + Vector3(0, y, 0), Vector3(0, -a, 0))
		for b in 4:
			var t := (b + 0.5) / 4.0 - 0.5
			var q := p + Vector3(-sin(a), 0, cos(a)) * t * seg
			MeshKit.part(self, MeshKit.box(Vector3(0.025, 1.6, 0.025)), iron, g + q + Vector3(0, 0.95, 0))

	# Fieldstone gate pillars, carved sign beam and open iron gates.
	var stones := [Color(0.72, 0.68, 0.6), Color(0.62, 0.58, 0.52), Color(0.78, 0.74, 0.66), Color(0.55, 0.52, 0.48)]
	for side in [-1.0, 1.0]:
		var base := g + Vector3(2.6 * side, 0, 23.0)
		MeshKit.part(self, MeshKit.box(Vector3(0.9, 3.4, 0.9)), MeshKit.mat(Color(0.6, 0.57, 0.5)), base + Vector3(0, 1.7, 0))
		for k in 40:
			var face := k % 4
			var off := Vector3.ZERO
			match face:
				0: off = Vector3(randf_range(-0.38, 0.38), 0, 0.46)
				1: off = Vector3(randf_range(-0.38, 0.38), 0, -0.46)
				2: off = Vector3(0.46, 0, randf_range(-0.38, 0.38))
				3: off = Vector3(-0.46, 0, randf_range(-0.38, 0.38))
			off.y = randf_range(0.2, 3.25)
			var s := MeshKit.part(self, MeshKit.sphere(randf_range(0.11, 0.17), -1.0, 7, 4), MeshKit.mat(stones[randi() % stones.size()]), base + off)
			s.scale = Vector3(1.0, 0.75, 1.0) if face < 2 else Vector3(1.0, 0.75, 1.0)
		# Gate leaf, swung open inward.
		var leaf := Node3D.new()
		leaf.position = base + Vector3(-0.45 * side, 0, 0)
		leaf.rotation.y = side * 1.2
		add_child(leaf)
		for b in 9:
			MeshKit.part(leaf, MeshKit.box(Vector3(0.03, 1.9, 0.03)), iron, Vector3(-side * (0.1 + b * 0.2), 1.0, 0))
		for y in [0.2, 1.0, 1.9]:
			MeshKit.part(leaf, MeshKit.box(Vector3(1.75, 0.05, 0.04)), iron, Vector3(-side * 0.9, y, 0))
	var beam := MeshKit.mat(Color(0.3, 0.17, 0.12))
	MeshKit.part(self, MeshKit.box(Vector3(9.0, 0.55, 0.22)), beam, g + Vector3(0, 3.0, 23.5))
	for side in [-1.0, 1.0]:
		MeshKit.part(self, MeshKit.box(Vector3(2.0, 0.3, 0.2)), beam, g + Vector3(4.05 * side, 2.1, 23.5))
	var sign := Label3D.new()
	sign.text = "Rose Test Garden"
	sign.font_size = 72
	sign.pixel_size = 0.005
	sign.modulate = Color(0.95, 0.92, 0.85)
	sign.outline_size = 0
	sign.shaded = true
	sign.position = g + Vector3(0, 3.0, 23.62)
	add_child(sign)

	# Trees around the garden: palms, airy mesquites and dark pines.
	for spot in [Vector3(-30, 0, 8), Vector3(-34, 0, -6), Vector3(-27, 0, -22), Vector3(31, 0, -12), Vector3(36, 0, 4), Vector3(28, 0, 20), Vector3(-26, 0, 26), Vector3(12, 0, -34), Vector3(-8, 0, -38)]:
		_palm(g + spot, randf_range(8.0, 12.0))
	for spot in [Vector3(-14, 0, -30), Vector3(4, 0, -31), Vector3(20, 0, -28), Vector3(-32, 0, 16)]:
		_mesquite(g + spot)
	var pine := MeshKit.mat(Color(0.18, 0.3, 0.18))
	var bark := MeshKit.mat(Color(0.35, 0.26, 0.2))
	for spot in [Vector3(30, 0, -26), Vector3(38, 0, -16), Vector3(-38, 0, -18), Vector3(34, 0, 26)]:
		MeshKit.part(self, MeshKit.cyl(0.35, 0.5, 6.0, 8), bark, g + spot + Vector3(0, 3.0, 0))
		for k in 5:
			var p := Vector3(randf_range(-2.5, 2.5), randf_range(6.5, 10.0), randf_range(-2.5, 2.5))
			MeshKit.part(self, MeshKit.sphere(randf_range(2.4, 3.4), randf_range(3.0, 4.0), 9, 5), pine, g + spot + p)


## Rose bushes filling the ring beds, each covered in blooms of one color.
func _rose_beds(center: Vector3, beds: Array) -> void:
	var palette := [Color(0.85, 0.06, 0.12), Color(0.95, 0.35, 0.5), Color(0.97, 0.95, 0.88), Color(0.98, 0.85, 0.3), Color(0.82, 0.08, 0.38), Color(0.98, 0.5, 0.42)]
	var spots: Array[Vector3] = []
	var colors: Array[Color] = []
	for bed in beds:
		var r0: float = bed[0]
		var r1: float = bed[1]
		var count := int((r1 * r1 - r0 * r0) * 1.1)
		for i in count:
			var a := randf() * TAU
			var r := sqrt(randf_range(r0 * r0, r1 * r1))
			var p := Vector3(cos(a) * r, 0, sin(a) * r)
			if absf(p.x) < 1.6 or absf(p.z) < 1.6:
				continue
			spots.append(p)
			colors.append(palette[int(absf(sin(floorf(a * 4.0) * 12.9898 + floorf(r / 3.0) * 78.233)) * 43758.5) % palette.size()])
	var bush := MeshKit.sphere(0.5, 0.75, 8, 5)
	bush.material = MeshKit.mat(Color(0.24, 0.42, 0.2))
	var bushes := _multimesh(bush, spots.size(), false)
	var bloom := MeshKit.sphere(0.1, 0.14, 7, 4)
	var bloom_mat := StandardMaterial3D.new()
	bloom_mat.vertex_color_use_as_albedo = true
	bloom_mat.roughness = 0.7
	bloom.material = bloom_mat
	var per := 26
	var blooms := _multimesh(bloom, spots.size() * per, true)
	for i in spots.size():
		var s := randf_range(0.75, 1.15)
		var p := center + spots[i]
		bushes.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), p + Vector3(0, 0.3 * s, 0)))
		for k in per:
			var dir := Vector3(randf_range(-1, 1), randf_range(-0.1, 1), randf_range(-1, 1)).normalized()
			var b := p + Vector3(0, 0.3 * s, 0) + Vector3(dir.x * 0.5, dir.y * 0.37, dir.z * 0.5) * s
			blooms.set_instance_transform(i * per + k, Transform3D(Basis(Vector3.UP, randf() * TAU), b))
			blooms.set_instance_color(i * per + k, colors[i].lerp(Color.WHITE, randf_range(0.0, 0.15)))


func _multimesh(mesh: Mesh, count: int, colored: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colored
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	return mm


func _palm(base: Vector3, height: float) -> void:
	var trunk := MeshKit.mat(Color(0.48, 0.4, 0.32))
	var lean := Vector3(randf_range(-0.06, 0.06), 0, randf_range(-0.06, 0.06))
	MeshKit.part(self, MeshKit.cyl(0.18, 0.3, height, 8), trunk, base + Vector3(0, height / 2, 0), lean)
	var top := base + Vector3(lean.z * -height * 0.5, height, lean.x * height * 0.5)
	MeshKit.part(self, MeshKit.cyl(0.45, 0.25, 1.2, 8), MeshKit.mat(Color(0.5, 0.42, 0.28)), top + Vector3(0, -0.5, 0))
	var frond := MeshKit.mat(Color(0.3, 0.45, 0.2))
	for k in 12:
		var a := TAU * k / 12.0
		var droop := randf_range(0.25, 0.6)
		var f := MeshKit.part(self, MeshKit.box(Vector3(0.5, 0.04, 2.4)), frond, top + Vector3(sin(a), -droop * 0.8, cos(a)) * 1.1)
		f.rotation = Vector3(droop, a, 0)


func _mesquite(at: Vector3, size := 1.0) -> void:
	var root := Node3D.new()
	root.position = at
	root.scale = Vector3.ONE * size
	add_child(root)
	var base := Vector3.ZERO
	var bark := MeshKit.mat(Color(0.3, 0.22, 0.17))
	var leaves := MeshKit.mat(Color(0.45, 0.62, 0.24))
	for side in [-1.0, 1.0]:
		MeshKit.part(root, MeshKit.cyl(0.12, 0.2, 3.2, 7), bark, base + Vector3(0.6 * side, 1.5, 0), Vector3(0, 0, -0.45 * side))
	for k in 6:
		var p := Vector3(randf_range(-3.0, 3.0), randf_range(3.2, 4.2), randf_range(-2.0, 2.0))
		var blob := MeshKit.part(root, MeshKit.sphere(2.0, 1.6, 10, 6), leaves, base + p)
		blob.scale = Vector3(1.3, 1.0, 1.1)


## The tree from the dream is the tree you wake up under.
func _great_tree(at: Vector3) -> void:
	var bark := MeshKit.mat(Color(0.36, 0.26, 0.18))
	var leaves := MeshKit.mat(Color(0.3, 0.56, 0.32))
	MeshKit.part(self, MeshKit.cyl(0.7, 1.3, 8.0, 10), bark, at + Vector3(0, 4.0, 0))
	for k in 5:
		var a := TAU * k / 5.0
		MeshKit.part(self, MeshKit.box(Vector3(0.5, 0.4, 2.4)), bark, at + Vector3(cos(a) * 1.3, 0.15, sin(a) * 1.3), Vector3(0, -a + PI / 2, 0))
	var blobs := [[Vector3(0, 9.5, 0), 5.2], [Vector3(-3.2, 8.4, 1.0), 3.6], [Vector3(3.0, 8.8, -0.8), 3.8], [Vector3(0.5, 12.0, 0.5), 3.4]]
	for b in blobs:
		MeshKit.part(self, MeshKit.sphere(b[1], b[1] * 1.4, 9, 6), leaves, at + b[0])
	var firefly := MeshKit.glow(Color(1.0, 0.9, 0.5), 5.0)
	for k in 24:
		MeshKit.part(self, MeshKit.sphere(0.06), firefly, at + Vector3(randf_range(-5, 5), randf_range(6, 12), randf_range(-4, 5)))


func _build_cliff() -> void:
	var rock := MeshKit.mat(Color(0.5, 0.5, 0.44))
	MeshKit.part(self, MeshKit.box(Vector3(46, 40, 50)), rock, CLIFF + Vector3(-8, -20, 0))
	MeshKit.part(self, MeshKit.box(Vector3(46, 0.2, 50)), MeshKit.mat(Color(0.42, 0.62, 0.3)), CLIFF + Vector3(-8, 0.0, 0))
	_flowers(CLIFF + Vector3(-6, 0.1, 0), 16.0, 700)
	var water := ShaderMaterial.new()
	water.shader = load("res://shaders/water.gdshader")
	water.set_shader_parameter("ripple_a", _ripples(11, 0.02))
	water.set_shader_parameter("ripple_b", _ripples(23, 0.035))
	water.set_shader_parameter("wave_height", 0.6)
	var sea := PlaneMesh.new()
	sea.size = Vector2(700, 700)
	sea.subdivide_width = 120
	sea.subdivide_depth = 120
	MeshKit.part(self, sea, water, CLIFF + Vector3(150, -26, 0))
	for k in 6:
		var r := randf_range(3.0, 7.0)
		MeshKit.part(self, MeshKit.sphere(r, r * randf_range(2.5, 4.0), 7, 5), rock,
			CLIFF + Vector3(randf_range(40, 120), -26, randf_range(-60, 60)))


## The family's first home: a two-story desert stucco house with a tile roof,
## arched entry, attached garage and a bottlebrush tree out front. Faces +Z.
func _build_home() -> void:
	MeshKit.part(self, _plane(150.0), MeshKit.mat(Color(0.6, 0.5, 0.4)), HOME)
	_hills(HOME, Color(0.6, 0.48, 0.38))
	var stucco := MeshKit.mat(Color(0.86, 0.75, 0.5), 0.95)
	var gable := MeshKit.mat(Color(0.93, 0.87, 0.7), 0.9)
	var trim := MeshKit.mat(Color(0.96, 0.95, 0.91), 0.7)
	var tile := MeshKit.mat(Color(0.6, 0.43, 0.34), 0.8)
	var stone := MeshKit.mat(Color(0.55, 0.45, 0.37))
	var concrete := MeshKit.mat(Color(0.8, 0.78, 0.74))

	# Main two-story block with a street-facing gable.
	MeshKit.part(self, MeshKit.box(Vector3(6.2, 6.0, 7.4)), stucco, HOME + Vector3(0.9, 3.0, -1.3))
	_gable_roof(HOME + Vector3(0.9, 6.0, -1.3), 6.2, 7.4, 2.0, gable, tile, trim)

	# Upstairs windows; the middle one has shutters.
	for x in [-1.0, 0.9, 2.9]:
		_window(HOME + Vector3(x, 4.75, 2.4), Vector2(0.85, 1.15), trim)
	var shutter := MeshKit.mat(Color(0.45, 0.32, 0.2))
	for side in [-1.0, 1.0]:
		MeshKit.part(self, MeshKit.box(Vector3(0.42, 1.3, 0.06)), shutter, HOME + Vector3(0.9 + 0.72 * side, 4.75, 2.44))
	_window(HOME + Vector3(3.45, 1.7, 2.4), Vector2(0.65, 1.2), trim)

	# Recessed entry porch behind an arched opening.
	var px0 := -1.3
	var px1 := 2.7
	var front := 4.4
	MeshKit.part(self, MeshKit.box(Vector3(px1 - px0, 0.2, front - 2.4)), concrete, HOME + Vector3((px0 + px1) / 2, 0.1, 3.4))
	for x in [px0 + 0.15, px1 - 0.15]:
		MeshKit.part(self, MeshKit.box(Vector3(0.3, 3.2, front - 2.4)), stucco, HOME + Vector3(x, 1.6, 3.4))
	var ox0 := -0.8
	var ox1 := 1.8
	MeshKit.part(self, MeshKit.box(Vector3(ox0 - px0, 3.2, 0.3)), stucco, HOME + Vector3((px0 + ox0) / 2, 1.6, front - 0.15))
	MeshKit.part(self, MeshKit.box(Vector3(px1 - ox1, 3.2, 0.3)), stucco, HOME + Vector3((px1 + ox1) / 2, 1.6, front - 0.15))
	var acx := (ox0 + ox1) / 2
	var half := (ox1 - ox0) / 2
	var spring := 1.9
	var rise := 0.9
	var strips := 18
	for k in strips:
		var w := (ox1 - ox0) / strips
		var xm := ox0 + w * (k + 0.5)
		var dx := (xm - acx) / half
		var ya := spring + rise * sqrt(maxf(0.0, 1.0 - dx * dx))
		MeshKit.part(self, MeshKit.box(Vector3(w + 0.01, 3.2 - ya, 0.3)), stucco, HOME + Vector3(xm, (ya + 3.2) / 2, front - 0.15))
	for k in 22:
		var a := PI * (k + 0.5) / 22.0
		var p := Vector3(acx + cos(a) * (half + 0.06), spring + sin(a) * (rise + 0.06), front + 0.02)
		MeshKit.part(self, MeshKit.box(Vector3(0.12, 0.25, 0.06)), trim, HOME + p, Vector3(0, 0, a))
	for x in [ox0 - 0.06, ox1 + 0.06]:
		MeshKit.part(self, MeshKit.box(Vector3(0.12, spring, 0.06)), trim, HOME + Vector3(x, spring / 2, front + 0.02))
	_gable_roof(HOME + Vector3((px0 + px1) / 2, 3.2, 3.4), px1 - px0, front - 2.4, 1.0, gable, tile, trim)

	# Front door, doorway and a porch light.
	MeshKit.part(self, MeshKit.box(Vector3(1.1, 2.3, 0.04)), trim, HOME + Vector3(0, 1.35, 2.41))
	_door = Node3D.new()
	_door.position = HOME + Vector3(-0.5, 0.2, 2.46)
	add_child(_door)
	MeshKit.part(_door, MeshKit.box(Vector3(1.0, 2.2, 0.08)), MeshKit.mat(Color(0.24, 0.14, 0.1), 0.6), Vector3(0.5, 1.1, 0))
	MeshKit.part(_door, MeshKit.sphere(0.035), MeshKit.mat(Color(0.7, 0.6, 0.35), 0.3, 0.9), Vector3(0.85, 1.05, -0.06))
	var lamp := MeshKit.glow(Color(1.0, 0.8, 0.5), 2.0)
	_window_mats.append(lamp)
	MeshKit.part(self, MeshKit.box(Vector3(0.16, 0.26, 0.12)), lamp, HOME + Vector3(0.85, 2.0, 2.47))
	_window_light(HOME + Vector3(0.6, 2.0, 3.2), 3.5)

	# Attached garage with stone pillars.
	MeshKit.part(self, MeshKit.box(Vector3(3.4, 3.0, 4.6)), stucco, HOME + Vector3(-3.9, 1.5, 1.3))
	var garage_roof := Node3D.new()
	garage_roof.position = HOME + Vector3(-3.9, 3.0, 1.3)
	garage_roof.rotation.y = PI / 2
	add_child(garage_roof)
	_gable_roof(Vector3.ZERO, 4.6, 3.4, 0.9, gable, tile, trim, garage_roof)
	MeshKit.part(self, MeshKit.box(Vector3(2.5, 2.25, 0.06)), trim, HOME + Vector3(-3.9, 1.13, 3.62))
	var groove := MeshKit.mat(Color(0.8, 0.8, 0.78))
	for k in 4:
		MeshKit.part(self, MeshKit.box(Vector3(2.45, 0.025, 0.02)), groove, HOME + Vector3(-3.9, 0.45 * (k + 1), 3.66))
	for x in [-5.42, -2.38]:
		MeshKit.part(self, MeshKit.box(Vector3(0.44, 1.3, 0.5)), stone, HOME + Vector3(x, 0.65, 3.62))

	# Steps, walkway, driveway, sidewalk and street.
	MeshKit.part(self, MeshKit.box(Vector3(1.8, 0.1, 0.45)), concrete, HOME + Vector3(acx, 0.05, front + 0.25))
	MeshKit.part(self, MeshKit.box(Vector3(1.5, 0.04, 5.6)), concrete, HOME + Vector3(acx, -0.012, 7.5))
	MeshKit.part(self, MeshKit.box(Vector3(3.6, 0.04, 8.4)), concrete, HOME + Vector3(-3.9, -0.012, 7.8))
	MeshKit.part(self, MeshKit.box(Vector3(60, 0.05, 1.6)), concrete, HOME + Vector3(0, -0.016, 11.0))
	MeshKit.part(self, MeshKit.box(Vector3(80, 0.03, 9.0)), MeshKit.mat(Color(0.25, 0.25, 0.27)), HOME + Vector3(0, -0.012, 16.3))
	MeshKit.part(self, MeshKit.box(Vector3(10, 0.03, 6.5)), MeshKit.mat(Color(0.5, 0.4, 0.32)), HOME + Vector3(0.5, -0.01, 7.2))

	_bottlebrush(HOME + Vector3(-2.0, 0, 5.5))
	var sage := MeshKit.mat(Color(0.36, 0.45, 0.28))
	for b in [[Vector3(4.0, 0, 6.2), 1.4], [Vector3(5.2, 0, 4.6), 1.0], [Vector3(-1.0, 0, 4.9), 0.5], [Vector3(-2.3, 0, 6.6), 0.55], [Vector3(2.4, 0, 5.4), 0.45]]:
		var r: float = b[1]
		MeshKit.part(self, MeshKit.sphere(r, r * 1.5, 10, 6), sage, HOME + b[0] + Vector3(0, r * 0.6, 0))

	# Neighbors on either side.
	for n in [[-12.0, Color(0.82, 0.68, 0.6)], [11.5, Color(0.84, 0.72, 0.62)]]:
		var nx: float = n[0]
		MeshKit.part(self, MeshKit.box(Vector3(7.0, 6.0, 9.0)), MeshKit.mat(n[1], 0.95), HOME + Vector3(nx, 3.0, -1.5))
		_gable_roof(HOME + Vector3(nx, 6.0, -1.5), 7.0, 9.0, 1.8, MeshKit.mat(n[1], 0.95), tile, trim)
		for x in [-2.0, 0.0, 2.0]:
			MeshKit.part(self, MeshKit.box(Vector3(0.9, 1.1, 0.05)), MeshKit.mat(Color(0.2, 0.24, 0.3), 0.2), HOME + Vector3(nx + x, 4.6, 3.03))


## A street-facing gable: a wall-colored triangle with tiled slopes and white
## trim along the front edge. The ridge runs along Z.
func _gable_roof(base: Vector3, width: float, depth: float, height: float, wall: Material, tile: Material, trim: Material, parent: Node3D = null) -> void:
	var root := Node3D.new()
	root.position = base
	(parent if parent else self).add_child(root)
	var prism := PrismMesh.new()
	prism.size = Vector3(width, height, depth)
	MeshKit.part(root, prism, wall, Vector3(0, height / 2, 0))
	var slope := atan2(height, width / 2)
	var length := sqrt(width * width / 4 + height * height) + 0.45
	for side in [-1.0, 1.0]:
		var n := Vector3(side * sin(slope), cos(slope), 0)
		var mid := Vector3(side * width / 4, height / 2, 0) + n * 0.07
		MeshKit.part(root, MeshKit.box(Vector3(length, 0.12, depth + 0.6)), tile, mid + Vector3(side * 0.2, -0.15, 0), Vector3(0, 0, -side * slope))
		# Barrel-tile ridges running down the slope.
		var rows := int(depth / 0.32)
		for k in rows:
			var z := -depth / 2 - 0.2 + (k + 0.5) * (depth + 0.4) / rows
			MeshKit.part(root, MeshKit.box(Vector3(length, 0.05, 0.08)), tile, mid + n * 0.07 + Vector3(side * 0.2, -0.15, z), Vector3(0, 0, -side * slope))
		MeshKit.part(root, MeshKit.box(Vector3(length - 0.3, 0.14, 0.06)), trim, mid + Vector3(side * 0.05, -0.2, depth / 2 + 0.05), Vector3(0, 0, -side * slope))


func _window(center: Vector3, size: Vector2, trim: Material) -> void:
	MeshKit.part(self, MeshKit.box(Vector3(size.x + 0.22, size.y + 0.22, 0.08)), trim, center + Vector3(0, 0, 0.03))
	var glass := MeshKit.glow(Color(1.0, 0.78, 0.45), 1.6)
	_window_mats.append(glass)
	MeshKit.part(self, MeshKit.box(Vector3(size.x, size.y, 0.06)), glass, center + Vector3(0, 0, 0.05))
	MeshKit.part(self, MeshKit.box(Vector3(size.x, 0.05, 0.04)), trim, center + Vector3(0, 0, 0.09))
	MeshKit.part(self, MeshKit.box(Vector3(size.x + 0.3, 0.07, 0.16)), trim, center + Vector3(0, -size.y / 2 - 0.12, 0.08))
	_window_light(center + Vector3(0, 0, 0.9), 6.0)


func _window_light(pos: Vector3, reach: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.78, 0.45)
	light.light_energy = 1.6
	light.omni_range = reach
	light.position = pos
	add_child(light)
	_window_lights.append(light)


## A bottlebrush tree: slim leaning trunk, airy canopy dotted with red blooms.
func _bottlebrush(base: Vector3) -> void:
	var bark := MeshKit.mat(Color(0.4, 0.32, 0.25))
	MeshKit.part(self, MeshKit.cyl(0.07, 0.12, 2.6, 8), bark, base + Vector3(0, 1.3, 0), Vector3(0.06, 0, -0.08))
	MeshKit.part(self, MeshKit.cyl(0.04, 0.06, 1.3, 6), bark, base + Vector3(-0.35, 2.4, 0), Vector3(0, 0, 0.6))
	MeshKit.part(self, MeshKit.cyl(0.04, 0.06, 1.2, 6), bark, base + Vector3(0.3, 2.5, 0.1), Vector3(0.2, 0, -0.5))
	var leaves := MeshKit.mat(Color(0.32, 0.42, 0.24))
	var blobs := [Vector3(0, 3.6, 0), Vector3(-0.9, 3.1, 0.2), Vector3(0.9, 3.2, -0.1), Vector3(-0.3, 2.6, 0.5), Vector3(0.4, 4.2, 0.1), Vector3(-0.6, 4.0, -0.3)]
	for b in blobs:
		MeshKit.part(self, MeshKit.sphere(0.85, 1.4, 10, 6), leaves, base + b)
	var bloom := MeshKit.sphere(0.04, 0.12, 5, 3)
	bloom.material = MeshKit.mat(Color(0.86, 0.2, 0.14), 0.7)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bloom
	mm.instance_count = 900
	for i in mm.instance_count:
		var b: Vector3 = blobs[i % blobs.size()]
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)).normalized()
		var p := base + b + Vector3(dir.x * 0.85, dir.y * 0.7, dir.z * 0.85) * randf_range(0.85, 1.02)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, randf() * TAU), p))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


## The second home: two-story beige stucco with a brown shingle roof, a front
## garage under a gable, and an entry recessed behind two arches. Faces +Z;
## the door sits at x = 0 like the other homes so scenes can share positions.
func _build_home2() -> void:
	var h := HOME2
	MeshKit.part(self, _plane(150.0), MeshKit.mat(Color(0.56, 0.47, 0.38)), h)
	_hills(h, Color(0.52, 0.48, 0.4))
	var stucco := MeshKit.mat(Color(0.84, 0.76, 0.63), 0.95)
	var shingle := MeshKit.mat(Color(0.42, 0.3, 0.22), 0.9)
	var trim := MeshKit.mat(Color(0.86, 0.79, 0.66), 0.9)
	var concrete := MeshKit.mat(Color(0.78, 0.76, 0.72))

	# Two-story main block, side-gabled, with a front gable over the middle.
	MeshKit.part(self, MeshKit.box(Vector3(6.4, 5.6, 7.4)), stucco, h + Vector3(-0.1, 2.8, -1.3))
	var main_roof := Node3D.new()
	main_roof.position = h + Vector3(-0.1, 5.6, -1.3)
	main_roof.rotation.y = PI / 2
	add_child(main_roof)
	_gable_roof(Vector3.ZERO, 7.4, 6.4, 1.8, stucco, shingle, trim, main_roof)
	_gable_roof(h + Vector3(1.3, 5.6, 2.0), 3.4, 1.4, 1.3, stucco, shingle, trim)
	MeshKit.part(self, MeshKit.cyl(0.08, 0.08, 1.2, 8), MeshKit.mat(Color(0.3, 0.3, 0.3), 0.5, 0.6), h + Vector3(1.8, 7.6, -1.0))
	for x in [0.6, 2.2]:
		_window(h + Vector3(x, 4.2, 2.4), Vector2(1.0, 0.9), trim)
	_window(h + Vector3(-1.9, 4.3, 2.4), Vector2(0.8, 0.9), trim)
	MeshKit.part(self, MeshKit.cyl(0.4, 0.4, 0.08, 16), trim, h + Vector3(-1.9, 4.8, 2.44), Vector3(PI / 2, 0, 0))

	# Garage pushed out front under its own gable, with a little sun emblem.
	MeshKit.part(self, MeshKit.box(Vector3(3.8, 3.0, 3.2)), stucco, h + Vector3(3.5, 1.5, 4.0))
	_gable_roof(h + Vector3(3.5, 3.0, 4.0), 3.8, 3.2, 1.1, stucco, shingle, trim)
	MeshKit.part(self, MeshKit.box(Vector3(2.7, 2.2, 0.06)), MeshKit.mat(Color(0.9, 0.86, 0.78)), h + Vector3(3.5, 1.1, 5.62))
	for k in 4:
		MeshKit.part(self, MeshKit.box(Vector3(2.65, 0.025, 0.02)), MeshKit.mat(Color(0.8, 0.76, 0.68)), h + Vector3(3.5, 0.45 * (k + 1), 5.66))
	var emblem := MeshKit.mat(Color(0.2, 0.17, 0.15), 0.5, 0.5)
	MeshKit.part(self, MeshKit.cyl(0.1, 0.1, 0.03, 10), emblem, h + Vector3(3.5, 3.55, 5.64), Vector3(PI / 2, 0, 0))
	for k in 8:
		var a := TAU * k / 8.0
		MeshKit.part(self, MeshKit.box(Vector3(0.03, 0.12, 0.02)), emblem, h + Vector3(3.5 + cos(a) * 0.17, 3.55 + sin(a) * 0.17, 5.65), Vector3(0, 0, a + PI / 2))

	# One-story entry bump-out with two arches: a window behind the left one,
	# the front door behind the right.
	MeshKit.part(self, MeshKit.box(Vector3(4.6, 0.2, 2.5)), concrete, h + Vector3(-0.7, 0.1, 3.65))
	for x in [-3.15, 1.45]:
		MeshKit.part(self, MeshKit.box(Vector3(0.3, 3.0, 2.0)), stucco, h + Vector3(x, 1.5, 3.4))
	_arch_wall(h + Vector3(0, 0, 4.4), -3.3, 1.6, 3.0, [[-2.75, -1.25, 1.6, 0.55], [-0.8, 0.8, 1.9, 0.6]], stucco)
	var porch_roof := Node3D.new()
	porch_roof.position = h + Vector3(-0.85, 3.0, 3.4)
	porch_roof.rotation.y = PI / 2
	add_child(porch_roof)
	_gable_roof(Vector3.ZERO, 2.2, 4.9, 0.7, stucco, shingle, trim, porch_roof)
	_window(h + Vector3(-2.0, 1.5, 2.4), Vector2(1.1, 1.3), trim)
	MeshKit.part(self, MeshKit.box(Vector3(1.0, 2.2, 0.04)), MeshKit.mat(Color(0.82, 0.78, 0.7)), h + Vector3(0, 1.3, 2.41))
	var door := Node3D.new()
	door.position = h + Vector3(-0.45, 0.2, 2.46)
	add_child(door)
	MeshKit.part(door, MeshKit.box(Vector3(0.9, 2.1, 0.08)), MeshKit.mat(Color(0.62, 0.6, 0.55), 0.6), Vector3(0.45, 1.05, 0))
	MeshKit.part(self, MeshKit.box(Vector3(0.14, 0.24, 0.1)), MeshKit.glow(Color(1.0, 0.8, 0.5), 1.5), h + Vector3(0.75, 1.9, 2.47))

	# Driveway, brick-edged path, sidewalk and street.
	MeshKit.part(self, MeshKit.box(Vector3(4.0, 0.04, 4.8)), concrete, h + Vector3(3.5, -0.012, 8.0))
	MeshKit.part(self, MeshKit.box(Vector3(1.0, 0.04, 5.6)), MeshKit.mat(Color(0.6, 0.48, 0.4)), h + Vector3(1.0, -0.012, 7.6))
	MeshKit.part(self, MeshKit.box(Vector3(60, 0.05, 1.5)), concrete, h + Vector3(0, -0.016, 11.1))
	MeshKit.part(self, MeshKit.box(Vector3(80, 0.03, 9.0)), MeshKit.mat(Color(0.25, 0.25, 0.27)), h + Vector3(0, -0.012, 16.3))
	_vehicle(h + Vector3(3.4, 0, 8.1), PI, Color(0.95, 0.95, 0.95), true)
	_vehicle(h + Vector3(-9.5, 0, 13.6), PI / 2, Color(0.95, 0.95, 0.95), false)
	for b in [[Vector3(-2.6, 0, 5.4), 0.6], [Vector3(6.3, 0, 6.2), 0.5], [Vector3(0.1, 0, 9.4), 0.35], [Vector3(6.6, 0, 9.6), 0.3]]:
		var r: float = b[1]
		MeshKit.part(self, MeshKit.sphere(r, r * 1.4, 9, 5), MeshKit.mat(Color(0.5, 0.48, 0.32)), h + b[0] + Vector3(0, r * 0.55, 0))

	# A big mesquite to the right and a weeping pepper tree to the left.
	_mesquite(h + Vector3(8.5, 0, 7.5))
	_mesquite(h + Vector3(7.0, 0, 5.0))
	var bark := MeshKit.mat(Color(0.32, 0.25, 0.2))
	var pepper := MeshKit.mat(Color(0.3, 0.42, 0.22))
	var trunk_base := h + Vector3(-8.0, 0, 4.2)
	MeshKit.part(self, MeshKit.cyl(0.25, 0.4, 4.0, 8), bark, trunk_base + Vector3(0, 2.0, 0))
	for k in 9:
		var p := Vector3(randf_range(-2.4, 2.4), randf_range(3.0, 7.0), randf_range(-2.0, 2.0))
		var blob := MeshKit.part(self, MeshKit.sphere(1.6, 3.6, 9, 6), pepper, trunk_base + p)
		blob.rotation.z = randf_range(-0.2, 0.2)
	# Neighbors: a one-story with a covered patio on the left, a garage on the right.
	MeshKit.part(self, MeshKit.box(Vector3(8.0, 3.0, 8.0)), stucco, h + Vector3(-12.5, 1.5, -0.5))
	var left_roof := Node3D.new()
	left_roof.position = h + Vector3(-12.5, 3.0, -0.5)
	left_roof.rotation.y = PI / 2
	add_child(left_roof)
	_gable_roof(Vector3.ZERO, 8.0, 8.0, 1.4, stucco, MeshKit.mat(Color(0.52, 0.32, 0.25)), trim, left_roof)
	MeshKit.part(self, MeshKit.box(Vector3(8.0, 3.2, 7.0)), stucco, h + Vector3(12.5, 1.6, -0.5))
	_gable_roof(h + Vector3(12.5, 3.2, -0.5), 8.0, 7.0, 1.4, stucco, shingle, trim)
	MeshKit.part(self, MeshKit.box(Vector3(2.8, 2.2, 0.06)), MeshKit.mat(Color(0.72, 0.6, 0.42)), h + Vector3(11.5, 1.1, 3.03))


## The final home: a one-story Sonoran ranch house with a terracotta tile roof,
## a tall arched entry tower, double garage on the left, stone wainscot, green-
## tinted windows and a red brick walk. Faces +Z with the door at x = 0.
func _build_home3() -> void:
	var h := HOME3
	MeshKit.part(self, _plane(150.0), MeshKit.mat(Color(0.56, 0.46, 0.38)), h)
	_hills(h, Color(0.55, 0.5, 0.42))
	var stucco := MeshKit.mat(Color(0.6, 0.53, 0.43), 0.95)
	var tile := MeshKit.mat(Color(0.6, 0.4, 0.32), 0.8)
	var trim := MeshKit.mat(Color(0.55, 0.48, 0.39), 0.9)
	var stone := MeshKit.mat(Color(0.58, 0.45, 0.35))
	var concrete := MeshKit.mat(Color(0.78, 0.76, 0.72))

	MeshKit.part(self, MeshKit.box(Vector3(12.4, 3.2, 8.4)), stucco, h + Vector3(0, 1.6, -1.8))
	var main_roof := Node3D.new()
	main_roof.position = h + Vector3(0, 3.2, -1.8)
	main_roof.rotation.y = PI / 2
	add_child(main_roof)
	_gable_roof(Vector3.ZERO, 8.4, 12.4, 1.7, stucco, tile, trim, main_roof)

	# Garage on the left, under a front gable.
	MeshKit.part(self, MeshKit.box(Vector3(4.8, 3.2, 2.2)), stucco, h + Vector3(-3.8, 1.6, 3.5))
	_gable_roof(h + Vector3(-3.8, 3.2, 3.5), 4.8, 2.2, 1.2, stucco, tile, trim)
	var door_tan := MeshKit.mat(Color(0.72, 0.64, 0.5))
	MeshKit.part(self, MeshKit.box(Vector3(3.6, 2.3, 0.06)), door_tan, h + Vector3(-3.8, 1.15, 4.62))
	var groove := MeshKit.mat(Color(0.6, 0.53, 0.42))
	for k in 3:
		MeshKit.part(self, MeshKit.box(Vector3(3.55, 0.03, 0.02)), groove, h + Vector3(-3.8, 0.58 * (k + 1), 4.66))
	for k in 3:
		MeshKit.part(self, MeshKit.box(Vector3(0.03, 2.25, 0.02)), groove, h + Vector3(-3.8 + (k - 1) * 0.9, 1.15, 4.66))
	for x in [-6.0, -1.6]:
		MeshKit.part(self, MeshKit.box(Vector3(0.45, 0.75, 0.3)), stone, h + Vector3(x, 0.38, 4.6))

	# Tall entry tower with a deep arched alcove.
	MeshKit.part(self, MeshKit.box(Vector3(2.4, 0.2, 2.9)), concrete, h + Vector3(0, 0.1, 3.85))
	for x in [-1.05, 1.05]:
		MeshKit.part(self, MeshKit.box(Vector3(0.3, 4.4, 2.6)), stucco, h + Vector3(x, 2.2, 3.7))
		MeshKit.part(self, MeshKit.box(Vector3(0.36, 0.7, 0.4)), stone, h + Vector3(x, 0.35, 4.9))
	_arch_wall(h + Vector3(0, 0, 5.0), -1.2, 1.2, 4.4, [[-0.6, 0.6, 2.2, 0.55]], stucco)
	_gable_roof(h + Vector3(0, 4.4, 3.7), 2.6, 2.8, 1.0, stucco, tile, trim)
	MeshKit.part(self, MeshKit.box(Vector3(1.0, 2.2, 0.04)), MeshKit.mat(Color(0.18, 0.12, 0.1)), h + Vector3(0, 1.3, 2.41))
	_door = Node3D.new()
	_door.position = h + Vector3(-0.45, 0.2, 2.46)
	add_child(_door)
	MeshKit.part(_door, MeshKit.box(Vector3(0.9, 2.1, 0.08)), MeshKit.mat(Color(0.26, 0.17, 0.12), 0.6), Vector3(0.45, 1.05, 0))
	var lamp := MeshKit.glow(Color(1.0, 0.8, 0.5), 2.0)
	_window_mats.append(lamp)
	MeshKit.part(self, MeshKit.box(Vector3(0.16, 0.28, 0.12)), lamp, h + Vector3(-1.3, 2.3, 5.06))
	_window_light(h + Vector3(0, 2.2, 4.4), 4.0)

	# Right wing: green-tinted windows over a stone wainscot.
	MeshKit.part(self, MeshKit.box(Vector3(5.0, 0.7, 0.12)), stone, h + Vector3(3.7, 0.35, 2.44))
	for x in [2.5, 4.9]:
		_window(h + Vector3(x, 1.65, 2.4), Vector2(1.4, 1.2), trim)
	_gable_roof(h + Vector3(3.7, 3.2, 2.7), 4.6, 0.8, 1.0, stucco, tile, trim)

	# Driveway, red brick walk, gravel yard, sidewalk and street.
	MeshKit.part(self, MeshKit.box(Vector3(4.8, 0.04, 5.8)), concrete, h + Vector3(-3.8, -0.012, 7.5))
	var brick := MeshKit.mat(Color(0.62, 0.3, 0.25))
	var walk_from := Vector3(0.4, 0, 5.3)
	var walk_to := Vector3(2.8, 0, 10.4)
	var walk := MeshKit.part(self, MeshKit.box(Vector3(1.0, 0.05, walk_from.distance_to(walk_to))), brick, h + (walk_from + walk_to) * 0.5 + Vector3(0, -0.017, 0))
	walk.rotation.y = atan2(walk_to.x - walk_from.x, walk_to.z - walk_from.z)
	MeshKit.part(self, MeshKit.box(Vector3(60, 0.05, 1.5)), concrete, h + Vector3(0, -0.016, 11.2))
	MeshKit.part(self, MeshKit.box(Vector3(80, 0.03, 9.0)), MeshKit.mat(Color(0.25, 0.25, 0.27)), h + Vector3(0, -0.012, 16.3))
	_vehicle(h + Vector3(-3.9, 0, 7.6), PI, Color(0.96, 0.96, 0.96), false, true)

	# Desert landscaping: shrubs, a small tree, a desert willow and spiky agaves.
	var sage := MeshKit.mat(Color(0.33, 0.42, 0.26))
	for b in [[Vector3(1.4, 0, 7.6), 0.75], [Vector3(2.9, 0, 6.2), 0.55], [Vector3(-7.2, 0, 7.0), 0.5], [Vector3(5.6, 0, 8.5), 0.45]]:
		var r: float = b[1]
		MeshKit.part(self, MeshKit.sphere(r, r * 1.5, 10, 6), sage, h + b[0] + Vector3(0, r * 0.6, 0))
	var topiary := MeshKit.part(self, MeshKit.sphere(0.9, 1.6, 10, 6), MeshKit.mat(Color(0.18, 0.3, 0.16)), h + Vector3(-9.6, 0.8, 5.6))
	topiary.scale = Vector3(1.0, 1.0, 0.8)
	_mesquite(h + Vector3(5.4, 0, 7.0), 0.55)
	_mesquite(h + Vector3(-8.8, 0, 3.6), 0.8)
	var agave := MeshKit.mat(Color(0.42, 0.52, 0.38))
	for spot in [Vector3(0.9, 0, 5.9), Vector3(-6.4, 0, 9.4), Vector3(4.0, 0, 9.8)]:
		for k in 9:
			var a := TAU * k / 9.0
			var leaf := MeshKit.part(self, MeshKit.cyl(0.0, 0.07, 0.9, 4), agave, h + spot + Vector3(cos(a) * 0.15, 0.4, sin(a) * 0.15))
			leaf.rotation = Vector3(sin(a) * 0.7, 0, -cos(a) * 0.7)
	# Matching neighbors on both sides.
	for nx in [-14.0, 14.0]:
		MeshKit.part(self, MeshKit.box(Vector3(11.0, 3.2, 9.0)), stucco, h + Vector3(nx, 1.6, -1.5))
		var nr := Node3D.new()
		nr.position = h + Vector3(nx, 3.2, -1.5)
		nr.rotation.y = PI / 2
		add_child(nr)
		_gable_roof(Vector3.ZERO, 9.0, 11.0, 1.6, stucco, tile, trim, nr)
		MeshKit.part(self, MeshKit.box(Vector3(3.6, 2.3, 0.06)), door_tan, h + Vector3(nx + signf(nx) * 2.5, 1.15, 3.03))


## A front wall from x0 to x1 (height `top`, face at `face.z`) with arched
## openings, each [left, right, spring height, arch rise].
func _arch_wall(face: Vector3, x0: float, x1: float, top: float, openings: Array, stucco: Material) -> void:
	var z := face.z - 0.15
	var base := Vector3(face.x, face.y, 0)
	var cursor := x0
	for o in openings:
		var ox0: float = o[0]
		var ox1: float = o[1]
		var spring: float = o[2]
		var rise: float = o[3]
		if ox0 > cursor:
			MeshKit.part(self, MeshKit.box(Vector3(ox0 - cursor, top, 0.3)), stucco, base + Vector3((cursor + ox0) / 2, top / 2, z))
		var cx := (ox0 + ox1) / 2
		var half := (ox1 - ox0) / 2
		var strips := 32
		var w := (ox1 - ox0) / strips
		for k in strips:
			var xm := ox0 + w * (k + 0.5)
			var dx := (xm - cx) / half
			var ya := spring + rise * sqrt(maxf(0.0, 1.0 - dx * dx))
			MeshKit.part(self, MeshKit.box(Vector3(w + 0.01, top - ya, 0.3)), stucco, base + Vector3(xm, (ya + top) / 2, z))
		cursor = ox1
	if x1 > cursor:
		MeshKit.part(self, MeshKit.box(Vector3(x1 - cursor, top, 0.3)), stucco, base + Vector3((cursor + x1) / 2, top / 2, z))


## Simple vehicles parked in the scenes: a cargo van, a pickup or an SUV.
## `yaw` 0 means the front points toward -Z.
func _vehicle(pos: Vector3, yaw: float, paint: Color, van: bool, suv := false) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	add_child(root)
	var body := MeshKit.mat(paint, 0.35, 0.3)
	var glass := MeshKit.mat(Color(0.08, 0.1, 0.12), 0.1, 0.4)
	var tire := MeshKit.mat(Color(0.08, 0.08, 0.08))
	var length := 5.8 if van else (4.6 if suv else 5.4)
	var wheel_z := length / 2 - 0.9
	for x in [-0.82, 0.82]:
		for z in [-wheel_z, wheel_z]:
			MeshKit.part(root, MeshKit.cyl(0.36, 0.36, 0.25, 12), tire, Vector3(x, 0.36, z), Vector3(0, 0, PI / 2))
	if van:
		MeshKit.part(root, MeshKit.box(Vector3(2.0, 2.3, length - 0.8)), body, Vector3(0, 1.55, 0.4))
		MeshKit.part(root, MeshKit.box(Vector3(2.0, 1.1, 0.9)), body, Vector3(0, 0.95, -length / 2 + 0.45))
		MeshKit.part(root, MeshKit.box(Vector3(1.9, 0.75, 0.05)), glass, Vector3(0, 1.85, -length / 2 + 0.82), Vector3(-0.35, 0, 0))
		MeshKit.part(root, MeshKit.box(Vector3(1.6, 0.7, 0.04)), glass, Vector3(0, 2.0, length / 2 + 0.01))
	elif suv:
		MeshKit.part(root, MeshKit.box(Vector3(1.9, 0.85, length)), body, Vector3(0, 0.8, 0))
		MeshKit.part(root, MeshKit.box(Vector3(1.75, 0.7, length - 1.6)), body, Vector3(0, 1.55, 0.25))
		MeshKit.part(root, MeshKit.box(Vector3(1.77, 0.5, length - 1.7)), glass, Vector3(0, 1.58, 0.25))
		var tail := MeshKit.glow(Color(0.9, 0.08, 0.06), 1.0)
		for x in [-0.75, 0.75]:
			MeshKit.part(root, MeshKit.box(Vector3(0.3, 0.12, 0.05)), tail, Vector3(x, 1.1, length / 2 + 0.01))
	else:
		MeshKit.part(root, MeshKit.box(Vector3(1.9, 0.8, length)), body, Vector3(0, 0.85, 0))
		MeshKit.part(root, MeshKit.box(Vector3(1.8, 0.75, 1.8)), body, Vector3(0, 1.6, -0.5))
		MeshKit.part(root, MeshKit.box(Vector3(1.82, 0.5, 1.6)), glass, Vector3(0, 1.62, -0.5))
		MeshKit.part(root, MeshKit.box(Vector3(1.7, 0.4, 1.9)), MeshKit.mat(Color(0.1, 0.1, 0.1)), Vector3(0, 1.1, 1.6))


func _build_cast() -> void:
	_hero = Figure.hero()
	_mate = Figure.mate()
	_fox = Critter.fox()
	_otter = Critter.otter()
	for actor in [_hero, _mate, _fox, _otter]:
		add_child(actor)
		actor.visible = false


func _build_weather() -> void:
	_rain = CPUParticles3D.new()
	var drop := MeshKit.box(Vector3(0.015, 0.5, 0.015))
	var drop_mat := StandardMaterial3D.new()
	drop_mat.albedo_color = Color(0.75, 0.82, 0.95, 0.45)
	drop_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = drop_mat
	_rain.mesh = drop
	_rain.amount = 2500
	_rain.lifetime = 1.2
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(18, 1, 18)
	_rain.direction = Vector3(0.1, -1, 0)
	_rain.spread = 3.0
	_rain.initial_velocity_min = 22.0
	_rain.initial_velocity_max = 26.0
	_rain.local_coords = false
	_rain.emitting = false
	_rain.position = Vector3(0, 10, -8)
	_camera.add_child(_rain)
	_rain_audio = AudioStreamPlayer.new()
	_rain_audio.stream = Audio.get_stream("loop_rain")
	_rain_audio.bus = "SFX"
	_rain_audio.volume_db = -60.0
	add_child(_rain_audio)


func _plane(size: float) -> PlaneMesh:
	var p := PlaneMesh.new()
	p.size = Vector2(size, size)
	return p


func _hills(center: Vector3, color: Color) -> void:
	var mat := MeshKit.mat(color)
	for k in 10:
		var a := TAU * k / 10.0 + randf_range(-0.2, 0.2)
		var r := randf_range(28.0, 45.0)
		MeshKit.part(self, MeshKit.sphere(r, r * randf_range(0.5, 0.8), 12, 6), mat,
			center + Vector3(cos(a), 0.0, sin(a)) * randf_range(85.0, 115.0))


func _flowers(center: Vector3, radius: float, count: int) -> void:
	var palette := [Color(1.0, 0.6, 0.75), Color(1.0, 0.9, 0.4), Color(0.98, 0.98, 0.95), Color(0.75, 0.6, 1.0), Color(1.0, 0.55, 0.35)]
	var mesh := MeshKit.sphere(0.07, -1.0, 6, 3)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		var a := randf() * TAU
		var d := sqrt(randf()) * radius
		mm.set_instance_transform(i, Transform3D(Basis(), center + Vector3(cos(a) * d, 0.1, sin(a) * d)))
		mm.set_instance_color(i, palette[randi() % palette.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _ripples(noise_seed: int, frequency: float) -> NoiseTexture2D:
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
