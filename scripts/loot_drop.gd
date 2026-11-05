class_name LootDrop
extends Area3D
## A dream tool lying in the world: slowly turning, softly lit, with a name tag
## (and a faint shaft of light for the rarer ones).
## Tells the player when they are in pickup range.

var weapon: WeaponData
var _model: Node3D
var _t := 0.0


## `announce` plays the rarity chime (skip it for drops placed at load or swapped).
static func spawn(parent: Node, w: WeaponData, pos: Vector3, announce := true) -> LootDrop:
	var drop := LootDrop.new()
	drop.weapon = w
	parent.add_child(drop)
	drop.global_position = pos
	if announce:
		Audio.play("loot_drop_%d" % w.rarity, pos, 0.0, 1.0, 0.0, 80.0)
	return drop


func _ready() -> void:
	collision_layer = 8
	collision_mask = 2
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.8
	shape.shape = sphere
	add_child(shape)

	var color := weapon.color
	_model = WeaponModel.build(weapon)
	_model.position.y = 0.8
	_model.scale = Vector3.ONE * 1.4
	add_child(_model)

	# Only the rarer finds get a faint shaft of light; plain ones just glow.
	if weapon.rarity >= 2:
		var beam_height := 1.0 + weapon.rarity * 0.6
		var beam := MeshKit.part(self, MeshKit.cyl(0.01, 0.06, beam_height, 8),
			MeshKit.glow(Color(color, 0.12), 0.7, true), Vector3(0, beam_height * 0.5, 0))
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var light := OmniLight3D.new()
	light.light_color = color.lerp(Color(1.0, 0.9, 0.7), 0.5)
	light.light_energy = 0.8
	light.omni_range = 3.0
	light.position.y = 1.0
	add_child(light)

	var label := Label3D.new()
	label.text = weapon.display_name
	label.modulate = color
	label.font_size = 32
	label.outline_size = 10
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 1.7
	add_child(label)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	_t += delta
	_model.rotation.y += delta * 0.6
	_model.position.y = 0.8 + sin(_t * 1.2) * 0.06


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		body.register_loot(self, true)


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		body.register_loot(self, false)
