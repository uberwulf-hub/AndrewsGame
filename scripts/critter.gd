class_name Critter
extends Node3D
## Low-poly animal companions: the Fox (older, sly, witty) and the Otter (younger,
## inventive, big-hearted). Faces -Z. Set `moving` for a bounding run cycle.

var moving := false
var _move_tween: Tween
var _t := 0.0
var _body: Node3D
var _tail: Node3D
var _rig: CharacterRig  # animated model from models/<name>, when there is one
var _last_pos := Vector3.ZERO
var _speed := 0.0
## In the water (the companion sets these): the Fox dog-paddles nose-up, the
## Otter undulates, rolls onto his back to float when he stops, and tips nose
## down when he dives (`dive` is how fast he's heading down, -1..1).
var swimming := false
var dive := 0.0
var _back := 0.0  # 0 belly down, 1 floating on his back
var _shake := 0.0  # seconds left of shaking off water
var _wet := 0.0
var _wet_mat: StandardMaterial3D
## Lying down for a rest: both curl up on their side (the Otter only floats
## on his back in the water).
var lounging := false
var _bob := 0.0  # the little trot bounce, kept apart from the roll's lift
var _lounge := 0.0
## The Fox lying on his side: how far over he rolls, how high the middle of
## his body is when standing, and how high it sits once he's lying down.
const LIE_ROLL := 1.45
const LIE_MIDDLE := 0.32
const LIE_SIDE := 0.13


static func fox() -> Critter:
	var rig := CharacterRig.create("fox", 0.78)
	if rig:
		var r := Critter.new()
		r._rig = rig
		r.add_child(rig)
		rig.play("idle")
		return r
	var c := Critter.new()
	var orange := MeshKit.mat(Color(0.93, 0.46, 0.13))
	var cream := MeshKit.mat(Color(0.97, 0.92, 0.84))
	var dark := MeshKit.mat(Color(0.12, 0.08, 0.07))
	var b := c._make_body()
	MeshKit.part(b, MeshKit.box(Vector3(0.26, 0.24, 0.55)), orange, Vector3(0, 0.38, 0))
	MeshKit.part(b, MeshKit.box(Vector3(0.2, 0.18, 0.12)), cream, Vector3(0, 0.35, -0.27))
	MeshKit.part(b, MeshKit.box(Vector3(0.24, 0.22, 0.24)), orange, Vector3(0, 0.56, -0.33))
	MeshKit.part(b, MeshKit.cyl(0.0, 0.08, 0.2, 4), cream, Vector3(0, 0.52, -0.52), Vector3(-PI / 2, 0, 0))
	MeshKit.part(b, MeshKit.sphere(0.025), dark, Vector3(0, 0.52, -0.62))
	for side in [-1.0, 1.0]:
		MeshKit.part(b, MeshKit.cyl(0.0, 0.065, 0.16, 4), orange, Vector3(0.08 * side, 0.74, -0.33))
		MeshKit.part(b, MeshKit.box(Vector3(0.04, 0.04, 0.02)), dark, Vector3(0.065 * side, 0.6, -0.455))
		for z in [-0.18, 0.18]:
			MeshKit.part(b, MeshKit.box(Vector3(0.06, 0.26, 0.06)), dark, Vector3(0.09 * side, 0.13, z))
	c._tail = Node3D.new()
	c._tail.position = Vector3(0, 0.42, 0.27)
	b.add_child(c._tail)
	MeshKit.part(c._tail, MeshKit.sphere(0.1, 0.5, 6, 4), orange, Vector3(0, 0.12, 0.16), Vector3(1.1, 0, 0))
	MeshKit.part(c._tail, MeshKit.sphere(0.065), cream, Vector3(0, 0.24, 0.36))
	return c


static func otter() -> Critter:
	var c := Critter.new()
	var brown := MeshKit.mat(Color(0.45, 0.3, 0.18))
	var cream := MeshKit.mat(Color(0.88, 0.78, 0.62))
	var dark := MeshKit.mat(Color(0.12, 0.08, 0.06))
	var b := c._make_body()
	MeshKit.part(b, MeshKit.sphere(0.17, 0.66, 8, 5), brown, Vector3(0, 0.24, 0), Vector3(PI / 2, 0, 0))
	MeshKit.part(b, MeshKit.sphere(0.13, 0.5, 8, 5), cream, Vector3(0, 0.19, -0.04), Vector3(PI / 2, 0, 0))
	MeshKit.part(b, MeshKit.sphere(0.14, 0.26, 8, 5), brown, Vector3(0, 0.36, -0.34))
	MeshKit.part(b, MeshKit.sphere(0.08, 0.12, 8, 4), cream, Vector3(0, 0.32, -0.45))
	MeshKit.part(b, MeshKit.sphere(0.025), dark, Vector3(0, 0.35, -0.51))
	for side in [-1.0, 1.0]:
		MeshKit.part(b, MeshKit.sphere(0.035), brown, Vector3(0.11 * side, 0.46, -0.31))
		MeshKit.part(b, MeshKit.box(Vector3(0.035, 0.035, 0.02)), dark, Vector3(0.06 * side, 0.4, -0.465))
		for z in [-0.17, 0.17]:
			MeshKit.part(b, MeshKit.sphere(0.055), dark, Vector3(0.1 * side, 0.06, z))
	c._tail = Node3D.new()
	c._tail.position = Vector3(0, 0.2, 0.3)
	b.add_child(c._tail)
	MeshKit.part(c._tail, MeshKit.cyl(0.02, 0.08, 0.45, 6), brown, Vector3(0, -0.04, 0.2), Vector3(1.45, 0, 0))
	return c


