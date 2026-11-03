class_name Figure
extends Node3D
## A stylized-realistic person built from primitives, for cutscenes and (later) NPCs
## and the character creator. Faces -Z. Set `walking` for a walk cycle; raise arms
## with left_raise/right_raise.
##
## Appearance comes from a "look" dictionary (see DEFAULT_LOOK). The hero and mate
## presets are modeled on reference/hero_and_mate.webp: a likeness in spirit, not a
## portrait, so they read as "them" without sliding into the uncanny.

const DEFAULT_LOOK := {
	"build": "male",            # "male" or "female": shoulders, hips, jaw
	"size": 1.0,                # 1.0 = about 1.78 m
	"head_scale": 1.0,          # >1 for kids
	"skin": Color(0.86, 0.68, 0.55),
	"hair": Color(0.25, 0.17, 0.1),
	"hair_style": "short",      # short, spiky, pulled_back, long, bald
	"eyes": Color(0.3, 0.2, 0.12),
	"lips": Color(0.78, 0.5, 0.48),
	"liner": false,             # darker upper lash line
	"glasses": false,
	"headband": Color(0, 0, 0, 0),
	"earrings": false,
	"shirt": Color(0.9, 0.9, 0.88),
	"shirt_style": "tee",       # tee or tank
	"print": Color(0, 0, 0, 0), # graphic on the shirt front
	"straps": Color(0.2, 0.35, 0.75),
	"pants": Color(0.17, 0.22, 0.32),
	"belt": Color(0.3, 0.2, 0.12),
	"shoes": Color(0.2, 0.17, 0.15),
}

# Heights: hero 6'4" (1.93 m, lean 180 lb), mate 4'11" (1.50 m, petite 100 lb).
const HERO_LOOK := {
	"build": "male",
	"size": 1.085,
	"skin": Color(0.93, 0.74, 0.64),
	"hair": Color(0.2, 0.14, 0.09),
	"hair_style": "spiky",
	"eyes": Color(0.36, 0.26, 0.14),
	"lips": Color(0.84, 0.56, 0.54),
	"glasses": true,
	"shirt": Color(0.93, 0.93, 0.9),
	"pants": Color(0.2, 0.26, 0.38),
}

const MATE_LOOK := {
	"build": "female",
	"size": 0.845,
	"head_scale": 1.06,
	"skin": Color(0.87, 0.67, 0.53),
	"hair": Color(0.05, 0.04, 0.045),
	"hair_style": "pulled_back",
	"eyes": Color(0.17, 0.09, 0.05),
	"lips": Color(0.76, 0.22, 0.3),
	"liner": true,
	"headband": Color(0.88, 0.1, 0.3),
	"earrings": true,
	"shirt": Color(0.1, 0.11, 0.17),
	"shirt_style": "tank",
	"straps": Color(0.22, 0.36, 0.78),
	"pants": Color(0.12, 0.13, 0.18),
	"shoes": Color(0.12, 0.1, 0.1),
}

# The two boys: the older one is the Fox's counterpart, the younger the Otter's.
const OLDER_KID_LOOK := {
	"build": "male",
	"size": 0.74,
	"head_scale": 1.2,
	"skin": Color(0.87, 0.68, 0.55),
	"hair": Color(0.07, 0.05, 0.045),
	"hair_style": "curly",
	"eyes": Color(0.2, 0.12, 0.07),
	"lips": Color(0.8, 0.52, 0.48),
	"glasses": true,
	"shirt": Color(0.58, 0.2, 0.18),
	"print": Color(0.55, 0.62, 0.72),
	"pants": Color(0.2, 0.22, 0.28),
	"shoes": Color(0.25, 0.25, 0.28),
}

const YOUNGER_KID_LOOK := {
	"build": "male",
	"size": 0.6,
	"head_scale": 1.32,
	"skin": Color(0.88, 0.69, 0.55),
	"hair": Color(0.24, 0.15, 0.09),
	"hair_style": "wavy",
	"eyes": Color(0.25, 0.15, 0.08),
	"lips": Color(0.82, 0.54, 0.5),
	"shirt": Color(0.94, 0.94, 0.92),
	"print": Color(0.3, 0.38, 0.55),
	"pants": Color(0.22, 0.3, 0.45),
	"shoes": Color(0.85, 0.85, 0.85),
}

const HEAD_PIVOT := 1.53   # top of the neck
const HEAD_CENTER := 0.11  # head center above the pivot

