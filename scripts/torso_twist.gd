class_name TorsoTwist
extends SkeletonModifier3D
## Twists the spine after the animation has posed it, so a rigged character's
## legs can run one way while the upper body turns to aim another. The turn is
## shared across the spine bones so it bends smoothly instead of at one joint.

var yaw := 0.0

var _bones := PackedInt32Array()


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or absf(yaw) < 0.001:
		return
	if _bones.is_empty():
		for i in skel.get_bone_count():
			var bone := skel.get_bone_name(i).to_lower()
			if bone.ends_with("spine") or bone.ends_with("spine1") or bone.ends_with("spine2"):
				_bones.append(i)
		if _bones.is_empty():
			return
	var share := Quaternion(Vector3.UP, yaw / _bones.size())
	for b in _bones:
		skel.set_bone_pose_rotation(b, skel.get_bone_pose_rotation(b) * share)