func _make_body() -> Node3D:
	_body = Node3D.new()
	add_child(_body)
	return _body


func _process(delta: float) -> void:
	_t += delta
	var smooth := 1.0 - exp(-6.0 * delta)
	_shake = maxf(0.0, _shake - delta)
	var shake_roll := sin(_t * 45.0) * 0.45 * minf(_shake / 0.4, 1.0)
	var flat := position - _last_pos
	flat.y = 0.0
	_last_pos = position
	_speed = lerpf(_speed, flat.length() / maxf(delta, 0.0001), smooth)
	if _rig:
		if swimming:
			# Dog paddle: legs going quick, nose up, whether moving or treading.
			_rig.play("walk", 1.9 if _speed > 0.3 else 1.2, 0.3)
			_rig.rotation.x = lerpf(_rig.rotation.x, 0.28, smooth)
		elif _speed > 2.5:
			_rig.play("run", clampf(_speed / 5.0, 0.7, 1.5), 0.25)
		elif _speed > 0.2 or moving:
			_rig.play("walk", clampf(_speed / 1.4, 0.6, 1.6), 0.25)
		else:
			_rig.play("idle", 0.35 if lounging else 1.0, 0.4)
		if not swimming:
			_rig.rotation.x = lerpf(_rig.rotation.x, 0.0, smooth)
		_lounge = move_toward(_lounge, 1.0 if lounging and not swimming and _speed < 0.2 else 0.0, delta * 2.0)
		# Tip over around the middle of his body (not his paws), then settle so
		# his side rests on the ground instead of sinking into it.
		var lie := smoothstep(0.0, 1.0, _lounge)
		var roll := LIE_ROLL * lie
		_rig.rotation.z = shake_roll + roll
		_rig.position.x = LIE_MIDDLE * sin(roll)
		_rig.position.y = LIE_MIDDLE - LIE_MIDDLE * cos(roll) - (LIE_MIDDLE - LIE_SIDE) * lie
		return
	var paddling := swimming and (_speed > 0.3 or absf(dive) > 0.1)
	var resting := lounging and not swimming and _speed < 0.2
	# Floating on his back in the water; on dry land he curls up on his side.
	_back = move_toward(_back, 1.0 if swimming and not paddling else 0.0, delta * 1.5)
	_lounge = move_toward(_lounge, 1.0 if resting else 0.0, delta * 1.5)
	var roll := PI * smoothstep(0.0, 1.0, _back) + 1.35 * smoothstep(0.0, 1.0, _lounge)
	if swimming:
		# Swimming like a little torpedo: the whole body ripples, the tail sculls.
		_body.rotation.x = lerpf(_body.rotation.x, (sin(_t * 7.0) * 0.12 - dive * 0.7) if paddling else 0.0, smooth)
		_tail.rotation.x = sin(_t * 7.0) * 0.4
		_bob = 0.0
	elif moving:
		_bob = absf(sin(_t * 12.0)) * 0.12
	else:
		_bob = lerpf(_bob, 0.0, 1.0 - exp(-10.0 * delta))
	_body.position.y = _bob
	if not swimming:
		_body.rotation.x = lerpf(_body.rotation.x, 0.0, smooth)
		_tail.rotation.x = lerpf(_tail.rotation.x, 0.0, smooth)
	# Rolling over keeps the middle of the body (0.24 up) where it was.
	_body.rotation.z = roll + shake_roll
	_body.position.x = 0.24 * sin(roll)
	_body.position.y += 0.24 - 0.24 * cos(roll)
	_tail.rotation.y = sin(_t * (10.0 if moving else 3.0)) * 0.4


## A big full-body shake to fling the water off.
func shake_off() -> void:
	_shake = 0.9


## Soaked fur looks darker and glossy; `amount` 0..1 dries it back out.
func set_wet(amount: float) -> void:
	if absf(amount - _wet) < 0.03 and (amount > 0.0 or _wet == 0.0):
		return
	if _wet_mat == null:
		_wet_mat = StandardMaterial3D.new()
		_wet_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_wet_mat.albedo_color = Color(0.03, 0.04, 0.06, 0.0)
		_wet_mat.roughness = 0.08
		_wet_mat.metallic_specular = 1.0
	var was_dry := _wet == 0.0
	_wet = amount
	_wet_mat.albedo_color.a = 0.42 * amount
	if was_dry != (amount == 0.0):
		for m in find_children("*", "MeshInstance3D", true, false):
			if not m.is_in_group("soot"):
				(m as MeshInstance3D).material_overlay = _wet_mat if amount > 0.0 else null


func face(target: Vector3, duration := 0.25) -> void:
	var d := target - position
	if Vector2(d.x, d.z).length() < 0.01:
		return
	var yaw := atan2(-d.x, -d.z)
	create_tween().tween_property(self, "rotation:y", rotation.y + angle_difference(rotation.y, yaw), duration)


func move_to(target: Vector3, duration: float) -> Tween:
	halt()
	face(target)
	moving = true
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", target, duration)
	_move_tween.tween_callback(func(): moving = false)
	return _move_tween


## Cancels any movement in progress.
func halt() -> void:
	if _move_tween:
		_move_tween.kill()
	moving = false
