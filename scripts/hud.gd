class_name Hud
extends CanvasLayer
## On-screen interface. Polls the player every frame for bars and counters and
## listens to signals for one-off events (hits, level ups, death, notifications).

## Controls, listed on the Help screen (pause menu and title screen).
const CONTROLS := [
	["WASD", "Move"], ["Shift (hold)", "Run"], ["Space", "Jump"], ["Mouse", "Look around"],
	["Mouse wheel", "Zoom (all the way in for first person)"],
	["Left click", "Punch (fire when you have a weapon)"], ["Right click", "Aim (with a weapon)"],
	["R", "Reload"], ["Q", "Rune Nova (with a weapon)"],
	["E", "Pick up / drink"], ["Tab", "Character, backpack, know-how & journal"],
	["Swimming", "Look to steer, Space to rise, C to dive"],
	["Esc", "Pause"], ["F11", "Fullscreen"], ["- / =", "Volume"],
]


## The controls as a two-column table, for the Help screens.
static func controls_grid(color: Color, font_size := 20, gap := 6) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", gap)
	for row in CONTROLS:
		for k in 2:
			var l := Label.new()
			l.text = row[k]
			l.add_theme_font_size_override("font_size", font_size)
			l.add_theme_color_override("font_color", Color(1.0, 0.84, 0.45) if k == 0 else color)
			grid.add_child(l)
	return grid

class Crosshair extends Control:
	var spread := 0.0
	var hit_time := 0.0
	var hit_crit := false

	func _draw() -> void:
		var c := size * 0.5
		var gap := 6.0 + spread
		var col := Color(1, 1, 1, 0.9)
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(c + d * gap, c + d * (gap + 8.0), col, 2.0, true)
		draw_circle(c, 1.5, col)
		if hit_time > 0.0:
			var hc := Color(1.0, 0.85, 0.2) if hit_crit else Color.WHITE
			hc.a = clampf(hit_time / 0.15, 0.0, 1.0)
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_line(c + d * 6.0, c + d * 13.0, hc, 2.5, true)

