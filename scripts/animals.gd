class_name Animals
extends Node3D
## Every so often a little forest animal turns up somewhere ahead: a rabbit
## nibbling at the grass, a squirrel or chipmunk near the trees, a pair of deer
## at the edge of a clearing, a frog by the water, now and then a skunk. Deer
## and skunks are about at night too. Animals far from the hero are let go. The
## first time the pets spot each kind, one of them says something.

const MAX_DAY := 6
const MAX_NIGHT := 2
const LET_GO := 120.0
## kind: [weight by day, weight by night]
const ODDS := {
	"rabbit": [3.0, 0.5], "squirrel": [3.0, 0.0], "chipmunk": [2.0, 0.0],
	"deer": [1.5, 1.5], "skunk": [0.6, 1.5], "frog": [2.0, 1.0],
}
## Who says what on first seeing each kind.
const SPOTTED := {
	"rabbit": ["otter", "A BUNNY! Look at his little nose go!"],
	"squirrel": ["fox", "Squirrel. They hide nuts and then forget where. Every time."],
	"chipmunk": ["otter", "That squirrel shrank!"],
	"deer": ["fox", "Shh. Deer. Walk slow or they'll run."],
	"stag": ["otter", "Whoa! That one has TREE BRANCHES on his head!"],
	"skunk": ["fox", "Skunk. Do not. Scare. The skunk."],
	"frog": ["otter", "Ribbit! I'm talking frog. He said hi."],
}

var _spawn_timer := 12.0
var _seen := {}


func _process(delta: float) -> void:
	var p := Game.player
	if p == null:
		return
	for a in get_children():
		var d := (a as Node3D).global_position.distance_to(p.global_position)
		if d > LET_GO:
			a.queue_free()
		elif not _seen.has(a.kind) and d < 14.0 and a.mode != Animal.Mode.FLEE:
			_spotted(a)
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = randf_range(25.0, 50.0)
	if p.frozen or Game.underwater:
		return
	if get_child_count() < (MAX_NIGHT if Game.is_night else MAX_DAY):
		spawn(p.global_position)


## Somewhere 22-40 m away, out of the camera's view if it can.
func spawn(near: Vector3, kind := "", spot := Vector3.INF) -> void:
	if kind == "":
		kind = _pick()
	var water := _near_water(near)
	if kind == "frog" and not water and spot == Vector3.INF:
		kind = "rabbit"
	if spot == Vector3.INF:
		spot = _find_spot(near, kind)
		if spot == Vector3.INF:
			return
	var count := 1
	if kind == "deer":
		count = randi_range(1, 3)
	for i in count:
		var k := kind
		if kind == "deer" and i == 0 and randf() < 0.45:
			k = "stag"
		var a := Animal.create(k)
		add_child(a)
		var at := spot + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5)) * (1.0 if i > 0 else 0.0)
		a.global_position = Vector3(at.x, Game.ground_at(at.x, at.z), at.z)
		a.rotation.y = randf() * TAU


func _pick() -> String:
	var col := 1 if Game.is_night else 0
	var total := 0.0
	for k in ODDS:
		total += ODDS[k][col]
	var roll := randf() * total
	for k in ODDS:
		roll -= ODDS[k][col]
		if roll <= 0.0:
			return k
	return "rabbit"


func _find_spot(near: Vector3, kind: String) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	for i in 20:
		var q := near + Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * randf_range(22.0, 40.0)
		var g := Game.ground_at(q.x, q.z)
		if g < Game.WATER_LEVEL + 0.3:
			continue
		q.y = g
		if kind == "frog" and not _near_water(q, 6.0):
			continue
		if cam and i < 14 and not cam.is_position_behind(q) and cam.unproject_position(q).x > -50.0 \
				and cam.unproject_position(q).x < get_viewport().get_visible_rect().size.x + 50.0:
			continue  # would pop in right in front of you
		return q
	return Vector3.INF


func _near_water(at: Vector3, reach := 25.0) -> bool:
	for k in 12:
		var q := at + Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 12.0) * reach
		if Game.ground_at(q.x, q.z) < Game.WATER_LEVEL - 0.3:
			return true
	return false


func _spotted(a: Animal) -> void:
	var line: Array = SPOTTED.get(a.kind, [])
	if line.is_empty():
		_seen[a.kind] = true
		return
	for c in get_tree().get_nodes_in_group("companions"):
		var pet := c as Companion
		if pet.who == line[0] and pet.state == Companion.State.FOLLOWING:
			pet.say([line[1]])
			_seen[a.kind] = true
			return
