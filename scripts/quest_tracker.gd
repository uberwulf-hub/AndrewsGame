class_name QuestTracker
extends VBoxContainer
## The quest list in the top-right corner: the main quest with its steps, then
## at most Game.MAX_SIDE side quests as single lines. Rebuilds whenever quests
## change and fades in so new quests are noticed without a popup.

const GOLD := Color(1.0, 0.84, 0.45)
const CREAM := Color(0.95, 0.92, 0.85)
const DIM := Color(0.68, 0.66, 0.6)


func _ready() -> void:
	add_theme_constant_override("separation", 2)
	alignment = BoxContainer.ALIGNMENT_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Game.quests_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	for q in Game.quests:
		if q.main:
			_line(q.title, 21, GOLD)
			for step in q.steps:
				_line(("✓  " if step.done else "•  ") + step.text, 17, DIM if step.done else CREAM)
	var sides := Game.quests.filter(func(q): return not q.main)
	if not sides.is_empty():
		_line("", 8, DIM)
		for q in sides:
			var next := ""
			for step in q.steps:
				if not step.done:
					next = "  -  " + step.text
					break
			_line("◇  " + q.title + next, 16, Color(0.75, 0.85, 1.0))
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.8)


func _line(text: String, size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 2)
	add_child(l)
