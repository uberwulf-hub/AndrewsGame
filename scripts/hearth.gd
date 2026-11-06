class_name Hearth
extends Campfire
## The home fire: a wide ring of flat stones, a low curved wall at the back to
## throw the heat forward, and a flat cooking stone at the side. It's a
## campfire in every other way (cook, sit, rest), just warmer and wider.

const HEARTH_WARM := 9.5


static func build_hearth(parent: Node, at: Vector3, yaw := 0.0) -> Hearth:
	var h := Hearth.new()
	h.position = at
	h.rotation.y = yaw
	parent.add_child(h)
	return h


static func hearth_ghost(material: Material) -> Node3D:
	var g := Node3D.new()
	_hearth_shape(g, material, material, material)
	return g


func _ready() -> void:
	super()
	add_to_group("hearths")


func _make_shape() -> void:
	_hearth_shape(self, MeshKit.mat(Color(0.5, 0.48, 0.44), 0.9), MeshKit.mat(Color(0.3, 0.2, 0.12)), MeshKit.mat(Color(0.4, 0.38, 0.35), 0.85))


func warm_radius() -> float:
	return HEARTH_WARM


static func _hearth_shape(parent: Node3D, stone: Material, wood: Material, slab: Material) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	# A floor of flat stones under the fire.
	MeshKit.part(parent, MeshKit.cyl(0.62, 0.66, 0.06, 12), slab, Vector3(0, 0.03, 0))
	# The ring: twelve flat stones.
	for k in 12:
		var a := TAU * k / 12.0
		var s := MeshKit.part(parent, MeshKit.sphere(0.17, 0.18, 7, 4), stone, Vector3(cos(a) * 0.68, 0.08, sin(a) * 0.68))
		s.scale = Vector3(rng.randf_range(1.1, 1.4), 0.9, rng.randf_range(0.9, 1.2))
		s.rotation.y = -a
	# The back wall (local -Z): stones stacked two high in an arc.
	for row in 2:
		for k in 5:
			var a := lerpf(-1.1, 1.1, k / 4.0) + row * 0.11 - PI / 2
			var s := MeshKit.part(parent, MeshKit.sphere(0.19, 0.22, 7, 4), stone, Vector3(cos(a) * 0.9, 0.17 + row * 0.27, sin(a) * 0.9))
			s.scale = Vector3(1.3, 0.75, 0.9)
			s.rotation.y = -a
	# A flat cooking stone off to one side.
	MeshKit.part(parent, MeshKit.cyl(0.3, 0.33, 0.1, 9), slab, Vector3(1.05, 0.12, 0.25))
	for k in 3:
		var a := TAU * k / 3.0
		MeshKit.part(parent, MeshKit.sphere(0.09, 0.1, 6, 3), stone, Vector3(1.05 + cos(a) * 0.2, 0.04, 0.25 + sin(a) * 0.2))
	# Split logs laid in a little cabin.
	for k in 4:
		MeshKit.part(parent, MeshKit.cyl(0.055, 0.065, 0.8, 6), wood, Vector3(0, 0.16, 0), Vector3(0.95, TAU * k / 4.0 + 0.4, 0))