var walking := false
var walk_speed := 8.0
var left_raise := 0.0
var right_raise := 0.0
var head: Node3D

var _move_tween: Tween
var _rig: CharacterRig  # set when this figure uses a rigged model
var _last_pos := Vector3.ZERO
var _speed := 0.0
var _stride := 0.0
var _phase := 0.0
var _legs: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _elbows: Array[Node3D] = []


static func from_look(look: Dictionary) -> Figure:
	var full := DEFAULT_LOOK.duplicate()
	full.merge(look, true)
	var f := Figure.new()
	f._build(full)
	f.scale = Vector3.ONE * float(full.size)
	return f


static func hero() -> Figure:
	return _rigged("hero", 1.93, HERO_LOOK)


## Uses the rigged model in models/<rig_name> when there is one, else builds
## the primitive figure from `look`.
static func _rigged(rig_name: String, height: float, look: Dictionary) -> Figure:
	var rig := CharacterRig.create(rig_name, height)
	if rig == null:
		return from_look(look)
	var f := Figure.new()
	f._rig = rig
	f.add_child(rig)
	f.head = Node3D.new()
	f.head.position = Vector3(0, height * 0.88, 0)
	f.add_child(f.head)
	rig.play("idle")
	return f


static func older_kid() -> Figure:
	return from_look(OLDER_KID_LOOK)


static func younger_kid() -> Figure:
	return _rigged("younger", 1.10, YOUNGER_KID_LOOK)


static func mate() -> Figure:
	return _rigged("mate", 1.50, MATE_LOOK)


## Simple outfit-based person (used for the kids).
static func person(cloth: Color, accent: Color, hair: Color, long_hair := false, skin := Color(0.86, 0.68, 0.55), size := 1.0) -> Figure:
	var child := size < 0.8
	return from_look({
		"build": "female" if long_hair else "male",
		"size": size,
		"head_scale": 1.35 if child else 1.0,
		"skin": skin,
		"hair": hair,
		"hair_style": "long" if long_hair else "short",
		"shirt": cloth,
		"belt": accent,
		"shoes": accent.darkened(0.4),
	})


## Tall, dark, crowned, with a cape and burning red eyes.
static func villain() -> Figure:
	var f := from_look({
		"size": 1.3,
		"skin": Color(0.62, 0.62, 0.7),
		"hair": Color(0.05, 0.05, 0.06),
		"hair_style": "short",
		"eyes": Color(0.05, 0.02, 0.02),
		"lips": Color(0.35, 0.3, 0.35),
		"shirt": Color(0.07, 0.05, 0.09),
		"pants": Color(0.06, 0.05, 0.07),
		"belt": Color(0.55, 0.05, 0.08),
		"shoes": Color(0.05, 0.04, 0.05),
	})
	var cape := MeshKit.mat(Color(0.3, 0.02, 0.05))
	MeshKit.part(f, MeshKit.box(Vector3(0.5, 1.3, 0.04)), cape, Vector3(0, 0.82, 0.13), Vector3(0.1, 0, 0))
	MeshKit.part(f, MeshKit.box(Vector3(0.52, 0.08, 0.24)), cape, Vector3(0, 1.45, 0.04))
	var gold := MeshKit.mat(Color(0.35, 0.28, 0.12), 0.3, 0.9)
	for k in 5:
		var a := (k - 2) * 0.4
		MeshKit.part(f.head, MeshKit.cyl(0.0, 0.025, 0.12, 4), gold, Vector3(sin(a) * 0.085, HEAD_CENTER + 0.15, -cos(a) * 0.09 + 0.01))
	var eyes := MeshKit.glow(Color(1.0, 0.15, 0.1), 6.0)
	for side in [-1.0, 1.0]:
		MeshKit.part(f.head, MeshKit.box(Vector3(0.03, 0.012, 0.01)), eyes, Vector3(0.038 * side, HEAD_CENTER + 0.012, -0.108))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.2, 0.15)
	light.light_energy = 2.0
	light.omni_range = 5.0
	light.position = Vector3(0, 1.4, -0.6)
	f.add_child(light)
	return f


# --- Building ----------------------------------------------------------------

