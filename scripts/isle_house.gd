class_name IsleHouse
extends Node3D
## A little wooden house on stilts, alone on a tiny island out in the lake:
## weathered boards, a mossy roof, a door hanging open, and a round window
## looking back toward the old stones on the shore. Someone lived here once.
## Inside there's a cot, a table, a shelf of empty jars, and on the table a
## page torn from someone else's dream journal (see World, "the little house").

const HALF_W := 2.0  # the house, side to side
const HALF_D := 1.8  # front to back
const DECK := 1.6  # how far the deck runs out in front
const WALL_H := 2.5
const WATER := Game.WATER_LEVEL

signal page_read

var floor_y := 0.0
var page: Page
var cot: Bedroll
var _ramp_from := Vector3.ZERO  # local: where the ramp leaves the deck
var _ramp_to := Vector3.ZERO  # and where it meets the ground


## On the little island (Game.ISLE), its front looking at `near` (the old
## stones on the shore). Returns {"at": Vector3, "face": Vector3}.
static func find_spot(near: Vector3) -> Dictionary:
	var at := Vector3(Game.ISLE.x, 0, Game.ISLE.y)
	at.y = Game.height_at(at.x, at.z)
	return {"at": at, "face": near}


static func build(parent: Node3D, spot: Dictionary, stone_mats: Array) -> IsleHouse:
	var h := IsleHouse.new()
	h.name = "IsleHouse"
	var at: Vector3 = spot.at
	var face: Vector3 = spot.face
	h.position = Vector3(at.x, 0, at.z)
	h.rotation.y = atan2(-(face.x - at.x), -(face.z - at.z))  # local -Z toward the shore stones
	parent.add_child(h)
	h._build(stone_mats)
	for n in parent.get_children():
		if n is StaticBody3D and n.name != "Sanctum" and Vector2((n as Node3D).position.x - at.x, (n as Node3D).position.z - at.z).length() < 6.0:
			n.queue_free()
	return h


func _ready() -> void:
	add_to_group("floors")


func _ground(local: Vector3) -> float:
	var g := to_global(Vector3(local.x, 0, local.z))
	return Game.ground_at(g.x, g.z)


## The top of the boards at a world point (for the pets), or -INF off them.
func floor_at(x: float, z: float) -> float:
	var l := to_local(Vector3(x, 0, z))
	if absf(l.x) < HALF_W + 0.05 and l.z > -HALF_D - DECK - 0.05 and l.z < HALF_D + 0.05:
		return floor_y
	var along := _ramp_to - _ramp_from
	along.y = 0.0
	var t := (Vector3(l.x, 0, l.z) - Vector3(_ramp_from.x, 0, _ramp_from.z)).dot(along) / along.length_squared()
	if t >= 0.0 and t <= 1.0:
		var side := Vector3(l.x, 0, l.z) - Vector3(_ramp_from.x, 0, _ramp_from.z) - along * t
		if side.length() < 0.55:
			return lerpf(_ramp_from.y, _ramp_to.y, t)
	return -INF


