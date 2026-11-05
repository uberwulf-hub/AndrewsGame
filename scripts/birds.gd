class_name Birds
extends Node3D
## Every so often some birds come by: a little flock of one kind of songbird
## drops in to land somewhere ahead and peck around, or a crow (a gull, over
## water) wheels overhead for a while. At night it's quiet but for the odd owl.
## Birds that end up far from the hero are let go.

const SONGBIRDS := ["sparrow", "robin", "bluebird", "cardinal", "goldfinch"]
const MAX_DAY := 14
const MAX_NIGHT := 1
const LET_GO := 140.0

var _spawn_timer := 8.0


func _process(delta: float) -> void:
	var p := Game.player
	if p == null:
		return
	for b in get_children():
		if (b as Node3D).global_position.distance_to(p.global_position) > LET_GO:
			b.queue_free()
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = randf_range(20.0, 45.0)
	var count := get_child_count()
	if Game.is_night:
		if count < MAX_NIGHT and randf() < 0.5:
			spawn_soarer("owl", p.global_position)
	elif count < MAX_DAY:
		if randf() < 0.7:
			spawn_flock(p.global_position)
		else:
			spawn_soarer("gull" if _near_water(p.global_position) else "crow", p.global_position)


## A few of one kind fly in from far off and settle near a spot 15-35 m away.
func spawn_flock(near: Vector3, kind := "", spot := Vector3.INF) -> void:
	if kind == "":
		kind = SONGBIRDS.pick_random()
	if spot == Vector3.INF:
		for i in 10:
			var q := near + Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * randf_range(15.0, 35.0)
			if Game.ground_at(q.x, q.z) > Game.WATER_LEVEL + 0.2:
				spot = q
				break
		if spot == Vector3.INF:
			return
	var from := spot + Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * 70.0
	from.y = Game.ground_at(from.x, from.z) + 18.0
	for i in randi_range(2, 5):
		var b := Bird.create(kind)
		add_child(b)
		b.global_position = from + Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(-2, 2))
		var land := spot + Vector3(randf_range(-1.8, 1.8), 0.0, randf_range(-1.8, 1.8))
		b.target = Vector3(land.x, Game.ground_at(land.x, land.z), land.z)
		b.landing = true


## One big bird circling, drifting in over the hero and later away.
func spawn_soarer(kind: String, near: Vector3) -> void:
	var b := Bird.create(kind)
	add_child(b)
	var from := near + Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * 80.0
	var over := near + Vector3(randf_range(-15, 15), 0, randf_range(-15, 15))
	var low := kind == "owl"
	b.start_soaring(from, over, randf_range(8.0, 12.0) if low else randf_range(16.0, 28.0), randf_range(10.0, 14.0) if low else randf_range(14.0, 24.0), randf_range(40.0, 80.0))
	b._soar(0.016)


func _near_water(at: Vector3) -> bool:
	for k in 12:
		var q := at + Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 12.0) * 25.0
		if Game.ground_at(q.x, q.z) < Game.WATER_LEVEL - 0.5:
			return true
	return false