var _player: Player
var _root: Control
var _crosshair: Crosshair
var _health_bar: ProgressBar
var _health_label: Label
var _xp_bar: ProgressBar
var _level_label: Label
var _weapon_name: Label
var _ammo_label: Label
var _weapon_info: Label
var _nova_label: Label
var _dash_label: Label
var _ready_style: StyleBoxFlat
var _cooldown_style: StyleBoxFlat
var _loot_panel: PanelContainer
var _loot_style: StyleBoxFlat
var _loot_text: RichTextLabel
var _shown_loot: LootDrop
var _shown_weapon: WeaponData
var _notice: Label
var _quests: QuestTracker
var _notice_time := 0.0
var _danger_label: Label
var _inventory: InventoryScreen
var _talk: TalkMenu
var _needs: Array[ProgressBar] = []
var _prompt: Label
var _paused_label: Label
var _death_overlay: ColorRect
var _damage_flash: ColorRect
var _underwater_overlay: ColorRect


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_underwater_overlay = _full_rect(Color.WHITE)
	var overlay_mat := ShaderMaterial.new()
	overlay_mat.shader = load("res://shaders/underwater.gdshader")
	_underwater_overlay.material = overlay_mat
	_underwater_overlay.visible = false
	_damage_flash = _full_rect(Color(0.8, 0.05, 0.05, 0.0))
	_crosshair = Crosshair.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_crosshair)

	_level_label = _place(_label("", 22, Color(1, 0.85, 0.4)), Vector2(0, 1), Vector2(30, -124), Vector2(380, 30))
	_health_bar = _bar(Color(0.85, 0.2, 0.2), Vector2(0, 1), Vector2(30, -88), Vector2(380, 24))
	_health_label = _place(_label("", 16, Color.WHITE), Vector2(0, 1), Vector2(40, -87), Vector2(360, 24))
	_xp_bar = _bar(Color(0.95, 0.75, 0.25), Vector2(0, 1), Vector2(30, -56), Vector2(380, 8))

	_weapon_name = _place(_label("", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT), Vector2(1, 1), Vector2(-530, -140), Vector2(500, 30))
	_ammo_label = _place(_label("", 40, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT), Vector2(1, 1), Vector2(-530, -110), Vector2(500, 50))
	_weapon_info = _place(_label("", 15, Color(0.8, 0.8, 0.8), HORIZONTAL_ALIGNMENT_RIGHT), Vector2(1, 1), Vector2(-530, -56), Vector2(500, 24))

	_ready_style = _style(Color(0.1, 0.45, 0.55, 0.75), Color(0.4, 0.9, 1.0))
	_cooldown_style = _style(Color(0.05, 0.05, 0.07, 0.75), Color(0.3, 0.3, 0.35))
	_nova_label = _place(_label("", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER), Vector2(0.5, 1), Vector2(-135, -84), Vector2(125, 50))
	_dash_label = _place(_label("", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER), Vector2(0.5, 1), Vector2(10, -84), Vector2(125, 50))
	for l in [_nova_label, _dash_label]:
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_loot_style = _style(Color(0.04, 0.05, 0.07, 0.88), Color.WHITE)
	_loot_panel = PanelContainer.new()
	_loot_panel.add_theme_stylebox_override("panel", _loot_style)
	_loot_text = _rich_text(340)
	_loot_panel.add_child(_loot_text)
	_place(_loot_panel, Vector2(0.5, 0.5), Vector2(70, -60), Vector2(340, 0))
	_loot_panel.visible = false

	process_mode = Node.PROCESS_MODE_ALWAYS  # Tab must work while the game is paused
	_inventory = InventoryScreen.new()
	_place(_inventory, Vector2(0.5, 0.5), Vector2(-460, -300), Vector2(920, 0))
	_talk = TalkMenu.new()
	_place(_talk, Vector2(0.5, 1), Vector2(-250, -380), Vector2(500, 0))

	# Needs: three small bars above the level line (story mode only).
	var needs_info := [["Warmth", Color(1.0, 0.6, 0.25)], ["Food", Color(0.6, 0.85, 0.35)], ["Water", Color(0.4, 0.7, 1.0)]]
	for i in needs_info.size():
		var row := HBoxContainer.new()
		var l := _label(needs_info[i][0], 14, Color(0.92, 0.92, 0.92))
		l.custom_minimum_size = Vector2(62, 0)
		row.add_child(l)
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(150, 10)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = needs_info[i][1]
		fill.set_corner_radius_all(4)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.5)
		bg.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("fill", fill)
		bar.add_theme_stylebox_override("background", bg)
		row.add_child(bar)
		_place(row, Vector2(0, 1), Vector2(30, -214 + i * 22), Vector2(230, 20))
		_needs.append(bar)
	_prompt = _place(_label("", 22, Color(1.0, 0.95, 0.8), HORIZONTAL_ALIGNMENT_CENTER), Vector2(0.5, 1), Vector2(-300, -170), Vector2(600, 34))

	_notice = _place(_label("", 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER), Vector2(0.5, 0), Vector2(-560, 110), Vector2(1120, 40))
	_danger_label = _place(_label("", 18, Color(1, 0.8, 0.6), HORIZONTAL_ALIGNMENT_RIGHT), Vector2(1, 0), Vector2(-530, 20), Vector2(510, 30))
	_quests = _place(QuestTracker.new(), Vector2(1, 0), Vector2(-620, 56), Vector2(600, 200)) as QuestTracker
	_paused_label = _place(_label("Click to resume", 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER), Vector2(0.5, 0.5), Vector2(-300, -120), Vector2(600, 40))

	_death_overlay = _full_rect(Color(0.25, 0.0, 0.0, 0.5))
	var death_label := _label("You fell.\nThe Sanctum calls you back...", 40, Color(1, 0.85, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	death_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_overlay.add_child(death_label)
	_death_overlay.visible = false


func bind(player: Player) -> void:
	_player = player
	_inventory.player = player
	if Game.shot_inventory:
		get_tree().create_timer(1.0).timeout.connect(func():
			Game.add_item("Sticks", 6)
			Game.add_item("Stones", 2)
			Game.add_item("Berries", 4)
			Game.practice("Foraging", 12.0)
			Game.learn("campfire")
			_inventory._tab = Game.shot_tab
			_inventory.open())
	for n in _needs:
		n.get_parent().visible = Game.story_start
	player.hit_confirmed.connect(_on_hit)
	player.says.connect(func(lines: Array): think(lines, 3.0))
	player.talk_requested.connect(_talk.open)
	player.damaged.connect(func(_amount: float): _damage_flash.color.a = 0.18)
	player.leveled_up.connect(func(new_level: int): notify("Level %d! Health and damage increased" % new_level, Color(1, 0.85, 0.3)))
	player.died.connect(func(): _death_overlay.visible = true)
	player.respawned.connect(func(): _death_overlay.visible = false)
	Game.notified.connect(notify)


## A thought bubble over any character (the hero, the Fox, the Otter).
func think(lines: Array, seconds_each := 3.6, done := Callable(), who: Node3D = null, tint := Color(0.97, 0.96, 0.93), head_height := 2.2) -> ThoughtBubble:
	return ThoughtBubble.show_for(_root, who if who else _player, lines, seconds_each, tint, head_height, done)


## Full-screen color that fades away (used for waking from the dream's white).
func fade_in(from: Color, duration: float) -> void:
	var cover := _full_rect(from)
	create_tween().tween_property(cover, "color:a", 0.0, duration).set_ease(Tween.EASE_IN)




func notify(text: String, color := Color.WHITE) -> void:
	_notice.text = text
	_notice.add_theme_color_override("font_color", color)
	_notice_time = 3.5


func _process(delta: float) -> void:
	if _player == null:
		return
	var p := _player
	var w := p.weapon
	_underwater_overlay.visible = Game.underwater
	_health_bar.value = p.health / p.max_health
	_health_label.text = "%d / %d" % [ceili(p.health), roundi(p.max_health)]
	_xp_bar.value = float(p.xp) / p.xp_to_next()
	_level_label.text = "Level %d" % p.level

	if w != _shown_weapon or (w == null and _weapon_name.text != "Unarmed"):
		_shown_weapon = w
		_shown_loot = null
		if w == null:
			_weapon_name.text = "Unarmed"
			_weapon_name.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
			_weapon_info.text = "Pocketknife, flint, canteen"
		else:
			_weapon_name.text = w.display_name
			_weapon_name.add_theme_color_override("font_color", w.color)
			var info := "Lv %d %s %s" % [w.level, WeaponData.RARITY_NAMES[w.rarity], w.archetype]
			if w.element != WeaponData.Element.KINETIC:
				info += "  |  " + WeaponData.ELEMENT_NAMES[w.element]
			_weapon_info.text = info
	if w == null:
		_ammo_label.text = ""
	else:
		_ammo_label.text = "RELOADING" if p.is_reloading() else "%d / %d" % [p.ammo, w.mag_size]
	_nova_label.visible = w != null
	_set_ability(_nova_label, "Q  Nova", p.nova_cooldown)
	_dash_label.visible = not Game.story_start  # Shift-to-run covers it in the story
	_set_ability(_dash_label, "F  Dash", p.dash_cooldown)

	_crosshair.visible = w != null and not p.frozen
	_crosshair.spread = (w.spread if w else 0.02) * (0.35 if p.aiming else 1.0) * 600.0
	_crosshair.hit_time = maxf(0.0, _crosshair.hit_time - delta)
	_crosshair.queue_redraw()
	_update_loot_card()

	_notice_time -= delta
	_notice.modulate.a = clampf(_notice_time, 0.0, 1.0)
	_damage_flash.color.a = maxf(0.0, _damage_flash.color.a - delta * 0.8)
	var biome: String = Game.BIOME_NAMES.get(Game.biome_at(p.global_position), "")
	_danger_label.text = biome if not Game.ENEMIES_ENABLED else "%s  |  Danger Lv %d" % [biome, Game.enemy_level_at(p.global_position)]
	_paused_label.visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not Game.screenshot_mode and p.alive and not get_tree().paused

	for i in _needs.size():
		var value: float = [Game.warmth, Game.hunger, Game.thirst][i]
		_needs[i].value = value / 100.0
		_needs[i].modulate = Color(1, 1, 1) if value > 25.0 else Color(1, 1, 1, 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() * 0.006)))
	var g := p.focused_gatherable
	if p.is_placing():
		_prompt.text = "Left click  build here      Right click  cancel"
	else:
		if not is_instance_valid(g) and is_instance_valid(p.focused_companion) and not p.frozen:
			_prompt.text = "[E] Talk to the %s" % ("Fox" if p.focused_companion.who == "fox" else "Otter")
		else:
			_prompt.text = g.prompt() if is_instance_valid(g) and not p.frozen else ("[E] Drink" if p.water_depth() > 0.15 and Game.story_start and not is_instance_valid(p.focused_loot) else "")

	if Input.is_action_just_pressed("character"):
		if _inventory.visible:
			_inventory.close()
		elif not get_tree().paused and not p.frozen:
			_inventory.open()