func _build(look: Dictionary) -> void:
	var female: bool = look.build == "female"
	var skin := _skin_mat(look.skin)
	var shirt := MeshKit.mat(look.shirt, 0.9)
	var pants := MeshKit.mat(look.pants, 0.95)
	var shoes := MeshKit.mat(look.shoes, 0.7)
	var belt := MeshKit.mat(look.belt, 0.6, 0.2)
	var tank: bool = look.shirt_style == "tank"
	var shoulder_x := 0.175 if female else 0.2
	var hip_r := 0.18 if female else 0.17
	var waist_r := 0.12 if female else 0.14

	# Legs: hip -> knee -> foot, so walking bends naturally.
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3((0.085 if female else 0.09) * side, 0.92, 0)
		add_child(hip)
		MeshKit.part(hip, MeshKit.cyl(0.085, 0.062, 0.46, 10), pants, Vector3(0, -0.22, 0))
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.44, 0)
		hip.add_child(knee)
		MeshKit.part(knee, MeshKit.cyl(0.062, 0.048, 0.42, 10), pants, Vector3(0, -0.2, 0))
		MeshKit.part(knee, MeshKit.box(Vector3(0.09, 0.07, 0.25)), shoes, Vector3(0, -0.445, -0.05))
		_legs.append(hip)
		_knees.append(knee)

	# Pelvis, waist, chest: tapered ovals rather than boxes.
	_oval(self, MeshKit.cyl(waist_r + 0.01, hip_r, 0.22, 12), pants, Vector3(0, 0.93, 0), 0.62)
	_oval(self, MeshKit.cyl(waist_r + 0.012, waist_r + 0.012, 0.04, 12), belt, Vector3(0, 1.04, 0), 0.62)
	var chest_top := shoulder_x - 0.02
	var chest_depth := 0.68 if female else 0.6
	if tank:
		_oval(self, MeshKit.cyl(chest_top - 0.035, waist_r - 0.01, 0.42, 12), skin, Vector3(0, 1.27, 0), chest_depth)
		_oval(self, MeshKit.cyl(chest_top - 0.012, waist_r + 0.006, 0.36, 12), shirt, Vector3(0, 1.24, 0), chest_depth + 0.04)
		var strap := MeshKit.mat(look.straps, 0.6)
		for side in [-1.0, 1.0]:
			MeshKit.part(self, MeshKit.box(Vector3(0.022, 0.06, 0.16)), strap, Vector3(0.085 * side, 1.46, 0), Vector3(0, 0, 0.1 * side))
	else:
		_oval(self, MeshKit.cyl(chest_top, waist_r, 0.42, 12), shirt, Vector3(0, 1.27, 0), chest_depth)
	var graphic: Color = look.print
	if graphic.a > 0.0:
		var front := lerpf(waist_r, chest_top, (1.25 - 1.06) / 0.42) * chest_depth
		MeshKit.part(self, MeshKit.box(Vector3(0.15, 0.11, 0.01)), MeshKit.mat(graphic, 0.9), Vector3(0, 1.25, -front - 0.002))
	# Sloped shoulders (trapezius) so the torso doesn't end in a flat shelf.
	var traps := MeshKit.part(self, MeshKit.sphere(chest_top - (0.04 if tank else 0.01), 0.1, 12, 6), skin if tank else shirt, Vector3(0, 1.47, 0))
	traps.scale = Vector3(1.0, 1.0, chest_depth)
	MeshKit.part(self, MeshKit.cyl(0.045, 0.055, 0.12, 10), skin, Vector3(0, 1.5, 0.005))

	# Arms: shoulder -> elbow -> hand, hanging slightly out from the body.
	for side in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(shoulder_x * side, 1.44, 0)
		add_child(shoulder)
		var upper := 0.048 if female else 0.056
		var cap := MeshKit.part(shoulder, MeshKit.sphere(upper + 0.006, -1.0, 10, 6), skin if tank else shirt, Vector3(0, -0.04, 0))
		cap.scale = Vector3(1.0, 1.3, 1.0)
		MeshKit.part(shoulder, MeshKit.cyl(upper, upper - 0.006, 0.29, 10), skin, Vector3(0, -0.14, 0))
		if not tank:
			MeshKit.part(shoulder, MeshKit.cyl(upper + 0.014, upper + 0.012, 0.16, 10), shirt, Vector3(0, -0.07, 0))
		var elbow := Node3D.new()
		elbow.position = Vector3(0, -0.28, 0)
		shoulder.add_child(elbow)
		MeshKit.part(elbow, MeshKit.cyl(upper - 0.006, upper - 0.016, 0.25, 10), skin, Vector3(0, -0.12, 0))
		var hand := MeshKit.part(elbow, MeshKit.sphere(0.042, -1.0, 8, 5), skin, Vector3(0, -0.28, -0.005))
		hand.scale = Vector3(0.65, 1.15, 1.0)
		_arms.append(shoulder)
		_elbows.append(elbow)

	head = Node3D.new()
	head.position = Vector3(0, HEAD_PIVOT, 0)
	head.scale = Vector3.ONE * float(look.head_scale)
	add_child(head)
	_build_head(look, skin, female)


