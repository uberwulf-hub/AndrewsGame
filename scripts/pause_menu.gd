class_name PauseMenu
extends CanvasLayer
## Esc pauses the game: Resume, Options (volume, fullscreen), Main Menu, Quit.
## It also pauses by itself after a few minutes without any input.

const TITLE_SCENE := "res://scenes/title.tscn"
const CREAM := Color(0.97, 0.9, 0.74)
const WOOD := Color(0.42, 0.26, 0.15)

var _dim: ColorRect
var _menu: VBoxContainer
var _options: VBoxContainer
var _help: VBoxContainer
var _save_button: Button
var _saved_label: Label


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.03, 0.06, 0.65)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.add_child(center)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	center.add_child(stack)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", CREAM)
	stack.add_child(title)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 12)
	stack.add_child(_menu)
	_menu.add_child(_button("Resume", close))
	_save_button = _button("Save Game", _save)
	_menu.add_child(_save_button)
	_menu.add_child(_button("Options", func():
		_menu.visible = false
		_options.visible = true))
	_menu.add_child(_button("Help", func():
		_menu.visible = false
		_help.visible = true))
	_menu.add_child(_button("Main Menu", func():
		get_tree().paused = false
		get_tree().change_scene_to_file(TITLE_SCENE)))
	_menu.add_child(_button("Quit", func(): get_tree().quit()))
	_saved_label = Label.new()
	_saved_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_saved_label.add_theme_font_size_override("font_size", 20)
	_saved_label.add_theme_color_override("font_color", CREAM)
	_menu.add_child(_saved_label)
	_options = _build_options()
	stack.add_child(_options)
	_options.visible = false
	_help = VBoxContainer.new()
	_help.add_theme_constant_override("separation", 16)
	_help.add_child(Hud.controls_grid(CREAM))
	_help.add_child(_button("Back", func():
		_help.visible = false
		_menu.visible = true))
	stack.add_child(_help)
	_help.visible = false
	_dim.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if Game.player and Game.player.is_placing():
			Game.player.cancel_placing()
		elif _dim.visible:
			close()
		elif not get_tree().paused:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	_dim.visible = true
	_menu.visible = true
	var world := get_parent()
	_save_button.visible = Game.story_start
	_save_button.disabled = not (world.has_method("can_save") and world.can_save())
	_saved_label.text = "" if not _save_button.disabled or not Game.story_start else "(You can save once you're on dry land and free to move.)"
	_options.visible = false
	_help.visible = false
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	_dim.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_options() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var vol := Label.new()
	vol.text = "Volume  %d%%" % roundi(Audio.master_volume * 100.0)
	vol.add_theme_font_size_override("font_size", 24)
	vol.add_theme_color_override("font_color", CREAM)
	box.add_child(vol)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Audio.master_volume
	slider.custom_minimum_size = Vector2(320, 28)
	slider.value_changed.connect(func(v: float):
		Audio.set_master_volume(v)
		vol.text = "Volume  %d%%" % roundi(v * 100.0))
	box.add_child(slider)
	var full := CheckButton.new()
	full.text = "Fullscreen"
	full.add_theme_font_size_override("font_size", 22)
	full.button_pressed = Game.is_fullscreen()
	full.toggled.connect(func(on: bool):
		Game.set_fullscreen(on))
	box.add_child(full)
	box.add_child(_button("Back", func():
		_options.visible = false
		_menu.visible = true))
	return box


func _button(label: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(320, 60)
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", CREAM)
	for state in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = WOOD.lightened(0.15) if state == "hover" else (WOOD.darkened(0.15) if state == "pressed" else WOOD)
		s.border_color = Color(0.95, 0.85, 0.55) if state == "focus" else Color(0.6, 0.6, 0.58)
		s.set_border_width_all(4)
		s.set_corner_radius_all(14)
		b.add_theme_stylebox_override(state, s)
	b.pressed.connect(on_press)
	return b


func _save() -> void:
	var world := get_parent()
	if world.has_method("save_game") and world.save_game():
		_saved_label.text = "Saved!"
		Audio.play("ui_notify", null, -8.0, 1.1)
	else:
		_saved_label.text = "Couldn't save just now."


# --- Away from the keyboard ----------------------------------------------------
# No input for a few minutes and the game pauses itself, so nobody starves
# (or freezes) while you're off making a sandwich.

const AFK_SECONDS := 180.0
var _idle := 0.0


func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion \
			or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_idle = 0.0


func _process(delta: float) -> void:
	if get_tree().paused or Game.screenshot_mode:
		_idle = 0.0
		return
	_idle += delta
	if _idle > AFK_SECONDS:
		_idle = 0.0
		open()
		_saved_label.text = "Paused while you were away."
