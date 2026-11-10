class_name HillLookout
extends StaticBody3D
## The other dreamer's lookout, on the highest hill inside the mountains: a few
## worn flagstones, a cold little fire ring, a tall standing stone with a
## third heartstone set at its foot (the beach-run echo: Running), and a cairn
## with another page from that same dream journal tucked under its top stone.
## Reading it shows a thin light far off in the mountains (see World).

var heartstone: Heartstone
var page: IsleHouse.Page
var out := Vector3.FORWARD  # from the lookout back across the valley, toward the far light


## The highest walkable hilltop between the woods and the mountains, away from
## where the hero woke and from the lake's old stones. Returns a Vector3 or
## Vector3.INF if nothing fits.
static func find_spot(avoid: Array) -> Vector3:
	var best := Vector3.INF
	var best_score := -INF
	for ring in range(50, 126, 3):
		for k in 96:
			var a := TAU * k / 96.0
			var p := Vector3(cos(a), 0, sin(a)) * ring
			p.y = Game.height_at(p.x, p.z)
			if p.y < Game.WATER_LEVEL + 3.0:
				continue
			if avoid.any(func(q: Vector3): return Vector2(p.x - q.x, p.z - q.z).length() < 35.0):
				continue
			if Vector2(p.x - Game.ISLE.x, p.z - Game.ISLE.y).length() < 25.0:
				continue
			# Fairly level on top, so there's room to stand around the stones.
			var spread := 0.0
			for j in 8:
				var b := TAU * j / 8.0
				spread = maxf(spread, absf(Game.height_at(p.x + cos(b) * 4.0, p.z + sin(b) * 4.0) - p.y))
			if spread > 1.6:
				continue
			# Open ground, so there's a view (and the far light can be seen).
			var trees := 0
			for t in Animal.trunks:
				if Vector2((t[0] as Vector3).x - p.x, (t[0] as Vector3).z - p.z).length() < 16.0:
					trees += 1
			if trees > 3:
				continue
			var score := p.y - spread * 1.5 - ring * 0.02 - trees * 2.0
			if score > best_score:
				best_score = score
				best = p
	return best


static func build(parent: Node3D, at: Vector3, stone_mats: Array) -> HillLookout:
	var l := HillLookout.new()
	l.name = "HillLookout"
	l.out = -Vector3(at.x, 0, at.z).normalized()
	l.position = Vector3(at.x, 0, at.z)
	l.rotation.y = atan2(-l.out.x, -l.out.z)  # local -Z looks out toward the far light
	parent.add_child(l)
	l._build(stone_mats)
	# Clear away any scattered trees or boulders standing in it.
	for n in parent.get_children():
		if n is StaticBody3D and n != l and not n.name in ["Sanctum", "ForestTrunks"]:
			if Vector2((n as Node3D).position.x - at.x, (n as Node3D).position.z - at.z).length() < 6.5:
				n.queue_free()
	return l


## Where the far light stands: on the mountains across the valley, the far side
## of the Sanctum from the lookout.
func far_light_at() -> Vector3:
	var p := out * 192.0
	p.y = Game.height_at(p.x, p.z)
	return p


func _ground(local: Vector3) -> float:
	var g := to_global(Vector3(local.x, 0, local.z))
	return Game.ground_at(g.x, g.z)


