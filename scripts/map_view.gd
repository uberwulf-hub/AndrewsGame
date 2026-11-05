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


func _draw_marks() -> void:
	var s := 1.0 if round else 1.6
	# Where they woke: the great tree, home for now.
	if Game.story_start and _seen(Game.wake_point):
		var home := _to_map(Game.wake_point)
		if _on_map(home):
			_marks.draw_circle(home, 6.0 * s, Color(0.2, 0.36, 0.16))
			_marks.draw_arc(home, 6.0 * s, 0.0, TAU, 16, INK, 1.5, true)
			if not round:
				_marks.draw_string(get_theme_default_font(), home + Vector2(10, 5), "The great tree", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)
	# The Sanctum, once he's been near it.
	if _seen(Vector3.ZERO):
		var sanctum := _to_map(Vector3.ZERO)
		if _on_map(sanctum):
			var d := 7.0 * s
			_marks.draw_colored_polygon(PackedVector2Array([sanctum + Vector2(0, -d), sanctum + Vector2(d, 0), sanctum + Vector2(0, d), sanctum + Vector2(-d, 0)]), Color(0.3, 0.6, 0.75))
			if not round:
				_marks.draw_string(get_theme_default_font(), sanctum + Vector2(12, 5), "The Sanctum", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)
	for f in get_tree().get_nodes_in_group("campfires"):
		var at := _to_map((f as Node3D).global_position)
		if _on_map(at):
			_marks.draw_circle(at, 3.5 * s, EMBER)
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
		_marks.draw_colored_polygon(PackedVector2Array([at + fwd * d * 1.3, at - fwd * d * 0.7 + side * d * 0.8, at - fwd * d * 0.3, at - fwd * d * 0.7 - side * d * 0.8]), Color(0.7, 0.12, 0.08))
	if round:
		_marks.draw_arc(size * 0.5, size.x * 0.5 - 1.0, 0.0, TAU, 48, Color(0.3, 0.2, 0.12), 3.0, true)
		_marks.draw_string(get_theme_default_font(), Vector2(size.x * 0.5 - 5, 16), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)
