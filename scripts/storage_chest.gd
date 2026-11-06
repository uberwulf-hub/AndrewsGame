class_name StorageChest
extends Node3D
## A chest woven from twigs and tied with vines, with a lid. E opens a little
## menu: put your building materials away, or take everything back out. All
## chests share one store (Game.stash), so it's there whichever one you use.

const USE_RADIUS := 1.6


static func build(parent: Node, at: Vector3, yaw: float) -> StorageChest:
	var c := StorageChest.new()
	c.position = at
	c.rotation.y = yaw
	parent.add_child(c)
	return c


static func ghost(material: Material) -> Node3D:
	var g := Node3D.new()
	_shape(g, material, material)
	return g


static func _shape(parent: Node3D, wicker: Material, vine: Material) -> void:
	MeshKit.part(parent, MeshKit.box(Vector3(0.9, 0.5, 0.55)), wicker, Vector3(0, 0.25, 0))
	# Woven bands round the sides, and a domed lid.
	for y in [0.1, 0.25, 0.4]:
		MeshKit.part(parent, MeshKit.box(Vector3(0.93, 0.035, 0.58)), vine, Vector3(0, y, 0))
	var lid := MeshKit.part(parent, MeshKit.cyl(0.28, 0.28, 0.92, 10), wicker, Vector3(0, 0.5, 0), Vector3(0, 0, PI / 2))
	lid.scale = Vector3(1.0, 1.0, 0.45)
	for x in [-0.3, 0.3]:
		MeshKit.part(parent, MeshKit.cyl(0.29, 0.29, 0.04, 10), vine, Vector3(x, 0.5, 0), Vector3(0, 0, PI / 2)).scale = Vector3(1.0, 1.0, 0.47)


func _ready() -> void:
	add_to_group("usables")
	add_to_group("chests")
	_shape(self, MeshKit.mat(Color(0.55, 0.4, 0.24), 0.95), MeshKit.mat(Color(0.32, 0.38, 0.17), 0.9))
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 0.7, 0.55)
	shape.shape = box
	shape.position.y = 0.35
	body.add_child(shape)
	add_child(body)


func use_radius() -> float:
	return USE_RADIUS


func use_prompt() -> String:
	return "[E] Open the storage chest"


func use(player: Player) -> void:
	var held := 0
	for item in Game.STASHABLE:
		held += Game.inventory.get(item, 0)
	var stored := 0
	for item in Game.stash:
		stored += Game.stash[item]
	var options := []
	if held > 0:
		options.append(["Put away your materials  (%d)" % held, func():
			Game.stash_all()
			Audio.play("gear_rustle", global_position, -4.0, 0.9)])
	if stored > 0:
		var list := ", ".join(Game.stash.keys().map(func(k): return "%s %d" % [k, Game.stash[k]]))
		options.append(["Take everything out  (%s)" % list, func():
			Game.unstash_all()
			Audio.play("gear_rustle", global_position, -4.0, 1.1)])
	if options.is_empty():
		player.says.emit(["It's empty, and so are my pockets.", "Nothing to put away."])
		return
	player.menu_requested.emit("The Storage Chest", options)
