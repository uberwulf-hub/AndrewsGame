class_name LakeRuin
extends StaticBody3D
## Old stones at the edge of the lake: a mossy plinth on the shore with a
## second heartstone on it, a broken arch standing in the shallows like a
## doorway into the water, and columns stepping down until the lake swallows
## them. Out past the last one, on the lake bed, something waits to glow
## (the second Memory Echo's dare, see World).

const DEEP := 2.6  # how far below the surface the lake bed must reach nearby
const WATER := Game.WATER_LEVEL

signal treasure_taken

var heartstone: Heartstone
var treasure: LakeTreasure
var out := Vector3.FORWARD  # from the shore out over the water


## The best shore for it: dry ground just above the waterline with deep water
## a short swim out, fairly near the Sanctum, away from trees and from where
## the hero woke. Returns {"shore": Vector3, "deep": Vector3}, or {} if none.
static func find_spot(avoid: Vector3) -> Dictionary:
	var best := {}
	var best_score := -INF
	for ring in range(34, 124, 3):
		for k in 72:
			var a := TAU * k / 72.0
			var p := Vector3(cos(a), 0, sin(a)) * ring
			p.y = Game.height_at(p.x, p.z)
			if p.y < WATER + 0.35 or p.y > WATER + 1.3:
				continue
			if Vector2(p.x - avoid.x, p.z - avoid.z).length() < 30.0:
				continue
			var deep := Vector3.ZERO
			var found := false
			for j in 16:
				var b := TAU * j / 16.0
				for r in [7.0, 10.0, 13.0]:
					var q: Vector3 = p + Vector3(cos(b), 0, sin(b)) * r
					q.y = Game.height_at(q.x, q.z)
					if q.y < WATER - DEEP and (not found or q.y < deep.y):
						deep = q
						found = true
			if not found:
				continue
			var land := Vector3(p.x - deep.x, 0, p.z - deep.z).normalized()
			# Room on dry, gentle ground behind it for the plinth.
			var back := p + land * 3.0
			var back_y := Game.height_at(back.x, back.z)
			if back_y < WATER + 0.3 or back_y > p.y + 1.6:
				continue
			var trees := 0
			for t in Animal.trunks:
				if Vector2((t[0] as Vector3).x - p.x, (t[0] as Vector3).z - p.z).length() < 9.0:
					trees += 1
			var score := -ring * 0.06 - trees * 5.0 + minf(WATER - deep.y, 4.0) * 0.5
			if score > best_score:
				best_score = score
				best = {"shore": p, "deep": deep}
	return best


static func build(parent: Node3D, spot: Dictionary, stone_mats: Array) -> LakeRuin:
	var r := LakeRuin.new()
	r.name = "LakeRuin"
	var shore: Vector3 = spot.shore
	var deep: Vector3 = spot.deep
	r.out = Vector3(deep.x - shore.x, 0, deep.z - shore.z).normalized()
	r.position = Vector3(shore.x, 0, shore.z)
	r.rotation.y = atan2(-r.out.x, -r.out.z)  # local -Z points out over the water
	parent.add_child(r)
	r._build(stone_mats, r.to_local(deep))
	# Clear away any scattered trees or boulders standing in it.
	for n in parent.get_children():
		if n is StaticBody3D and n != r and not n.name in ["Sanctum", "ForestTrunks"]:
			if Vector2((n as Node3D).position.x - shore.x, (n as Node3D).position.z - shore.z).length() < 7.5:
				n.queue_free()
	return r


## The ground (or lake bed) under a local point.
func _ground(local: Vector3) -> float:
	var g := to_global(Vector3(local.x, 0, local.z))
	return Game.ground_at(g.x, g.z)


