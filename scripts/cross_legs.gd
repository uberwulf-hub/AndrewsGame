class_name CrossLegs
extends SkeletonModifier3D
## Sits the hero cross-legged on the ground on top of the "sit" animation (which
## is a chair sit): drops the hips to the ground, swings the knees out wide and
## tucks each ankle in under the other knee. `amount` (0..1) blends it in and
## out; the player sets `ground` and `forward` (world space) each frame.

var amount := 0.0
var ground := 0.0
var forward := Vector3.FORWARD

const SEAT_HEIGHT := 0.16  # hips above the ground, sitting
var _bones := {}


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or amount < 0.001:
		return
	if _bones.is_empty():
		for part in ["hips", "leftupleg", "leftleg", "leftfoot", "rightupleg", "rightleg", "rightfoot"]:
			_bones[part] = _find(skel, part)
		if _bones.values().has(-1):
			_bones.clear()
			return
	var to_world := skel.global_transform
	var to_skel := to_world.affine_inverse()
	# Hips down onto the ground.
	var hips: int = _bones["hips"]
	var pose := skel.get_bone_global_pose(hips)
	var hips_world := to_world * pose.origin
	var seat := Vector3(hips_world.x, ground + SEAT_HEIGHT, hips_world.z) - forward * 0.05
	pose.origin = pose.origin.lerp(to_skel * seat, amount)
	skel.set_bone_global_pose(hips, pose)
	var up := Vector3.UP
	var right := forward.cross(up).normalized()
	var center := to_world * skel.get_bone_global_pose(hips).origin
	for side in ["left", "right"]:
		var out := -right if side == "left" else right
		var hip_joint := to_world * skel.get_bone_global_pose(_bones[side + "upleg"]).origin
		var knee := hip_joint + forward * 0.3 + out * 0.3 + up * 0.04
		# Each ankle tucks under the opposite knee; the left one sits a bit in front.
		var ankle := center + forward * (0.3 if side == "left" else 0.2) - out * 0.16 + up * (0.02 if side == "left" else 0.05)
		knee.y = maxf(knee.y, ground + 0.12)
		ankle.y = maxf(ankle.y, ground + 0.06)
		_aim(skel, _bones[side + "upleg"], _bones[side + "leg"], to_skel * knee)
		_aim(skel, _bones[side + "leg"], _bones[side + "foot"], to_skel * ankle)


func _find(skel: Skeleton3D, suffix: String) -> int:
	for i in skel.get_bone_count():
		if skel.get_bone_name(i).to_lower().ends_with(suffix):
			return i
	return -1


## Turns `bone` so its child points at `goal` (skeleton space), blended by `amount`.
func _aim(skel: Skeleton3D, bone: int, child: int, goal: Vector3) -> void:
	var pose := skel.get_bone_global_pose(bone)
	var now := (skel.get_bone_global_pose(child).origin - pose.origin).normalized()
	var want := (goal - pose.origin).normalized()
	if now.dot(want) > 0.9999:
		return
	pose.basis = Basis(Quaternion.IDENTITY.slerp(Quaternion(now, want), amount)) * pose.basis
	skel.set_bone_global_pose(bone, pose)
