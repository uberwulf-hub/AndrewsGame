class_name DreamCatcher
extends Node3D
## A stick bent into a hoop with a vine web across it, hung from a little
## crooked post, with bone beads and feathers dangling underneath. It sways in
## the breeze. Sleep on a bedroll near one and the good dreams stay longer:
## "well rested" lasts twice as long (see Bedroll.use).

const REACH := 4.0  # how near a bedroll it has to hang
const HANG := Vector3(0.3, 1.66, 0.0)  # where the hoop hangs from the post's arm

var _hoop: Node3D
var _t := randf() * TAU
var _flick := 0.0


static func build(parent: Node, at: Vector3, yaw: float) -> DreamCatcher:
	var d := DreamCatcher.new()
	d.position = at
	d.rotation.y = yaw
	parent.add_child(d)
	return d


static func ghost(material: Material) -> Node3D:
	var g := Node3D.new()
	_post(g, material)
	var hoop := Node3D.new()
	hoop.position = HANG
	g.add_child(hoop)
	_charm(hoop, material, material, material, material, material)
	return g


## True when a dream catcher hangs close enough to `spot` (a bedroll).
static func near(tree: SceneTree, spot: Vector3) -> bool:
	for d in tree.get_nodes_in_group("dream_catchers"):
		if (d as Node3D).global_position.distance_to(spot) < REACH:
			return true
	return false


## A post pushed into the ground with a short arm sticking out at the top.
static func _post(parent: Node3D, wood: Material) -> void:
	MeshKit.part(parent, MeshKit.cyl(0.025, 0.035, 1.75, 6), wood, Vector3(0, 0.875, 0), Vector3(0.04, 0, 0.03))
	MeshKit.part(parent, MeshKit.cyl(0.02, 0.025, 0.36, 5), wood, Vector3(0.15, 1.62, 0), Vector3(0, 0, -(PI / 2 - 0.2)))


## The hoop and everything hanging off it, built around the hang point (0, 0, 0).
static func _charm(parent: Node3D, wood: Material, vine: Material, bone: Material, feather: Material, tip: Material) -> void:
	const R := 0.22
	var c := Vector3(0, -0.04 - R, 0)
	MeshKit.part(parent, MeshKit.cyl(0.004, 0.004, 0.06, 3), vine, Vector3(0, -0.03, 0))
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = R - 0.012
	torus.outer_radius = R + 0.012
	torus.rings = 24
	torus.ring_segments = 5
	ring.mesh = torus
	ring.material_override = wood
	ring.position = c
	ring.rotation.x = PI / 2  # stand the hoop up, facing out along Z
	parent.add_child(ring)
	# The web: a woven star (each point tied to the ones three along), with a
	# smaller star inside it and a bone bead in the middle.
	for web in [[R * 0.97, 9, 4], [R * 0.55, 7, 3]]:
		var r: float = web[0]
		var points: int = web[1]
		var skip: int = web[2]
		for k in points:
			var a1 := TAU * k / points + 0.3
			var a2 := TAU * (k + skip) / points + 0.3
			var p1 := Vector2(cos(a1), sin(a1)) * r
			var p2 := Vector2(cos(a2), sin(a2)) * r
			var mid := (p1 + p2) * 0.5
			var thread := MeshKit.part(parent, MeshKit.box(Vector3(p1.distance_to(p2), 0.005, 0.005)), vine, c + Vector3(mid.x, mid.y, 0))
			thread.rotation.z = (p2 - p1).angle()
	MeshKit.part(parent, MeshKit.sphere(0.024, -1.0, 6, 4), bone, c + Vector3(0, 0, 0.004))
	# Three strings of bone beads, each ending in a long feather (the middle one longest).
	for k in 3:
		var x := (k - 1) * 0.13
		var top := c.y - sqrt(R * R - x * x)
		var length := 0.12 + (0.08 if k == 1 else 0.0)
		MeshKit.part(parent, MeshKit.cyl(0.004, 0.004, length, 3), vine, Vector3(x, top - length / 2.0, 0))
		MeshKit.part(parent, MeshKit.cyl(0.02, 0.02, 0.05, 6), bone, Vector3(x, top - length * 0.4, 0))
		var tilt := -x * 0.9
		var holder := Node3D.new()
		holder.position = Vector3(x, top - length, 0)
		holder.rotation.z = tilt
		parent.add_child(holder)
		MeshKit.part(holder, MeshKit.cyl(0.004, 0.004, 0.3, 3), bone, Vector3(0, -0.15, 0.006))  # the quill
		var vane := MeshKit.part(holder, MeshKit.sphere(0.05, 0.3, 6, 4), feather, Vector3(0, -0.16, 0))
		vane.scale = Vector3(1.0, 1.0, 0.15)
		MeshKit.part(holder, MeshKit.sphere(0.045, 0.09, 6, 3), tip, Vector3(0, -0.28, 0)).scale = Vector3(1.0, 1.0, 0.15)


func _ready() -> void:
	add_to_group("dream_catchers")
	var wood := MeshKit.mat(Color(0.7, 0.52, 0.32), 0.9)  # wrapped in pale bark
	_post(self, MeshKit.mat(Color(0.36, 0.26, 0.17), 0.95))
	_hoop = Node3D.new()
	_hoop.position = HANG
	add_child(_hoop)
	_charm(_hoop, wood, MeshKit.mat(Color(0.5, 0.55, 0.3), 0.9), MeshKit.mat(Color(0.93, 0.9, 0.82), 0.6),
		MeshKit.mat(Color(0.62, 0.42, 0.26), 0.8), MeshKit.mat(Color(0.95, 0.93, 0.88), 0.8))


func _process(delta: float) -> void:
	# A slow sway in the breeze, plus a bigger swing after a nap nearby.
	_t += delta
	_flick = maxf(0.0, _flick - delta * 0.4)
	_hoop.rotation.z = sin(_t * 1.3) * 0.06 + sin(_t * 4.0) * _flick * 0.35
	_hoop.rotation.y = sin(_t * 0.7) * 0.25


## Gives it a little swing (the good dreams sliding down the feathers).
func flick() -> void:
	_flick = 1.0
