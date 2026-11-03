class_name NatureKit
extends RefCounted
## Irregular natural meshes for scattering with MultiMesh: grass clumps,
## ferns, twigs, leaf litter, pebbles and mushrooms. Each is built once from a
## seeded random generator so instances can share it; variety comes from the
## per-instance transform and color.


## A clump of curved, tapered blades of different heights leaning different
## ways. Vertex color runs dark at the root to white at the tip (multiplied by
## the instance color).
static func grass_clump(blades := 7, seed := 5) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in blades:
		var a := r.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.0, 0.09)
		var h := r.randf_range(0.18, 0.55)
		var w := r.randf_range(0.014, 0.03)
		var lean_a := a + r.randf_range(-0.8, 0.8)
		var lean := Vector3(cos(lean_a), 0, sin(lean_a)) * r.randf_range(0.04, 0.3)
		var side_a := r.randf() * TAU
		var side := Vector3(cos(side_a), 0, sin(side_a))
		var segs := 4
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for k in segs + 1:
			var t := float(k) / segs
			var center := base + Vector3(0, h * t, 0) + lean * h * t * t * 2.0
			var half := w * (1.0 - t * 0.92)
			var l := center - side * half
			var rr := center + side * half
			if k > 0:
				var c0 := Color.WHITE * lerpf(0.35, 1.0, float(k - 1) / segs)
				var c1 := Color.WHITE * lerpf(0.35, 1.0, t)
				c0.a = 1.0
				c1.a = 1.0
				_tri(st, prev_l, prev_r, l, c0, c0, c1)
				_tri(st, prev_r, rr, l, c0, c1, c1)
			prev_l = l
			prev_r = rr
	return st.commit()


## A fern: a fan of arching fronds made of thin tapering strips.
static func fern(fronds := 9, seed := 11) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f in fronds:
		var a := TAU * f / fronds + r.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var length := r.randf_range(0.45, 0.8)
		var rise := r.randf_range(0.25, 0.45)
		var segs := 6
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for k in segs + 1:
			var t := float(k) / segs
			var p := dir * length * t + Vector3(0, rise * sin(t * PI * 0.8), 0)
			var half := 0.07 * sin(t * PI) + 0.005
			var l := p - side * half
			var rr := p + side * half
			if k > 0:
				var c := Color.WHITE * lerpf(0.5, 1.0, t)
				c.a = 1.0
				_tri(st, prev_l, prev_r, l, c, c, c)
				_tri(st, prev_r, rr, l, c, c, c)
			prev_l = l
			prev_r = rr
	return st.commit()


## A short crooked stick with one side branch, lying on the ground.
static func twig() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_stick(st, Vector3(-0.22, 0.015, 0), Vector3(0.0, 0.02, 0.03), 0.012)
	_stick(st, Vector3(0.0, 0.02, 0.03), Vector3(0.24, 0.015, -0.01), 0.01)
	_stick(st, Vector3(0.05, 0.02, 0.02), Vector3(0.14, 0.03, 0.12), 0.006)
	return st.commit()


## A fallen leaf: a slightly cupped diamond.
static func leaf() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := Vector3(0, 0.004, -0.06)
	var stem := Vector3(0, 0.004, 0.06)
	var l := Vector3(-0.035, 0.012, 0)
	var rr := Vector3(0.035, 0.012, 0)
	var mid := Vector3(0, 0.0, 0)
	for pair in [[tip, l], [l, stem], [stem, rr], [rr, tip]]:
		_tri(st, mid, pair[0], pair[1], Color.WHITE, Color.WHITE, Color.WHITE)
	return st.commit()


static func pebble() -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = 0.1
	s.height = 0.12
	s.radial_segments = 6
	s.rings = 3
	return s


