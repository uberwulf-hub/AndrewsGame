class_name TalkMenu
extends PanelContainer
## Talking to the Fox or the Otter (E beside them): a few questions to pick
## from. Picking one closes the menu and the pet answers in a thought bubble.
## The campfire uses the same menu for its choices. Pauses the game while
## open; Esc or E closes it without picking.

const CREAM := Color(0.97, 0.92, 0.8)
const GOLD := Color(1.0, 0.84, 0.45)

var _box: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.07, 0.05, 0.92)
	style.border_color = Color(0.55, 0.4, 0.25)
	style.set_border_width_all(3)
	style.set_corner_radius_all(14)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	add_theme_stylebox_override("panel", style)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	add_child(_box)
	visible = false


func open(companion: Companion) -> void:
	open_menu("The Fox" if companion.who == "fox" else "The Otter", companion.talk_options())


## `options` are [label, Callable] pairs.
func open_menu(heading: String, options: Array) -> void:
	for c in _box.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = heading
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", GOLD)
	_box.add_child(title)
	var first: Button = null
	for option in options:
		var b := Button.new()
		b.text = option[0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(440, 40)
		b.add_theme_font_size_override("font_size", 19)
		b.add_theme_color_override("font_color", CREAM)
		var answer: Callable = option[1]
		b.pressed.connect(func():
			close()
			answer.call())
		_box.add_child(b)
		if first == null:
			first = b
	var hint := Label.new()
	hint.text = "Esc  never mind"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.7, 0.68, 0.62))
	_box.add_child(hint)
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if first:
		first.grab_focus.call_deferred()


func close() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("pause") or event.is_action_pressed("interact")):
		close()
		get_viewport().set_input_as_handled()
