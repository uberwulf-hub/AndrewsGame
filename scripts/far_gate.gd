class_name FarGate
extends StaticBody3D
## Where the far light comes from: a ledge up on the mountains across the
## valley, reached by an old stone stair, with a great stone ring standing on
## it. Five little sockets sit around the ring; one still holds the other
## dreamer's marble, faintly glowing. Their backpack leans against the ring
## with a last page in it. The light rises from a basin in front of the ring.


const LEDGE_R := 4.6
const SOCKETS := 5

var page: IsleHouse.Page
var ring_stone: RingStone
var stair_foot := Vector3.ZERO  # world position where the stair starts, down in the valley
var _sockets: Array[MeshInstance3D] = []
var _socket_lights: Array[OmniLight3D] = []
var _lit := 0


## Builds it on the mountains along `dir` (flat, unit) from the Sanctum.
static func build(parent: Node3D, dir: Vector3, stone_mats: Array) -> FarGate:
	var g := FarGate.new()
	g.name = "FarGate"
	var at := dir * 184.0
	# The ledge: level with the highest ground under it.
	var top := -INF
	for k in 16:
		var a := TAU * k / 16.0
		for r in [0.0, 2.5, LEDGE_R]:
			top = maxf(top, Game.height_at(at.x + cos(a) * r, at.z + sin(a) * r))
	g.position = Vector3(at.x, top + 0.15, at.z)
	g.rotation.y = atan2(-dir.x, -dir.z)  # local +Z looks back across the valley
	parent.add_child(g)
	g._build(stone_mats, dir)
	# Clear trees and boulders off the ledge and the stair.
	var spots: Array = [[at, 13.0]]
	var n_samples := int(g.stair_foot.distance_to(at) / 3.0)
	for k in n_samples:
		spots.append([g.stair_foot.lerp(at, float(k) / n_samples), 4.5])
	g._clear(parent, spots)
	return g


## Removes trees, bushes and rocks within each [point, radius] of `spots`.
func _clear(parent: Node3D, spots: Array) -> void:
	var center: Vector3 = spots[0][0]
	var reach := stair_foot.distance_to(center) + 15.0
	var near := func(p: Vector3) -> bool:
		if absf(p.x - center.x) > reach or absf(p.z - center.z) > reach:
			return false
		for s in spots:
			if Vector2(p.x - (s[0] as Vector3).x, p.z - (s[0] as Vector3).z).length() < s[1]:
				return true
		return false
	for n in parent.get_children():
		if n is StaticBody3D and n != self and n.name.begins_with("@") and near.call((n as Node3D).global_position):
			n.queue_free()
		elif n is MultiMeshInstance3D:
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			for i in mm.instance_count:
				var t := mm.get_instance_transform(i)
				if near.call(t.origin):
					mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), t.origin))
		elif n.name == "ForestTrunks":
			for s in n.get_children():
				if s is CollisionShape3D and near.call((s as Node3D).position):
					s.queue_free()
	Animal.trunks = Animal.trunks.filter(func(t): return not near.call(t[0]))


## Where the light column stands (the basin in front of the ring).
func light_at() -> Vector3:
	return to_global(Vector3(0, 0, 1.2))


func ring_center() -> Vector3:
	return to_global(Vector3(0, 2.6, -0.6))


