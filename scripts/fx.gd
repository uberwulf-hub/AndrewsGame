extends Node
## Short-lived visual effects (autoload "FX"): tracers, particle bursts, rings,
## the Bloom flower, light flashes and floating damage numbers.


func _scene() -> Node:
	return get_tree().current_scene


func tracer(from: Vector3, to: Vector3, color: Color, width := 0.035) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.box(Vector3(width, width, length))
	var mat := MeshKit.glow(color, 6.0, true)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scene().add_child(mi)
	var dir := (to - from) / length
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	mi.look_at_from_position((from + to) * 0.5, to, up)
	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.09)
	tw.tween_callback(mi.queue_free)


func burst(pos: Vector3, color: Color, amount := 12, speed := 5.0, size := 0.08) -> void:
	var p := CPUParticles3D.new()
	var mesh := MeshKit.box(Vector3.ONE * size)
	mesh.material = MeshKit.glow(color, 3.0)
	p.mesh = mesh
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.55
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -12.0, 0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	_scene().add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func ring(pos: Vector3, radius: float, color: Color, duration := 0.35) -> void:
	var mi := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.88
	mesh.outer_radius = 1.0
	mesh.rings = 48
	mi.mesh = mesh
	var mat := MeshKit.glow(color, 5.0, true)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scene().add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.2
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(mi.queue_free)


## Bloom: a flower of light opens at your feet, its petals unfurling, then a
## wave of petals drifts out across `radius` and settles. Soft, not a blast.
func bloom(pos: Vector3, radius: float, color: Color) -> void:
	var root := Node3D.new()
	_scene().add_child(root)
	root.global_position = pos
	var petal_mat := MeshKit.glow(color, 1.1, true)
	petal_mat.albedo_color.a = 0.85
	var heart_mat := MeshKit.glow(color.lerp(Color(1.0, 0.95, 0.7), 0.6), 3.0, true)
	# The flower: two layers of petals that open from closed, lift a little,
	# then fade.
	for layer in 2:
		var count := 8 if layer == 0 else 6
		for k in count:
			var hinge := Node3D.new()
			hinge.rotation.y = TAU * k / count + layer * 0.3
			root.add_child(hinge)
			var petal := MeshKit.part(hinge, MeshKit.sphere(0.32 - layer * 0.08, 0.1, 8, 4), petal_mat, Vector3(0, 0, -0.38 + layer * 0.1))
			petal.scale = Vector3(0.55, 1.0, 1.4)
			petal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			hinge.rotation.x = 1.3  # closed, petals pointing up
			var tw := hinge.create_tween()
			tw.tween_property(hinge, "rotation:x", -0.15 - layer * 0.25, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(layer * 0.06)
	var heart := MeshKit.part(root, MeshKit.sphere(0.12, 0.24, 8, 4), heart_mat, Vector3(0, 0.05, 0))
	heart.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var grow := root.create_tween().set_parallel()
	root.scale = Vector3.ONE * 0.4
	grow.tween_property(root, "scale", Vector3.ONE * 1.6, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	grow.tween_property(root, "position:y", root.position.y + 0.25, 1.4)
	grow.tween_property(petal_mat, "albedo_color:a", 0.0, 1.0).set_delay(0.5)
	grow.tween_property(heart_mat, "albedo_color:a", 0.0, 0.8).set_delay(0.6)
	grow.chain().tween_callback(root.queue_free)
	# The wave of petals drifting out and down.
	var p := CPUParticles3D.new()
	var leaf := MeshKit.sphere(0.07, 0.03, 6, 3)
	leaf.material = MeshKit.glow(color.lerp(Color.WHITE, 0.2), 1.6)
	p.mesh = leaf
	p.one_shot = true
	p.amount = 70
	p.lifetime = 1.6
	p.explosiveness = 0.9
	p.direction = Vector3(1, 0.25, 0)
	p.spread = 180.0
	p.flatness = 0.85
	p.initial_velocity_min = radius * 0.9
	p.initial_velocity_max = radius * 1.4
	p.damping_min = radius * 0.7
	p.damping_max = radius * 0.9
	p.gravity = Vector3(0, -0.6, 0)
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.particle_flag_rotate_y = true
	var fade := Curve.new()
	fade.add_point(Vector2(0, 1))
	fade.add_point(Vector2(0.7, 0.8))
	fade.add_point(Vector2(1, 0))
	p.scale_amount_curve = fade
	_scene().add_child(p)
	p.global_position = pos + Vector3(0, 0.3, 0)
	p.emitting = true
	get_tree().create_timer(2.2).timeout.connect(p.queue_free)


func flash(pos: Vector3, color: Color, energy := 4.0, light_range := 8.0, duration := 0.25) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	_scene().add_child(light)
	light.global_position = pos
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, duration)
	tw.tween_callback(light.queue_free)


func damage_number(pos: Vector3, amount: float, color: Color, crit := false) -> void:
	var label := Label3D.new()
	label.text = str(roundi(amount)) + ("!" if crit else "")
	label.font_size = 64 if crit else 42
	label.outline_size = 14
	label.modulate = color
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0008
	_scene().add_child(label)
	label.global_position = pos + Vector3(randf_range(-0.4, 0.4), randf_range(0.0, 0.3), randf_range(-0.4, 0.4))
	var tw := label.create_tween().set_parallel()
	tw.tween_property(label, "position:y", label.position.y + 1.2, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(label, "modulate:a", 0.0, 0.45).set_delay(0.25)
	tw.tween_property(label, "outline_modulate:a", 0.0, 0.45).set_delay(0.25)
	tw.chain().tween_callback(label.queue_free)
