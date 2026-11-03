extends Node3D
## Shows models/hero once it's dropped in, cycling through its animations
## (Space = next). Without a model it says what to add.
## godot_console --path . res://tools/rig_preview.tscn [-- --rig=mate --anim=walk --screenshot=path]

var _rig: CharacterRig
var _states: PackedStringArray
var _index := 0
var _label: Label


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.36, 0.42)
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := MeshKit.part(self, MeshKit.cyl(2.0, 2.0, 0.05, 32), MeshKit.mat(Color(0.25, 0.27, 0.3)), Vector3(0, -0.025, 0))
	floor_mesh.name = "Floor"
	var cam := Camera3D.new()
	cam.fov = 35.0
	cam.position = Vector3(0, 1.2, 5.2)
	add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0))
	cam.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(24, 20)
	_label.add_theme_font_size_override("font_size", 22)
	layer.add_child(_label)

	var rig_name := "hero"
	var start_anim := ""
	var no_soft := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rig="):
			rig_name = a.trim_prefix("--rig=")
		elif a == "--head-side":
			# Close on the side of the head, where single-picture paint used to streak.
			cam.fov = 22.0
			cam.position = Vector3(1.6, 1.75, 0.5)
			cam.look_at(Vector3(0, 1.72, 0))
		elif a == "--head-34":
			# Three-quarter view from a little below, to see the jaw and under the chin.
			cam.fov = 22.0
			cam.position = Vector3(1.1, 1.45, 1.3)
			cam.look_at(Vector3(0, 1.7, 0))
		elif a == "--head-front":
			cam.fov = 22.0
			cam.position = Vector3(0.0, 1.72, 1.7)
			cam.look_at(Vector3(0, 1.72, 0))
		elif a == "--no-soft":
			no_soft = true
		elif a.begins_with("--anim="):
			start_anim = a.trim_prefix("--anim=")
	_rig = CharacterRig.create(rig_name, 1.93 if rig_name == "hero" else 1.5)
	if _rig and no_soft:
		for mi: MeshInstance3D in _rig.find_children("*", "MeshInstance3D", true, false):
			mi.set_surface_override_material(0, null)
	if _rig == null:
		_label.text = "No model yet: put hero.fbx in models/hero/ and animations in models/hero/anims/"
		var stand_in := Figure.hero()
		stand_in.rotation.y = PI
		add_child(stand_in)
	else:
		_rig.rotation.y = PI  # face the camera
		add_child(_rig)
		_states = _rig.states()
		_index = maxi(_states.find(start_anim), 0)
		_show_state()
	if Game.screenshot_mode:
		await get_tree().create_timer(Game.screenshot_delay).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(Game.screenshot_path)
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE and not _states.is_empty():
		_index = (_index + 1) % _states.size()
		_show_state()



func _show_state() -> void:
	if _states.is_empty():
		_label.text = "Model loaded, no animations in models/hero/anims/ yet"
		return
	_rig.play(_states[_index])
	_label.text = "Animation: %s   (%d/%d, Space = next)" % [_states[_index], _index + 1, _states.size()]