## Mushroom: stem and cap as one mesh; vertex color marks the cap (white) and
## stem (light gray) so an instance color tints mostly the cap.
static func mushroom() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem := Color(0.95, 0.92, 0.85)
	var sides := 7
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var b0 := Vector3(cos(a0), 0, sin(a0)) * 0.018
		var b1 := Vector3(cos(a1), 0, sin(a1)) * 0.018
		var t0 := b0 * 0.8 + Vector3(0, 0.07, 0)
		var t1 := b1 * 0.8 + Vector3(0, 0.07, 0)
		_tri(st, b0, b1, t0, stem, stem, stem)
		_tri(st, b1, t1, t0, stem, stem, stem)
		var top := Vector3(0, 0.1, 0)
		var r0 := Vector3(cos(a0), 0, sin(a0)) * 0.055 + Vector3(0, 0.065, 0)
		var r1 := Vector3(cos(a1), 0, sin(a1)) * 0.055 + Vector3(0, 0.065, 0)
		_tri(st, top, r1, r0, Color.WHITE, Color.WHITE, Color.WHITE)
	return st.commit()


## Root flare for a trunk of radius 1 at the origin: `count` tapered roots
## that leave the trunk a little above the ground, arch outward over the soil,
## wander sideways and dive below the surface. Scale it to the trunk radius.
static func root_flare(count := 6, seed := 3) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in count:
		var a := TAU * i / count + r.randf_range(-0.35, 0.35)
		var reach := r.randf_range(2.4, 4.2)
		var wander := r.randf_range(-0.5, 0.5)
		var thick := r.randf_range(0.32, 0.5)
		var pts: Array[Vector3] = []
		var radii: Array[float] = []
		var steps := 7
		for k in steps + 1:
			var t := float(k) / steps
			var ang := a + wander * t * t
			var dist := lerpf(0.55, reach, t)
			# Up on the trunk, a hump over the soil, then down under it.
			var y := lerpf(0.9, 0.0, smoothstep(0.0, 0.45, t)) + sin(t * PI) * 0.12 - smoothstep(0.6, 1.0, t) * 0.45
			pts.append(Vector3(cos(ang) * dist, y, sin(ang) * dist))
			radii.append(thick * lerpf(1.0, 0.12, pow(t, 0.8)))
		_tube(st, pts, radii, 7)
	return st.commit()


static func _tube(st: SurfaceTool, pts: Array[Vector3], radii: Array[float], sides: int) -> void:
	var rings: Array = []
	for k in pts.size():
		var forward := (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
		var side := forward.cross(Vector3.UP).normalized()
		if side.length() < 0.1:
			side = Vector3.RIGHT
		var up := side.cross(forward).normalized()
		var ring: Array[Vector3] = []
		for s in sides:
			var a := TAU * s / sides
			# Roots are flattened: wider than they are tall.
			ring.append(pts[k] + (side * cos(a) * 1.25 + up * sin(a) * 0.8) * radii[k])
		rings.append(ring)
	var c := Color.WHITE
	for k in rings.size() - 1:
		for s in sides:
			var quad := [[k, s], [k + 1, s], [k, (s + 1) % sides], [k, (s + 1) % sides], [k + 1, s], [k + 1, (s + 1) % sides]]
			for q in quad:
				var v: Vector3 = rings[q[0]][q[1]]
				st.set_normal((v - pts[q[0]]).normalized())  # outward from the root's core
				st.set_color(c)
				st.add_vertex(v)


## Shared double-sided material that uses vertex x instance colors.
static func tinted(roughness := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = roughness
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _stick(st: SurfaceTool, a: Vector3, b: Vector3, radius: float) -> void:
	var axis := (b - a).normalized()
	var u := axis.cross(Vector3.UP).normalized()
	var v := axis.cross(u)
	var c := Color.WHITE
	for i in 4:
		var a0 := TAU * i / 4.0
		var a1 := TAU * (i + 1) / 4.0
		var o0 := (u * cos(a0) + v * sin(a0)) * radius
		var o1 := (u * cos(a1) + v * sin(a1)) * radius
		_tri(st, a + o0, b + o0, a + o1, c, c, c)
		_tri(st, b + o0, b + o1, a + o1, c, c, c)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
	n = n.lerp(Vector3.UP, 0.6).normalized()  # soft, ground-like shading on thin parts
	st.set_normal(n)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(cc)
	st.add_vertex(c)