func _build_head(look: Dictionary, skin: Material, female: bool) -> void:
	var c := Vector3(0, HEAD_CENTER, 0)
	var skull := MeshKit.part(head, MeshKit.sphere(0.1, 0.235, 16, 10), skin, c + Vector3(0, 0.012, 0.005))
	skull.scale = Vector3(0.92, 1.0, 1.1)
	var jaw_r := 0.068 if female else 0.076
	var jaw := MeshKit.part(head, MeshKit.sphere(jaw_r, 0.12, 14, 8), skin, c + Vector3(0, -0.058, -0.028))
	jaw.scale = Vector3(1.0, 1.0, 1.05)
	for side in [-1.0, 1.0]:
		var ear := MeshKit.part(head, MeshKit.sphere(0.026, -1.0, 8, 5), skin, c + Vector3(0.091 * side, 0.0, 0.012))
		ear.scale = Vector3(0.35, 1.0, 0.7)

	# Nose: bridge plus a rounded tip.
	MeshKit.part(head, MeshKit.box(Vector3(0.02, 0.048, 0.028)), skin, c + Vector3(0, -0.012, -0.1), Vector3(-0.3, 0, 0))
	var tip := MeshKit.part(head, MeshKit.sphere(0.016, -1.0, 8, 5), skin, c + Vector3(0, -0.036, -0.112))
	tip.scale = Vector3(1.25, 0.9, 1.0)

	# Eyes: white, iris, pupil, lash line, brow.
	var white := MeshKit.mat(Color(0.95, 0.93, 0.9), 0.3)
	var iris := MeshKit.mat(look.eyes, 0.25)
	var pupil := MeshKit.mat(Color(0.02, 0.02, 0.02), 0.2)
	var lash := MeshKit.mat(Color(0.05, 0.04, 0.04))
	var brow := MeshKit.mat(Color(look.hair).lerp(Color(0.1, 0.07, 0.05), 0.3))
	for side in [-1.0, 1.0]:
		var e := c + Vector3(0.037 * side, 0.012, 0)
		var ew := MeshKit.part(head, MeshKit.sphere(0.017, -1.0, 10, 6), white, e + Vector3(0, 0, -0.093))
		ew.scale = Vector3(1.1, 0.7, 0.6)
		var ir := MeshKit.part(head, MeshKit.sphere(0.0095, -1.0, 8, 5), iris, e + Vector3(0, -0.001, -0.101))
		ir.scale = Vector3(1, 1, 0.5)
		MeshKit.part(head, MeshKit.sphere(0.0045, -1.0, 6, 4), pupil, e + Vector3(0, -0.001, -0.1055))
		var liner := 0.009 if look.liner else 0.005
		MeshKit.part(head, MeshKit.box(Vector3(0.038, liner, 0.012)), lash, e + Vector3(0.002 * side, 0.011, -0.099), Vector3(0, 0, -0.12 * side))
		MeshKit.part(head, MeshKit.box(Vector3(0.042, 0.008 if female else 0.011, 0.014)), brow, e + Vector3(0.004 * side, 0.036, -0.099), Vector3(0.15, 0, -0.1 * side))

	var lips := MeshKit.part(head, MeshKit.sphere(0.023, -1.0, 10, 6), MeshKit.mat(look.lips, 0.45), c + Vector3(0, -0.064, 0.004 - (0.028 + jaw_r * 1.05)))
	lips.scale = Vector3(1.1, 0.4, 0.45)

	_build_hair(look, c)

	if look.glasses:
		var frame := MeshKit.mat(Color(0.18, 0.18, 0.2), 0.3, 0.8)
		var t := 0.0035
		for side in [-1.0, 1.0]:
			var g := c + Vector3(0.039 * side, 0.013, -0.118)
			MeshKit.part(head, MeshKit.box(Vector3(0.048, t, t)), frame, g + Vector3(0, 0.015, 0))
			MeshKit.part(head, MeshKit.box(Vector3(0.048, t, t)), frame, g + Vector3(0, -0.014, 0))
			MeshKit.part(head, MeshKit.box(Vector3(t, 0.03, t)), frame, g + Vector3(0.024, 0, 0))
			MeshKit.part(head, MeshKit.box(Vector3(t, 0.03, t)), frame, g + Vector3(-0.024, 0, 0))
			# Temple arm from the outer frame corner back to the ear.
			var p0 := c + Vector3(0.064 * side, 0.024, -0.118)
			var p1 := c + Vector3(0.093 * side, 0.02, -0.005)
			var arm := MeshKit.part(head, MeshKit.box(Vector3(t, t, p0.distance_to(p1))), frame, (p0 + p1) * 0.5)
			arm.basis = Basis.looking_at(p1 - p0)
		MeshKit.part(head, MeshKit.box(Vector3(0.032, t, t)), frame, c + Vector3(0, 0.024, -0.12))

	if look.earrings:
		var silver := MeshKit.mat(Color(0.85, 0.85, 0.9), 0.2, 1.0)
		for side in [-1.0, 1.0]:
			MeshKit.part(head, MeshKit.sphere(0.006, -1.0, 6, 4), silver, c + Vector3(0.094 * side, -0.026, 0.0))


