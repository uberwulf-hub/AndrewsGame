class_name Gatherable
extends Node3D
## Something lying in the world that can be picked up with E: a pile of sticks,
## a few loose stones, a berry bush. Picking it up adds items to the backpack
## and practices the matching skill. Berry bushes regrow after a while.

const KINDS := {
	"sticks": {"item": "Sticks", "count": [1, 2], "skill": "Woodcraft", "verb": "Gather sticks"},
	"stones": {"item": "Stones", "count": [1, 2], "skill": "Foraging", "verb": "Pick up stones"},
	"berries": {"item": "Berries", "count": [2, 4], "skill": "Foraging", "verb": "Pick berries", "regrow": 240.0},
	"ferns": {"item": "Ferns", "count": [2, 3], "skill": "Foraging", "verb": "Cut some ferns"},
	# Finding these gives the Otter an idea (see Game.spark).
	"vines": {"item": "Vines", "count": [2, 3], "skill": "Woodcraft", "verb": "Pull down some vines", "sparks": "torch_post",
		"spark_thought": ["These vines are tough. Like rope.", "...I bet the Otter would have an idea for these."]},
	"bark": {"item": "Birch bark", "count": [2, 3], "skill": "Woodcraft", "verb": "Peel some birch bark", "sparks": "rain_catcher",
		"spark_thought": ["Birch bark. Papery, and it doesn't soak up water.", "...I bet the Otter would have an idea for this."]},
	# Brought back by the Fox and the Otter and dropped at your feet.
	"grubs": {"item": "Grubs", "count": [2, 3], "skill": "Foraging", "verb": "Take the grubs (ew)"},
	"mushrooms": {"item": "Mushrooms", "count": [2, 3], "skill": "Foraging", "verb": "Take the mushrooms"},
	"eggs": {"item": "Bird eggs", "count": [2, 3], "skill": "Foraging", "verb": "Take the eggs"},
	"fish": {"item": "Fish", "count": [1, 1], "skill": "Foraging", "verb": "Take the fish"},
	"crayfish": {"item": "Crayfish", "count": [2, 3], "skill": "Foraging", "verb": "Take the crayfish"},
	"clams": {"item": "Clams", "count": [2, 4], "skill": "Foraging", "verb": "Take the clams"},
	# Not picked up: looking at it teaches something.
	"fire_ring": {"verb": "Look at the old fire ring", "teaches": "campfire", "skill": "Survival",
		"thought": ["Someone made a fire here, a long time ago...", "Sticks in the middle, stones in a ring around them. I could do that."]},
}

var kind := "sticks"
var available := true
var _visual: Node3D
var _berries: Node3D
var _mats: Array[StandardMaterial3D] = []
var _focused := false


static func spawn(parent: Node, at: Vector3, what: String, rng: RandomNumberGenerator) -> Gatherable:
	var g := Gatherable.new()
	g.kind = what
	g.position = at
	g.rotation.y = rng.randf() * TAU
	parent.add_child(g)
	g._build(rng)
	return g


func _ready() -> void:
	add_to_group("gatherables")


func prompt() -> String:
	return "[E] " + KINDS[kind].verb




## Called by the player. Returns what was gathered, for the notification.
func gather(rng: RandomNumberGenerator) -> String:
	if not available:
		return ""
	var info: Dictionary = KINDS[kind]
	if info.has("teaches"):
		available = false
		Game.practice(info.skill, 3.0)
		Game.learn(info.teaches, info.thought)
		return ""
	var bonus := 1 if rng.randf() < Game.skill_level(info.skill) * 0.02 else 0
	var count: int = rng.randi_range(info.count[0], info.count[1]) + bonus
	Game.add_item(info.item, count)
	if info.has("sparks"):
		Game.spark(info.sparks, info.spark_thought)
	if Game.FOODS.has(info.item):
		Game.food_found += count
	Game.practice(info.skill, 2.0)
	Audio.play("gear_rustle", global_position, 4.0, 1.1)
	if info.has("regrow"):
		available = false
		_berries.visible = false
		get_tree().create_timer(info.regrow).timeout.connect(func():
			available = true
			_berries.visible = true)
	else:
		queue_free()
	return "+%d %s" % [count, info.item]


