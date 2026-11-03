extends SceneTree
## Turns an untextured image-to-3D shape into a textured, game-sized model by
## projecting the front-view picture it was made from onto it, then packs it as
## OBJ + MTL + PNG in a zip that Mixamo can auto-rig.
##
## godot_console --headless --path . -s res://tools/paint_model.gd -- shape.glb picture.png out_dir height_m name
##
## The texture is an atlas: left half = the picture (front-facing triangles),
## right half = a "back view" made from the picture with the face replaced by
## hair and neck, plus solid swatches (backpack). Each triangle picks a half by
## its normal, so nothing smears across the silhouette.

const TARGET_TRIS := 25000
const FRONT := Vector3(0, 0, 1)

# Per-character tweaks for the back of the head (bands are fractions of the
# figure height from the top; head_half is a fraction of the figure width) and
# where to sample hair/skin colors in the picture: [y_from, y_to, x].
const PROFILES := {
	"hero": {"hair_from": 0.065, "hair_to": 0.13, "neck_to": 0.2, "head_half": 0.12,
		"hair_at": [0.11, 0.13, 0.5], "hair_darken": 0.15, "skin_at": [0.5, 0.56, 0.06], "backpack": true},
	"mate": {"hair_from": 0.0, "hair_to": 0.2, "neck_to": 0.2, "head_half": 0.2,
		"hair_at": [0.1, 0.16, 0.32], "hair_darken": 0.0, "skin_at": [0.45, 0.5, 0.08], "backpack": false},
	"younger": {"hair_from": 0.0, "hair_to": 0.25, "neck_to": 0.31, "head_half": 0.23,
		"hair_at": [0.05, 0.12, 0.3], "hair_darken": 0.0, "skin_at": [0.52, 0.58, 0.1], "backpack": false},
}
const PACK_TOP := 0.2
const PACK_BOTTOM := 0.5

var _img: Image
var _fig: Rect2i  # figure bounds inside the picture
var _w := 0
var _h := 0
var _pack_tris := 0
var _name := "hero"
var _p: Dictionary


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var shape_path: String = args[0]
	_img = Image.load_from_file(args[1])
	_img.convert(Image.FORMAT_RGBA8)
	var out_dir: String = args[2]
	var height := float(args[3])
	_name = args[4] if args.size() > 4 else "hero"
	_p = PROFILES.get(_name, PROFILES.hero)
	_w = _img.get_width()
	_h = _img.get_height()
	_fig = _figure_bounds()
	print("figure in picture: ", _fig)

	var mesh := _load_mesh(shape_path)
	var verts: PackedVector3Array = mesh[0]
	var tris: PackedInt32Array = _simplify(verts, mesh[1])
	print("triangles: ", tris.size() / 3)

	var box := AABB(verts[tris[0]], Vector3.ZERO)
	for i in tris:
		box = box.expand(verts[i])
	var atlas := _build_atlas()
	_write_obj(out_dir, verts, tris, box, height)
	atlas.save_png(out_dir.path_join(_name + "_tex.png"))
	_zip(out_dir)
	print("backpack triangles: ", _pack_tris)
	print("done: ", out_dir)
	quit()


# --- Picture -----------------------------------------------------------------

func _is_figure(c: Color, bg: Color) -> bool:
	var diff := absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b)
	return diff > 0.12 and (c.s > 0.1 or c.v < 0.35)


func _figure_bounds() -> Rect2i:
	var bg := _img.get_pixel(4, 4)
	var x0 := _w
	var y0 := _h
	var x1 := 0
	var y1 := 0
	for y in range(0, _h, 2):
		for x in range(0, _w, 2):
			if _is_figure(_img.get_pixel(x, y), bg):
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	return Rect2i(x0, y0, x1 - x0, y1 - y0)


func _sample_band(y_frac0: float, y_frac1: float, x_frac: float) -> Color:
	var bg := _img.get_pixel(4, 4)
	var acc := Color(0, 0, 0)
	var n := 0
	for k in 40:
		var y := int(_fig.position.y + lerpf(y_frac0, y_frac1, k / 40.0) * _fig.size.y)
		var x := int(_fig.position.x + x_frac * _fig.size.x)
		var c := _img.get_pixel(clampi(x, 0, _w - 1), clampi(y, 0, _h - 1))
		if _is_figure(c, bg):
			acc += c
			n += 1
	return acc / maxf(n, 1) if n > 0 else Color(0.3, 0.2, 0.15)