func _build_hair(look: Dictionary, c: Vector3) -> void:
	var style: String = look.hair_style
	if style == "bald":
		return
	var hair := MeshKit.mat(look.hair, 0.75)
	# A cap that sits back from the face so the hairline is on the forehead.
	var cap := MeshKit.part(head, MeshKit.sphere(0.106, 0.24, 16, 10), hair, c + Vector3(0, 0.035, 0.018))
	cap.scale = Vector3(0.95, 1.0, 1.08)
	match style:
		"spiky":
			# Short, textured, pushed up at the front.
			for i in 22:
				var a := float(i) / 22.0 * TAU
				var ring := 0.35 if i % 2 == 0 else 0.65
				var dir := Vector3(sin(a) * ring, 1.0, -cos(a) * ring * 0.9).normalized()
				var spike := MeshKit.part(head, MeshKit.cyl(0.0, 0.028, 0.05, 5), hair, c + Vector3(0, 0.03, 0.015) + dir * 0.11)
				# Point each tuft outward, tipped a little toward the front.
				spike.basis = Basis(Quaternion(Vector3.UP, (dir + Vector3(0, 0, -0.3)).normalized()))
			var quiff := MeshKit.part(head, MeshKit.sphere(0.055, 0.045, 12, 6), hair, c + Vector3(0, 0.105, -0.06), Vector3(-0.45, 0, 0))
			quiff.scale = Vector3(1.4, 1.0, 1.0)
		"short":
			pass
		"wavy":
			# Tousled, a little long on top, with a fringe brushing the forehead.
			for i in 16:
				var a := float(i) * 2.39996
				var ring := 0.25 + 0.6 * sqrt(float(i) / 16.0)
				var dir := Vector3(sin(a) * ring, 1.0, -cos(a) * ring).normalized()
				var tuft := MeshKit.part(head, MeshKit.sphere(0.038, 0.05, 8, 5), hair, c + Vector3(0, 0.03, 0.015) + dir * 0.1)
				tuft.basis = Basis(Quaternion(Vector3.UP, dir)).scaled(Vector3(1.0, 0.8, 1.0))
			var fringe := MeshKit.part(head, MeshKit.sphere(0.06, 0.035, 12, 5), hair, c + Vector3(0.012, 0.072, -0.088), Vector3(-0.75, 0, 0.12))
			fringe.scale = Vector3(1.35, 1.0, 1.0)
		"curly":
			# Tight dark curls piled up on top.
			for i in 30:
				var a := float(i) * 2.39996
				var r := sqrt(float(i) / 30.0)
				var p := Vector3(sin(a) * r * 0.085, 0.0, -cos(a) * r * 0.095)
				p.y = 0.115 - r * r * 0.05
				MeshKit.part(head, MeshKit.sphere(0.032, -1.0, 8, 5), hair, c + p + Vector3(0, 0.0, 0.012))
		"pulled_back":
			# Volume swept back, gathered behind the head, falling to the shoulders.
			var top := MeshKit.part(head, MeshKit.sphere(0.1, 0.12, 14, 8), hair, c + Vector3(0, 0.1, 0.0))
			top.scale = Vector3(0.95, 1.0, 1.1)
			var back := MeshKit.part(head, MeshKit.sphere(0.095, 0.24, 14, 8), hair, c + Vector3(0, -0.02, 0.06))
			back.scale = Vector3(1.05, 1.0, 1.0)
			var fall := MeshKit.part(head, MeshKit.sphere(0.085, 0.36, 12, 8), hair, c + Vector3(0, -0.2, 0.085), Vector3(0.12, 0, 0))
			fall.scale = Vector3(1.25, 1.0, 0.7)
		"long":
			var fall := MeshKit.part(head, MeshKit.sphere(0.1, 0.4, 12, 8), hair, c + Vector3(0, -0.1, 0.06))
			fall.scale = Vector3(1.05, 1.0, 0.75)
	var band: Color = look.headband
	if band.a > 0.0:
		var sparkle := MeshKit.mat(band, 0.25, 0.55)
		sparkle.emission_enabled = true
		sparkle.emission = band
		sparkle.emission_energy_multiplier = 0.25
		for k in 11:
			var a := lerpf(0.5, PI - 0.5, float(k) / 10.0)
			var p := c + Vector3(cos(a) * 0.104, 0.035 + sin(a) * 0.118, -0.02)
			MeshKit.part(head, MeshKit.box(Vector3(0.032, 0.024, 0.03)), sparkle, p, Vector3(0, 0, a - PI / 2))


