class_name ThoughtBubble
extends Control
## A cloud-like thought bubble that floats above a 3D character, with three
## shrinking dots trailing down to its head. Plays its lines one after another,
## then frees itself (and calls `done`).

var target: Node3D
var height := 2.2
var _panel: PanelContainer
var _label: Label
var _dots: Array[Panel] = []


static func show_for(parent: Control, who: Node3D, lines: Array, seconds_each := 3.6, tint := Color(0.97, 0.96, 0.93), head_height := 2.2, done := Callable()) -> ThoughtBubble:
	var b := ThoughtBubble.new()
	b.target = who
	b.height = head_height
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	b._build(tint)
	b._play(lines, seconds_each, done)
	return b


func _build(tint: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(tint, 0.93)
	style.set_corner_radius_all(40)
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 10
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(0.18, 0.16, 0.2))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(320, 0)
	_panel.add_child(_label)
	add_child(_panel)
	for k in 3:
		var dot := Panel.new()
		var ds := style.duplicate() as StyleBoxFlat
		ds.set_corner_radius_all(30)
		ds.shadow_size = 4
		dot.add_theme_stylebox_override("panel", ds)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dot)
		_dots.append(dot)
	modulate.a = 0.0


func _play(lines: Array, seconds_each: float, done: Callable) -> void:
	var tw := create_tween()
	for line in lines:
		tw.tween_callback(func():
			_label.text = "\"%s\"" % line
			_panel.reset_size())
		tw.tween_property(self, "modulate:a", 1.0, 0.35)
		tw.tween_interval(seconds_each)
		tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func():
		if done.is_valid():
			done.call()
		queue_free())


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not is_instance_valid(target):
		visible = false
		return
	var head := target.global_position + Vector3.UP * height
	var on_screen := not cam.is_position_behind(head) and cam.global_position.distance_to(head) < 40.0
	visible = on_screen
	if not on_screen:
		return
	var anchor := cam.unproject_position(head)
	var size := _panel.size
	var pos := anchor + Vector2(30, -120 - size.y * 0.5)
	var screen := get_viewport().get_visible_rect().size
	pos.x = clampf(pos.x, 16, screen.x - size.x - 16)
	pos.y = clampf(pos.y, 80, screen.y - size.y - 140)
	_panel.position = pos
	var bubble_bottom := pos + Vector2(size.x * 0.25, size.y)
	for k in 3:
		var d := 18.0 - k * 5.0
		var c := bubble_bottom.lerp(anchor, (k + 1) / 4.0)
		_dots[k].position = c - Vector2(d, d) * 0.5
		_dots[k].size = Vector2(d, d)
