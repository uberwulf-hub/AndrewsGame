extends SceneTree
## Gives an unrigged A-pose character the skeleton of an already-rigged A-pose
## character (for when Mixamo's auto-rigger won't take a model, e.g. a dress).
##
## godot_console --headless --path . -s res://tools/transfer_rig.gd -- res://models/hero/hero.fbx res://models/preview/mate.obj res://models/mate/mate.scn
##
## - The donor skeleton's joints are moved to the new body's proportions
##   (each axis scaled between the two bodies' bounding boxes).
## - Each new vertex copies the bone weights of the nearest donor vertex, with
##   both bodies normalized to their bounding boxes so shoulders meet shoulders.
## - The result is a scene with the same node layout and bone names as the
##   donor, so the donor's animations play on it unchanged.

const GRID := 24


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var donor := (load(args[0]) as PackedScene).instantiate()
	var body := load(args[1]) as Mesh
	var out_path: String = args[2]

	var mi: MeshInstance3D = donor.find_children("*", "MeshInstance3D", true, false)[0]
	var sk: Skeleton3D = donor.find_children("*", "Skeleton3D", true, false)[0]
	var d_arr: Array = mi.mesh.surface_get_arrays(0)
	var d_verts: PackedVector3Array = d_arr[Mesh.ARRAY_VERTEX]
	var d_bones: PackedInt32Array = d_arr[Mesh.ARRAY_BONES]
	var d_weights: PackedFloat32Array = d_arr[Mesh.ARRAY_WEIGHTS]
	var per := d_bones.size() / d_verts.size()
	var d_box := _bounds(d_verts)

	# Bring the new body into the donor's units, matched in height, standing
	# where the donor stands (centered in x/z, feet together at the bottom).
	var b_arr: Array = body.surface_get_arrays(0)
	var b_src: PackedVector3Array = b_arr[Mesh.ARRAY_VERTEX]
	var b_box_src := _bounds(b_src)
	var k := d_box.size.y / b_box_src.size.y
	var b_verts := PackedVector3Array()
	for p in b_src:
		var q := (p - b_box_src.position) * k
		b_verts.append(Vector3(
			q.x - b_box_src.size.x * k * 0.5 + d_box.get_center().x,
			q.y + d_box.position.y,
			q.z - b_box_src.size.z * k * 0.5 + d_box.get_center().z))
	var b_box := _bounds(b_verts)
	var ratio := b_box.size / d_box.size
	print("donor size ", d_box.size, " body size ", b_box.size, " ratio ", ratio)

	# Nearest donor vertex for each body vertex, in normalized space.
	var grid := {}
	for i in d_verts.size():
		var key := _cell(_norm(d_verts[i], d_box))
		if not grid.has(key):
			grid[key] = PackedInt32Array()
		grid[key].append(i)
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	bones.resize(b_verts.size() * per)
	weights.resize(b_verts.size() * per)
	for i in b_verts.size():
		var n := _norm(b_verts[i], b_box)
		var best := _nearest(n, grid, d_verts, d_box)
		for w in per:
			bones[i * per + w] = d_bones[best * per + w]
			weights[i * per + w] = d_weights[best * per + w]

	var arrays := b_arr.duplicate()
	arrays[Mesh.ARRAY_VERTEX] = b_verts
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_TANGENT] = null
	var mesh := ArrayMesh.new()
	var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per == 8 else 0
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	mesh.surface_set_material(0, body.surface_get_material(0))

	# Move the joints to the new proportions and rebuild the bind poses.
	var old_global: Array[Transform3D] = []
	var new_global: Array[Transform3D] = []
	for b in sk.get_bone_count():
		var g := sk.get_bone_global_rest(b)
		old_global.append(g)
		var o := g.origin - d_box.position
		var c := d_box.get_center() - d_box.position
		var mapped := Vector3((o.x - c.x) * ratio.x + c.x, o.y * ratio.y, (o.z - c.z) * ratio.z + c.z)
		new_global.append(Transform3D(g.basis, mapped + d_box.position))
	for b in sk.get_bone_count():
		var parent := sk.get_bone_parent(b)
		var local := new_global[b] if parent < 0 else new_global[parent].affine_inverse() * new_global[b]
		sk.set_bone_rest(b, local)
	sk.reset_bone_poses()
	var skin := Skin.new()
	for j in mi.skin.get_bind_count():
		var bone := sk.find_bone(mi.skin.get_bind_name(j)) if mi.skin.get_bind_name(j) != "" else mi.skin.get_bind_bone(j)
		var mesh_to_skel := old_global[bone] * mi.skin.get_bind_pose(j)
		skin.add_named_bind(sk.get_bone_name(bone), new_global[bone].affine_inverse() * mesh_to_skel)
	mi.mesh = mesh
	mi.skin = skin
	mi.name = out_path.get_file().get_basename()

	for n in donor.find_children("*", "", true, false):
		n.owner = donor
	for old in donor.find_children("*", "AnimationPlayer", true, false):
		old.free()
	var packed := PackedScene.new()
	packed.pack(donor)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
	print("saved ", out_path, " -> ", ResourceSaver.save(packed, out_path))
	quit()


func _bounds(v: PackedVector3Array) -> AABB:
	var box := AABB(v[0], Vector3.ZERO)
	for p in v:
		box = box.expand(p)
	return box


func _norm(p: Vector3, box: AABB) -> Vector3:
	return (p - box.position) / box.size


func _cell(n: Vector3) -> Vector3i:
	return Vector3i(clampi(int(n.x * GRID), 0, GRID - 1), clampi(int(n.y * GRID), 0, GRID - 1), clampi(int(n.z * GRID), 0, GRID - 1))


func _nearest(n: Vector3, grid: Dictionary, d_verts: PackedVector3Array, d_box: AABB) -> int:
	var c := _cell(n)
	var best := -1
	var best_d := INF
	var r := 1
	while best < 0 or r <= 2:
		for x in range(c.x - r, c.x + r + 1):
			for y in range(c.y - r, c.y + r + 1):
				for z in range(c.z - r, c.z + r + 1):
					var key := Vector3i(x, y, z)
					if not grid.has(key):
						continue
					for i in grid[key]:
						var d := _norm(d_verts[i], d_box).distance_squared_to(n)
						if d < best_d:
							best_d = d
							best = i
		r += 1
		if r > GRID:
			break
	return best
