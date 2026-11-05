class_name Animal
extends Node3D
## A little forest animal going about its day: nibbling, sniffing, pottering
## about. When someone gets too close it lifts its head to look, then bolts:
## rabbits and deer race off, squirrels and chipmunks dash for the nearest tree
## and scamper up the trunk, frogs hop for the water, and the skunk just
## waddles off in a huff. Models are free ones from Poly Pizza (see CREDITS.md).
## The deer, stag and rabbit come with their own animations; the rest are moved
## by code. Faces -Z like everything else.

enum Mode { IDLE, WANDER, ALERT, FLEE, CLIMB, PERCHED, LEAVING }

## file, scale, turn (to face -Z), gait, walk speed, run speed, notice distance,
## bolt distance, lift (model units, for rigged ones not standing on y = 0).
## Small ones are a bit bigger than life so they read on screen.
const KINDS := {
	"deer": ["deer", 0.36, PI, "anim", 1.2, 8.5, 26.0, 15.0, 0.0],
	"stag": ["stag", 0.4, PI, "anim", 1.2, 8.5, 28.0, 16.0, 0.0],
	"rabbit": ["rabbit", 1.0, PI, "anim", 1.4, 6.5, 11.0, 6.5, 0.16],
	"squirrel": ["squirrel", 0.008, PI, "scurry", 1.6, 6.0, 9.0, 5.5, 0.0],
	"chipmunk": ["chipmunk", 0.22, PI, "scurry", 1.5, 5.5, 8.0, 5.0, 0.0],
	"skunk": ["skunk", 0.075, PI, "waddle", 0.7, 1.6, 6.0, 4.0, 0.0],
	"frog": ["frog", 0.0016, PI / 2, "hop", 0.8, 3.5, 5.0, 3.0, 0.0],
}
## Only for tests: nothing scares them off.
static var fearless := false
## Trunks of the forest trees, as [base, radius], for squirrels to climb.
static var trunks: Array = []

var kind := "rabbit"
var mode := Mode.IDLE
var _spec: Array
var _model: Node3D
var _anim: AnimationPlayer
var _t := 0.0
var _timer := 0.0
var _goal := Vector3.ZERO
var _threat := Vector3.ZERO
var _hop := 0.0  # height of the current hop/bounce
var _hop_v := 0.0
var _speed := 0.0
var _trunk: Array = []
var _climb := 0.0  # how far up the trunk


static func create(animal_kind: String) -> Animal:
	var a := Animal.new()
	a.kind = animal_kind
	a._spec = KINDS[animal_kind]
	a._t = randf() * 10.0
	a._build()
	return a


