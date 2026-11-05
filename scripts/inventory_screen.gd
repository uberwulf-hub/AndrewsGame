class_name InventoryScreen
extends PanelContainer
## The backpack screen (Tab): character level and XP, needs, skills, what's in
## the backpack (with Eat / Drink), know-how and the journal. Pauses the game while open.

const CREAM := Color(0.97, 0.92, 0.8)
const GOLD := Color(1.0, 0.84, 0.45)


var player: Player
var _tab := "Backpack"
var _left: VBoxContainer
var _right: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.07, 0.05, 0.94)
	style.border_color = Color(0.55, 0.4, 0.25)
	style.set_border_width_all(4)
	style.set_corner_radius_all(16)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	add_theme_stylebox_override("panel", style)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 40)
	add_child(columns)
	_left = VBoxContainer.new()
	_left.custom_minimum_size = Vector2(380, 0)
	_left.add_theme_constant_override("separation", 8)
	columns.add_child(_left)
	_right = VBoxContainer.new()
	_right.custom_minimum_size = Vector2(400, 0)
	_right.add_theme_constant_override("separation", 8)
	columns.add_child(_right)
	visible = false
	Game.inventory_changed.connect(func():
		if visible:
			refresh())


func open() -> void:
	visible = true
	refresh()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func refresh() -> void:
	for box in [_left, _right]:
		for c in box.get_children():
			c.queue_free()
	var p := player
	_heading(_left, "Wayfinder", 30)
	_text(_left, "Level %d   (%d / %d XP)" % [p.level, p.xp, p.xp_to_next()])
	_bar(_left, "Health", p.health / p.max_health, Color(0.85, 0.25, 0.25), "%d / %d" % [ceili(p.health), roundi(p.max_health)])
	if Game.story_start:
		_bar(_left, "Warmth", Game.warmth / 100.0, Color(1.0, 0.6, 0.25))
		_bar(_left, "Food", Game.hunger / 100.0, Color(0.6, 0.85, 0.35))
		_bar(_left, "Water", Game.thirst / 100.0, Color(0.4, 0.7, 1.0))
	_heading(_left, "Skills", 22)
	for skill in Game.SKILLS:
		_skill_bar(skill, skill, Color(0.75, 0.6, 1.0))
	if Game.story_start:
		_heading(_left, "Fox & Otter", 22)
		for knack in Game.PET_KNACKS.values():
			_skill_bar(knack, knack.get_slice(": ", 1), Color(1.0, 0.65, 0.35))
	if p.weapon:
		_heading(_left, "Dream tool", 22)
		_text(_left, "%s\nLv %d %s %s" % [p.weapon.display_name, p.weapon.level, WeaponData.RARITY_NAMES[p.weapon.rarity], p.weapon.kind], p.weapon.color)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	_right.add_child(tabs)
	for t in ["Backpack", "Know-how", "Journal"]:
		var b := Button.new()
		b.text = t
		b.toggle_mode = true
		b.button_pressed = t == _tab
		b.custom_minimum_size = Vector2(124, 40)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(func():
			_tab = t
			refresh())
		tabs.add_child(b)
	match _tab:
		"Know-how":
			_know_how()
		"Journal":
			_journal()
		_:
			_backpack()
	_text(_right, "\nTab  close", Color(0.7, 0.68, 0.62))


func _backpack() -> void:
	for item in Game.backpack:
		if item == "Canteen":
			_row(_right, "Canteen  (%d sips)" % Game.canteen_sips, "Drink", Game.canteen_sips > 0, func():
				player.drink_canteen()
				refresh())
		else:
			_text(_right, "•  " + item)
	if Game.inventory.is_empty():
		_text(_right, "Nothing gathered yet. Press E near sticks, stones and berries.", Color(0.7, 0.68, 0.62))
	for item in Game.inventory:
		var count: int = Game.inventory[item]
		if Game.FOODS.has(item):
			_row(_right, "%s  x%d" % [item, count], "Eat", true, func():
				player.eat(item)
				refresh())
		else:
			_text(_right, "%s  x%d" % [item, count])


