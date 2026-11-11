class_name Bird
extends Node3D
## One small low-poly bird. Songbirds fly in, land, hop about pecking at the
## ground and chirping, and scatter when someone comes too close (some settle
## again a little way off, some leave for good). Soaring birds (crows, gulls,
## owls at night) wheel in wide lazy circles, calling now and then, then drift
## off. Faces -Z like everything else.

enum Mode { FLYING, GROUND, SOARING, LEAVING, FALLING }

## Look: [back, belly, wings, beak, size, call pitch]
const KINDS := {
	"sparrow": [Color(0.5, 0.38, 0.26), Color(0.82, 0.74, 0.62), Color(0.35, 0.26, 0.18), Color(0.3, 0.25, 0.2), 1.0, 1.0],
	"robin": [Color(0.32, 0.3, 0.3), Color(0.85, 0.42, 0.18), Color(0.25, 0.23, 0.23), Color(0.85, 0.7, 0.2), 1.25, 0.88],
	"bluebird": [Color(0.22, 0.42, 0.85), Color(0.85, 0.55, 0.35), Color(0.18, 0.32, 0.7), Color(0.15, 0.15, 0.15), 1.0, 1.1],
	"cardinal": [Color(0.8, 0.1, 0.1), Color(0.75, 0.14, 0.1), Color(0.6, 0.08, 0.08), Color(0.95, 0.5, 0.2), 1.1, 0.95],
	"goldfinch": [Color(0.95, 0.8, 0.15), Color(0.98, 0.88, 0.3), Color(0.12, 0.12, 0.12), Color(0.9, 0.6, 0.4), 0.85, 1.25],
	"crow": [Color(0.08, 0.08, 0.1), Color(0.12, 0.12, 0.14), Color(0.06, 0.06, 0.08), Color(0.1, 0.1, 0.1), 2.7, 1.0],
	"gull": [Color(0.95, 0.95, 0.95), Color(0.98, 0.98, 0.98), Color(0.6, 0.63, 0.68), Color(0.95, 0.75, 0.2), 3.0, 1.0],
	"owl": [Color(0.5, 0.4, 0.3), Color(0.8, 0.72, 0.6), Color(0.42, 0.33, 0.24), Color(0.3, 0.28, 0.2), 2.8, 1.0],
}
const CALLS := {"crow": "crow_caw", "gull": "gull_call", "owl": "owl_hoot"}
## Only for tests: nothing scares them off.
static var fearless := false

var kind := "sparrow"
var mode := Mode.FLYING
var velocity := Vector3.ZERO
var target := Vector3.ZERO
var landing := false  # FLYING: settle at `target` (else just pass through)

var _pitch := 1.0
var _wings: Array[Node3D] = []
var _head: Node3D
var _legs: Node3D
var _t := 0.0
var _bank := 0.0
var _flap := 1.0  # how hard the wings are beating (0 = gliding)
var _timer := 0.0  # GROUND: time left before moving on; SOARING: before drifting off
var _hop_timer := 0.0
var _hop_v := 0.0
var _hop_dir := Vector3.ZERO
var _peck := 0.0
var _call_timer := 0.0
## SOARING: circling `center` at `radius`, gliding toward `drift_to`.
var center := Vector3.ZERO
var drift_to := Vector3.ZERO
var radius := 16.0
var _angle := 0.0
var _height := 20.0


static func create(bird_kind: String) -> Bird:
	var b := Bird.new()
	b.kind = bird_kind
	var look: Array = KINDS[bird_kind]
	b._pitch = look[5] * randf_range(0.92, 1.08)
	b._t = randf() * 10.0
	b._call_timer = randf_range(2.0, 8.0)
	b._build(look)
	b.add_to_group("birds")
	return b


