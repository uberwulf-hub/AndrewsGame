class_name PunchArm
extends SkeletonModifier3D
## Throws a punch on top of whatever the animation is doing: swings one arm so
## the fist reaches toward a point in front of the chest, then pulls it back.
## `amount` (0..1) is driven by the player; `left` picks the arm.

var amount := 0.0
var left := false
## Where the fist is headed, in world space.
var target := Vector3.ZERO

var _bones := {}  # side -> [upper arm, forearm, hand]


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or amount < 0.001:
		return
	if _bones.is_empty():
		for side in ["left", "right"]:
			var chain := []
			for part in ["arm", "forearm", "hand"]:
				chain.append(_find(skel, side + part))
			if not chain.has(-1):
				_bones[side] = chain
	var chain: Array = _bones.get("left" if left else "right", [])
	if chain.is_empty():
		return
	var goal := skel.global_transform.affine_inverse() * target
	_aim(skel, chain[0], chain[1], goal)
	_aim(skel, chain[1], chain[2], goal)


func _find(skel: Skeleton3D, suffix: String) -> int:
	return CharacterRig.find_bone(skel, suffix)


## Turns `bone` so its child points at `goal`, blended by `amount`.
func _aim(skel: Skeleton3D, bone: int, child: int, goal: Vector3) -> void:
	var pose := skel.get_bone_global_pose(bone)
	var now := (skel.get_bone_global_pose(child).origin - pose.origin).normalized()
	var want := (goal - pose.origin).normalized()
	if now.dot(want) > 0.9999:
		return
	var turn := Quaternion.IDENTITY.slerp(Quaternion(now, want), amount)
	pose.basis = Basis(turn) * pose.basis
	skel.set_bone_global_pose(bone, pose)