func _build(stone_mats: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5151
	var wood := MeshKit.mat(Color(0.47, 0.4, 0.33), 0.95)
	var grey := MeshKit.mat(Color(0.56, 0.53, 0.48), 0.95)
	var dark := MeshKit.mat(Color(0.32, 0.26, 0.21), 0.95)
	var roof := MeshKit.mat(Color(0.36, 0.33, 0.3), 0.95)
	var moss := MeshKit.mat(Color(0.3, 0.44, 0.2), 0.95)
	var vine := MeshKit.mat(Color(0.26, 0.42, 0.18), 0.9)
	var stone: StandardMaterial3D = stone_mats[0]

	# How high the boards sit: well clear of the water, a step above the island.
	var top := -INF
	for x in [-HALF_W, 0.0, HALF_W]:
		for z in [-HALF_D - DECK, 0.0, HALF_D]:
			top = maxf(top, _ground(Vector3(x, 0, z)))
	floor_y = maxf(WATER + 1.1, top + 0.45)

	# Stilts down to the island (or the lake bed), with stones at their feet.
	for x in [-HALF_W + 0.1, HALF_W - 0.1]:
		for z in [-HALF_D - DECK + 0.1, -HALF_D, 0.0, HALF_D - 0.1]:
			var at := Vector3(x, 0, z)
			var foot := _ground(at) - 0.3
			var h := floor_y - foot
			MeshKit.part(self, MeshKit.cyl(0.11, 0.13, h, 6), dark, at + Vector3(0, foot + h * 0.5, 0), Vector3(rng.randf_range(-0.03, 0.03), 0, rng.randf_range(-0.03, 0.03)))
			if foot + 0.3 > WATER - 0.3:
				MeshKit.part(self, MeshKit.sphere(0.25, 0.2, 6, 3), stone, at + Vector3(0, foot + 0.35, 0))

	# The boards: one collision slab under the house and the deck, planks on top.
	var depth := HALF_D * 2.0 + DECK
	_solid(Vector3(HALF_W * 2.0, 0.16, depth), Vector3(0, floor_y - 0.08, HALF_D - depth * 0.5))
	var plank_z := -HALF_D - DECK + 0.15
	while plank_z < HALF_D:
		MeshKit.part(self, MeshKit.box(Vector3(HALF_W * 2.0 + rng.randf_range(-0.05, 0.08), 0.06, 0.27)), grey if rng.randf() < 0.5 else wood,
			Vector3(rng.randf_range(-0.04, 0.04), floor_y + 0.01, plank_z), Vector3(0, rng.randf_range(-0.01, 0.01), 0))
		plank_z += 0.3
	# A low rail round the deck sides.
	# A low rail along the deck's left side (the ramp leaves from the right).
	var rail := Vector3(-HALF_W + 0.05, floor_y + 0.55, -HALF_D - DECK * 0.5)
	MeshKit.part(self, MeshKit.box(Vector3(0.08, 0.08, DECK)), wood, rail)
	_solid(Vector3(0.1, 1.0, DECK), rail + Vector3(0, -0.05, 0))
	for z in [-HALF_D - DECK + 0.1, -HALF_D - DECK * 0.5]:
		MeshKit.part(self, MeshKit.box(Vector3(0.08, 0.55, 0.08)), dark, Vector3(rail.x, floor_y + 0.27, z))

	# The walls, with a doorway and the round window cut out of the front.
	var walls := CSGCombiner3D.new()
	walls.use_collision = true
	add_child(walls)
	var wy := floor_y + WALL_H * 0.5
	for w in [
		[Vector3(HALF_W * 2.0, WALL_H, 0.14), Vector3(0, wy, -HALF_D)],
		[Vector3(HALF_W * 2.0, WALL_H, 0.14), Vector3(0, wy, HALF_D)],
		[Vector3(0.14, WALL_H, HALF_D * 2.0), Vector3(-HALF_W, wy, 0)],
		[Vector3(0.14, WALL_H, HALF_D * 2.0), Vector3(HALF_W, wy, 0)],
	]:
		var b := CSGBox3D.new()
		b.size = w[0]
		b.position = w[1]
		b.material = wood
		walls.add_child(b)
	var door := CSGBox3D.new()
	door.operation = CSGShape3D.OPERATION_SUBTRACTION
	door.size = Vector3(0.95, 2.15, 0.6)
	door.position = Vector3(0.85, floor_y + 1.075, -HALF_D)
	walls.add_child(door)
	var window := CSGCylinder3D.new()
	window.operation = CSGShape3D.OPERATION_SUBTRACTION
	window.radius = 0.42
	window.height = 0.6
	window.sides = 20
	window.rotation.x = PI / 2
	window.position = Vector3(-0.9, floor_y + 1.45, -HALF_D)
	walls.add_child(window)
	var back_window := CSGBox3D.new()
	back_window.operation = CSGShape3D.OPERATION_SUBTRACTION
	back_window.size = Vector3(0.6, 0.5, 0.6)
	back_window.position = Vector3(0.7, floor_y + 1.5, HALF_D)
	walls.add_child(back_window)
	# Boards running up the walls, outside, so they read as planks.
	for side in [-1.0, 1.0]:
		for k in 7:
			var z := lerpf(-HALF_D + 0.25, HALF_D - 0.25, k / 6.0)
			MeshKit.part(self, MeshKit.box(Vector3(0.03, WALL_H, 0.04)), dark, Vector3(side * (HALF_W + 0.08), wy, z))
	for k in 3:
		MeshKit.part(self, MeshKit.box(Vector3(HALF_W * 2.0, 0.05, 0.03)), dark, Vector3(0, floor_y + 0.6 + k * 0.85, HALF_D + 0.08))

	# The round window's frame, with a cross in it.
	var ring := TorusMesh.new()
	ring.inner_radius = 0.4
	ring.outer_radius = 0.52
	ring.rings = 20
	ring.ring_segments = 6
	MeshKit.part(self, ring, dark, Vector3(-0.9, floor_y + 1.45, -HALF_D - 0.07), Vector3(PI / 2, 0, 0))
	for r in [0.0, PI / 2]:
		MeshKit.part(self, MeshKit.box(Vector3(0.82, 0.05, 0.05)), dark, Vector3(-0.9, floor_y + 1.45, -HALF_D - 0.02), Vector3(0, 0, r))
	# The door, hanging open on one hinge.
	var slab := MeshKit.part(self, MeshKit.box(Vector3(0.9, 2.05, 0.06)), grey, Vector3(0.4 + 0.45 * cos(1.2), floor_y + 1.04, -HALF_D - 0.45 * sin(1.2)))
	slab.rotation = Vector3(0, 1.2, 0.04)
	# A frame round the doorway.
	for x in [0.85 - 0.52, 0.85 + 0.52]:
		MeshKit.part(self, MeshKit.box(Vector3(0.1, 2.2, 0.2)), dark, Vector3(x, floor_y + 1.1, -HALF_D))
	MeshKit.part(self, MeshKit.box(Vector3(1.15, 0.1, 0.2)), dark, Vector3(0.85, floor_y + 2.2, -HALF_D))

	# A pitched roof, mossy, with gable ends.
	var eave := HALF_D + 0.35
	var rise := HALF_D * tan(0.5)  # ridge above the wall tops
	var low := floor_y + WALL_H - 0.35 * tan(0.5)  # the roof's edge, out past the walls
	for side in [-1.0, 1.0]:
		var panel := MeshKit.part(self, MeshKit.box(Vector3(HALF_W * 2.0 + 0.5, 0.1, eave / cos(0.5))), roof,
			Vector3(0, low + eave * tan(0.5) * 0.5 + 0.05, side * eave * 0.5), Vector3(side * 0.5, 0, 0))
		for k in 3:
			MeshKit.part(panel, MeshKit.box(Vector3(rng.randf_range(0.6, 1.3), 0.04, rng.randf_range(0.4, 0.9))), moss,
				Vector3(rng.randf_range(-1.6, 1.6), 0.07, rng.randf_range(-0.6, 0.6)))
	for side in [-1.0, 1.0]:
		var gable := PrismMesh.new()
		gable.size = Vector3(HALF_D * 2.0, rise, 0.12)
		MeshKit.part(self, gable, wood, Vector3(side * HALF_W, floor_y + WALL_H + rise * 0.5, 0), Vector3(0, PI / 2, 0))
	MeshKit.part(self, MeshKit.cyl(0.07, 0.07, HALF_W * 2.0 + 0.6, 6), dark, Vector3(0, floor_y + WALL_H + rise + 0.02, 0), Vector3(0, 0, PI / 2))

	# Vines climbing the walls and hanging off the eaves.
	for k in 9:
		var on_front := k < 5
		var x := rng.randf_range(-HALF_W + 0.2, HALF_W - 0.2) if on_front else (HALF_W + 0.1) * (1.0 if k % 2 == 0 else -1.0)
		var z := -HALF_D - 0.09 if on_front else rng.randf_range(-HALF_D + 0.2, HALF_D - 0.2)
		if on_front and absf(x - 0.85) < 0.6:
			continue  # not across the doorway
		var length := rng.randf_range(0.9, 2.1)
		MeshKit.part(self, MeshKit.cyl(0.025, 0.035, length, 4), vine, Vector3(x, floor_y + WALL_H + 0.1 - length * 0.5, z), Vector3(0, 0, rng.randf_range(-0.12, 0.12)))
		MeshKit.part(self, MeshKit.sphere(0.16, 0.2, 5, 3), moss, Vector3(x, floor_y + WALL_H + 0.05, z))

	# The ramp down to the island, off the side of the deck.
	_ramp_from = Vector3(HALF_W, floor_y, -HALF_D - DECK * 0.5)
	var end_x := HALF_W + 2.6
	var end_ground := _ground(Vector3(end_x, 0, _ramp_from.z))
	_ramp_to = Vector3(end_x, maxf(end_ground, WATER - 0.6), _ramp_from.z)
	var mid := (_ramp_from + _ramp_to) * 0.5
	var run := Vector2(_ramp_to.x - _ramp_from.x, _ramp_to.y - _ramp_from.y)
	var tilt := atan2(run.y, run.x)
	var ramp_size := Vector3(run.length() + 0.2, 0.1, 0.9)
	MeshKit.part(self, MeshKit.box(ramp_size), grey, mid, Vector3(0, 0, tilt))
	_solid(ramp_size, mid - Vector3(0, 0.05, 0), Vector3(0, 0, tilt))
	for k in 4:
		var t := (k + 0.5) / 4.0
		MeshKit.part(self, MeshKit.box(Vector3(0.05, 0.03, 0.9)), dark, _ramp_from.lerp(_ramp_to, t) + Vector3(0, 0.06, 0), Vector3(0, 0, tilt))
	# And a little ladder off the front of the deck, down into the water.
	for x in [-0.3, 0.3]:
		MeshKit.part(self, MeshKit.cyl(0.04, 0.04, floor_y - WATER + 0.8, 5), dark, Vector3(x, (floor_y + WATER - 0.8) * 0.5, -HALF_D - DECK - 0.05))
	for k in 4:
		MeshKit.part(self, MeshKit.cyl(0.03, 0.03, 0.62, 5), wood, Vector3(0, floor_y - 0.3 - k * 0.35, -HALF_D - DECK - 0.05), Vector3(0, 0, PI / 2))
	# Where a raft ties up: hop off onto the deck.
	var landing := Marker3D.new()
	landing.position = Vector3(0, floor_y + 0.1, -HALF_D - DECK * 0.5)
	landing.add_to_group("landings")
	add_child(landing)

	# Inside: a cot, a table with the page on it, a stool, a shelf of jars.
	cot = Bedroll.build(self, Vector3(1.4, floor_y + 0.32, 0.6), 0.0)
	cot.remove_from_group("bedrolls")  # part of the house, not something you built
	for x in [1.0, 1.8]:
		for z in [-0.4, 1.6]:
			MeshKit.part(self, MeshKit.box(Vector3(0.07, 0.32, 0.07)), dark, Vector3(x, floor_y + 0.16, z))
	MeshKit.part(self, MeshKit.box(Vector3(0.9, 0.06, 2.1)), wood, Vector3(1.4, floor_y + 0.33, 0.6))
	_solid(Vector3(0.9, 0.4, 2.1), Vector3(1.4, floor_y + 0.2, 0.6))
	var table := Vector3(-1.2, floor_y, 0.95)
	MeshKit.part(self, MeshKit.box(Vector3(1.1, 0.06, 0.7)), grey, table + Vector3(0, 0.78, 0))
	for x in [-0.48, 0.48]:
		for z in [-0.28, 0.28]:
			MeshKit.part(self, MeshKit.box(Vector3(0.06, 0.76, 0.06)), dark, table + Vector3(x, 0.38, z))
	_solid(Vector3(1.1, 0.8, 0.7), table + Vector3(0, 0.4, 0))
	MeshKit.part(self, MeshKit.cyl(0.2, 0.2, 0.05, 8), wood, table + Vector3(0.1, 0.45, -0.75))
	MeshKit.part(self, MeshKit.cyl(0.03, 0.03, 0.43, 4), dark, table + Vector3(0.1, 0.22, -0.75))
	var shelf := Vector3(-HALF_W + 0.2, floor_y + 1.5, -0.7)
	MeshKit.part(self, MeshKit.box(Vector3(0.28, 0.04, 1.0)), wood, shelf)
	var glass := MeshKit.mat(Color(0.62, 0.75, 0.72, 0.6), 0.2)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for k in 3:
		MeshKit.part(self, MeshKit.cyl(0.07, 0.08, rng.randf_range(0.16, 0.26), 8), glass, shelf + Vector3(0, 0.12, -0.3 + k * 0.3))
	# A mossy patch or two creeping in at the door.
	for k in 3:
		MeshKit.part(self, MeshKit.box(Vector3(rng.randf_range(0.3, 0.6), 0.02, rng.randf_range(0.3, 0.5))), moss,
			Vector3(rng.randf_range(0.4, 1.3), floor_y + 0.05, -HALF_D + 0.3 + rng.randf_range(0.0, 0.4)), Vector3(0, rng.randf() * TAU, 0))

	page = Page.new()
	page.position = table + Vector3(0.15, 0.83, 0.05)
	add_child(page)
	page.read.connect(func(): page_read.emit())


func _solid(size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.position = pos
	body.rotation = rot
	body.add_child(shape)
	add_child(body)


## The page on the table: a torn-out sheet, curling at the edges, with a
## pebble on it to stop it blowing away. Glows a little until it's been read.
class Page:
	extends Node3D

	signal read

	var ready_to_read := false
	var _light: OmniLight3D
	var _t := 0.0

	func _ready() -> void:
		var paper := MeshKit.mat(Color(0.93, 0.89, 0.78), 0.9)
		paper.emission_enabled = true
		paper.emission = Color(1.0, 0.92, 0.7)
		paper.emission_energy_multiplier = 0.25
		MeshKit.part(self, MeshKit.box(Vector3(0.3, 0.008, 0.4)), paper, Vector3.ZERO, Vector3(0, 0.25, 0))
		MeshKit.part(self, MeshKit.box(Vector3(0.3, 0.008, 0.08)), paper, Vector3(0.02, 0.02, 0.2), Vector3(-0.35, 0.25, 0))
		var ink := MeshKit.mat(Color(0.25, 0.22, 0.2), 0.9)
		for k in 6:
			MeshKit.part(self, MeshKit.box(Vector3(0.2 - (k % 3) * 0.03, 0.002, 0.012)), ink, Vector3(-0.01, 0.006, -0.14 + k * 0.045), Vector3(0, 0.25, 0))
		MeshKit.part(self, MeshKit.sphere(0.04, 0.03, 6, 3), MeshKit.mat(Color(0.5, 0.52, 0.5), 0.6), Vector3(0.1, 0.015, 0.12))
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.85, 0.6)
		_light.light_energy = 0.0
		_light.omni_range = 3.5
		_light.position.y = 0.35
		add_child(_light)

	func light_up() -> void:
		ready_to_read = true
		add_to_group("usables")

	func _process(delta: float) -> void:
		_t += delta
		var want := (0.5 + 0.25 * sin(_t * 2.2)) if ready_to_read else 0.15
		_light.light_energy = lerpf(_light.light_energy, want, 1.0 - exp(-3.0 * delta))

	func use_radius() -> float:
		return 2.2

	func use_prompt() -> String:
		return "[E] Read the page"

	func use(_player: Player) -> void:
		if not ready_to_read:
			return
		ready_to_read = false
		remove_from_group("usables")
		Audio.play("gear_rustle", global_position, -4.0, 1.3)
		read.emit()
