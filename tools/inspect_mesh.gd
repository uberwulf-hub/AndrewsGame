extends SceneTree
## godot_console --headless --path . -s res://tools/inspect_mesh.gd -- model.glb


func _init() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		print("load failed")
		quit()
		return
	var root := doc.generate_scene(state)
	var stats := {"verts": 0, "tris": 0}
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		var xf: Transform3D = mi.global_transform if mi.is_inside_tree() else _xf(mi)
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			stats.verts += verts.size()
			stats.tris += idx.size() / 3 if idx.size() > 0 else verts.size() / 3
			for v in verts:
				var p := xf * v
				if first:
					box = AABB(p, Vector3.ZERO)
					first = false
				else:
					box = box.expand(p)
	print(stats, " bounds ", box)
	# Which way is the face? Compare forward extent in the head band.
	var top := box.position.y + box.size.y
	var zs := []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var arr: Array = mi.mesh.surface_get_arrays(0)
		for v in arr[Mesh.ARRAY_VERTEX]:
			var p: Vector3 = _xf(mi) * v
			if p.y > top - box.size.y * 0.1:
				zs.append(p.z)
	zs.sort()
	print("head z range ", zs[0], " .. ", zs[zs.size() - 1], " center ", box.get_center().z)
	quit()


func _xf(n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
