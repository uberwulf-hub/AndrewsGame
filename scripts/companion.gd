class_name Companion
extends Node
## Drives a Critter as a travelling companion: sleeps curled up until it wakes
## (after the hero does), then follows loosely - a few meters back, catching up
## at a run when left behind, hopping now and then. When the hero stands around
## too long it gets antsy: wanders, bounces, and thinks out loud in its own
## voice (the Fox and Otter are the boys, so the lines carry their personalities).
## Every couple of minutes each goes on a food run and brings something back.

const FOX_THOUGHTS := [
	"If we get lost, I'm blaming you. Officially.",
	"Did you hear that? ...Nope. Just my stomach.",
	"*burp* ...Excuse me. Forest air.",
	"Walking. Standing. Walking. Thrilling stuff.",
	"I could totally out-sneak an owl. Watch.",
	"You talk in your sleep, by the way. Embarrassing stuff.",
	"Stand here any longer and I'm naming a tree after you.",
	"Bet I find the way before that marble does.",
	"If something eats us, I'm going first. Less waiting.",
]
const OTTER_THOUGHTS := [
	"We could build a raft! Or a boat! Or a boat-raft!",
	"I miss home... but we've got each other, right?",
	"Ooh, a shiny rock! It's mine now.",
	"Don't worry. We're gonna find them. I just know it.",
	"I'm hungry. Are you hungry? I'm hungry.",
	"If I stack enough sticks, that's basically a house.",
	"That noise was weird. I'm not scared. YOU'RE scared.",
	"I have an idea! ...Wait. Hold on. It's loading.",
	"Are you okay? You look like you're thinking really hard.",
]

## Food runs: every so often the Fox noses out something to eat on land and
## the Otter (only near water) dives for something, then they bring it back
## and drop it at the hero's feet. [kind, chance weight, line]
const FOX_FINDS := [
	["grubs", 5.0, "Found grubs! Crunchy. Wiggly. Protein. You're welcome."],
	["mushrooms", 3.0, "Mushrooms! These ones are fine. Probably. Mostly."],
	["eggs", 2.0, "Eggs! Some bird left them unguarded. Their mistake."],
]
const OTTER_FINDS := [
	["fish", 4.0, "I caught a fish! With my HANDS! ...Well, paws."],
	["crayfish", 3.0, "Tiny lobsters! One pinched me. We're even now."],
	["clams", 3.0, "Clams! I opened one with a rock. I'm basically an inventor."],
]
const FORAGE_START := [70.0, 110.0]  # first run after waking
const FORAGE_EVERY := [110.0, 170.0]

enum State { SLEEPING, WAKING, FOLLOWING, FORAGING }
enum Run { GOING, SEARCHING, RETURNING }

var body: Critter
var hud: Hud
var who := "fox"
var state := State.SLEEPING
var follow_distance := 3.0
var side := 1.0  # which side of the hero it tends to hang around
var head_height := 1.1

var _zzz: Label3D
var _idle_time := 0.0
var _wander_timer := 0.0
var _wander_point := Vector3.ZERO
var _hop_timer := 0.0
var _hop := 0.0
var _hop_v := 0.0
var _think_timer := 0.0
var _thoughts: Array = []
var _rng := RandomNumberGenerator.new()
var _bubble: ThoughtBubble
var _forage_timer := 0.0
var _run := Run.GOING
var _run_spot := Vector3.ZERO
var _run_time := 0.0
var _find: Array = []


static func create(parent: Node, critter: Critter, kind: String, at: Vector3, the_hud: Hud) -> Companion:
	var c := Companion.new()
	c.body = critter
	c.who = kind
	c.hud = the_hud
	c.side = 1.0 if kind == "fox" else -1.0
	c.follow_distance = 3.2 if kind == "fox" else 2.6
	c.head_height = 1.0 if kind == "fox" else 0.8
	c._thoughts = (FOX_THOUGHTS if kind == "fox" else OTTER_THOUGHTS).duplicate()
	c._thoughts.shuffle()
	parent.add_child(c)
	parent.add_child(critter)
	critter.position = at
	c._sleep()
	return c


