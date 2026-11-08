class_name CharacterRig
extends Node3D
## A rigged character model (e.g. made with image-to-3D and auto-rigged on Mixamo)
## with its animations, loaded from res://models/<name>/:
##
##   models/<name>/<name>.fbx (or .glb)   the skinned model
##   models/<name>/anims/<state>.fbx       one animation per file ("Without Skin")
##
## Each animation is named after its file (idle, walk, run, jump, swim, ...).
## The model is scaled to `target_height`, stood on y = 0 and turned to face -Z
## like every other character in the game.

const ROOT := "res://models/%s/"
const LOOPING := ["idle", "sit", "walk", "run", "walk_back", "strafe_left", "strafe_right", "swim", "tread", "fall", "aim_idle", "sprint"]
const EXTENSIONS := ["fbx", "glb", "gltf", "scn", "tscn"]
## Embedded animation names mapped to our state names.
const EMBEDDED_NAMES := {
	"survey": "idle",
	# KayKit adventurers (Kay Lousberg, CC0): their built-in animation set.
	"walking_a": "walk", "running_a": "run", "walking_backwards": "walk_back",
	"jump_start": "jump", "jump_idle": "fall", "lie_standup": "getting_up",
	"sit_floor_idle": "sit", "1h_ranged_aiming": "aim_idle",
	"running_strafe_left": "strafe_left", "running_strafe_right": "strafe_right",
	"unarmed_melee_attack_punch_a": "punch", "1h_melee_attack_chop": "attack",
	"hit_a": "hit", "death_a": "death", "pickup": "pick_up", "running_b": "sprint",
}
## Props that come in a character's hands (KayKit knives and crossbows); the
## game gives the hero its own tools, so these are hidden.
const PROP_MESHES := ["knife", "knife_offhand", "1h_crossbow", "2h_crossbow", "throwable"]

## Our helpers look bones up by Mixamo-style name endings ("leftupleg",
## "rightforearm"). Other skeletons are translated to those names here.
const BONE_ALIASES := {
	"upperarm": "arm", "lowerarm": "forearm", "hand": "hand",
	"upperleg": "upleg", "lowerleg": "leg", "foot": "foot", "toes": "toebase",
	"chest": "spine1",
}


static func canonical_bone(bone: String) -> String:
	var b := bone.to_lower()
	for side in [[".l", "left"], [".r", "right"], ["_l", "left"], ["_r", "right"]]:
		if b.ends_with(side[0]):
			var part := b.trim_suffix(side[0])
			if BONE_ALIASES.has(part):
				return side[1] + BONE_ALIASES[part]
	return BONE_ALIASES.get(b, b)


static func find_bone(skel: Skeleton3D, suffix: String) -> int:
	for i in skel.get_bone_count():
		if canonical_bone(skel.get_bone_name(i)).ends_with(suffix):
			return i
	return -1

## Emitted when a non-looping state (jump, getting_up, ...) plays to its end.
signal finished(state: String)

var anim_player: AnimationPlayer
var skeleton: Skeleton3D
var current := ""

var _model: Node3D


static func exists(rig_name: String) -> bool:
	return _model_path(rig_name) != ""


## Returns null when no model has been dropped in yet. A character without its
## own anims/ folder borrows `anims_from`'s (same Mixamo bone names).
static func create(rig_name: String, target_height := 1.8, anims_from := "hero") -> CharacterRig:
	var path: String = _model_path(rig_name)
	if path == "":
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var rig := CharacterRig.new()
	rig.name = "Rig_" + rig_name
	rig.soft_sides = rig_name in PAINTED
	rig._rig_name = rig_name
	rig._setup(scene.instantiate() as Node3D, target_height)
	var anims: String = ROOT % rig_name + "anims/"
	if DirAccess.open(anims) == null:
		if not rig.states().is_empty():
			return rig  # it brought its own animations
		anims = ROOT % anims_from + "anims/"
	rig._load_animations(anims)
	return rig


func has_state(state: String) -> bool:
	return anim_player.has_animation("rig/" + state)


func states() -> PackedStringArray:
	var out := PackedStringArray()
	if anim_player.has_animation_library("rig"):
		for a in anim_player.get_animation_library("rig").get_animation_list():
			out.append(a)
	return out