static func _skin_mat(color: Color) -> StandardMaterial3D:
	var m := MeshKit.mat(color, 0.6)
	m.subsurf_scatter_enabled = true
	m.subsurf_scatter_strength = 0.25
	m.rim_enabled = true
	m.rim = 0.15
	return m


func _oval(parent: Node3D, mesh: Mesh, material: Material, pos: Vector3, depth: float) -> MeshInstance3D:
	var mi := MeshKit.part(parent, mesh, material, pos)
	mi.scale = Vector3(1.0, 1.0, depth)
	return mi


# --- Animation ---------------------------------------------------------------

func _process(delta: float) -> void:
	if _rig:
		# Scenes move figures by tween (walk_to) or directly (circling kids),
		# so pick the gait from how fast this figure is actually moving.
		var speed := (position - _last_pos).length() / maxf(delta, 0.0001)
		_last_pos = position
		_speed = lerpf(_speed, speed, 1.0 - exp(-6.0 * delta))
		if _speed > 2.2:
			_rig.play("run", clampf(_speed / 4.0, 0.7, 1.4), 0.3)
		elif _speed > 0.25 or walking:
			_rig.play("walk", clampf(_speed / 1.2, 0.6, 1.3), 0.3)
		else:
			_rig.play("idle", 1.0, 0.3)
		return
	_stride = lerpf(_stride, 1.0 if walking else 0.0, 1.0 - exp(-8.0 * delta))
	_phase += delta * walk_speed * _stride
	var swing := sin(_phase) * 0.55 * _stride
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing
	# Knees bend most as each leg swings through.
	_knees[0].rotation.x = -(0.08 + maxf(0.0, cos(_phase)) * 0.7) * _stride
	_knees[1].rotation.x = -(0.08 + maxf(0.0, -cos(_phase)) * 0.7) * _stride
	_arms[0].rotation.x = -swing * 0.7 + left_raise
	_arms[1].rotation.x = swing * 0.7 + right_raise
	_arms[0].rotation.z = -0.06
	_arms[1].rotation.z = 0.06
	_elbows[0].rotation.x = 0.12 + maxf(0.0, _arms[0].rotation.x) * 0.35
	_elbows[1].rotation.x = 0.12 + maxf(0.0, _arms[1].rotation.x) * 0.35


## Turns to face a point, taking the short way around.
func face(target: Vector3, duration := 0.35) -> void:
	var d := target - position
	if Vector2(d.x, d.z).length() < 0.01:
		return
	var yaw := atan2(-d.x, -d.z)
	create_tween().tween_property(self, "rotation:y", rotation.y + angle_difference(rotation.y, yaw), duration)


func walk_to(target: Vector3, duration: float) -> Tween:
	halt()
	face(target)
	walking = true
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", target, duration)
	_move_tween.tween_callback(func(): walking = false)
	return _move_tween


## Cancels any walk in progress (so a new placement isn't dragged back).
func halt() -> void:
	if _move_tween:
		_move_tween.kill()
	walking = false


func raise_arms(left: float, right: float, duration := 0.6) -> void:
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "left_raise", left, duration)
	tw.tween_property(self, "right_raise", right, duration)
