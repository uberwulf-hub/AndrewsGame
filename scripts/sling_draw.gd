class_name SlingDraw
extends SkeletonModifier3D
## The sling's draw, on top of the aiming animation: the left arm reaches out
## along the aim holding the fork, and the right hand pulls the band back to
## the cheek, elbow out to the side. `hold` and `draw` (0..1) are driven by
## the player: hold while aiming the sling, draw until the stone flies.

var hold := 0.0
var draw := 0.0
## 0..1: his arms trembling as they tire from holding the draw.
var shake := 0.0
var _t := 0.0
## Where he's aiming, in world space (a unit direction).
var aim_dir := Vector3.FORWARD

var _left := []   # upper arm, forearm, hand
var _right := []
var _head := -1
var _chest := -1


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or (hold < 0.001 and draw < 0.001):
		return
	if _left.is_empty():
		for part in ["arm", "forearm", "hand"]:
			_left.append(CharacterRig.find_bone(skel, "left" + part))
			_right.append(CharacterRig.find_bone(skel, "right" + part))
		_head = CharacterRig.find_bone(skel, "head")
		_chest = CharacterRig.find_bone(skel, "spine1")
	if _left.has(-1) or _right.has(-1) or _head < 0 or _chest < 0:
		return
	# Everything below is in the skeleton's own space.
	var to_local := skel.global_transform.affine_inverse()
	var fwd := (to_local.basis * aim_dir).normalized()
	var up := (to_local.basis * Vector3.UP).normalized()
	var right := fwd.cross(up).normalized()
	var unit := (to_local.basis * Vector3.RIGHT).length()  # skeleton units per metre
	var chest := skel.get_bone_global_pose(_chest).origin
	var head := skel.get_bone_global_pose(_head).origin
	var shoulder_y := chest + up * 0.12 * unit
	# Fork held out in front, a touch left of centre and at eye-line.
	var front := shoulder_y + fwd * 0.5 * unit - right * 0.04 * unit + up * 0.08 * unit
	# Band pulled back to just beside the right cheek.
	var cheek := head + right * 0.13 * unit + fwd * 0.06 * unit - up * 0.06 * unit
	if shake > 0.001:
		_t += get_process_delta_time()
		var jitter := (right * sin(_t * 37.0) + up * sin(_t * 29.0 + 1.3)) * 0.025 * unit * shake
		front += jitter
		cheek += jitter * 0.6
	if hold > 0.001:
		_reach(skel, _left, front, -right * 0.6 - up, hold)
	if draw > 0.001:
		_reach(skel, _right, cheek, right - up * 0.2 - fwd * 0.4, draw)


## Two-bone reach: bends the elbow toward `pole` so the hand lands on `goal`,
## blended by `amount`.
func _reach(skel: Skeleton3D, chain: Array, goal: Vector3, pole: Vector3, amount: float) -> void:
	var s := skel.get_bone_global_pose(chain[0]).origin
	var e := skel.get_bone_global_pose(chain[1]).origin
	var h := skel.get_bone_global_pose(chain[2]).origin
	var a := s.distance_to(e)
	var b := e.distance_to(h)
	var to_goal := goal - s
	var d := clampf(to_goal.length(), absf(a - b) + 0.001, (a + b) * 0.999)
	var dir := to_goal.normalized()
	var x := (a * a - b * b + d * d) / (2.0 * d)
	var lift := sqrt(maxf(a * a - x * x, 0.0))
	var side := (pole - dir * pole.dot(dir)).normalized()
	var elbow := s + dir * x + side * lift
	var hand := s + dir * d
	_point(skel, chain[0], chain[1], elbow, amount)
	_point(skel, chain[1], chain[2], hand, amount)


## Turns `bone` so its child points at `at`, blended by `amount`.
func _point(skel: Skeleton3D, bone: int, child: int, at: Vector3, amount: float) -> void:
	var pose := skel.get_bone_global_pose(bone)
	var now := (skel.get_bone_global_pose(child).origin - pose.origin).normalized()
	var want := (at - pose.origin).normalized()
	if now.dot(want) > 0.9999:
		return
	pose.basis = Basis(Quaternion.IDENTITY.slerp(Quaternion(now, want), amount)) * pose.basis
	skel.set_bone_global_pose(bone, pose)
