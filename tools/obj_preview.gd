extends Node3D
## Front / side / back of the first .obj in models/preview (a painted, unrigged model).


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.36, 0.42)
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 20, 0)
	add_child(sun)
	var mesh: Mesh
	var want := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--obj="):
			want = a.trim_prefix("--obj=")
	for f in DirAccess.get_files_at("res://models/preview"):
		if f.get_extension() == "obj" and (want == "" or f.get_basename() == want):
			mesh = load("res://models/preview/" + f)
	for k in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = Vector3((k - 1) * 1.4, 0, 0)
		mi.rotation.y = [0.0, PI / 2, PI][k]
		add_child(mi)
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.position = Vector3(0, 0.6, 4.0)
	add_child(cam)
	cam.current = true
	if Game.screenshot_mode:
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(Game.screenshot_path)
		get_tree().quit()