func _on_hit(crit: bool, _killed: bool) -> void:
	_crosshair.hit_time = 0.15
	_crosshair.hit_crit = crit


func _set_ability(label: Label, title: String, cooldown: float) -> void:
	label.text = title if cooldown <= 0.0 else "%s  %.1f" % [title, cooldown]
	label.add_theme_stylebox_override("normal", _ready_style if cooldown <= 0.0 else _cooldown_style)


func _update_loot_card() -> void:
	var drop := _player.focused_loot
	if not is_instance_valid(drop):
		_loot_panel.visible = false
		_shown_loot = null
		return
	_loot_panel.visible = true
	if drop != _shown_loot:
		_shown_loot = drop
		_loot_style.border_color = drop.weapon.color
		_loot_text.text = _compare_text(drop.weapon, _player.weapon)


func _compare_text(n: WeaponData, cur: WeaponData) -> String:
	var t := "[font_size=22][color=#%s]%s[/color][/font_size]\n" % [n.color.to_html(false), n.display_name]
	t += "[color=#b0b0b0]Lv %d %s %s  |  %s[/color]\n\n" % [n.level, WeaponData.RARITY_NAMES[n.rarity], n.archetype, WeaponData.ELEMENT_NAMES[n.element]]
	if cur == null:
		t += "DPS: [b]%.0f[/b]\nDamage: [b]%.0f[/b]\nFire rate: [b]%.1f/s[/b]\nMagazine: [b]%d[/b]\n" % [n.dps(), n.damage, n.fire_rate, n.mag_size]
		return t + _traits(n) + "\n[color=#ffffff][b][lb]E[rb][/b] Pick up[/color]"
	t += _row("DPS", n.dps(), cur.dps(), "%.0f")
	t += _row("Damage" + (" (x%d)" % n.pellets if n.pellets > 1 else ""), n.damage, cur.damage, "%.0f")
	t += _row("Fire rate", n.fire_rate, cur.fire_rate, "%.1f/s")
	t += _row("Magazine", n.mag_size, cur.mag_size, "%.0f")
	t += _row("Reload", n.reload_time, cur.reload_time, "%.1fs", false)
	t += _row("Crit chance", n.crit_chance * 100.0, cur.crit_chance * 100.0, "%.0f%%")
	t += _traits(n)
	t += "\n[color=#ffffff][b][lb]E[rb][/b] Swap weapons[/color]"
	return t


