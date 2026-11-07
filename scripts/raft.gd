class_name Raft
extends Node3D
## Driftwood logs lashed together with vines, floating where it was pushed out.
## E climbs aboard (from the shore or from the water); then WASD paddles it
## toward where you look, and the Fox and the Otter hop on too if they're
## close. E again hops off: onto a dock or the shore if there's one in reach,
## else into the water. It won't go aground: shallow water stops it.

const LENGTH := 3.0
const WIDTH := 1.8
const DECK := 0.26  # deck top above the water
const SPEED := 3.0
const FAST := 4.4
const REACH := 3.2  # how close you need to be to climb aboard
const SHALLOW := 0.3  # how deep the water must be under the hull

## Where everyone sits, in the raft's own space (-Z is the front).
const SEAT := Vector3(0, DECK, 0.35)
const FOX_SEAT := Vector3(0.1, DECK, -1.05)
const OTTER_SEAT := Vector3(0.5, DECK, 1.1)

var rider: Player
var _speed := 0.0
var _turn := 0.0
var _bob := 0.0
var _stroke := 0.0
var _bumped := 0.0


static func build(parent: Node, at: Vector3, yaw: float) -> Raft:
	var r := Raft.new()
	r.position = Vector3(at.x, Game.WATER_LEVEL, at.z)
	r.rotation.y = yaw
	parent.add_child(r)
	return r


static func ghost(material: Material) -> Node3D:
	var g := Node3D.new()
	_shape(g, material, material, material)
	return g


static func _shape(parent: Node3D, wood: Material, pale: Material, vine: Material) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	# Five logs side by side, not quite the same length or thickness.
	for k in 5:
		var x := lerpf(-WIDTH * 0.5 + 0.18, WIDTH * 0.5 - 0.18, k / 4.0)
		var r := rng.randf_range(0.15, 0.19)
		var log_len := LENGTH + rng.randf_range(-0.25, 0.15)
		var piece := MeshKit.part(parent, MeshKit.cyl(r, r * 1.08, log_len, 7), wood if k % 2 == 0 else pale,
			Vector3(x, DECK - r, rng.randf_range(-0.08, 0.08)), Vector3(PI / 2, 0, rng.randf_range(-0.3, 0.3)))
		piece.rotation.y = rng.randf_range(-0.03, 0.03)
	# Two cross pieces and the vine lashings.
	for z in [-0.95, 0.95]:
		MeshKit.part(parent, MeshKit.cyl(0.07, 0.07, WIDTH + 0.2, 6), wood, Vector3(0, DECK + 0.03, z), Vector3(0, 0, PI / 2))
		for k in 5:
			var x := lerpf(-WIDTH * 0.5 + 0.18, WIDTH * 0.5 - 0.18, k / 4.0)
			MeshKit.part(parent, MeshKit.box(Vector3(0.05, 0.1, 0.2)), vine, Vector3(x, DECK + 0.02, z))
	# A paddle lying across the back.
	MeshKit.part(parent, MeshKit.cyl(0.03, 0.03, 1.5, 5), pale, Vector3(-0.35, DECK + 0.06, 1.25), Vector3(0, 0.3, PI / 2))
	MeshKit.part(parent, MeshKit.box(Vector3(0.38, 0.03, 0.16)), pale, Vector3(0.38, DECK + 0.06, 1.47), Vector3(0, 0.3, 0))


func _ready() -> void:
	add_to_group("usables")
	add_to_group("rafts")
	_shape(self, MeshKit.mat(Color(0.5, 0.44, 0.36), 0.95), MeshKit.mat(Color(0.66, 0.6, 0.5), 0.95), MeshKit.mat(Color(0.32, 0.4, 0.18), 0.9))


func use_radius() -> float:
	return REACH


func use_prompt() -> String:
	return "[E] Climb aboard the raft"


func use(player: Player) -> void:
	if rider == null and not player.frozen:
		player.board(self)


func boarded(player: Player) -> void:
	rider = player
	remove_from_group("usables")
	Audio.play("splash_out", global_position, -6.0, 0.8)


func left() -> void:
	rider = null
	_speed = 0.0
	_turn = 0.0
	add_to_group("usables")


func seat(offset: Vector3) -> Vector3:
	return to_global(offset)


## Paddle toward `wish` (a flat world direction, up to length 1): turns the
## raft to face it and pushes it along, unless the water ahead is too shallow.
func paddle(wish: Vector3, fast: bool, delta: float) -> void:
	var forward := -global_basis.z
	var want := 0.0
	if wish.length() > 0.1:
		var target := atan2(-wish.x, -wish.z)
		var diff := wrapf(target - rotation.y, -PI, PI)
		_turn = lerpf(_turn, clampf(diff * 1.6, -1.1, 1.1), 1.0 - exp(-4.0 * delta))
		want = (FAST if fast else SPEED) * clampf(wish.length(), 0.0, 1.0) * clampf(1.0 - absf(diff) / 1.6, 0.15, 1.0)
	else:
		_turn = lerpf(_turn, 0.0, 1.0 - exp(-3.0 * delta))
	rotation.y += _turn * delta
	_speed = lerpf(_speed, want, 1.0 - exp(-1.6 * delta))
	var step := forward * _speed * delta
	if _speed > 0.05 and not _floats_at(global_position + step + forward * (LENGTH * 0.5)):
		_speed = 0.0
		step = Vector3.ZERO
		_bumped -= delta
		if _bumped <= 0.0:
			_bumped = 1.5
			Audio.play("gear_rustle", global_position, -8.0, 0.6)
	global_position += step
	_stroke -= delta
	if want > 0.1 and _stroke <= 0.0:
		_stroke = 1.0 if not fast else 0.75
		Audio.play("swim_stroke", global_position, -6.0, 0.9)
		var side := 1.0 if randf() < 0.5 else -1.0
		FX.burst(to_global(Vector3(side * (WIDTH * 0.5 + 0.2), 0.0, 0.6)), Color(0.8, 0.95, 1.0), 6, 1.5, 0.04)


## Deep enough to float here (the lake bed well under the hull).
static func _floats_at(p: Vector3) -> bool:
	return Game.ground_at(p.x, p.z) < Game.WATER_LEVEL - SHALLOW


## Somewhere dry to hop off to: a dock in reach first, else the nearest bit
## of shore close by. Vector3.INF if there's only water around.
func landing() -> Vector3:
	for n in get_tree().get_nodes_in_group("landings"):
		var at: Vector3 = (n as Node3D).global_position
		if Vector2(at.x - global_position.x, at.z - global_position.z).length() < 5.5:
			return at
	var best := Vector3.INF
	var best_d := INF
	for r in [1.6, 2.4, 3.2, 4.0]:
		for k in 16:
			var a := TAU * k / 16.0
			var p: Vector3 = global_position + Vector3(cos(a), 0, sin(a)) * r
			var g := Game.ground_at(p.x, p.z)
			if g > Game.WATER_LEVEL + 0.05 and float(r) < best_d:
				best = Vector3(p.x, g + 0.1, p.z)
				best_d = r
		if best != Vector3.INF:
			return best
	return best


func _process(delta: float) -> void:
	_bob += delta
	var sink := 0.06 if rider else 0.0
	position.y = Game.WATER_LEVEL - sink + sin(_bob * 1.3) * 0.04
	rotation.x = sin(_bob * 0.9) * 0.02 + _speed * 0.004
	rotation.z = sin(_bob * 1.1 + 1.0) * 0.025 - _turn * 0.03