## Crossfades to a state if it exists; returns false otherwise so callers can fall back.
func play(state: String, speed := 1.0, blend := 0.2) -> bool:
	if not has_state(state):
		return false
	if current != state:
		anim_player.play("rig/" + state, blend, speed)
		current = state
	else:
		anim_player.speed_scale = speed
	return true


# --- Setup -------------------------------------------------------------------

func _setup(model: Node3D, target_height: float) -> void:
	_model = model
	add_child(_model)
	skeleton = _find(_model, "Skeleton3D") as Skeleton3D
	# Imported animations are replaced by our own player rooted at the model;
	# any that came inside the model file (e.g. the fox's Survey/Walk/Run) are kept.
	var embedded := {}
	for old in _model.find_children("*", "AnimationPlayer", true, false):
		for anim_name in old.get_animation_list():
			if anim_name != "RESET":
				embedded[String(anim_name).to_lower()] = old.get_animation(anim_name).duplicate(true)
		old.queue_free()
	anim_player = AnimationPlayer.new()
	anim_player.name = "RigAnimations"
	_model.add_child(anim_player)
	anim_player.root_node = NodePath("..")
	anim_player.add_animation_library("rig", AnimationLibrary.new())
	anim_player.animation_finished.connect(func(anim: StringName): finished.emit(String(anim).trim_prefix("rig/")))

	var box := _bounds(_model, Transform3D.IDENTITY)
	if box.size.y > 0.01:
		var s := target_height / box.size.y
		_model.scale = Vector3.ONE * s
		_model.position.y = -box.position.y * s
	_model.rotation.y = PI  # Mixamo characters face +Z; ours face -Z.
	_base_y = _model.position.y
	if soft_sides:
		_soften_sides()
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).to_lower() in PROP_MESHES:
			mi.visible = false
	for anim_name in embedded:
		_add_animation(EMBEDDED_NAMES.get(anim_name, anim_name), embedded[anim_name])
	if skeleton:
		for b in skeleton.get_bone_count():
			var bone := canonical_bone(skeleton.get_bone_name(b))
			if bone.ends_with("toebase") or bone.ends_with("foot"):
				_feet.append(b)


## Models painted from one front picture (the family) blur their side-facing
## surfaces so the picture's edge doesn't streak across cheeks and temples.
const PAINTED := ["hero", "mate", "younger"]
const SOFT_SIDES := preload("res://shaders/soft_sides.gdshader")
## Where a beard sits in a painted model's texture (in UVs), so it can wrap
## around the side of the jaw: the head column, the band from just under the cap
## to the jawline, and two spots on the beard to take its color from.
const BEARDS := {
	"hero": {"box": Vector4(0.205, 0.143, 0.300, 0.214), "a": Vector2(0.273, 0.190), "b": Vector2(0.267, 0.203), "front": Vector4(0.255, 0.168, 0.031, 0.036)},
}
var soft_sides := false
var _rig_name := ""


func _soften_sides() -> void:
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var base := mi.get_active_material(s) as BaseMaterial3D
			if base == null or base.albedo_texture == null:
				continue
			var m := ShaderMaterial.new()
			m.shader = SOFT_SIDES
			m.set_shader_parameter("albedo_tex", base.albedo_texture)
			if BEARDS.has(_rig_name):
				var beard: Dictionary = BEARDS[_rig_name]
				m.set_shader_parameter("beard_strength", 1.0)
				m.set_shader_parameter("beard_box", beard.box)
				m.set_shader_parameter("beard_uv_a", beard.a)
				m.set_shader_parameter("beard_uv_b", beard.b)
				m.set_shader_parameter("front_oval", beard.front)
			mi.set_surface_override_material(s, m)


# --- Foot grounding ------------------------------------------------------------

## States where the feet are supposed to leave the ground (or the body lies down).
const AIRBORNE := ["jump", "fall", "swim", "tread", "getting_up", "sit"]

var _base_y := 0.0
var _feet := PackedInt32Array()
var _rest_sole := NAN
var _lift := 0.0


