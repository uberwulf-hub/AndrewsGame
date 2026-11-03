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
	if _rig:
		var speed := (position - _last_pos).length() / maxf(delta, 0.0001)
		_last_pos = position
		_speed = lerpf(_speed, speed, 1.0 - exp(-6.0 * delta))
		if _speed > 2.5:
			_rig.play("run", clampf(_speed / 5.0, 0.7, 1.5), 0.25)
		elif _speed > 0.2 or moving:
			_rig.play("walk", clampf(_speed / 1.4, 0.6, 1.6), 0.25)
		else:
			_rig.play("idle", 1.0, 0.4)
		return
	if moving:
		_body.position.y = absf(sin(_t * 12.0)) * 0.12
	else:
		_body.position.y = lerpf(_body.position.y, 0.0, 1.0 - exp(-10.0 * delta))
	_tail.rotation.y = sin(_t * (10.0 if moving else 3.0)) * 0.4


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