const FOX_TIPS := [
	["Pale sticks are dead wood. Dead wood burns.", "Green wood just sits there and sulks."],
	["Berry bushes like the edges of the trees, where the light gets in.", "Same as me, honestly."],
	["Punch a tree and sometimes a branch falls.", "Sometimes your hand hurts. Science."],
	["Ferns make a decent roof.", "Also a decent hat. I'm wearing one later."],
	["Water runs downhill. Usually.", "Find low ground, find water. Find water, find fish. Find fish... give it to me."],
]
const FOX_FEELINGS := [
	"Me? Great. Totally not freezing. My tail is just doing this on its own.",
	"Honestly? Weird night. But you're less boring than I expected.",
	"I'm fine. Ask the little guy, he worries enough for all of us.",
]
const OTTER_FEELINGS := [
	"I'm okay! A little scared. But you're here, so it's fine.",
	"I keep thinking about home... but we'll find it. Together, right?",
	"Honestly? Kind of excited! Is that weird? It's a little weird.",
]

var _tips_given := 0
var _feelings := 0
var _since_run := 999.0


func _ready() -> void:
	add_to_group("companions")
	_rng.randomize()
	_think_timer = _rng.randf_range(25.0, 45.0)
	_hop_timer = _rng.randf_range(4.0, 10.0)
	_forage_timer = _rng.randf_range(FORAGE_START[0], FORAGE_START[1]) + (0.0 if who == "fox" else 25.0)


## Wakes after `delay` seconds and says `line`.
func wake(delay: float, line: String) -> void:
	get_tree().create_timer(delay).timeout.connect(func():
		state = State.WAKING
		if _zzz:
			_zzz.queue_free()
		var tw := create_tween()
		tw.tween_property(body, "rotation:z", 0.0, 0.5).set_trans(Tween.TRANS_BACK)
		tw.tween_callback(func(): _hop_v = 3.2)
		tw.tween_interval(0.6)
		tw.tween_callback(func():
			say([line])
			state = State.FOLLOWING))


func say(lines: Array) -> void:
	if hud:
		if is_instance_valid(_bubble):
			_bubble.queue_free()  # a new thought replaces the last one
		_bubble = hud.think(lines, 3.4, Callable(), body, Color(1.0, 0.94, 0.86) if who == "fox" else Color(0.9, 0.95, 1.0), head_height + 0.6)


func _sleep() -> void:
	state = State.SLEEPING
	body.rotation.z = 1.35  # curled up on its side
	_zzz = Label3D.new()
	_zzz.text = "z Z z"
	_zzz.font_size = 48
	_zzz.pixel_size = 0.004
	_zzz.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_zzz.modulate = Color(0.85, 0.9, 1.0, 0.8)
	_zzz.position = Vector3(0, 0.9, 0)
	body.add_child(_zzz)
	var tw := _zzz.create_tween().set_loops()
	tw.tween_property(_zzz, "position:y", 1.2, 1.4)
	tw.tween_property(_zzz, "position:y", 0.9, 1.4)


func _process(delta: float) -> void:
	var player := Game.player
	if player == null or not is_instance_valid(body):
		return
	_update_hop(delta)
	_since_run += delta
	if state == State.FORAGING:
		_forage(delta, player)
		return
	if state != State.FOLLOWING:
		body.position.y = Game.ground_at(body.position.x, body.position.z) + _hop
		return
	if not player.frozen:
		_forage_timer -= delta
		if _forage_timer <= 0.0:
			_start_run(player)
	var to_player := player.global_position - body.position
	to_player.y = 0.0
	var dist := to_player.length()
	if dist > 35.0:
		# Left far behind (or the hero respawned): pop back nearby.
		body.position = player.global_position - to_player.normalized() * 4.0
		dist = 4.0
	var player_moving := Vector2(player.velocity.x, player.velocity.z).length() > 0.5
	_idle_time = 0.0 if player_moving else _idle_time + delta
	var goal := body.position
	var speed := 0.0
	if dist > follow_distance + 1.5:
		# Catch up to a spot beside and a bit behind the hero.
		var back := -to_player.normalized()
		var beside := Vector3(-back.z, 0, back.x) * side
		goal = player.global_position + (back * 0.8 + beside * 0.6).normalized() * follow_distance
		speed = 6.5 if dist > 9.0 else 3.4
	elif _idle_time > 7.0:
		_antsy(delta, player)
		goal = _wander_point
		speed = 1.8
	var step := goal - body.position
	step.y = 0.0
	if speed > 0.0 and step.length() > 0.3:
		var move := step.normalized() * minf(speed * delta, step.length())
		body.position += move
		var yaw := atan2(-step.x, -step.z)
		body.rotation.y = lerp_angle(body.rotation.y, yaw, 1.0 - exp(-8.0 * delta))
		body.moving = true
	else:
		body.moving = false
		var face := atan2(-to_player.x, -to_player.z)
		body.rotation.y = lerp_angle(body.rotation.y, face, 1.0 - exp(-2.0 * delta))
	body.position.y = Game.ground_at(body.position.x, body.position.z) + _hop
	_hop_timer -= delta
	if _hop_timer <= 0.0:
		_hop_timer = _rng.randf_range(5.0, 14.0) if player_moving else _rng.randf_range(2.5, 6.0)
		if _hop == 0.0:
			_hop_v = _rng.randf_range(2.2, 3.4)