func _build(stone_mats: Array, dir: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8484
	var stone: StandardMaterial3D = stone_mats[0]
	var pale: StandardMaterial3D = stone_mats[2]
	var moss := MeshKit.mat(Color(0.3, 0.44, 0.2), 0.95)

	# The ledge: a round stone floor, deep enough to sit into the mountainside.
	var floor_mesh := MeshKit.part(self, MeshKit.cyl(LEDGE_R, LEDGE_R + 0.6, 6.0, 20), stone, Vector3(0, -3.0, 0))
	floor_mesh.name = "Ledge"
	var floor_shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = LEDGE_R
	cyl.height = 6.0
	floor_shape.shape = cyl
	floor_shape.position = Vector3(0, -3.0, 0)
	add_child(floor_shape)
	for k in 7:
		var a := rng.randf() * TAU
		MeshKit.part(self, MeshKit.box(Vector3(1.0, 0.05, 0.8)), pale, Vector3(cos(a), 0, sin(a)) * rng.randf_range(1.0, 3.6) + Vector3(0, 0.02, 0), Vector3(0, rng.randf() * TAU, 0))

	# The stair: one long stone ramp down to the valley floor, worn steps on top.
	var edge := Vector3(0, 0, LEDGE_R - 0.3)  # local, on the valley side
	var foot_r := 150.0
	var foot := dir * foot_r
	foot.y = Game.ground_at(foot.x, foot.z)
	var top_world := to_global(edge)
	# No steeper than about 33 degrees: start further in if the climb is big.
	while foot_r > 120.0 and (top_world.y - foot.y) / Vector2(top_world.x - foot.x, top_world.z - foot.z).length() > 0.65:
		foot_r -= 3.0
		foot = dir * foot_r
		foot.y = Game.ground_at(foot.x, foot.z)
	# And it starts on dry land, not in a lake.
	while foot_r < 176.0 and foot.y < Game.WATER_LEVEL + 0.4:
		foot_r += 1.0
		foot = dir * foot_r
		foot.y = Game.ground_at(foot.x, foot.z)
	stair_foot = foot
	var foot_l := to_local(foot)
	var run := Vector3(foot_l.x - edge.x, foot_l.y - edge.y, foot_l.z - edge.z)
	var length := run.length()
	var mid := edge + run * 0.5
	var basis := Basis.looking_at(-run.normalized(), Vector3.UP)  # -Z up the stair... local +Z down it
	var ramp := MeshInstance3D.new()
	ramp.mesh = MeshKit.box(Vector3(2.4, 0.6, length))
	ramp.material_override = stone
	ramp.transform = Transform3D(basis, mid + basis.y * -0.3)
	add_child(ramp)
	var ramp_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 0.6, length)
	ramp_shape.shape = box
	ramp_shape.transform = ramp.transform
	add_child(ramp_shape)
	var steps := int(length / 0.9)
	for k in steps:
		var t := (k + 0.5) / steps
		var p := edge + run * t
		var step := MeshKit.part(self, MeshKit.box(Vector3(2.2, 0.08, 0.5)), pale if k % 2 else stone, p + basis.y * 0.02)
		step.basis = basis
		# Little cairns along the way, every so often.
		if k % 9 == 4:
			var side := 1.6 if (k / 9) % 2 == 0 else -1.6
			var c := p + basis.x * side
			var gy := Game.ground_at(to_global(c).x, to_global(c).z) - position.y
			for s in 3:
				MeshKit.part(self, MeshKit.sphere(0.24 - s * 0.06, 0.18, 6, 3), stone, Vector3(c.x, maxf(gy, c.y - 1.0) + 0.1 + s * 0.16, c.z))

	# The ring, standing at the back of the ledge, facing the valley.
	ring_stone = RingStone.new()
	ring_stone.position = Vector3(0, 2.6, -0.6)
	add_child(ring_stone)
	var torus := TorusMesh.new()
	torus.inner_radius = 1.9
	torus.outer_radius = 2.6
	torus.rings = 40
	torus.ring_segments = 10
	var ring := MeshKit.part(ring_stone, torus, pale, Vector3.ZERO, Vector3(PI / 2, 0, 0))
	ring.name = "Ring"
	MeshKit.part(ring_stone, MeshKit.box(Vector3(1.4, 0.5, 0.9)), stone, Vector3(0, -2.55, 0))
	_shape(Vector3(1.0, 0.8, 0.8), Vector3(-2.2, 0.4, -0.6))
	_shape(Vector3(1.0, 0.8, 0.8), Vector3(2.2, 0.4, -0.6))
	_shape(Vector3(0.8, 5.2, 0.8), Vector3(-2.3, 2.6, -0.6))
	_shape(Vector3(0.8, 5.2, 0.8), Vector3(2.3, 2.6, -0.6))
	MeshKit.part(ring_stone, MeshKit.sphere(0.6, 0.25, 7, 3), moss, Vector3(0.4, 2.55, 0))
	# The sockets, spaced round the upper part of the ring.
	for k in SOCKETS:
		var a := lerpf(0.35, PI - 0.35, float(k) / (SOCKETS - 1))
		var at := Vector3(cos(a) * 2.25, sin(a) * 2.25, 0.33)
		MeshKit.part(ring_stone, MeshKit.cyl(0.2, 0.2, 0.12, 10), stone, at, Vector3(PI / 2, 0, 0))
		var gem := MeshKit.part(ring_stone, MeshKit.sphere(0.13), MeshKit.mat(Color(0.25, 0.25, 0.28), 0.4), at + Vector3(0, 0, 0.06))
		_sockets.append(gem)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.88, 0.6)
		l.light_energy = 0.0
		l.omni_range = 3.0
		l.position = at + Vector3(0, 0, 0.3)
		ring_stone.add_child(l)
		_socket_lights.append(l)
	set_lit(1)  # theirs, still singing softly

	# The basin the light rises from.
	MeshKit.part(self, MeshKit.cyl(0.9, 0.7, 0.5, 14), stone, Vector3(0, 0.25, 1.2))
	MeshKit.part(self, MeshKit.cyl(0.75, 0.75, 0.04, 14), MeshKit.glow(Color(1.0, 0.92, 0.7), 3.0), Vector3(0, 0.5, 1.2))
	_shape(Vector3(1.6, 0.5, 1.6), Vector3(0, 0.25, 1.2))
	Audio.attach_loop(self, "loop_crystal", -10.0, 18.0, 4.0)

	# Their backpack, leaning on the ring, with the last page sticking out.
	var bag := MeshKit.mat(Color(0.42, 0.3, 0.2), 0.95)
	MeshKit.part(self, MeshKit.box(Vector3(0.5, 0.6, 0.3)), bag, Vector3(1.5, 0.3, -0.1), Vector3(-0.2, 0.4, 0.05))
	MeshKit.part(self, MeshKit.box(Vector3(0.52, 0.12, 0.34)), MeshKit.mat(Color(0.32, 0.22, 0.15), 0.95), Vector3(1.5, 0.62, -0.05), Vector3(-0.2, 0.4, 0.05))
	MeshKit.part(self, MeshKit.cyl(0.08, 0.08, 0.5, 6), MeshKit.mat(Color(0.5, 0.48, 0.42)), Vector3(1.25, 0.25, 0.2), Vector3(0, 0, PI / 2))
	page = IsleHouse.Page.new()
	page.position = Vector3(1.4, 0.05, 0.45)
	page.rotation = Vector3(0, 0.4, 0)
	add_child(page)


## How many of the ring's sockets glow.
func set_lit(count: int, animate := false) -> void:
	_lit = count
	for k in SOCKETS:
		var on := k < count
		var m := MeshKit.glow(Color(1.0, 0.88, 0.6), 3.0) if on else MeshKit.mat(Color(0.25, 0.25, 0.28), 0.4)
		_sockets[k].material_override = m
		var want := 1.2 if on else 0.0
		if animate:
			create_tween().tween_property(_socket_lights[k], "light_energy", want, 2.0)
		else:
			_socket_lights[k].light_energy = want


func lit() -> int:
	return _lit


func _shape(size: Vector3, pos: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	add_child(shape)


## The ring itself: when it's ready, E holds the marble up to it.
class RingStone:
	extends Node3D

	signal used
	var ready_for_marble := false

	func use_radius() -> float:
		return 4.0

	func use_prompt() -> String:
		return "[E] Hold up your marble"

	func use(_player: Player) -> void:
		if not ready_for_marble:
			return
		ready_for_marble = false
		remove_from_group("usables")
		used.emit()

	func make_ready() -> void:
		ready_for_marble = true
		add_to_group("usables")