## The dream journal: every active quest in full, who suggested it, and ideas
## that are waiting until there's room on the tracker.
func _journal() -> void:
	if Game.quests.is_empty():
		_text(_right, "No quests right now. Explore, or listen to the Fox and the Otter.", Color(0.7, 0.68, 0.62))
	for q in Game.quests:
		var by: String = ("   (%s's idea)" % q.giver) if q.giver != "" else ""
		_text(_right, ("Main: " if q.main else "Side: ") + q.title + by, GOLD if q.main else Color(0.75, 0.85, 1.0))
		for step in q.steps:
			_text(_right, ("    ✓  " if step.done else "    •  ") + step.text, Color(0.6, 0.58, 0.54) if step.done else CREAM)
	if not Game.ideas.is_empty():
		_text(_right, "\nIdeas for later (one main quest and %d side quests at a time):" % Game.MAX_SIDE, Color(0.78, 0.75, 0.68))
		for idea in Game.ideas:
			_text(_right, "    ◇  " + idea, Color(0.78, 0.75, 0.68))


## What the hero has figured out how to make: what each needs, how much of
## it you have, and a Build button. Undiscovered things stay hidden.
func _know_how() -> void:
	if Game.known.is_empty():
		_text(_right, "You haven't figured anything out yet.\nLook around. The world is full of ideas.", Color(0.7, 0.68, 0.62))
	for id in Game.known:
		var entry: Dictionary = Game.KNOW_HOW[id]
		if entry.get("at_fire", false):
			_text(_right, entry.name + "   (at a campfire)", CREAM)
			_text(_right, "    " + entry.about, Color(0.78, 0.75, 0.68))
			continue
		var needs: Dictionary = entry.needs
		var craftable := true
		var parts: Array[String] = []
		for item in needs:
			var have: int = Game.inventory.get(item, 0)
			craftable = craftable and have >= needs[item]
			parts.append("%s %d/%d" % [item, mini(have, needs[item]), needs[item]])
		if entry.get("carried", false):
			var made := Game.backpack.has(entry.name)
			_row(_right, entry.name + ("   (in your backpack)" if made else ""), "Make", craftable and not made, func():
				player.make(id)
				close())
		else:
			_row(_right, entry.name, "Build", craftable, func():
				if player.begin_placing(id):
					close())
		_text(_right, "    " + "   ".join(parts), GOLD if craftable else Color(0.7, 0.68, 0.62))
		_text(_right, "    " + entry.about, Color(0.78, 0.75, 0.68))
	var unknown := Game.KNOW_HOW.size() - Game.known.size()
	if unknown > 0 and not Game.known.is_empty():
		_text(_right, "\n    ...and more you haven't discovered yet.", Color(0.6, 0.58, 0.54))


func _skill_bar(skill: String, label: String, color: Color) -> void:
	var xp: float = Game.skills.get(skill, 0.0)
	var lvl := Game.xp_to_level(xp)
	var lo := Game.level_floor_xp(lvl)
	var hi := Game.level_floor_xp(lvl + 1)
	_bar(_left, "%s  %d" % [label, lvl], (xp - lo) / maxf(hi - lo, 0.001), color)


func _heading(box: VBoxContainer, s: String, size: int) -> void:
	var l := _text(box, s, GOLD)
	l.add_theme_font_size_override("font_size", size)


func _text(box: VBoxContainer, s: String, color := CREAM) -> Label:
	var l := Label.new()
	l.text = s
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", color)
	box.add_child(l)
	return l


func _bar(box: VBoxContainer, label: String, value: float, color: Color, right := "") -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(150, 0)
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", CREAM)
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(value, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(190, 16)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	row.add_child(bar)
	if right != "":
		var r := Label.new()
		r.text = "  " + right
		r.add_theme_font_size_override("font_size", 15)
		r.add_theme_color_override("font_color", CREAM)
		row.add_child(r)
	box.add_child(row)


func _row(box: VBoxContainer, label: String, action: String, enabled: bool, on_press: Callable) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", CREAM if enabled else Color(0.6, 0.58, 0.54))
	row.add_child(l)
	var b := Button.new()
	b.text = action
	b.disabled = not enabled
	b.custom_minimum_size = Vector2(90, 34)
	b.pressed.connect(on_press)
	row.add_child(b)
	box.add_child(row)