## Standing around too long: wander about near the hero and think out loud.
func _antsy(delta: float, player: Player) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = _rng.randf_range(2.5, 5.0)
		var a := _rng.randf() * TAU
		_wander_point = player.global_position + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(1.5, 4.0)
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = _rng.randf_range(20.0, 40.0)
		if _thoughts.is_empty():
			_thoughts = (FOX_THOUGHTS if who == "fox" else OTTER_THOUGHTS).duplicate()
			_thoughts.shuffle()
		say([_thoughts.pop_back()])


## What the hero can ask this one right now: [question, what happens].
## The Otter is the inventor (he teaches you things to build); the Fox finds
## food and has clever ideas.
func talk_options() -> Array:
	var out := []
	if who == "otter":
		if not Game.known.has("lean_to"):
			out.append(["Any ideas how we stay safe tonight?", _teach_lean_to])
		else:
			out.append(["What else could we build?", func(): say(["Hmm... show me new stuff and I'll figure something out!", "My brain's like a toolbox. A fuzzy toolbox."])])
	else:
		out.append(["Can you sniff out some food?", request_food])
		out.append(["Got any clever ideas?", func():
			say(FOX_TIPS[_tips_given % FOX_TIPS.size()])
			_tips_given += 1])
	var feelings: Array = FOX_FEELINGS if who == "fox" else OTTER_FEELINGS
	out.append(["How are you holding up?", func():
		say([feelings[_feelings % feelings.size()]])
		_feelings += 1])
	return out


func _teach_lean_to() -> void:
	say(["Ooh, ooh! A lean-to!", "Lean sticks against a branch, then pile ferns on top. Ferns are the big floppy leaves.", "It's like a tiny roof. A tiny, AMAZING roof."])
	get_tree().create_timer(10.5).timeout.connect(func():
		Game.learn("lean_to", ["A lean-to. Sticks on a pole, ferns on top.", "And he's got more ideas where that came from."], "Otter"))


## Asked to go find food now, unless he just got back from a run.
func request_food() -> void:
	if state != State.FOLLOWING or _since_run < 25.0:
		say(["My nose needs a minute. It's been working overtime."])
		return
	say(["On it. Try not to get lost while I'm gone."])
	get_tree().create_timer(1.5).timeout.connect(func():
		if state == State.FOLLOWING and Game.player:
			_start_run(Game.player, false))


## Picks where to look (land for the Fox, water for the Otter) and what will
## turn up. Better knacks mean more frequent runs and rarer finds.
func _start_run(player: Player, announce := true) -> void:
	var knack: String = Game.PET_KNACKS[who]
	var level := Game.skill_level(knack)
	_forage_timer = _rng.randf_range(FORAGE_EVERY[0], FORAGE_EVERY[1]) * maxf(0.45, 1.0 - level * 0.05)
	var spot := _water_spot(player.global_position) if who == "otter" else _land_spot(player.global_position)
	if spot == Vector3.INF:
		_forage_timer = 30.0  # no water nearby; check again later
		return
	var finds: Array = FOX_FINDS if who == "fox" else OTTER_FINDS
	# Later entries are the rarer finds; each knack level tilts the odds toward them.
	var weights: Array[float] = []
	var total := 0.0
	for i in finds.size():
		var w: float = finds[i][1] * (1.0 + (level - 1) * 0.15 * i)
		weights.append(w)
		total += w
	var pick := _rng.randf() * total
	_find = finds[finds.size() - 1]
	for i in finds.size():
		pick -= weights[i]
		if pick <= 0.0:
			_find = finds[i]
			break
	_run_spot = spot
	_run = Run.GOING
	_run_time = 0.0
	state = State.FORAGING
	if announce and _rng.randf() < 0.6:
		say(["Hang on... I smell something."] if who == "fox" else ["Ooh, water! Be right back!"])