func _build(stone_mats: Array, deep_local: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var stone: StandardMaterial3D = stone_mats[0]
	var pale: StandardMaterial3D = stone_mats[2]
	var moss := MeshKit.mat(Color(0.3, 0.44, 0.2), 0.95)
	var deep_moss := MeshKit.mat(Color(0.22, 0.36, 0.16), 0.95)
	var wet := MeshKit.mat(Color(0.28, 0.3, 0.27), 0.35)  # dark and slick where the water laps
	var weed := MeshKit.mat(Color(0.2, 0.34, 0.2), 0.9)

	# The plinth, back on the dry shore: two worn steps and a block, mossy.
	var base := Vector3(0, 0, 1.4)
	var y := _ground(base) - 0.15
	_box(Vector3(2.6, 0.5, 2.2), base + Vector3(0, y + 0.25, 0), Vector3(0, 0.05, 0), stone)
	_box(Vector3(1.6, 0.6, 1.3), base + Vector3(0, y + 0.8, 0), Vector3(0, -0.04, 0), pale)
	_box(Vector3(1.9, 0.14, 1.55), base + Vector3(0, y + 1.17, 0), Vector3(0, 0.03, 0), stone)
	MeshKit.part(self, MeshKit.box(Vector3(1.0, 0.04, 0.7)), moss, base + Vector3(0.35, y + 1.25, 0.2), Vector3(0, 0.4, 0))
	MeshKit.part(self, MeshKit.cyl(1.5, 1.6, 0.3, 9), deep_moss, base + Vector3(0, y + 0.1, 0)).scale = Vector3(1.0, 1.0, 0.85)
	heartstone = Heartstone.new()
	heartstone.position = base + Vector3(0, y + 1.42, -0.1)
	add_child(heartstone)
	MeshKit.part(heartstone, MeshKit.sphere(0.2, 0.3, 7, 4), MeshKit.glow(Color(0.6, 0.85, 1.0), 1.6))
	var light := OmniLight3D.new()
	light.light_color = Color(0.6, 0.85, 1.0)
	light.light_energy = 0.8
	light.omni_range = 7.0
	light.position.y = 0.3
	heartstone.add_child(light)
	Audio.attach_loop(heartstone, "loop_crystal", -12.0, 14.0, 4.0)

	# Broken columns either side of the plinth, one standing, one snapped short.
	for c in [[Vector3(-2.4, 0, 1.0), 2.6], [Vector3(2.5, 0, 0.8), 1.3]]:
		var at: Vector3 = c[0]
		_column(at, _ground(at) - 0.2, c[1], stone, moss, rng)

	# A few worn steps leading down to the water.
	for k in 3:
		var at := Vector3(rng.randf_range(-0.2, 0.2), 0, -0.4 - k * 1.1)
		var g := _ground(at)
		MeshKit.part(self, MeshKit.box(Vector3(1.8 - k * 0.2, 0.22, 0.9)), stone if k == 0 else wet,
			at + Vector3(0, g + 0.02, 0), Vector3(rng.randf_range(-0.05, 0.05), rng.randf_range(-0.15, 0.15), rng.randf_range(-0.05, 0.05)))

	# The arch in the shallows: a doorway into the lake.
	var arch_z := -4.2
	var top := WATER + 2.3
	for side in [-1.0, 1.0]:
		var at := Vector3(side * 1.4, 0, arch_z)
		var foot := _ground(at) - 0.3
		var h := top - foot
		var post := MeshKit.part(self, MeshKit.box(Vector3(0.6, h, 0.6)), pale, at + Vector3(0, foot + h * 0.5, 0))
		post.rotation.z = side * 0.03
		_shape(true, Vector3(0.6, h, 0.6), at + Vector3(0, foot + h * 0.5, 0), Vector3.ZERO)
		MeshKit.part(self, MeshKit.box(Vector3(0.64, 0.5, 0.64)), wet, at + Vector3(0, WATER + 0.05, 0))
		MeshKit.part(self, MeshKit.sphere(0.36, 0.2, 7, 3), moss, at + Vector3(0, top + 0.02, 0))
	_box(Vector3(3.6, 0.5, 0.75), Vector3(0, top + 0.25, arch_z), Vector3(0, 0, 0.03), stone)
	MeshKit.part(self, MeshKit.box(Vector3(2.4, 0.06, 0.6)), moss, Vector3(-0.3, top + 0.53, arch_z))
	# A chunk of the arch that fell, lying in the shallows beside it.
	MeshKit.part(self, MeshKit.box(Vector3(1.1, 0.45, 0.6)), wet, Vector3(2.4, _ground(Vector3(2.4, 0, arch_z + 0.8)) + 0.15, arch_z + 0.8), Vector3(0.2, 0.7, 0.15))

	# Columns stepping out into the lake, each one a little more drowned.
	var heights := [1.4, 0.5, -0.4, -1.0]
	for k in heights.size():
		var t := float(k + 1) / (heights.size() + 1.0)
		var along := Vector3(0, 0, -6.5).lerp(Vector3(deep_local.x, 0, deep_local.z) * 0.85, t)
		for side in [-1.0, 1.0]:
			var at := along + Vector3(side * rng.randf_range(1.6, 2.1), 0, 0)
			var foot := _ground(at) - 0.2
			var h: float = WATER + float(heights[k]) - foot + rng.randf_range(-0.15, 0.15)
			if h < 0.6:
				continue
			_column(at, foot, h, stone, weed if heights[k] < 0.0 else moss, rng)
	# One long fallen column on the lake bed, pointing the way out.
	var fall := Vector3(deep_local.x, 0, deep_local.z) * 0.62
	var fall_y := _ground(fall) + 0.25
	var fallen := MeshKit.part(self, MeshKit.cyl(0.3, 0.34, 3.6, 8), stone, fall + Vector3(0, fall_y, 0))
	fallen.rotation = Vector3(PI / 2, atan2(deep_local.x, deep_local.z) + 0.3, 0)
	# Weed swaying up from the bed around the columns.
	for k in 14:
		var at := Vector3(deep_local.x, 0, deep_local.z) * rng.randf_range(0.3, 0.95) + Vector3(rng.randf_range(-3.0, 3.0), 0, rng.randf_range(-1.5, 1.5))
		var g := _ground(at)
		if g > WATER - 0.6:
			continue
		var h := minf(rng.randf_range(0.6, 1.6), WATER - g - 0.3)
		MeshKit.part(self, MeshKit.cyl(0.02, 0.06, h, 4), weed, at + Vector3(0, g + h * 0.5, 0), Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2)))

	# What waits on the lake bed (dark until the dare).
	treasure = LakeTreasure.new()
	treasure.position = Vector3(deep_local.x, _ground(deep_local) + 0.12, deep_local.z)
	add_child(treasure)
	treasure.taken.connect(func(): treasure_taken.emit())


