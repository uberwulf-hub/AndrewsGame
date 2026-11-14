class_name MapView
extends Control
## The hero's hand-drawn map: the world as the World draws it, shown only where
## he's been, with charcoal marks for him, the camp and anything else found.
## Used twice: small and round in the corner (centered on him), and big when
## he unfolds it (M), fitted to everywhere he's been.

const INK := Color(0.16, 0.12, 0.09)
const EMBER := Color(0.85, 0.35, 0.12)

var round := false
## How much of the world's width it shows, and where it's centered (world x, z).
var span := 90.0
var center := Vector2.ZERO
var _rect: ColorRect
var _marks: Control
var _mat: ShaderMaterial


func _init(base: Texture2D, seen: Texture2D, is_round: bool) -> void:
	round = is_round
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/map.gdshader")
	_mat.set_shader_parameter("base_tex", base)
	_mat.set_shader_parameter("seen_tex", seen)
	_mat.set_shader_parameter("round_mask", round)
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_marks = Control.new()
	_marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.draw.connect(_draw_marks)
	add_child(_marks)


## Fits the view around everywhere he's been, with a margin.
func fit_explored() -> void:
	var n := Game.MAP_CELLS
	var cell := Game.TERRAIN_SIZE / n
	var lo := Vector2(INF, INF)
	var hi := -lo
	for z in n:
		for x in n:
			if Game.explored.size() == n * n and Game.explored[z * n + x] > 0:
				lo = lo.min(Vector2(x, z))
				hi = hi.max(Vector2(x + 1, z + 1))
	if lo.x == INF:
		center = Vector2.ZERO
		span = 120.0
		return
	lo = lo * cell - Vector2.ONE * Game.TERRAIN_SIZE * 0.5
	hi = hi * cell - Vector2.ONE * Game.TERRAIN_SIZE * 0.5
	center = (lo + hi) * 0.5
	span = maxf(maxf(hi.x - lo.x, hi.y - lo.y) * 1.15, 120.0)


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var p := Game.player
	if round and p:
		center = Vector2(p.global_position.x, p.global_position.z)
	_mat.set_shader_parameter("center_uv", (center + Vector2.ONE * Game.TERRAIN_SIZE * 0.5) / Game.TERRAIN_SIZE)
	_mat.set_shader_parameter("span_uv", span / Game.TERRAIN_SIZE)
	_marks.queue_redraw()


## World x, z to a spot on this map.
func _to_map(at: Vector3) -> Vector2:
	return (Vector2(at.x, at.z) - center) / span * size + size * 0.5


func _seen(at: Vector3) -> bool:
	var n := Game.MAP_CELLS
	var cell := Game.TERRAIN_SIZE / n
	var x := int((at.x + Game.TERRAIN_SIZE * 0.5) / cell)
	var z := int((at.z + Game.TERRAIN_SIZE * 0.5) / cell)
	return x >= 0 and z >= 0 and x < n and z < n and Game.explored.size() == n * n and Game.explored[z * n + x] > 0


func _on_map(spot: Vector2) -> bool:
	if round:
		return spot.distance_to(size * 0.5) < size.x * 0.46
	return Rect2(Vector2.ZERO, size).grow(-8.0).has_point(spot)


## Hand lettering: a handwriting font from the player's own computer (Windows
## has Ink Free), falling back to the default if there isn't one.
static var _hand_font: Font


static func hand_font() -> Font:
	if _hand_font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Ink Free", "Segoe Print", "Comic Sans MS", "Bradley Hand", "cursive"])
		_hand_font = f
	return _hand_font


## Writes like charcoal: a soft smudge under slightly uneven strokes.
func _scrawl(text: String, at: Vector2, font_size: int, alpha := 1.0, centered := false) -> void:
	var font := hand_font()
	if centered:
		at.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
	_marks.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0.86, 0.79, 0.64, 0.55 * alpha))
	_marks.draw_string(font, at + Vector2(0.8, 0.9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(INK, 0.28 * alpha))
	_marks.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(INK, 0.9 * alpha))


func _line(a: Vector2, b: Vector2, width: float, alpha := 0.8) -> void:
	_marks.draw_line(a, b, Color(INK, alpha), width, true)


