class_name RainCover
extends Node3D
## Four forked poles and a thatched fern roof, tall enough to walk under. Put
## it over the hearth or the bedroll: under it the cold creeps in slower, like
## a lean-to (see Shelter.covers).

const HALF := 1.35  # half the roof's width
const HEIGHT := 2.3
const COVER_RADIUS := 1.7


static func build(parent: Node, at: Vector3, yaw: float) -> RainCover:
	var c := RainCover.new()
	c.position = at
	c.rotation.y = yaw
	parent.add_child(c)
	return c


static func ghost(material: Material) -> Node3D:
	var g := Node3D.new()
	_shape(g, material, material, material)
	return g


static func _shape(parent: Node3D, poles: Material, thatch: Material, vine: Material) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			MeshKit.part(parent, MeshKit.cyl(0.045, 0.06, HEIGHT, 6), poles, Vector3(sx * HALF, HEIGHT * 0.5, sz * HALF))
	# Cross beams, tied at the corners.
	for sz in [-1.0, 1.0]:
		MeshKit.part(parent, MeshKit.cyl(0.04, 0.04, HALF * 2.2, 6), poles, Vector3(0, HEIGHT, sz * HALF), Vector3(0, 0, PI / 2))
	for sx in [-1.0, 1.0]:
		MeshKit.part(parent, MeshKit.cyl(0.04, 0.04, HALF * 2.2, 6), poles, Vector3(sx * HALF, HEIGHT + 0.06, 0), Vector3(PI / 2, 0, 0))
		for sz in [-1.0, 1.0]:
			MeshKit.part(parent, MeshKit.sphere(0.07, 0.1, 5, 3), vine, Vector3(sx * HALF, HEIGHT + 0.03, sz * HALF))
	# The thatch: two gentle slopes of fern bundles meeting at a low ridge.
	for side in [-1.0, 1.0]:
		for row in 3:
			for k in 4:
				var x: float = side * (0.25 + row * 0.42)
				var z := lerpf(-HALF, HALF, (k + 0.5) / 4.0)
				var leaf := MeshKit.part(parent, MeshKit.box(Vector3(0.62, 0.05, 0.85)), thatch,
					Vector3(x + rng.randf_range(-0.04, 0.04), HEIGHT + 0.42 - row * 0.15, z + rng.randf_range(-0.05, 0.05)),
					Vector3(rng.randf_range(-0.05, 0.05), 0, side * -0.34))
				leaf.scale.x = rng.randf_range(0.95, 1.15)


func _ready() -> void:
	add_to_group("rain_covers")
	_shape(self, MeshKit.mat(Color(0.36, 0.26, 0.17), 0.95), MeshKit.mat(Color(0.3, 0.42, 0.18), 0.9), MeshKit.mat(Color(0.3, 0.36, 0.16), 0.9))
	var body := StaticBody3D.new()
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var pole := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 0.08
			cyl.height = HEIGHT
			pole.shape = cyl
			pole.position = Vector3(sx * HALF, HEIGHT * 0.5, sz * HALF)
			body.add_child(pole)
	add_child(body)
