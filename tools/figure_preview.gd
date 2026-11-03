extends Node3D
## Lineup of the family for checking faces and bodies.
## godot_console --path . res://tools/figure_preview.tscn -- --screenshot=path [--shot-yaw=deg] [--shot-pos=dist,height]


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.36, 0.42)
	env.ambient_light_color = Color(0.7, 0.72, 0.78)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var lineup := [[Figure.hero(), -0.75], [Figure.older_kid(), -0.25], [Figure.younger_kid(), 0.22], [Figure.mate(), 0.7]]
	for entry in lineup:
		var f: Figure = entry[0]
		f.position = Vector3(entry[1], 0, 0)
		f.rotation.y = PI + Game.shot_yaw
		add_child(f)
	var cam := Camera3D.new()
	cam.fov = 35.0
	var dist := 6.0
	var height := 1.0
	var aim_x := 0.0
	if Game.has_shot_pos:
		dist = Game.shot_pos.x
		height = Game.shot_pos.y
	if dist < 2.5:
		aim_x = -0.75 if height > 1.6 else 0.0
	cam.position = Vector3(aim_x, height, dist)
	add_child(cam)
	cam.look_at(Vector3(aim_x, height - 0.03 * dist, 0))
	cam.current = true
	if Game.screenshot_mode:
		await get_tree().create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(Game.screenshot_path)
		get_tree().quit()