## A worn, mossy column, broken off at height `h` above `foot`.
func _column(at: Vector3, foot: float, h: float, stone: Material, cap: Material, rng: RandomNumberGenerator) -> void:
	var lean := Vector3(rng.randf_range(-0.06, 0.06), rng.randf() * TAU, rng.randf_range(-0.06, 0.06))
	MeshKit.part(self, MeshKit.cyl(0.3, 0.36, h, 8), stone, at + Vector3(0, foot + h * 0.5, 0), lean)
	MeshKit.part(self, MeshKit.cyl(0.44, 0.48, 0.3, 8), stone, at + Vector3(0, foot + 0.15, 0))
	MeshKit.part(self, MeshKit.sphere(0.32, 0.18, 7, 3), cap, at + Vector3(0, foot + h, 0), lean)
	_shape(false, Vector3(0.34, h, 0), at + Vector3(0, foot + h * 0.5, 0), lean)


func _box(size: Vector3, pos: Vector3, rot: Vector3, material: Material) -> void:
	MeshKit.part(self, MeshKit.box(size), material, pos, rot)
	_shape(true, size, pos, rot)


func _shape(box_shape: bool, size: Vector3, pos: Vector3, rot: Vector3) -> void:
	var shape := CollisionShape3D.new()
	if box_shape:
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
	else:
		var cyl := CylinderShape3D.new()
		cyl.radius = size.x
		cyl.height = size.y
		shape.shape = cyl
	shape.position = pos
	shape.rotation = rot
	add_child(shape)