## Left: the picture. Right: the back view.
func _build_atlas() -> Image:
	var atlas := Image.create(_w * 2, _h, false, Image.FORMAT_RGBA8)
	var bg := _img.get_pixel(4, 4)
	var front := _bleed(_img, bg)
	atlas.blit_rect(front, Rect2i(0, 0, _w, _h), Vector2i.ZERO)
	var back := front.duplicate() as Image
	var hair_at: Array = _p.hair_at
	var skin_at: Array = _p.skin_at
	var hair := _sample_band(hair_at[0], hair_at[1], hair_at[2]).darkened(_p.hair_darken)
	var skin := _sample_band(skin_at[0], skin_at[1], skin_at[2])
	# Seen from behind, the face is hair (and the neck below it is skin).
	for y in range(_fig.position.y, _fig.end.y):
		var f := float(y - _fig.position.y) / _fig.size.y
		if f < _p.hair_from or f > _p.neck_to:
			continue
		for x in range(_fig.position.x, _fig.end.x):
			if not _is_figure(_img.get_pixel(x, y), bg):
				continue
			var xf := float(x - _fig.position.x) / _fig.size.x
			if absf(xf - 0.5) > _p.head_half:
				continue  # only the head column; shoulders stay as they are
			back.set_pixel(x, y, hair if f < _p.hair_to else skin)
	atlas.blit_rect(back, Rect2i(0, 0, _w, _h), Vector2i(_w, 0))
	# Solid swatches in an empty corner of the back half.
	_swatch(atlas, Vector2i(_w + 8, 8), Color(0.2, 0.2, 0.19))   # backpack
	_swatch(atlas, Vector2i(_w + 48, 8), hair)
	return atlas


## Background pixels near the figure take the color of the nearest figure pixel
## on their row, so silhouette edges and side-facing triangles (which the 3D
## shape and the picture never line up on exactly) pick up clothing, not wall.
func _bleed(src: Image, bg: Color) -> Image:
	var out := src.duplicate() as Image
	var reach := 60
	for y in range(maxi(_fig.position.y - 20, 0), mini(_fig.end.y + 20, _h)):
		var hits := PackedInt32Array()
		for x in _w:
			if _is_figure(src.get_pixel(x, y), bg):
				hits.append(x)
		if hits.is_empty():
			continue
		var k := 0
		for x in _w:
			while k + 1 < hits.size() and absi(hits[k + 1] - x) <= absi(hits[k] - x):
				k += 1
			var d := absi(hits[k] - x)
			if d == 0 or d > reach:
				continue
			# Step a couple of pixels inside so anti-aliased edges don't leak in.
			var inward := clampi(hits[k] + signi(hits[k] - x) * 2, 0, _w - 1)
			out.set_pixel(x, y, src.get_pixel(inward, y))
	return out


func _swatch(atlas: Image, at: Vector2i, c: Color) -> void:
	atlas.fill_rect(Rect2i(at, Vector2i(32, 32)), c)


func _swatch_uv(index: int) -> Vector2:
	return Vector2((_w + 8 + 40 * index + 16) / float(_w * 2), (8 + 16) / float(_h))


# --- Mesh --------------------------------------------------------------------

func _load_mesh(path: String) -> Array:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_file(path, state)
	var root := doc.generate_scene(state)
	var verts := PackedVector3Array()
	var tris := PackedInt32Array()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var xf := _xf(mi)
		for s in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(s)
			var base := verts.size()
			for v in arr[Mesh.ARRAY_VERTEX]:
				verts.append(xf * v)
			# Godot stores front faces clockwise; flip back to the usual
			# counter-clockwise so normals point out and the OBJ isn't inside out.
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for t in range(0, idx.size(), 3):
				tris.append_array([base + idx[t], base + idx[t + 2], base + idx[t + 1]])
	root.free()
	return [verts, tris]


func _simplify(verts: PackedVector3Array, tris: PackedInt32Array) -> PackedInt32Array:
	var im := ImporterMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_INDEX] = tris
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr)
	im.generate_lods(25.0, 60.0, [])
	var best := tris
	for lod in im.get_surface_lod_count(0):
		var idx := im.get_surface_lod_indices(0, lod)
		if idx.size() / 3 >= TARGET_TRIS:
			best = idx
	return best


