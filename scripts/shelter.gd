class_name Shelter
extends Node3D
## A lean-to: two forked poles holding a ridge pole, sticks leaned from the
## ridge down to the ground behind, and ferns layered over them. The open side
## faces the way it was built from (local +Z). Resting under it slows the cold.

const COVER_RADIUS := 1.5

## Where the roof is, relative to the ridge: it slopes down toward local -Z.
const DEPTH := 1.5
const WIDTH := 2.0
const HEIGHT := 1.35


static func build(parent: Node, at: Vector3, yaw: float) -> Shelter:
	var s := Shelter.new()
	s.position = at
	s.rotation.y = yaw
	parent.add_child(s)
	return s


## The see-through preview shown while choosing where to build.
static func ghost(material: Material) -> Node3D:
	var g := Node3D.new()
	_shape(g, material, material, material)
	return g


## True when `pos` is under the roof of any lean-to.
static func covers(tree: SceneTree, pos: Vector3) -> bool:
	for s in tree.get_nodes_in_group("shelters"):
		var under := (s as Node3D).global_transform * Vector3(0, 0, -DEPTH * 0.45)
		if Vector2(pos.x - under.x, pos.z - under.z).length() < COVER_RADIUS:
			return true
	return false


func _ready() -> void:
	add_to_group("shelters")
	_shape(self, MeshKit.mat(Color(0.36, 0.26, 0.17), 0.95), MeshKit.mat(Color(0.42, 0.31, 0.2), 0.95), MeshKit.mat(Color(0.22, 0.42, 0.18), 0.9))
	_solid()


## Solid roof and uprights, so you can't walk through it; the open front
## stays open to tuck in at.
func _solid() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var roof := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(WIDTH + 0.2, 0.15, Vector2(DEPTH, HEIGHT).length() + 0.2)
	roof.shape = slab
	roof.position = Vector3(0, HEIGHT * 0.5, -DEPTH * 0.5)
	roof.rotation.x = -atan2(HEIGHT, DEPTH)  # along the slope, ridge to ground
	body.add_child(roof)
	# The roof's gentle enough to walk up, so the back half is walled off tall.
	var back := CollisionShape3D.new()
	var block := BoxShape3D.new()
	block.size = Vector3(WIDTH + 0.2, 2.2, DEPTH * 0.6)
	back.shape = block
	back.position = Vector3(0, 1.1, -DEPTH * 0.7)
	body.add_child(back)
	for side in [-1.0, 1.0]:
		var pole := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.08
		cyl.height = HEIGHT
		pole.shape = cyl
		pole.position = Vector3(side * WIDTH * 0.5, HEIGHT * 0.5, 0)
		body.add_child(pole)


static func _shape(parent: Node3D, poles: Material, sticks: Material, ferns: Material) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	# Forked uprights and the ridge across them.
	for side in [-1.0, 1.0]:
		MeshKit.part(parent, MeshKit.cyl(0.04, 0.05, HEIGHT, 6), poles, Vector3(side * WIDTH * 0.5, HEIGHT * 0.5, 0))
		MeshKit.part(parent, MeshKit.cyl(0.02, 0.03, 0.3, 5), poles, Vector3(side * (WIDTH * 0.5 + 0.06), HEIGHT + 0.08, 0), Vector3(0, 0, -side * 0.5))
	MeshKit.part(parent, MeshKit.cyl(0.045, 0.045, WIDTH + 0.3, 6), poles, Vector3(0, HEIGHT, 0), Vector3(0, 0, PI / 2))
	# Sticks leaned from the ridge to the ground behind.
	var slope := atan2(DEPTH, HEIGHT)
	var length := Vector2(DEPTH, HEIGHT).length() + 0.2
	for k in 9:
		var x := lerpf(-WIDTH * 0.45, WIDTH * 0.45, k / 8.0) + rng.randf_range(-0.05, 0.05)
		MeshKit.part(parent, MeshKit.cyl(0.025, 0.035, length, 5), sticks, Vector3(x, HEIGHT * 0.5, -DEPTH * 0.5), Vector3(slope + rng.randf_range(-0.04, 0.04), 0, 0))
	# Ferns laid over the sticks in overlapping rows.
	for row in 3:
		for k in 4:
			var t := (row + 0.5) / 3.0
			var leaf := MeshKit.part(parent, MeshKit.box(Vector3(0.62, 0.03, 0.62)), ferns,
				Vector3(lerpf(-WIDTH * 0.38, WIDTH * 0.38, k / 3.0) + rng.randf_range(-0.06, 0.06), HEIGHT * (1.0 - t) + 0.05, -DEPTH * t),
				Vector3(-(PI / 2 - slope) + rng.randf_range(-0.08, 0.08), rng.randf_range(-0.3, 0.3), 0))
			leaf.scale = Vector3(rng.randf_range(0.9, 1.15), 1.0, rng.randf_range(0.9, 1.15))