func _build() -> void:
	var holder := Node3D.new()
	holder.rotation.y = _spec[2]
	add_child(holder)
	_model = (load("res://models/animals/%s.glb" % _spec[0]) as PackedScene).instantiate()
	_model.scale = Vector3.ONE * float(_spec[1]) * randf_range(0.9, 1.1)
	_model.position.y = float(_spec[8]) * _model.scale.y
	holder.add_child(_model)
	for m in _model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind in ["deer", "stag"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		_anim = players[0]
		for a in _anim.get_animation_list():
			_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_idle()


func _ready() -> void:
	_lift_to_ground()


## Plain models aren't always modelled standing on y = 0: sit them on it.
func _lift_to_ground() -> void:
	if _anim:
		return
	var low := INF
	for m in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var box: AABB = global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		low = minf(low, box.position.y)
	if low != INF:
		_model.position.y -= low


func _process(delta: float) -> void:
	_t += delta
	_timer -= delta
	var scare := _scared_by()
	match mode:
		Mode.IDLE:
			if scare != Vector3.INF:
				_alert(scare)
			elif _timer <= 0.0:
				_wander()
		Mode.WANDER:
			if scare != Vector3.INF:
				_alert(scare)
			elif _move_toward(_goal, float(_spec[4]), delta) < 0.3 or _timer <= 0.0:
				_idle()
		Mode.ALERT:
			_turn_toward(_threat, delta)
			if scare != Vector3.INF:
				_threat = scare
			if _close_to(_threat, float(_spec[7])) or _timer <= 0.0:
				if scare != Vector3.INF or _close_to(_threat, float(_spec[7])):
					_bolt()
				else:
					_idle()
		Mode.FLEE:
			if not _trunk.is_empty() and _flat_dist(_trunk[0]) < float(_trunk[1]) + 0.25:
				mode = Mode.CLIMB
				_climb = 0.0
			elif _move_toward(_goal, _speed, delta) < 0.5 or _timer <= 0.0:
				if kind == "frog" and Game.ground_at(global_position.x, global_position.z) < Game.WATER_LEVEL:
					queue_free()  # plop
				elif scare != Vector3.INF:
					_bolt()
				else:
					_idle()
		Mode.CLIMB:
			_climb += 2.2 * delta
			_hop = _climb
			if _climb >= 2.6:
				mode = Mode.PERCHED
				_timer = randf_range(15.0, 30.0)
		Mode.PERCHED:
			if _timer <= 0.0 and scare == Vector3.INF:
				_climb = maxf(0.0, _climb - 1.5 * delta)
				_hop = _climb
				if _climb <= 0.0:
					_trunk = []
					_idle()
		Mode.LEAVING:
			if _move_toward(_goal, float(_spec[4]), delta) < 0.5:
				queue_free()
	_animate(delta)


func _idle() -> void:
	mode = Mode.IDLE
	_timer = randf_range(3.0, 9.0)
	_play(["Eating", "Idle", "Idle_Headlow", "Eating"].pick_random() if kind in ["deer", "stag"] else "Bunny|Bunny_idle", 1.0)


## A short potter to somewhere nearby.
func _wander() -> void:
	for i in 6:
		var spot := global_position + Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * randf_range(1.5, 6.0 if kind in ["deer", "stag"] else 3.0)
		if _ok_ground(spot):
			mode = Mode.WANDER
			_goal = spot
			_timer = 8.0
			_play("Walk" if kind in ["deer", "stag"] else "Bunny|Bunny_walk", 1.0)
			return
	_timer = 2.0


## Head up, looking at whatever it heard.
func _alert(from: Vector3) -> void:
	mode = Mode.ALERT
	_threat = from
	_timer = randf_range(1.2, 2.5)
	_play("Idle_2" if kind in ["deer", "stag"] else "Bunny|Bunny_idle", 1.0)


func _bolt() -> void:
	mode = Mode.FLEE
	var away := global_position - _threat
	away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	_speed = float(_spec[5]) * randf_range(0.9, 1.1)
	_timer = 6.0
	_trunk = []
	if kind in ["squirrel", "chipmunk"]:
		_trunk = _nearest_trunk(away)
	if not _trunk.is_empty():
		_goal = _trunk[0]
	elif kind == "frog":
		_goal = _water_near(away)
	else:
		_goal = global_position + away.rotated(Vector3.UP, randf_range(-0.6, 0.6)) * randf_range(18.0, 30.0)
		if kind in ["deer", "stag", "rabbit"] and randf() < 0.5:
			_goal = global_position + away * 70.0  # gone for good
			_timer = 12.0
	_play("Gallop" if kind in ["deer", "stag"] else "Bunny|Bunny_walk", 2.4 if kind == "rabbit" else 1.0)
	Audio.play("gear_rustle", global_position, 6.0, randf_range(0.7, 0.9), 0.0, 25.0)


## Out of view for a while: wander away and vanish.
func leave() -> void:
	if mode in [Mode.FLEE, Mode.CLIMB, Mode.LEAVING]:
		return
	mode = Mode.LEAVING
	var away := (global_position - Game.player.global_position)
	away.y = 0.0
	_goal = global_position + away.normalized() * 40.0
	_play("Walk" if kind in ["deer", "stag"] else "Bunny|Bunny_walk", 1.0)


## Whatever's too close (the hero, a pet), or INF.
func _scared_by() -> Vector3:
	if fearless or mode in [Mode.CLIMB, Mode.LEAVING]:
		return Vector3.INF
	var notice: float = _spec[6]
	if mode == Mode.PERCHED:
		notice = 3.0  # safe up the tree
	var p := Game.player
	if p:
		var moving := Vector2(p.velocity.x, p.velocity.z).length()
		var close := notice * (0.6 if moving < 0.5 else 1.0) + moving * 0.6  # sneak up slowly and you'll get closer
		if p.global_position.distance_to(global_position) < close:
			return p.global_position
	for c in get_tree().get_nodes_in_group("companions"):
		var pet := c as Companion
		if pet.body.global_position.distance_to(global_position) < notice * 0.6:
			return pet.body.global_position
	return Vector3.INF


func _close_to(at: Vector3, dist: float) -> bool:
	return Vector2(at.x - global_position.x, at.z - global_position.z).length() < dist


func _flat_dist(at: Vector3) -> float:
	return Vector2(at.x - global_position.x, at.z - global_position.z).length()


## Moves along the ground toward `to`, turning to face it. Returns the distance left.
func _move_toward(to: Vector3, speed: float, delta: float) -> float:
	var step := to - global_position
	step.y = 0.0
	var dist := step.length()
	if dist < 0.01:
		return 0.0
	_turn_toward(to, delta)
	var dir := step / dist
	var next := global_position + dir * minf(speed * delta, dist)
	if not _ok_ground(next) and not (kind == "frog" and mode == Mode.FLEE):
		_timer = 0.0  # don't walk into the lake
		return dist
	global_position = Vector3(next.x, Game.ground_at(next.x, next.z), next.z)
	return dist


func _turn_toward(to: Vector3, delta: float) -> void:
	var d := to - global_position
	if Vector2(d.x, d.z).length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), 1.0 - exp(-8.0 * delta))