## Lit up while the player is close enough to pick it up.
func set_focused(on: bool) -> void:
	if on == _focused:
		return
	_focused = on
	for m in _mats:
		m.emission_energy_multiplier = 0.8 if on else 0.12


func _build(rng: RandomNumberGenerator) -> void:
	_visual = Node3D.new()
	add_child(_visual)
	match kind:
		"sticks":
			# Pale, freshly fallen wood: easy to tell apart from the dark twig litter.
			var bark := _readable(Color(0.66, 0.5, 0.32))
			for k in rng.randi_range(5, 7):
				var stick := MeshKit.part(_visual, MeshKit.cyl(0.03, 0.042, rng.randf_range(0.75, 1.05), 6), bark,
					Vector3(rng.randf_range(-0.12, 0.12), 0.05 + k * 0.035, rng.randf_range(-0.12, 0.12)))
				stick.rotation = Vector3(PI / 2 + rng.randf_range(-0.2, 0.2), (k % 2) * 0.9 + rng.randf_range(-0.3, 0.3), 0)
		"stones":
			var stone := _readable(Color(0.72, 0.7, 0.66))
			for k in rng.randi_range(3, 4):
				var s := MeshKit.part(_visual, MeshKit.sphere(0.13, 0.15, 7, 5), stone, Vector3(rng.randf_range(-0.22, 0.22), 0.06, rng.randf_range(-0.22, 0.22)))
				s.scale = Vector3(rng.randf_range(0.8, 1.4), rng.randf_range(0.6, 0.9), rng.randf_range(0.8, 1.3))
		"ferns":
			# A bigger, brighter clump than the forest-floor ferns, so it reads as "take me".
			var frond := _readable(Color(0.32, 0.62, 0.26))
			var clump := MeshKit.part(_visual, NatureKit.fern(10, rng.randi()), frond)
			clump.scale = Vector3.ONE * 1.5
		"vines":
			# Vines draped over a mossy stone, a few loose loops on the ground.
			var moss := MeshKit.mat(Color(0.3, 0.36, 0.24), 0.95)
			var rock := MeshKit.part(_visual, MeshKit.sphere(0.32, 0.36, 8, 5), moss, Vector3(0, 0.12, 0))
			rock.scale = Vector3(1.3, 0.75, 1.0)
			var vine := _readable(Color(0.38, 0.55, 0.2))
			for k in 6:
				var a := TAU * k / 6.0 + rng.randf_range(-0.3, 0.3)
				var strand := MeshKit.part(_visual, MeshKit.cyl(0.018, 0.018, rng.randf_range(0.7, 1.0), 5), vine,
					Vector3(cos(a), 0, sin(a)) * 0.28 + Vector3(0, 0.2, 0))
				strand.rotation = Vector3(PI / 2 - 0.5, -a + PI / 2, 0)
			for k in 3:
				var loop := MeshKit.part(_visual, MeshKit.cyl(0.16, 0.16, 0.025, 10), vine,
					Vector3(rng.randf_range(-0.5, 0.5), 0.02, rng.randf_range(0.3, 0.55)))
				loop.scale = Vector3(1.0, 1.0, rng.randf_range(0.6, 1.0))
		"bark":
			# A fallen birch: white bark with dark marks, a curl peeling off.
			var white := _readable(Color(0.9, 0.88, 0.82))
			var birch := MeshKit.part(_visual, MeshKit.cyl(0.16, 0.18, 1.6, 9), white, Vector3(0, 0.16, 0), Vector3(0, 0, PI / 2))
			birch.rotation.y = rng.randf_range(-0.2, 0.2)
			var mark := MeshKit.mat(Color(0.15, 0.13, 0.12), 0.9)
			for k in 7:
				var x := rng.randf_range(-0.7, 0.7)
				var a := rng.randf() * TAU
				MeshKit.part(_visual, MeshKit.box(Vector3(0.03, 0.02, 0.09)), mark,
					Vector3(x, 0.16 + sin(a) * 0.17, cos(a) * 0.17), Vector3(a, 0, 0))
			MeshKit.part(_visual, MeshKit.box(Vector3(0.3, 0.012, 0.2)), white, Vector3(0.35, 0.36, 0.05), Vector3(0.4, 0.2, 0.3))
		"grubs":
			MeshKit.part(_visual, MeshKit.sphere(0.16, 0.06, 7, 3), MeshKit.mat(Color(0.2, 0.14, 0.09), 1.0), Vector3(0, 0.02, 0))
			var grub := _readable(Color(0.92, 0.85, 0.66))
			for k in 4:
				var g := MeshKit.part(_visual, MeshKit.sphere(0.022, 0.07, 5, 3), grub, Vector3(rng.randf_range(-0.08, 0.08), 0.06, rng.randf_range(-0.08, 0.08)))
				g.rotation = Vector3(PI / 2, rng.randf() * TAU, rng.randf_range(-0.5, 0.5))
		"mushrooms":
			var stem := MeshKit.mat(Color(0.9, 0.86, 0.76))
			var cap := _readable(Color(0.72, 0.5, 0.3))
			for k in 3:
				var at := Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1))
				var h := rng.randf_range(0.06, 0.11)
				MeshKit.part(_visual, MeshKit.cyl(0.012, 0.016, h, 5), stem, at + Vector3(0, h * 0.5, 0))
				MeshKit.part(_visual, MeshKit.sphere(0.045, 0.04, 7, 3), cap, at + Vector3(0, h, 0))
		"eggs":
			var twig := MeshKit.mat(Color(0.4, 0.3, 0.2))
			for k in 8:
				MeshKit.part(_visual, MeshKit.cyl(0.008, 0.008, 0.2, 4), twig, Vector3(cos(TAU * k / 8.0), 0, sin(TAU * k / 8.0)) * 0.08 + Vector3(0, 0.02, 0), Vector3(PI / 2, TAU * k / 8.0 + PI / 2, 0))
			var egg := _readable(Color(0.72, 0.86, 0.92))
			for k in 3:
				MeshKit.part(_visual, MeshKit.sphere(0.03, 0.08, 6, 4), egg, Vector3(cos(TAU * k / 3.0), 0, sin(TAU * k / 3.0)) * 0.035 + Vector3(0, 0.04, 0))
		"fish":
			var scales := _readable(Color(0.62, 0.7, 0.74))
			MeshKit.part(_visual, MeshKit.sphere(0.05, 0.32, 7, 4), scales, Vector3(0, 0.05, 0), Vector3(0, 0, PI / 2))
			MeshKit.part(_visual, MeshKit.cyl(0.0, 0.06, 0.1, 4), scales, Vector3(0.2, 0.05, 0), Vector3(0, 0, PI / 2)).scale = Vector3(1, 1, 0.3)
		"crayfish", "clams":
			var shell := _readable(Color(0.8, 0.3, 0.2) if kind == "crayfish" else Color(0.55, 0.55, 0.52))
			for k in 3:
				var s := MeshKit.part(_visual, MeshKit.sphere(0.04, 0.05, 6, 4), shell, Vector3(rng.randf_range(-0.1, 0.1), 0.03, rng.randf_range(-0.1, 0.1)))
				s.scale = Vector3(1.0, 0.6, 1.8 if kind == "crayfish" else 1.2)
		"fire_ring":
			# Long cold, and the same size as the campfire you'll build (stones at
			# half a metre): a faded scorch, only some of the stones left, sunk and
			# weathered, one knocked out of place, and the wood burned down to
			# black stubs and pale ash. Nothing glows any more.
			var scorch := MeshKit.mat(Color(0.12, 0.11, 0.1), 1.0)
			var char_wood := MeshKit.mat(Color(0.08, 0.07, 0.06), 1.0)
			var ash := MeshKit.mat(Color(0.55, 0.54, 0.52), 1.0)
			var stones := [_readable(Color(0.6, 0.58, 0.54)), _readable(Color(0.52, 0.5, 0.46)), _readable(Color(0.46, 0.5, 0.4))]  # the last one mossy
			MeshKit.part(_visual, MeshKit.cyl(0.72, 0.78, 0.012, 14), scorch, Vector3(0, 0.006, 0)).scale = Vector3(1.0, 1.0, 0.85)
			MeshKit.part(_visual, MeshKit.cyl(0.3, 0.34, 0.02, 10), ash, Vector3(0.04, 0.014, -0.02))
			# Nine places in the ring, like the campfire's; three in a row are gone.
			for k in 9:
				if k == 2 or k == 3 or k == 4:
					continue
				var a := TAU * k / 9.0 + rng.randf_range(-0.12, 0.12)
				var r := 0.5 + rng.randf_range(-0.04, 0.06)
				var size := rng.randf_range(0.11, 0.16)  # worn down, some cracked smaller
				var s := MeshKit.part(_visual, MeshKit.sphere(size, size * 1.1, 7, 4), stones[k % 3], Vector3(cos(a) * r, size * 0.15, sin(a) * r))
				s.scale = Vector3(rng.randf_range(0.9, 1.3), rng.randf_range(0.6, 0.85), rng.randf_range(0.9, 1.3))
				s.rotation.y = rng.randf() * TAU
			# The one that got knocked out, lying a step away.
			var stray := MeshKit.part(_visual, MeshKit.sphere(0.13, 0.15, 7, 4), stones[0], Vector3(cos(TAU * 3.0 / 9.0), 0.02, sin(TAU * 3.0 / 9.0)) * 0.95)
			stray.scale = Vector3(1.2, 0.7, 1.0)
			# Burned-down wood: short black stubs fallen in, one longer log end
			# that never quite caught.
			for k in 4:
				var stub := MeshKit.part(_visual, MeshKit.cyl(0.035, 0.045, rng.randf_range(0.18, 0.3), 5), char_wood,
					Vector3(rng.randf_range(-0.15, 0.15), 0.035, rng.randf_range(-0.15, 0.15)))
				stub.rotation = Vector3(PI / 2, rng.randf() * TAU, 0)
			var log_end := MeshKit.part(_visual, MeshKit.cyl(0.05, 0.055, 0.42, 6), char_wood, Vector3(0.18, 0.05, 0.12), Vector3(PI / 2, 0.7, 0))
			log_end.scale = Vector3(1.0, 1.0, 0.9)
		"berries":
			var leaf := MeshKit.mat(Color(0.16, 0.34, 0.14), 0.9)
			for k in 4:
				var b := MeshKit.part(_visual, MeshKit.sphere(0.32, 0.42, 8, 5), leaf, Vector3(rng.randf_range(-0.25, 0.25), 0.28 + rng.randf_range(0, 0.15), rng.randf_range(-0.25, 0.25)))
				b.scale = Vector3.ONE * rng.randf_range(0.8, 1.2)
			_berries = Node3D.new()
			_visual.add_child(_berries)
			var berry := MeshKit.mat(Color(0.75, 0.08, 0.2), 0.3)
			berry.emission_enabled = true
			berry.emission = Color(0.5, 0.02, 0.1)
			berry.emission_energy_multiplier = 0.15
			for k in 18:
				var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.0, 1), rng.randf_range(-1, 1)).normalized()
				MeshKit.part(_berries, MeshKit.sphere(0.035, -1.0, 5, 3), berry, Vector3(0, 0.35, 0) + dir * 0.38)
			_mats.append(berry)
	if kind != "berries":
		_add_glint()


## A material that faintly glows in its own color, so it reads in moonlight.
func _readable(color: Color) -> StandardMaterial3D:
	var m := MeshKit.mat(color, 0.9)
	m.emission_enabled = true
	m.emission = color * 0.5
	m.emission_energy_multiplier = 0.12
	_mats.append(m)
	return m


## A few slow pale motes drifting up, visible from a distance in the dark.
func _add_glint() -> void:
	var motes := CPUParticles3D.new()
	var dot := MeshKit.sphere(0.012, -1.0, 4, 2)
	dot.material = MeshKit.glow(Color(1.0, 0.95, 0.75), 1.2)
	motes.mesh = dot
	motes.amount = 2
	motes.lifetime = 2.5
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = 0.3
	motes.direction = Vector3.UP
	motes.spread = 20.0
	motes.gravity = Vector3.ZERO
	motes.initial_velocity_min = 0.1
	motes.initial_velocity_max = 0.25
	motes.position.y = 0.15
	motes.visibility_range_end = 18.0
	add_child(motes)