func _build(look: Array) -> void:
	var back := MeshKit.mat(look[0])
	var belly := MeshKit.mat(look[1])
	var wing := MeshKit.mat(look[2])
	var beak := MeshKit.mat(look[3])
	var dark := MeshKit.mat(Color(0.05, 0.05, 0.05))
	var model := Node3D.new()
	model.scale = Vector3.ONE * float(look[4]) * 1.5  # a bit bigger than life, so they read on screen
	add_child(model)
	MeshKit.part(model, MeshKit.sphere(0.05, 0.09, 8, 5), back, Vector3(0, 0.06, 0)).scale = Vector3(1, 1, 1.5)
	MeshKit.part(model, MeshKit.sphere(0.045, 0.08, 8, 5), belly, Vector3(0, 0.05, -0.02)).scale = Vector3(1, 1, 1.3)
	MeshKit.part(model, MeshKit.box(Vector3(0.05, 0.008, 0.08)), wing, Vector3(0, 0.07, 0.1), Vector3(0.25, 0, 0))  # tail
	_head = Node3D.new()
	_head.position = Vector3(0, 0.1, -0.06)
	model.add_child(_head)
	var big_head := 1.5 if kind == "owl" else 1.0
	MeshKit.part(_head, MeshKit.sphere(0.035 * big_head), back, Vector3.ZERO)
	MeshKit.part(_head, MeshKit.cyl(0.0, 0.011, 0.035, 4), beak, Vector3(0, -0.005, -0.045 * big_head), Vector3(-PI / 2, 0, 0))
	for s in [-1.0, 1.0]:
		MeshKit.part(_head, MeshKit.sphere(0.008), dark, Vector3(0.024 * s * big_head, 0.01, -0.022 * big_head))
		var pivot := Node3D.new()
		pivot.position = Vector3(0.035 * s, 0.08, 0.0)
		model.add_child(pivot)
		MeshKit.part(pivot, MeshKit.box(Vector3(0.12, 0.006, 0.065)), wing, Vector3(0.06 * s, 0, 0.01))
		_wings.append(pivot)
	_legs = Node3D.new()
	model.add_child(_legs)
	for s in [-1.0, 1.0]:
		MeshKit.part(_legs, MeshKit.box(Vector3(0.006, 0.03, 0.006)), dark, Vector3(0.015 * s, 0.015, 0))
	_legs.visible = false
	for m in model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	_t += delta
	match mode:
		Mode.FLYING, Mode.LEAVING:
			_fly(delta)
		Mode.GROUND:
			_on_ground(delta)
		Mode.SOARING:
			_soar(delta)
		Mode.FALLING:
			_fall(delta)
			return
	_animate(delta)
	_call_timer -= delta
	if _call_timer <= 0.0:
		_call()


## Hit by a sling stone: a puff of feathers, then it tumbles to the ground
## and leaves something to gather (feathers, meat and bones).
func shot_down(from: Vector3) -> void:
	if mode == Mode.FALLING:
		return
	mode = Mode.FALLING
	var push := global_position - from
	push.y = 0.0
	velocity = push.normalized() * 1.5 + Vector3.UP * 1.2
	FX.burst(global_position + Vector3.UP * 0.08, (KINDS[kind][0] as Color).lightened(0.2), 14, 2.0, 0.035)
	Audio.play("wing_flap", global_position, 0.0, 1.4, 0.0, 30.0)
	remove_from_group("birds")


func _fall(delta: float) -> void:
	velocity.y -= 12.0 * delta
	global_position += velocity * delta
	rotation.z += 9.0 * delta
	var ground := maxf(Game.ground_at(global_position.x, global_position.z), Game.WATER_LEVEL)
	if global_position.y <= ground:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var g := Gatherable.new()
		g.kind = "bird"
		g.set_meta("color", KINDS[kind][0])
		g.set_meta("size", KINDS[kind][4])
		g.position = Vector3(global_position.x, ground, global_position.z)
		g.rotation.y = rng.randf() * TAU
		get_parent().get_parent().add_child(g)
		g._build(rng)
		queue_free()


func _fly(delta: float) -> void:
	var speed := 8.0 if mode == Mode.LEAVING else 6.5
	var to := target - global_position
	var dist := to.length()
	var want := to / maxf(dist, 0.001) * speed
	if landing:
		want *= clampf(dist / 3.5, 0.2, 1.0)  # slow down to settle
	var before := velocity
	velocity = velocity.lerp(want, 1.0 - exp(-2.5 * delta))
	global_position += velocity * delta
	_face(velocity, before, delta)
	_flap = 1.0 if velocity.y > -1.0 or landing else 0.3
	if landing and dist < 0.12:
		_land()
	elif mode == Mode.LEAVING and dist < 2.0:
		queue_free()


func _land() -> void:
	mode = Mode.GROUND
	velocity = Vector3.ZERO
	global_position = Vector3(target.x, Game.ground_at(target.x, target.z), target.z)
	rotation = Vector3(0, rotation.y, 0)
	_legs.visible = true
	_timer = randf_range(20.0, 45.0)
	_hop_timer = randf_range(0.5, 2.0)


## Hopping about and pecking until something big comes close or it gets bored.
func _on_ground(delta: float) -> void:
	_hop_timer -= delta
	if _hop_timer <= 0.0 and _hop_v == 0.0:
		_hop_timer = randf_range(0.6, 2.4)
		if randf() < 0.5:
			_peck = 0.35  # a quick peck at something in the grass
		else:
			_hop_dir = Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
			rotation.y = atan2(-_hop_dir.x, -_hop_dir.z)
			_hop_v = 1.6
	var ground := Game.ground_at(global_position.x, global_position.z)
	if _hop_v != 0.0 or global_position.y > ground + 0.001:
		_hop_v -= 14.0 * delta
		global_position += _hop_dir * 0.9 * delta + Vector3.UP * _hop_v * delta
		if global_position.y <= ground:
			global_position.y = ground
			_hop_v = 0.0
	_peck = maxf(0.0, _peck - delta)
	_timer -= delta
	var scare := _scared_by()
	if scare != Vector3.INF:
		take_off(scare)
	elif _timer <= 0.0:
		take_off(global_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)))