func _ok_ground(at: Vector3) -> bool:
	return Game.ground_at(at.x, at.z) > Game.WATER_LEVEL + 0.15


func _nearest_trunk(away: Vector3) -> Array:
	var best: Array = []
	var best_d := 12.0
	for t in trunks:
		var to: Vector3 = t[0] - global_position
		to.y = 0.0
		if to.length() < best_d and to.normalized().dot(away) > -0.3:
			best = t
			best_d = to.length()
	return best


func _water_near(away: Vector3) -> Vector3:
	for k in 16:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 16.0)
		for r in [2.0, 4.0, 7.0]:
			var q: Vector3 = global_position + dir * float(r)
			if Game.ground_at(q.x, q.z) < Game.WATER_LEVEL - 0.1:
				return q
	return global_position + away * 6.0


func _play(anim_name: String, speed: float) -> void:
	if _anim == null:
		return
	if not _anim.has_animation(anim_name):
		anim_name = "Idle" if _anim.has_animation("Idle") else _anim.get_animation_list()[0]
	if _anim.current_animation != anim_name:
		_anim.play(anim_name, 0.3)
	_anim.speed_scale = speed


## Code-driven motion for the models that come without animations.
func _animate(delta: float) -> void:
	var gait: String = _spec[3]
	var moving := mode in [Mode.WANDER, Mode.FLEE, Mode.LEAVING]
	if mode in [Mode.CLIMB, Mode.PERCHED]:
		# Clinging to the trunk, head up, on the side away from the hero.
		var side := global_position - Vector3(_trunk[0].x, global_position.y, _trunk[0].z)
		var r: float = _trunk[1] + 0.08
		var base: Vector3 = _trunk[0]
		var out := side.normalized() if side.length() > 0.01 else Vector3.BACK
		global_position = Vector3(base.x, 0, base.z) + out * r + Vector3(0, Game.ground_at(base.x, base.z), 0)
		rotation.y = atan2(out.x, out.z)
		_model.get_parent().rotation.x = PI / 2 - 0.1
		_model.get_parent().position = Vector3(0, _hop, 0)
		return
	_model.get_parent().rotation.x = 0.0
	match gait:
		"hop":
			if moving and _hop_v == 0.0 and _hop <= 0.0:
				_hop_v = 3.2
			if _hop_v != 0.0 or _hop > 0.0:
				_hop_v -= 16.0 * delta
				_hop = maxf(0.0, _hop + _hop_v * delta)
				if _hop <= 0.0:
					_hop_v = 0.0
			_model.get_parent().rotation.x = clampf(_hop_v * 0.08, -0.3, 0.3)
		"scurry":
			# Quick little bounds when running, a sniff-and-twitch when still.
			_hop = absf(sin(_t * (22.0 if mode == Mode.FLEE else 14.0))) * (0.06 if moving else 0.0)
			_model.get_parent().rotation.x = sin(_t * 9.0) * 0.06 if not moving else -0.12
			if mode == Mode.ALERT:
				_model.get_parent().rotation.x = 0.35  # up on its haunches, looking
		"waddle":
			_model.get_parent().rotation.z = sin(_t * 7.0) * (0.12 if moving else 0.02)
	_model.get_parent().position.y = _hop