## Keeps the soles from sinking below the rig's origin (the ground): when an
## animation pushes the lowest foot under where it stands at rest, the body is
## lifted by the difference. It never pulls the body down, so steps and hops
## stay as animated.
func _process(delta: float) -> void:
	if _feet.is_empty() or not is_inside_tree():
		return
	if is_nan(_rest_sole):
		_rest_sole = _lowest_foot(true)
	var target := 0.0
	if current not in AIRBORNE:
		target = clampf(_rest_sole - _lowest_foot(false), 0.0, 0.25)
	_lift = lerpf(_lift, target, 1.0 - exp(-20.0 * delta))
	_model.position.y = _base_y + _lift


## Height of the lowest foot bone in this rig's own space, as if unlifted
## (rest pose or current animated pose).
func _lowest_foot(rest: bool) -> float:
	var lowest := INF
	var to_rig := global_transform.affine_inverse() * skeleton.global_transform
	for b in _feet:
		var pose := skeleton.get_bone_global_rest(b) if rest else skeleton.get_bone_global_pose(b)
		lowest = minf(lowest, (to_rig * pose.origin).y)
	return lowest - (_model.position.y - _base_y)


func _load_animations(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	var seen := {}
	for file in dir.get_files():
		# Exported builds list "x.fbx.import" instead of "x.fbx".
		var base := file.trim_suffix(".import").trim_suffix(".remap")
		if base.get_extension().to_lower() not in EXTENSIONS or seen.has(base):
			continue
		seen[base] = true
		var scene := load(dir_path + base) as PackedScene
		if scene == null:
			continue
		var holder := scene.instantiate()
		var player := _find(holder, "AnimationPlayer") as AnimationPlayer
		if player:
			for anim_name in player.get_animation_list():
				if anim_name == "RESET":
					continue
				var state := base.get_basename().to_lower()
				_add_animation(state, player.get_animation(anim_name).duplicate(true), _hips_ratio(_find(holder, "Skeleton3D") as Skeleton3D))
				break
		holder.free()


## How much shorter or taller our legs are than the skeleton the animation was
## made for, so borrowed animations keep the feet on the ground.
func _hips_ratio(source: Skeleton3D) -> float:
	if source == null or skeleton == null:
		return 1.0
	var ours := _hips_height(skeleton)
	var theirs := _hips_height(source)
	return ours / theirs if theirs > 0.0001 else 1.0


static func _hips_height(sk: Skeleton3D) -> float:
	for b in sk.get_bone_count():
		if canonical_bone(sk.get_bone_name(b)).ends_with("hips"):
			return sk.get_bone_rest(b).origin.y
	return 0.0


func _add_animation(state: String, anim: Animation, hips_ratio := 1.0) -> void:
	var skel_path := String(_model.get_path_to(skeleton)) if skeleton else "Skeleton3D"
	for t in anim.get_track_count():
		var path: NodePath = anim.track_get_path(t)
		if path.get_subname_count() == 0:
			continue
		var bone := path.get_concatenated_subnames()
		# Point every bone track at our skeleton, whatever the source file called it.
		anim.track_set_path(t, NodePath(skel_path + ":" + bone))
		# Keep the character in place: drop horizontal root motion on the hips.
		if anim.track_get_type(t) == Animation.TYPE_POSITION_3D and bone.to_lower().ends_with("hips"):
			for k in anim.track_get_key_count(t):
				var p: Vector3 = anim.track_get_key_value(t, k)
				anim.track_set_key_value(t, k, Vector3(0.0, p.y * hips_ratio, 0.0))
	anim.loop_mode = Animation.LOOP_LINEAR if state in LOOPING else Animation.LOOP_NONE
	anim_player.get_animation_library("rig").add_animation(state, anim)


static func _model_path(rig_name: String) -> String:
	for ext in EXTENSIONS:
		var path: String = (ROOT % rig_name) + rig_name + "." + ext
		if ResourceLoader.exists(path):
			return path
	return ""


static func _find(node: Node, type: String) -> Node:
	if node.is_class(type):
		return node
	for child in node.get_children():
		var hit := _find(child, type)
		if hit:
			return hit
	return null


static func _bounds(node: Node, xform: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	var here := xform
	if node is Node3D:
		here = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh and String(node.name).to_lower() not in PROP_MESHES:
		box = here * (node as MeshInstance3D).mesh.get_aabb()
		first = false
	for child in node.get_children():
		var sub := _bounds(child, here)
		if sub.size == Vector3.ZERO:
			continue
		box = sub if first else box.merge(sub)
		first = false
	return box
