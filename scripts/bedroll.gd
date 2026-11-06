class_name Bedroll
extends Node3D
## Ferns bundled into a soft mattress on a low stick frame, tied with vines,
## with a rolled-up end for a pillow. E: sleep a while, and wake up well
## rested (skills grow faster for a while, see Game.rested).

const USE_RADIUS := 1.6


static func build(parent: Node, at: Vector3, yaw: float) -> Bedroll:
	var b := Bedroll.new()
	b.position = at
	b.rotation.y = yaw
	parent.add_child(b)
	return b


static func ghost(material: Material) -> Node3D:
	var g := Node3D.new()
	_shape(g, material, material, material)
	return g


static func _shape(parent: Node3D, wood: Material, fern: Material, vine: Material) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for side in [-1.0, 1.0]:
		MeshKit.part(parent, MeshKit.cyl(0.03, 0.03, 2.0, 5), wood, Vector3(side * 0.42, 0.05, 0), Vector3(PI / 2, 0, 0))
	# The mattress: overlapping fern bundles, a bit lumpy.
	for k in 6:
		var z := lerpf(-0.8, 0.65, k / 5.0)
		var bundle := MeshKit.part(parent, MeshKit.box(Vector3(0.82, 0.12, 0.34)), fern, Vector3(rng.randf_range(-0.03, 0.03), 0.11, z))
		bundle.rotation = Vector3(rng.randf_range(-0.05, 0.05), rng.randf_range(-0.08, 0.08), rng.randf_range(-0.04, 0.04))
	# Rolled-up pillow end and two vine ties.
	MeshKit.part(parent, MeshKit.cyl(0.13, 0.13, 0.8, 8), fern, Vector3(0, 0.2, -0.95), Vector3(0, 0, PI / 2))
	for z in [-0.4, 0.35]:
		MeshKit.part(parent, MeshKit.box(Vector3(0.86, 0.14, 0.04)), vine, Vector3(0, 0.12, z))


func _ready() -> void:
	add_to_group("usables")
	add_to_group("bedrolls")
	_shape(self, MeshKit.mat(Color(0.36, 0.26, 0.17), 0.95), MeshKit.mat(Color(0.27, 0.45, 0.2), 0.95), MeshKit.mat(Color(0.3, 0.36, 0.16), 0.9))


func use_radius() -> float:
	return USE_RADIUS


func use_prompt() -> String:
	return "[E] Sleep on the bedroll"


func use(player: Player) -> void:
	if player.frozen:
		return
	player.frozen = true
	var layer := CanvasLayer.new()
	layer.layer = 40
	var dark := ColorRect.new()
	dark.color = Color(0.02, 0.02, 0.05, 0.0)
	dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(dark)
	add_child(layer)
	Audio.play("gear_rustle", global_position, -6.0, 0.8)
	var tw := create_tween()
	tw.tween_property(dark, "color:a", 1.0, 1.4)
	tw.tween_interval(1.6)
	tw.tween_callback(func():
		Game.rested = Game.RESTED_TIME
		Game.warmth = minf(100.0, Game.warmth + 25.0)
		player.heal(player.max_health * 0.5)
		Game.practice("Survival", 1.0))
	tw.tween_property(dark, "color:a", 0.0, 1.6)
	tw.tween_callback(func():
		player.frozen = false
		layer.queue_free()
		Game.notify("You wake up well rested. Skills grow faster for a while.", Color(1.0, 0.9, 0.6))
		Game.built.emit("sleep", global_position))