func _build(stone_mats: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5151
	var stone: StandardMaterial3D = stone_mats[0]
	var pale: StandardMaterial3D = stone_mats[2]
	var moss := MeshKit.mat(Color(0.3, 0.44, 0.2), 0.95)
	var soot := MeshKit.mat(Color(0.12, 0.11, 0.1), 1.0)

	# Worn flagstones, sunk into the grass.
	for k in 9:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.6, 3.4)
		var at := Vector3(cos(a) * r, 0, sin(a) * r)
		MeshKit.part(self, MeshKit.box(Vector3(rng.randf_range(0.7, 1.2), 0.12, rng.randf_range(0.6, 1.0))), stone if k % 3 else pale,
			at + Vector3(0, _ground(at) + 0.02, 0), Vector3(0, rng.randf() * TAU, 0))

	# The standing stone, out at the edge, facing the view.
	var post := Vector3(0, 0, -2.6)
	var foot := _ground(post) - 0.3
	var slab := MeshKit.part(self, MeshKit.box(Vector3(1.1, 3.6, 0.55)), pale, post + Vector3(0, foot + 1.8, 0), Vector3(0.03, 0.1, 0.02))
	# A round window cut through it, like the little house's.
	MeshKit.part(slab, MeshKit.cyl(0.3, 0.3, 0.6, 14), MeshKit.mat(Color(0.1, 0.1, 0.1), 1.0), Vector3(0, 0.9, 0), Vector3(PI / 2, 0, 0))
	MeshKit.part(self, MeshKit.sphere(0.5, 0.22, 7, 3), moss, post + Vector3(0.1, foot + 3.6, 0), Vector3(0, 0, 0.05))
	_shape(Vector3(1.1, 3.6, 0.55), post + Vector3(0, foot + 1.8, 0), Vector3(0.03, 0.1, 0.02))

	# A low plinth at its foot with the heartstone on it.
	var base := Vector3(0, 0, -1.6)
	var y := _ground(base) - 0.1
	_box(Vector3(1.3, 0.5, 0.9), base + Vector3(0, y + 0.25, 0), Vector3(0, 0.08, 0), stone)
	_box(Vector3(1.0, 0.12, 0.7), base + Vector3(0, y + 0.56, 0), Vector3(0, -0.05, 0), pale)
	heartstone = Heartstone.new()
	heartstone.position = base + Vector3(0, y + 0.82, 0)
	add_child(heartstone)
	MeshKit.part(heartstone, MeshKit.sphere(0.2, 0.3, 7, 4), MeshKit.glow(Color(1.0, 0.8, 0.5), 1.6))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.5)
	light.light_energy = 0.8
	light.omni_range = 7.0
	light.position.y = 0.3
	heartstone.add_child(light)
	Audio.attach_loop(heartstone, "loop_crystal", -12.0, 14.0, 4.0)

	# The other dreamer's cold fire ring: stones and a smudge of old soot.
	var ring := Vector3(1.9, 0, 0.9)
	var ry := _ground(ring)
	MeshKit.part(self, MeshKit.cyl(0.5, 0.5, 0.02, 12), soot, ring + Vector3(0, ry + 0.02, 0))
	for k in 7:
		var a := TAU * k / 7.0
		MeshKit.part(self, MeshKit.sphere(0.14, 0.18, 6, 3), stone, ring + Vector3(cos(a) * 0.55, ry + 0.06, sin(a) * 0.55))

	# The cairn, with the page tucked under its top stone.
	var cairn := Vector3(-1.8, 0, 0.6)
	var cy := _ground(cairn)
	var h := cy
	for k in 4:
		var w := 0.7 - k * 0.13
		MeshKit.part(self, MeshKit.sphere(w * 0.5, 0.22, 7, 3), stone if k % 2 else pale, cairn + Vector3(rng.randf_range(-0.04, 0.04), h + 0.1, 0), Vector3(0, rng.randf() * TAU, 0))
		h += 0.2
	_shape(Vector3(0.7, 0.9, 0.7), cairn + Vector3(0, cy + 0.45, 0), Vector3.ZERO)
	page = IsleHouse.Page.new()
	page.position = cairn + Vector3(0.28, h - 0.12, 0.25)
	page.rotation = Vector3(0.25, 0.6, 0.1)
	add_child(page)


func _box(size: Vector3, pos: Vector3, rot: Vector3, material: Material) -> void:
	MeshKit.part(self, MeshKit.box(size), material, pos, rot)
	_shape(size, pos, rot)


func _shape(size: Vector3, pos: Vector3, rot: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	shape.rotation = rot
	add_child(shape)


## A thin, pale column of light rising from the far mountains, seen from
## anywhere once the page has pointed it out.
static func make_far_light(parent: Node3D, at: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "FarLight"
	root.position = at
	parent.add_child(root)
	var beam := MeshKit.glow(Color(1.0, 0.92, 0.7, 0.35), 2.5, true)
	beam.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam.disable_fog = true
	beam.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Fades away up close, so standing in it doesn't white out the screen.
	beam.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	beam.distance_fade_min_distance = 2.0
	beam.distance_fade_max_distance = 16.0
	var column := MeshKit.part(root, MeshKit.cyl(1.3, 0.6, 140.0, 10), beam, Vector3(0, 70.0, 0))
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var core := MeshKit.glow(Color(1.0, 0.95, 0.8), 6.0)
	core.disable_fog = true
	var star := MeshKit.part(root, MeshKit.sphere(0.55, 1.1, 10, 6), core, Vector3(0, 0.9, 0))
	star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tw := root.create_tween().set_loops()
	tw.tween_property(column, "scale", Vector3(1.25, 1.0, 1.25), 2.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(column, "scale", Vector3.ONE, 2.6).set_trans(Tween.TRANS_SINE)
	return root