func _row(label: String, a: float, b: float, fmt: String, higher_better := true) -> String:
	var diff := a - b
	var change := ""
	if absf(diff) > 0.05:
		var good := (diff > 0.0) == higher_better
		change = "  [color=%s](%s%s)[/color]" % ["#66ff66" if good else "#ff6666", "+" if diff > 0.0 else "-", fmt % absf(diff)]
	return "%s: [b]%s[/b]%s\n" % [label, fmt % a, change]


func _traits(w: WeaponData) -> String:
	var t := ""
	if w.element != WeaponData.Element.KINETIC:
		t += "\n[color=#%s]* %s[/color]" % [WeaponData.ELEMENT_COLORS[w.element].to_html(false), WeaponData.ELEMENT_DESCRIPTIONS[w.element]]
	for perk in w.perks:
		t += "\n[color=#ffd27a]* %s[/color]" % WeaponData.PERKS[perk]
	return t + ("\n" if t != "" else "")


func _character_sheet() -> String:
	var p := _player
	var w := p.weapon
	var t := "[font_size=24][color=#66e6ff]Wayfinder[/color][/font_size]\n"
	t += "Level %d   (%d / %d XP)\n" % [p.level, p.xp, p.xp_to_next()]
	t += "Health %d / %d\n" % [ceili(p.health), roundi(p.max_health)]
	t += "Damage bonus +%d%%\n\n" % roundi((p.damage_multiplier() - 1.0) * 100.0)
	if not Game.backpack.is_empty():
		t += "[color=#ffd27a]Backpack:[/color] %s\n\n" % ", ".join(Game.backpack)
	if w == null:
		return t + "[color=#a0a0a0]No weapon yet.[/color]"
	t += "[font_size=20][color=#%s]%s[/color][/font_size]\n" % [w.color.to_html(false), w.display_name]
	t += "Lv %d %s %s\n" % [w.level, WeaponData.RARITY_NAMES[w.rarity], w.archetype]
	t += "DPS %.0f   |   Damage %.0f%s   |   %.1f shots/s\n" % [w.dps(), w.damage, (" x%d" % w.pellets) if w.pellets > 1 else "", w.fire_rate]
	t += "Magazine %d   |   Reload %.1fs   |   Crit %.0f%%\n" % [w.mag_size, w.reload_time, w.crit_chance * 100.0]
	t += _traits(w)
	t += "\n[color=#a0a0a0]Rune Nova takes on your weapon's element.[/color]"
	return t


# --- Builders ----------------------------------------------------------------

func _place(c: Control, anchor: Vector2, offset: Vector2, box_size: Vector2) -> Control:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = offset.x
	c.offset_top = offset.y
	c.offset_right = offset.x + box_size.x
	c.offset_bottom = offset.y + box_size.y
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(c)
	return c


func _label(text: String, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(fill: Color, anchor: Vector2, offset: Vector2, box_size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(4)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)
	_place(bar, anchor, offset, box_size)
	return bar


func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(6)
	s.set_content_margin_all(12)
	return s


func _rich_text(width: float) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size = Vector2(width, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_constant_override("outline_size", 0)
	return r


func _full_rect(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rect)
	return rect