func _write_obj(out_dir: String, verts: PackedVector3Array, tris: PackedInt32Array, box: AABB, height: float) -> void:
	var scale := height / box.size.y
	var lift := -box.position.y
	# Compact the vertices this LOD uses, and give them smooth normals.
	var remap := {}
	var used := PackedVector3Array()
	for i in tris:
		if not remap.has(i):
			remap[i] = used.size()
			used.append(verts[i])
	var normals := PackedVector3Array()
	normals.resize(used.size())
	for t in range(0, tris.size(), 3):
		var a: Vector3 = used[remap[tris[t]]]
		var b: Vector3 = used[remap[tris[t + 1]]]
		var c: Vector3 = used[remap[tris[t + 2]]]
		var n := (b - a).cross(c - a)
		for k in 3:
			normals[remap[tris[t + k]]] += n
	var lines := PackedStringArray(["mtllib %s.mtl" % _name, "o " + _name])
	for v in used:
		var p := (v + Vector3(0, lift, 0)) * scale
		lines.append("v %.5f %.5f %.5f" % [p.x, p.y, p.z])
	for n in normals:
		var nn := n.normalized()
		lines.append("vn %.4f %.4f %.4f" % [nn.x, nn.y, nn.z])
	# UVs are per triangle corner: front or back half of the atlas, or a swatch.
	var vt := PackedStringArray()
	var faces := PackedStringArray()
	var top := box.position.y + box.size.y
	var center_z := box.get_center().z
	for t in range(0, tris.size(), 3):
		var pa: Vector3 = used[remap[tris[t]]]
		var pb: Vector3 = used[remap[tris[t + 1]]]
		var pc: Vector3 = used[remap[tris[t + 2]]]
		var n := (pb - pa).cross(pc - pa)
		var centroid := (pa + pb + pc) / 3.0
		var band := (top - centroid.y) / box.size.y
		var back := n.dot(FRONT) < 0.0
		var swatch := -1
		if _p.backpack and back and band > PACK_TOP and band < PACK_BOTTOM and centroid.z < center_z - box.size.z * 0.06 and absf(centroid.x - box.get_center().x) < box.size.x * 0.19:
			swatch = 0  # the backpack sticks out behind the torso
			_pack_tris += 1
		var corner := []
		for p: Vector3 in [pa, pb, pc]:
			var uv: Vector2
			if swatch >= 0:
				uv = _swatch_uv(swatch)
			else:
				var u: float = (p.x - box.position.x) / box.size.x
				var v: float = (top - p.y) / box.size.y
				var px: float = _fig.position.x + u * _fig.size.x
				var py: float = _fig.position.y + v * _fig.size.y
				uv = Vector2((px + (_w if back else 0)) / (_w * 2.0), py / _h)
			vt.append("vt %.5f %.5f" % [uv.x, 1.0 - uv.y])
			corner.append(vt.size())
		var ia: int = remap[tris[t]] + 1
		var ib: int = remap[tris[t + 1]] + 1
		var ic: int = remap[tris[t + 2]] + 1
		faces.append("f %d/%d/%d %d/%d/%d %d/%d/%d" % [ia, corner[0], ia, ib, corner[1], ib, ic, corner[2], ic])
	lines.append_array(vt)
	lines.append("usemtl " + _name)
	lines.append("s 1")
	lines.append_array(faces)
	var f := FileAccess.open(out_dir.path_join(_name + ".obj"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	var m := FileAccess.open(out_dir.path_join(_name + ".mtl"), FileAccess.WRITE)
	m.store_string("newmtl %s\nKd 1 1 1\nmap_Kd %s_tex.png\n" % [_name, _name])
	m.close()


func _zip(out_dir: String) -> void:
	var zip := ZIPPacker.new()
	zip.open(out_dir.path_join(_name + "_mixamo.zip"))
	for name in [_name + ".obj", _name + ".mtl", _name + "_tex.png"]:
		zip.start_file(name)
		zip.write_file(FileAccess.get_file_as_bytes(out_dir.path_join(name)))
		zip.close_file()
	zip.close()


func _xf(n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
