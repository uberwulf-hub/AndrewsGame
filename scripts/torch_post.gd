class_name TorchPost
extends Node3D
## A stick pushed into the ground with birch bark tied around the top and lit:
## a small flame, warm light, and a little warmth right beside it.

const WARM_RADIUS := 2.2

var _light: OmniLight3D
var _t := 0.0
var _burn_check := 0.0


static func build(parent: Node, at: Vector3) -> TorchPost:
	var t := TorchPost.new()
	t.position = at
	parent.add_child(t)
	return t


static func ghost(material: Material) -> Node3D:
	var g := Node3D.new()
	_shape(g, material, material, material)
	return g


static func _shape(parent: Node3D, wood: Material, bark: Material, vine: Material) -> void:
	MeshKit.part(parent, MeshKit.cyl(0.035, 0.045, 1.5, 6), wood, Vector3(0, 0.75, 0))
	MeshKit.part(parent, MeshKit.cyl(0.08, 0.07, 0.24, 8), bark, Vector3(0, 1.5, 0))
	for y in [1.44, 1.56]:
		MeshKit.part(parent, MeshKit.cyl(0.085, 0.085, 0.025, 8), vine, Vector3(0, y, 0))


## True when `pos` is close enough to a torch to feel it.
static func warms(tree: SceneTree, pos: Vector3) -> bool:
	for t in tree.get_nodes_in_group("torches"):
		if (t as Node3D).global_position.distance_to(pos) < WARM_RADIUS:
			return true
	return false


func _ready() -> void:
	add_to_group("torches")
	_shape(self, MeshKit.mat(Color(0.36, 0.26, 0.17), 0.95), MeshKit.mat(Color(0.85, 0.82, 0.74), 0.9), MeshKit.mat(Color(0.3, 0.42, 0.18), 0.9))
	var flame := CPUParticles3D.new()
	var flame_mesh := MeshKit.sphere(0.05, 0.13, 6, 3)
	flame_mesh.material = MeshKit.glow(Color(1.0, 0.58, 0.18), 6.0, true)
	flame.mesh = flame_mesh
	flame.amount = 16
	flame.lifetime = 0.5
	flame.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flame.emission_sphere_radius = 0.06
	flame.direction = Vector3.UP
	flame.spread = 10.0
	flame.initial_velocity_min = 0.5
	flame.initial_velocity_max = 0.9
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 1))
	shrink.add_point(Vector2(1, 0))
	flame.scale_amount_curve = shrink
	flame.position = Vector3(0, 1.64, 0)
	add_child(flame)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.62, 0.3)
	_light.omni_range = 7.0
	_light.position = Vector3(0, 1.8, 0)
	add_child(_light)


func _process(delta: float) -> void:
	_t += delta
	_light.light_energy = 1.3 + sin(_t * 11.0) * 0.15 + sin(_t * 6.1) * 0.2
	_burn_check -= delta
	if _burn_check <= 0.0:
		_burn_check = 0.1
		Burns.check(self, 0.32, 0.0, 0.0, 1.64)
