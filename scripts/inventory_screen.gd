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
## Where the open tab draws (inside a scroll box, so the panel keeps its size).
var _body: VBoxContainer
## Which sections are folded open, and the one thing whose details are showing.
var _open := {}
var _picked := ""

## Know-how, grouped like a crafting book: things for camp, for the Sanctum
## home, and things you make and carry. Anything new goes under "Other".
const KNOW_HOW_SECTIONS := {
	"Camp": ["campfire", "cooking", "lean_to", "torch_post", "rain_catcher", "raft"],
	"Home": ["hearth", "bedroll", "chest", "rain_cover", "dream_catcher"],
	"Carried": ["map", "bone_whistle"],
}
const BODY_HEIGHT := 480.0


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
		if Game.rested > 0.0:
			_text(_left, "Well rested: skills grow faster (%d min left)" % ceili(Game.rested / 60.0), Color(1.0, 0.9, 0.6))
	_heading(_left, "Skills", 22)
	for skill in Game.SKILLS + Game.REMEMBERED_SKILLS.filter(func(s): return Game.skills.has(s)):
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
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(440, BODY_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_right.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	scroll.add_child(_body)
	match _tab:
		"Know-how":
			_know_how()
		"Journal":
			_journal()
		_:
			_backpack()
	_text(_right, "Tab  close", Color(0.7, 0.68, 0.62))


func _backpack() -> void:
	if Game.inventory.is_empty() and Game.backpack.is_empty():
		_text(_body, "Nothing gathered yet. Press E near sticks, stones and berries.", Color(0.7, 0.68, 0.62))
	if _section("Carried", str(Game.backpack.size())):
		for item in Game.backpack:
			if item == "Canteen":
				_row(_body, "    Canteen  (%d sips)" % Game.canteen_sips, "Drink", Game.canteen_sips > 0, func():
					player.drink_canteen()
					refresh())
			else:
				_text(_body, "    " + item)
	var food: Array = Game.inventory.keys().filter(func(i): return Game.FOODS.has(i))
	var stuff: Array = Game.inventory.keys().filter(func(i): return not Game.FOODS.has(i))
	if not food.is_empty() and _section("Food", str(food.size())):
		for item in food:
			_row(_body, "    %s  x%d" % [item, Game.inventory[item]], "Eat", true, func():
				player.eat(item)
				refresh())
	if not stuff.is_empty() and _section("Materials", str(stuff.size())):
		for item in stuff:
			_text(_body, "    %s  x%d" % [item, Game.inventory[item]])


## A fold-open section header (a click opens or closes it). True when open.
## `note` goes after the name, and `ready` (if any) is said in gold.
func _section(name: String, note := "", ready := 0) -> bool:
	var open: bool = _open.get(_tab + "/" + name, false)
	var b := Button.new()
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = ("▾  " if open else "▸  ") + name + ("   (%s)" % note if note != "" else "") + ("   ★ %d ready" % ready if ready > 0 else "")
	b.add_theme_font_size_override("font_size", 21)
	b.add_theme_color_override("font_color", GOLD if ready > 0 else CREAM)
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.75))
	b.pressed.connect(func():
		_open[_tab + "/" + name] = not open
		refresh())
	_body.add_child(b)
	return open


## The dream journal: every active quest in full, who suggested it, and ideas
## that are waiting until there's room on the tracker.
func _journal() -> void:
	if Game.quests.is_empty():
		_text(_body, "No quests right now. Explore, or listen to the Fox and the Otter.", Color(0.7, 0.68, 0.62))
	for q in Game.quests:
		var by: String = ("   (%s's idea)" % q.giver) if q.giver != "" else ""
		_text(_body, ("Main: " if q.main else "Side: ") + q.title + by, GOLD if q.main else Color(0.75, 0.85, 1.0))
		for step in q.steps:
			_text(_body, ("    ✓  " if step.done else "    •  ") + step.text, Color(0.6, 0.58, 0.54) if step.done else CREAM)
	if not Game.ideas.is_empty():
		_text(_body, "\nIdeas for later (one main quest and %d side quests at a time):" % Game.MAX_SIDE, Color(0.78, 0.75, 0.68))
		for idea in Game.ideas:
			_text(_body, "    ◇  " + idea, Color(0.78, 0.75, 0.68))


## What the hero has figured out how to make, in fold-open sections. Each
## line shows what it needs and how much you have; click a name to read about
## it. Undiscovered things stay hidden.
func _know_how() -> void:
	if Game.known.is_empty():
		_text(_body, "You haven't figured anything out yet.\nLook around. The world is full of ideas.", Color(0.7, 0.68, 0.62))
		return
	var sections := KNOW_HOW_SECTIONS.duplicate(true)
	sections["Other"] = Game.known.filter(func(id): return not KNOW_HOW_SECTIONS.values().any(func(l): return l.has(id)))
	for name in sections:
		var ids: Array = sections[name].filter(func(id): return Game.known.has(id))
		if ids.is_empty():
			continue
		var ready := ids.filter(func(id): return _can_make(id)).size()
		if not _section(name, str(ids.size()), ready):
			continue
		for id in ids:
			_know_how_entry(id)
	var unknown := Game.KNOW_HOW.size() - Game.known.size()
	if unknown > 0:
		_text(_body, "\n    ...and more you haven't discovered yet.", Color(0.6, 0.58, 0.54))


func _can_make(id: String) -> bool:
	var entry: Dictionary = Game.KNOW_HOW[id]
	if entry.get("at_fire", false) or (entry.get("carried", false) and Game.backpack.has(entry.name)):
		return false
	for item in entry.needs:
		if Game.inventory.get(item, 0) < entry.needs[item]:
			return false
	return true


func _know_how_entry(id: String) -> void:
	var entry: Dictionary = Game.KNOW_HOW[id]
	var row := HBoxContainer.new()
	var name := Button.new()
	name.flat = true
	name.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.add_theme_font_size_override("font_size", 18)
	name.add_theme_color_override("font_color", CREAM)
	name.pressed.connect(func():
		_picked = "" if _picked == id else id
		refresh())
	row.add_child(name)
	_body.add_child(row)
	if entry.get("at_fire", false):
		name.text = "      " + entry.name + "   (at a campfire)"
	else:
		var craftable := _can_make(id)
		var b := Button.new()
		b.custom_minimum_size = Vector2(90, 32)
		if entry.get("carried", false):
			var made := Game.backpack.has(entry.name)
			name.text = "      " + entry.name + ("   (in your backpack)" if made else "")
			b.text = "Make"
			b.pressed.connect(func():
				player.make(id)
				close())
		else:
			name.text = "      " + entry.name
			b.text = "Build"
			b.pressed.connect(func():
				if player.begin_placing(id):
					close())
		b.disabled = not craftable
		row.add_child(b)
		var parts: Array[String] = []
		for item in entry.needs:
			parts.append("%s %d/%d" % [item, mini(Game.inventory.get(item, 0), entry.needs[item]), entry.needs[item]])
		var l := _text(_body, "          " + "   ".join(parts), GOLD if craftable else Color(0.62, 0.6, 0.56))
		l.add_theme_font_size_override("font_size", 15)
	if _picked == id:
		var indent := MarginContainer.new()
		indent.add_theme_constant_override("margin_left", 40)
		indent.add_theme_constant_override("margin_right", 12)
		_body.add_child(indent)
		var about := Label.new()
		about.text = entry.about
		about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		about.add_theme_font_size_override("font_size", 16)
		about.add_theme_color_override("font_color", Color(0.78, 0.75, 0.68))
		indent.add_child(about)


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