## Whatever's too close (the hero, a pet), or INF.
func _scared_by() -> Vector3:
	if fearless:
		return Vector3.INF
	var p := Game.player
	if p:
		var close := 6.0 + Vector2(p.velocity.x, p.velocity.z).length() * 0.5
		if p.global_position.distance_to(global_position) < close:
			return p.global_position
	for c in get_tree().get_nodes_in_group("companions"):
		var pet := c as Companion
		if pet.body.global_position.distance_to(global_position) < 3.5:
			return pet.body.global_position
	return Vector3.INF


## Away from `from`: flutters up and either settles again a little way off or
## leaves for good.
func take_off(from: Vector3) -> void:
	var away := global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.05 else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	away = away.rotated(Vector3.UP, randf_range(-0.5, 0.5))
	_legs.visible = false
	velocity = away * 3.0 + Vector3.UP * 4.0
	Audio.play("wing_flap", global_position, randf_range(-4.0, 0.0), randf_range(0.9, 1.2), 0.0, 30.0)
	if randf() < 0.3:
		_call_timer = randf_range(0.1, 0.5)  # an alarmed chirp on the way up
	var spot := global_position + away * randf_range(18.0, 32.0)
	if randf() < 0.45 and Game.ground_at(spot.x, spot.z) > Game.WATER_LEVEL + 0.2:
		mode = Mode.FLYING
		landing = true
		target = Vector3(spot.x, Game.ground_at(spot.x, spot.z), spot.z)
	else:
		mode = Mode.LEAVING
		landing = false
		target = global_position + away * 90.0 + Vector3.UP * randf_range(20.0, 35.0)


## Wide lazy circles, mostly gliding, the circle drifting toward `drift_to`.
func _soar(delta: float) -> void:
	center = center.move_toward(drift_to, 3.0 * delta)
	var speed := 5.5
	_angle += speed / radius * delta
	var ground := Game.ground_at(center.x, center.z)
	var spot := center + Vector3(cos(_angle), 0.0, sin(_angle)) * radius
	spot.y = maxf(ground, Game.WATER_LEVEL) + _height + sin(_t * 0.3) * 1.5
	var before := velocity
	velocity = (spot - global_position) / maxf(delta, 0.001)
	global_position = spot
	_face(velocity, before, delta)
	_flap = 1.0 if fmod(_t, 7.0) < 1.2 else 0.0  # a few beats now and then
	_timer -= delta
	if _timer <= 0.0:
		mode = Mode.LEAVING
		var away := Vector3(cos(_angle + PI / 2), 0, sin(_angle + PI / 2))
		target = global_position + away * 120.0 + Vector3.UP * 10.0


func start_soaring(from_center: Vector3, toward: Vector3, height: float, circle: float, time: float) -> void:
	mode = Mode.SOARING
	center = from_center
	drift_to = toward
	_height = height
	radius = circle
	_angle = randf() * TAU
	_timer = time


## Nose along the flight path, leaning into turns.
func _face(vel: Vector3, before: Vector3, delta: float) -> void:
	if vel.length() < 0.1:
		return
	var dir := vel.normalized()
	var turn := 0.0
	if before.length() > 0.1:
		turn = Vector2(before.x, before.z).angle_to(Vector2(vel.x, vel.z)) / maxf(delta, 0.001)
	_bank = lerpf(_bank, clampf(-turn * 0.35, -0.9, 0.9), 1.0 - exp(-4.0 * delta))
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD
	global_basis = Basis.looking_at(dir, up).rotated(dir, _bank)


func _animate(delta: float) -> void:
	var on_ground := mode == Mode.GROUND
	var beat := 0.0
	if not on_ground:
		var rate := 16.0 if kind in ["crow", "gull", "owl"] else 26.0
		if kind not in ["crow", "gull", "owl"]:
			_flap = maxf(_flap, 0.6)  # little birds never really glide
		beat = sin(_t * rate) * 0.9 * _flap
	for i in _wings.size():
		var s := -1.0 if i == 0 else 1.0
		# Folded: swung back to lie along the body. Flying: beating up and down.
		var k := 1.0 - exp(-30.0 * delta)
		_wings[i].rotation.y = lerpf(_wings[i].rotation.y, -s * 1.45 if on_ground else 0.0, k)
		_wings[i].rotation.z = lerpf(_wings[i].rotation.z, 0.0 if on_ground else beat * s, k)
		_wings[i].scale.x = lerpf(_wings[i].scale.x, 0.55 if on_ground else 1.0, 1.0 - exp(-10.0 * delta))
	_head.rotation.x = -0.9 if _peck > 0.0 else sin(_t * 1.7) * 0.15


func _call() -> void:
	var sound: String = CALLS.get(kind, "bird_chirp")
	var resting := mode == Mode.GROUND
	_call_timer = randf_range(3.0, 9.0) if resting else randf_range(6.0, 16.0)
	if sound == "bird_chirp" and mode == Mode.LEAVING and randf() < 0.6:
		return
	Audio.play(sound, global_position, randf_range(-6.0, 0.0), _pitch * randf_range(0.94, 1.06), 0.0, 70.0 if sound != "bird_chirp" else 45.0)
