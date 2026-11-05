class_name Campfire
extends Node3D
## A campfire built from sticks and stones: a stone ring, crossed logs, flames,
## embers, flickering warm light and crackle. Standing near it warms you up;
## E beside it opens the fire menu (cook, warm up, rest).

const WARM_RADIUS := 6.5

var _light: OmniLight3D
var _t := 0.0
var _burn_check := 0.0


static func build(parent: Node, at: Vector3) -> Campfire:
	var f := Campfire.new()
	f.position = at
	parent.add_child(f)
	return f


## The see-through preview shown while choosing where to build: just the ring
## and logs, all in one material.
static func ghost(material: Material) -> Node3D:
	var g := Node3D.new()
	_shape(g, material, material)
	return g


static func _shape(parent: Node3D, stone: Material, wood: Material) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for k in 9:
		var a := TAU * k / 9.0
		var s := MeshKit.part(parent, MeshKit.sphere(0.16, 0.2, 7, 4), stone, Vector3(cos(a) * 0.5, 0.06, sin(a) * 0.5))
		s.scale = Vector3(rng.randf_range(0.9, 1.3), 1.0, rng.randf_range(0.9, 1.3))
	for k in 4:
		MeshKit.part(parent, MeshKit.cyl(0.05, 0.06, 0.7, 6), wood, Vector3(0, 0.14, 0), Vector3(0.9, TAU * k / 4.0, 0))


func _ready() -> void:
	add_to_group("campfires")
	add_to_group("usables")
	# Built over the old fire ring, the new fire takes its place.
	for g in get_tree().get_nodes_in_group("gatherables"):
		if (g as Gatherable).kind == "fire_ring" and (g as Node3D).global_position.distance_to(global_position) < 1.6:
			g.queue_free()
	_shape(self, MeshKit.mat(Color(0.42, 0.4, 0.38), 0.9), MeshKit.mat(Color(0.3, 0.2, 0.12)))
	var flame := CPUParticles3D.new()
	var flame_mesh := MeshKit.sphere(0.1, 0.26, 6, 3)
	flame_mesh.material = MeshKit.glow(Color(1.0, 0.55, 0.15), 6.0, true)
	flame.mesh = flame_mesh
	flame.amount = 36
	flame.lifetime = 0.7
	flame.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flame.emission_sphere_radius = 0.16
	flame.direction = Vector3.UP
	flame.spread = 12.0
	flame.initial_velocity_min = 0.7
	flame.initial_velocity_max = 1.4
	flame.gravity = Vector3(0, 0.5, 0)
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0))
	flame.scale_amount_curve = shrink
	flame.position = Vector3(0, 0.2, 0)
	add_child(flame)
	var embers := CPUParticles3D.new()
	var ember_mesh := MeshKit.sphere(0.012, -1.0, 4, 2)
	ember_mesh.material = MeshKit.glow(Color(1.0, 0.6, 0.2), 8.0)
	embers.mesh = ember_mesh
	embers.amount = 20
	embers.lifetime = 2.2
	embers.direction = Vector3.UP
	embers.spread = 25.0
	embers.initial_velocity_min = 0.5
	embers.initial_velocity_max = 1.2
	embers.position = Vector3(0, 0.35, 0)
	add_child(embers)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.28)
	_light.omni_range = 10.0
	_light.shadow_enabled = true
	_light.position = Vector3(0, 0.6, 0)
	add_child(_light)
	Audio.attach_loop(self, "loop_fire", 0.0, 22.0, 4.0)


func _process(delta: float) -> void:
	_t += delta
	_light.light_energy = 2.4 + sin(_t * 13.0) * 0.25 + sin(_t * 7.3) * 0.35 + sin(_t * 23.0) * 0.12
	_burn_check -= delta
	if _burn_check <= 0.0:
		_burn_check = 0.1
		Burns.check(self, 0.62, -0.4, 0.75)


## True when `pos` is close enough to any campfire to be warmed by it.
static func warms(tree: SceneTree, pos: Vector3) -> bool:
	for f in tree.get_nodes_in_group("campfires"):
		if (f as Node3D).global_position.distance_to(pos) < WARM_RADIUS:
			return true
	return false


# --- Used with E: cook, warm up, or sit with the pets -----------------------------

func use_radius() -> float:
	return 2.3


func use_prompt() -> String:
	return "[E] Sit by the fire"


func use(player: Player) -> void:
	player.fire_requested.emit(self)