func _land_spot(from: Vector3) -> Vector3:
	for i in 12:
		var a := _rng.randf() * TAU
		var p := from + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(5.0, 9.0)
		if Game.ground_at(p.x, p.z) > Game.WATER_LEVEL + 0.3:
			return p
	return Vector3.INF


## Nearest swimmable water within reach, or INF.
func _water_spot(from: Vector3) -> Vector3:
	for r in [6.0, 10.0, 14.0, 18.0, 22.0]:
		for k in 16:
			var a := TAU * k / 16.0
			var p: Vector3 = from + Vector3(cos(a), 0, sin(a)) * r
			if Game.ground_at(p.x, p.z) < Game.WATER_LEVEL - 0.4:
				return p
	return Vector3.INF


## Out to the spot, a few seconds of digging (or a dive), back to the hero,
## and the find is dropped at his feet with a word about it.
func _forage(delta: float, player: Player) -> void:
	_run_time += delta
	var target := _run_spot if _run != Run.RETURNING else player.global_position
	var step := target - body.position
	step.y = 0.0
	var ground := Game.ground_at(body.position.x, body.position.z)
	match _run:
		Run.GOING, Run.RETURNING:
			var arrive := 1.4 if _run == Run.RETURNING else 0.4
			if step.length() > arrive and _run_time < 25.0:
				body.position += step.normalized() * minf(4.5 * delta, step.length())
				body.rotation.y = lerp_angle(body.rotation.y, atan2(-step.x, -step.z), 1.0 - exp(-8.0 * delta))
				body.moving = true
			elif _run == Run.GOING:
				_run = Run.SEARCHING
				_run_time = 0.0
				body.moving = false
				if who == "otter":
					Audio.play("splash_in", body.global_position, -4.0)
			else:
				_bring_back(player)
		Run.SEARCHING:
			if who == "fox":
				# Nose down, digging: a quick bob and a spray of dirt.
				body.rotation.x = -0.35 + sin(_run_time * 18.0) * 0.12
				if fmod(_run_time, 0.5) < delta:
					FX.burst(body.position + Vector3(0, 0.1, 0), Color(0.3, 0.22, 0.14), 6, 1.6, 0.03)
			else:
				# Under the surface for a moment, a few bubbles.
				ground = Game.WATER_LEVEL - 0.9
				if fmod(_run_time, 0.6) < delta:
					FX.burst(body.position + Vector3(0, Game.WATER_LEVEL - body.position.y, 0), Color(0.8, 0.9, 1.0), 4, 1.0, 0.025)
			if _run_time > 2.6:
				body.rotation.x = 0.0
				_run = Run.RETURNING
				_run_time = 0.0
				if who == "otter":
					Audio.play("splash_out", body.global_position, -4.0)
	body.position.y = (maxf(ground, Game.WATER_LEVEL - 0.25) if who == "otter" and _run != Run.SEARCHING else ground)


func _bring_back(player: Player) -> void:
	body.moving = false
	var away := body.position - player.global_position
	away.y = 0.0
	if away.length() > 4.0:
		body.position = player.global_position + away.normalized() * 2.0  # gave up chasing; catch up
		away = body.position - player.global_position
	var drop := player.global_position + away.normalized() * 1.1
	drop.y = Game.ground_at(drop.x, drop.z)
	Gatherable.spawn(body.get_parent(), drop, _find[0], _rng)
	Game.practice(Game.PET_KNACKS[who], 4.0)
	say([_find[2]])
	_hop_v = 3.0
	state = State.FOLLOWING
	_since_run = 0.0


func _update_hop(delta: float) -> void:
	if _hop_v == 0.0 and _hop == 0.0:
		return
	_hop_v -= 12.0 * delta
	_hop = maxf(0.0, _hop + _hop_v * delta)
	if _hop == 0.0 and _hop_v < 0.0:
		_hop_v = 0.0