func _draw_marks() -> void:
	var s := 1.0 if round else 1.6
	var px := size.x / span  # map pixels per meter
	# The land's own marks first: trees, ripples and peaks where he's been.
	var glyph := clampf(px * 2.2, 3.0, 9.0) * (0.8 if round else 1.0)
	for g in Game.map_symbols:
		var spot := Vector3(g[1].x, 0, g[1].y)
		var at := _to_map(spot)
		if not _on_map(at) or not _seen(spot):
			continue
		var d: float = glyph * g[2]
		match g[0]:
			"tree":
				_line(at + Vector2(0, -d * 1.2), at + Vector2(-d * 0.6, d * 0.3), 1.3, 0.55)
				_line(at + Vector2(0, -d * 1.2), at + Vector2(d * 0.6, d * 0.3), 1.3, 0.55)
				_line(at + Vector2(-d * 0.6, d * 0.3), at + Vector2(d * 0.6, d * 0.3), 1.0, 0.4)
				_line(at + Vector2(0, d * 0.3), at + Vector2(0, d * 0.75), 1.3, 0.55)
			"wave":
				var pts := PackedVector2Array()
				for k in 7:
					var u := k / 6.0
					pts.append(at + Vector2((u - 0.5) * d * 2.2, sin(u * TAU) * d * 0.25))
				_marks.draw_polyline(pts, Color(0.15, 0.22, 0.3, 0.5), 1.2, true)
			"peak":
				_line(at + Vector2(-d * 1.1, d * 0.5), at + Vector2(0, -d * 0.9), 1.5, 0.7)
				_line(at + Vector2(0, -d * 0.9), at + Vector2(d * 1.1, d * 0.5), 1.5, 0.7)
				for k in 3:  # shading down the shadow side
					var t := 0.3 + k * 0.2
					var top := at + Vector2(d * 1.1 * t, -d * 0.9 + d * 1.4 * t)
					_line(top, top + Vector2(-d * 0.25, d * 0.35), 1.0, 0.45)
	# Places he's found, each with a little drawing and its name.
	for place in Game.map_places:
		var pos: Vector3 = place[1]
		if not _seen(pos):
			continue
		var at := _to_map(pos)
		if not _on_map(at):
			continue
		_place_icon(place[2], at, 6.5 * s)
		if not round:
			# Written to the right of the drawing, or to the left near the edge.
			var w := hand_font().get_string_size(place[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
			var right := at.x + 13.0 * s + w < size.x - 12.0
			_scrawl(place[0], at + Vector2(13.0 * s if right else -13.0 * s - w, 6.0), 24)
	for f in get_tree().get_nodes_in_group("campfires"):
		var at := _to_map((f as Node3D).global_position)
		if _on_map(at):
			_marks.draw_circle(at, 3.5 * s, EMBER)
			_marks.draw_arc(at, 3.5 * s, 0.0, TAU, 12, Color(INK, 0.7), 1.0, true)
	for t in get_tree().get_nodes_in_group("shelters"):
		var at := _to_map((t as Node3D).global_position)
		if _on_map(at):
			var d := 4.0 * s
			_marks.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -d), at + Vector2(d, d * 0.7), at + Vector2(-d, d * 0.7)]), INK)
	# Him: an arrow the way he's looking.
	var p := Game.player
	if p:
		var at := _to_map(p.global_position)
		var fwd := Vector2(-sin(p._yaw), -cos(p._yaw))
		var side := Vector2(-fwd.y, fwd.x)
		var d := 7.0 * s
		var arrow := PackedVector2Array([at + fwd * d * 1.3, at - fwd * d * 0.7 + side * d * 0.8, at - fwd * d * 0.3, at - fwd * d * 0.7 - side * d * 0.8])
		_marks.draw_colored_polygon(arrow, Color(0.7, 0.12, 0.08))
		arrow.append(arrow[0])
		_marks.draw_polyline(arrow, Color(INK, 0.8), 1.2, true)
	if round:
		_marks.draw_arc(size * 0.5, size.x * 0.5 - 1.0, 0.0, TAU, 48, Color(0.3, 0.2, 0.12), 3.0, true)
		_scrawl("N", Vector2(size.x * 0.5, 22), 18, 1.0, true)
		return
	# The big map: a title across the top and a compass in the corner.
	_scrawl("The Whispering Woods", Vector2(size.x * 0.5, 54), 40, 1.0, true)
	var w := hand_font().get_string_size("The Whispering Woods", HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	var ul := PackedVector2Array()
	for k in 13:
		var u := k / 12.0
		ul.append(Vector2(size.x * 0.5 + (u - 0.5) * w * 0.9, 66 + sin(u * 9.0) * 1.6))
	_marks.draw_polyline(ul, Color(INK, 0.6), 1.6, true)
	_compass(size - Vector2(70, 80), 34.0)


## A small drawing for each kind of place.
func _place_icon(kind: String, at: Vector2, d: float) -> void:
	match kind:
		"sanctum":
			var diamond := PackedVector2Array([at + Vector2(0, -d), at + Vector2(d, 0), at + Vector2(0, d), at + Vector2(-d, 0)])
			_marks.draw_colored_polygon(diamond, Color(0.3, 0.6, 0.75))
			diamond.append(diamond[0])
			_marks.draw_polyline(diamond, Color(INK, 0.85), 1.4, true)
		"tree":
			_marks.draw_circle(at + Vector2(0, -d * 0.4), d * 0.9, Color(0.2, 0.36, 0.16))
			_marks.draw_arc(at + Vector2(0, -d * 0.4), d * 0.9, 0.0, TAU, 16, Color(INK, 0.85), 1.4, true)
			_line(at + Vector2(0, d * 0.5), at + Vector2(0, d * 1.2), 2.0, 0.9)
		"ruin":
			for x in [-0.6, 0.0, 0.6]:
				var hgt: float = d * (1.3 if x == 0.0 else 0.8)
				var r := Rect2(at + Vector2(x * d - d * 0.18, d * 0.6 - hgt), Vector2(d * 0.36, hgt))
				_marks.draw_rect(r, Color(0.62, 0.6, 0.55))
				_marks.draw_rect(r, Color(INK, 0.8), false, 1.2)
			_line(at + Vector2(-d, d * 0.6), at + Vector2(d, d * 0.6), 1.4)
		"house":
			var wall := Rect2(at + Vector2(-d * 0.75, -d * 0.1), Vector2(d * 1.5, d * 0.9))
			_marks.draw_rect(wall, Color(0.72, 0.58, 0.4))
			_marks.draw_rect(wall, Color(INK, 0.85), false, 1.2)
			_marks.draw_polyline(PackedVector2Array([at + Vector2(-d, -d * 0.1), at + Vector2(0, -d), at + Vector2(d, -d * 0.1)]), Color(INK, 0.9), 1.6, true)
		"hill":
			_line(at + Vector2(-d * 1.2, d * 0.6), at + Vector2(0, -d * 0.6), 1.6, 0.9)
			_line(at + Vector2(0, -d * 0.6), at + Vector2(d * 1.2, d * 0.6), 1.6, 0.9)
			_line(at + Vector2(0, -d * 0.6), at + Vector2(0, -d * 1.6), 1.3, 0.9)
			_marks.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -d * 1.6), at + Vector2(d * 0.7, -d * 1.35), at + Vector2(0, -d * 1.1)]), Color(0.75, 0.2, 0.12))
		"ring":
			_marks.draw_arc(at, d, 0.0, TAU, 20, Color(INK, 0.9), 2.0, true)
			for k in 5:
				var a := TAU * k / 5.0 - PI / 2
				_marks.draw_circle(at + Vector2(cos(a), sin(a)) * d, d * 0.22, Color(0.55, 0.75, 0.95))
		"crow":
			_line(at + Vector2(0, d), at + Vector2(0, -d * 0.6), 1.8, 0.9)
			_line(at + Vector2(0, -d * 0.2), at + Vector2(-d * 0.6, -d * 0.7), 1.3, 0.9)
			_line(at + Vector2(0, -d * 0.4), at + Vector2(d * 0.6, -d * 0.9), 1.3, 0.9)
			_line(at + Vector2(-d * 0.5, -d * 1.4), at + Vector2(-d * 0.1, -d * 1.15), 1.4, 0.9)
			_line(at + Vector2(-d * 0.1, -d * 1.15), at + Vector2(d * 0.35, -d * 1.45), 1.4, 0.9)
		_:
			_marks.draw_circle(at, d * 0.5, INK)


## A charcoal compass rose: a four-point star, N on top.
func _compass(at: Vector2, r: float) -> void:
	for k in 4:
		var a := TAU * k / 4.0 - PI / 2
		var tip := at + Vector2(cos(a), sin(a)) * r
		var l := at + Vector2(cos(a - PI / 4), sin(a - PI / 4)) * r * 0.22
		var rr := at + Vector2(cos(a + PI / 4), sin(a + PI / 4)) * r * 0.22
		_marks.draw_colored_polygon(PackedVector2Array([tip, l, at]), Color(INK, 0.85))
		_marks.draw_colored_polygon(PackedVector2Array([tip, at, rr]), Color(0.84, 0.76, 0.6))
		_marks.draw_polyline(PackedVector2Array([tip, l, at, rr, tip]), Color(INK, 0.85), 1.2, true)
	_marks.draw_arc(at, r * 0.55, 0.0, TAU, 24, Color(INK, 0.6), 1.2, true)
	_scrawl("N", at + Vector2(0, -r - 6), 26, 1.0, true)
