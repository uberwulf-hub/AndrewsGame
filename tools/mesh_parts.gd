extends SceneTree
## Lists the connected pieces of an OBJ (triangles that share vertices).
## godot_console --headless --path . -s res://tools/mesh_parts.gd -- model.obj


func _init() -> void:
	var lines := FileAccess.get_file_as_string(OS.get_cmdline_user_args()[0]).split("\n")
	var faces: Array[PackedInt32Array] = []
	var nverts := 0
	for l in lines:
		if l.begins_with("v "):
			nverts += 1
		elif l.begins_with("f "):
			var p := l.split(" ")
			faces.append(PackedInt32Array([int(p[1].split("/")[0]) - 1, int(p[2].split("/")[0]) - 1, int(p[3].split("/")[0]) - 1]))
	var parent := PackedInt32Array()
	parent.resize(nverts)
	for i in nverts:
		parent[i] = i
	for f in faces:
		_union(parent, f[0], f[1])
		_union(parent, f[1], f[2])
	var sizes := {}
	for f in faces:
		var r := _find(parent, f[0])
		sizes[r] = sizes.get(r, 0) + 1
	var counts := sizes.values()
	counts.sort()
	counts.reverse()
	print("pieces: ", counts.size(), "  largest: ", counts.slice(0, 8))
	quit()


func _find(p: PackedInt32Array, i: int) -> int:
	while p[i] != i:
		p[i] = p[p[i]]
		i = p[i]
	return i


func _union(p: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(p, a)
	var rb := _find(p, b)
	if ra != rb:
		p[ra] = rb
