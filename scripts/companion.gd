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

## Before there's a fire, idle thoughts stay on the one thing that matters.
const FOX_COLD := [
	"My nose is so cold it's basically an ice cube with opinions.",
	"That old fire ring isn't going to look at itself.",
	"Sticks. Stones. Fire. It's not rocket science. It's ROCK science.",
]
const OTTER_COLD := [
	"Brrr... my toes are popsicles.",
	"A fire would be SO cozy right now. Just saying.",
	"I can help carry sticks! Little ones. Okay, one stick.",
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

enum State { SLEEPING, WAKING, FOLLOWING, FORAGING, RESTING, RESCUING, RIDING }
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
var _snack: Gatherable  # food on the ground he's trotting over to eat, when hungry
var _snacking := false  # this run is a snack run (the snack itself may be gone by now)
var _shove := Vector3.ZERO  # a hop back out of a fire
## Only for tests: walks straight into fires (pets normally steer around them).
var _careless := false


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
	["Vines hang off the mossy rocks. Strong as rope.", "The Otter will go NUTS for those."],
	["See the white logs? Birch. The bark peels right off.", "Burns even when it's damp. Nature's cheat code."],
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
	if state != State.FOLLOWING:
		body.lounging = false
	_update_hop(delta)
	_since_run += delta
	_update_needs(delta)
	if _shove.length_squared() > 0.01:
		body.position += _shove * delta
		_shove = _shove.lerp(Vector3.ZERO, 1.0 - exp(-5.0 * delta))
	if not _careless:
		_keep_off_fires(delta)
	_update_wet(delta)
	if state == State.RESCUING:
		_update_rescue(delta, player)
		return
	if state == State.RIDING:
		_update_riding(delta)
		return
	if state == State.FORAGING:
		_forage(delta, player)
		return
	_update_showing(player)
	if state != State.FOLLOWING:
		body.position.y = _ride_height(delta)
		return
	if not player.frozen:
		_forage_timer -= delta
		if _forage_timer <= 0.0:
			_start_run(player)
		_snack_check -= delta
		if _snack_check <= 0.0:
			_snack_check = 4.0
			if _gift_left_behind(player) or (hunger < SNACK_BELOW and _go_snack()):
				return
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
		body.lounging = false
		_wander_timer = 0.0  # a fresh spot next time he stops
		var back := -to_player.normalized()
		var beside := Vector3(-back.z, 0, back.x) * side
		goal = player.global_position + (back * 0.8 + beside * 0.6).normalized() * follow_distance
		speed = 6.5 if dist > 9.0 else 3.4
	elif _idle_time > 4.0:
		_antsy(delta, player)
		goal = _wander_point
		speed = 1.8
	if in_water:
		speed *= 0.55 if who == "fox" else 1.15  # the Fox paddles; the Otter zooms
	var step := goal - body.position
	step.y = 0.0
	if speed > 0.0 and step.length() > 0.3:
		var dir := _steer(step.normalized())
		body.position += dir * minf(speed * delta, step.length())
		var yaw := atan2(-dir.x, -dir.z)
		body.rotation.y = lerp_angle(body.rotation.y, yaw, 1.0 - exp(-8.0 * delta))
		body.moving = true
	else:
		body.moving = false
		var face := atan2(-to_player.x, -to_player.z)
		body.rotation.y = lerp_angle(body.rotation.y, face, 1.0 - exp(-2.0 * delta))
	body.position.y = _ride_height(delta)
	_hop_timer -= delta
	if _hop_timer <= 0.0:
		_hop_timer = _rng.randf_range(5.0, 14.0) if player_moving else _rng.randf_range(2.5, 6.0)
		if _hop == 0.0 and not body.lounging:
			_hop_v = _rng.randf_range(2.2, 3.4)


## Standing around a while: find a comfy spot off to his side, a few steps
## away, lie down there, and think out loud now and then. Every so often, get
## up and pick a new spot.
func _antsy(delta: float, player: Player) -> void:
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		_wander_timer = _rng.randf_range(35.0, 70.0)
		var base := player._yaw + (0.0 if side > 0.0 else PI)  # his side of the hero
		# Never curl up in the fire (or under the lean-to's roof): try a few
		# spots, swinging further round each time, and take the first clear one.
		for tries in 12:
			var a := base + _rng.randf_range(-0.7, 0.7) + (tries / 2) * 0.6 * (1.0 if tries % 2 == 0 else -1.0)
			_wander_point = player.global_position + Vector3(cos(a), 0, -sin(a)) * _rng.randf_range(2.4, 3.6)
			if _comfy(_wander_point):
				break
		body.lounging = false
	if Vector2(_wander_point.x - body.position.x, _wander_point.z - body.position.z).length() < 0.35:
		body.lounging = true
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = _rng.randf_range(20.0, 40.0)
		if get_tree().get_nodes_in_group("campfires").is_empty():
			say([(FOX_COLD if who == "fox" else OTTER_COLD).pick_random()])
			return
		if _thoughts.is_empty():
			_thoughts = (FOX_THOUGHTS if who == "fox" else OTTER_THOUGHTS).duplicate()
			_thoughts.shuffle()
		say([_thoughts.pop_back()])


## Ways of asking each question; one is picked each time the menu opens, so
## the meaning stays put but the words change a little.
const ASKS := {
	"feed": ["Here, have something to eat", "Hungry? I've got a snack for you", "Want something to munch on?", "I saved you a bite"],
	"fire": ["How do we make a fire?", "Any idea how to get a fire going?", "How do we start a fire, buddy?", "Can you help me make a fire?"],
	"safe": ["Any ideas how we stay safe tonight?", "How do we keep safe tonight?", "How do we stay snug tonight?", "Got a plan for tonight?"],
	"spark": ["Look what I found! Any ideas?", "Check this out! What can we make?", "Found something! Any ideas, inventor?", "What could we do with this?"],
	"build": ["What else could we build?", "Got any more inventions?", "What should we make next?", "Any new building ideas?"],
	"food": ["Can you sniff out some food?", "Smell anything tasty out there?", "Can that nose find us some food?", "Help me find something to eat?"],
	"ideas": ["Got any clever ideas?", "What do you think we should do?", "Any smart ideas, buddy?", "Got a tip for me?"],
	"feel": ["How are you holding up?", "You doing okay?", "How are you feeling, bud?", "Everything all right with you?"],
}
## The Otter's fire answer and his "what else" answer, a few ways each.
const OTTER_FIRE := [
	["The Fox found an old fire ring! Look at it, and you'll know how.", "Then sticks and stones. I'll do the cheering. Cheering is my job."],
	["Go look at the old fire ring the Fox found! It'll show you.", "Then we need sticks and stones. I'm in charge of cheering."],
	["The fire ring! The one the Fox found! Look at it and you'll get it.", "Sticks, stones, then FIRE. I'll cheer. I'm a great cheerer."],
]
const OTTER_MORE := [
	["Hmm... show me new stuff and I'll figure something out!", "My brain's like a toolbox. A fuzzy toolbox."],
	["Bring me something new and I'll invent a thing!", "My brain is a toolbox. A furry one."],
	["Find me new stuff and I'll think up something!", "Inventing is easy. You just need stuff. And a fuzzy brain."],
]


## What the hero can ask this one right now: [question, what happens].
## The Otter is the inventor (he teaches you things to build); the Fox finds
## food and has clever ideas.
func talk_options() -> Array:
	var out := []
	if not feed_options().is_empty():
		out.append([ASKS.feed.pick_random(), func(): hud._talk.open_menu("Feed the %s" % ("Fox" if who == "fox" else "Otter"), feed_options())])
	var before_fire := get_tree().get_nodes_in_group("campfires").is_empty()
	if who == "otter" and before_fire:
		# One thing at a time: until there's a fire, the fire is all he talks about.
		out.append([ASKS.fire.pick_random(), func(): say(OTTER_FIRE.pick_random())])
	elif who == "otter":
		if not Game.known.has("lean_to"):
			out.append([ASKS.safe.pick_random(), _teach_lean_to])
		if not Game.sparks.is_empty():
			out.append([ASKS.spark.pick_random(), _teach_spark])
		elif Game.known.has("lean_to"):
			out.append([ASKS.build.pick_random(), func(): say(OTTER_MORE.pick_random())])
	else:
		out.append([ASKS.food.pick_random(), request_food])
		out.append([ASKS.ideas.pick_random(), func():
			if get_tree().get_nodes_in_group("campfires").is_empty():
				say(FOX_TIPS[0])  # fire first; the rest can wait
				return
			say(FOX_TIPS[_tips_given % FOX_TIPS.size()])
			_tips_given += 1])
	var feelings: Array = FOX_FEELINGS if who == "fox" else OTTER_FEELINGS
	out.append([ASKS.feel.pick_random(), func():
		say([feelings[_feelings % feelings.size()]])
		_feelings += 1])
	return out


func _teach_lean_to() -> void:
	say(["Ooh, ooh! A lean-to!", "Lean sticks against a branch, then pile ferns on top. Ferns are the big floppy leaves. Lots of them out past our clearing.", "It's like a tiny roof. A tiny, AMAZING roof."])
	get_tree().create_timer(10.5).timeout.connect(func():
		Game.learn("lean_to", ["A lean-to. Sticks on a pole, ferns on top.", "And he's got more ideas where that came from."], "Otter"))


## What the Otter says when you show him something new, and what the hero
## thinks once it clicks.
const OTTER_LESSONS := {
	"torch_post": [
		["Vines! Okay okay okay. Take a stick, wrap birch bark around the top...", "...tie it on tight with a vine, and LIGHT it!", "A torch! Stick it in the ground. BOOM. Night light."],
		["A torch post. Stick, bark, vine.", "He comes up with this stuff so fast."]],
	"rain_catcher": [
		["Birch bark! Did you know it doesn't soak up water? I knew.", "Fold it into a bowl, prop it up on three sticks, tie them with a vine...", "...and it fills up with rain and dew! Free water! Drinky drinky."],
		["A rain catcher. Water, right at camp.", "Little genius. I mean it."]],
}


## Shown something new (vines, bark): the Otter works out what to make with it.
func _teach_spark() -> void:
	if Game.sparks.is_empty():
		return
	var id: String = Game.sparks.pop_front()
	var lesson: Array = OTTER_LESSONS[id]
	say(lesson[0])
	get_tree().create_timer(3.6 * lesson[0].size()).timeout.connect(func():
		Game.learn(id, lesson[1], "Otter"))


## Gets comfy by the fire (for the night passing) until follow() is called.
func rest_at(spot: Vector3, toward: Vector3) -> void:
	state = State.RESTING
	body.moving = false
	body.position = Vector3(spot.x, Game.ground_at(spot.x, spot.z), spot.z)
	var to := toward - spot
	body.rotation.y = atan2(-to.x, -to.z)


func follow() -> void:
	state = State.FOLLOWING
	_sitting_fire = null
	_showing = false
	body.halt()
	_idle_time = 0.0


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
				var dir := _steer(step.normalized())
				body.position += dir * minf(4.5 * delta, step.length())
				body.rotation.y = lerp_angle(body.rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-8.0 * delta))
				body.moving = true
			elif _run == Run.GOING and _snack_arrived():
				return
			elif _run == Run.GOING:
				_run = Run.SEARCHING
				_run_time = 0.0
				body.moving = false
				if who == "otter":
					Audio.play("splash_in", body.global_position, -4.0)
					Burns.wash_off(body)
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
	if _find.is_empty():
		state = State.FOLLOWING
		return
	if hunger < SNACK_BELOW:
		# Too hungry to share: finders keepers.
		_eat(Gatherable.KINDS[_find[0]].item, 2)
		Game.practice(Game.PET_KNACKS[who], 4.0)
		say([SELF_FED_LINES[who].pick_random()])
		state = State.FOLLOWING
		_since_run = 0.0
		return
	var away := body.position - player.global_position
	away.y = 0.0
	if away.length() > 4.0:
		body.position = player.global_position + away.normalized() * 2.0  # gave up chasing; catch up
		away = body.position - player.global_position
	var drop := player.global_position + away.normalized() * 1.1
	drop.y = Game.ground_at(drop.x, drop.z)
	_gift = Gatherable.spawn(body.get_parent(), drop, _find[0], _rng)
	Game.practice(Game.PET_KNACKS[who], 4.0)
	say([_find[2]])
	_hop_v = 3.0
	state = State.FOLLOWING
	_since_run = 0.0


## Going around trees and rocks instead of through them: looks a little way
## ahead at knee height and, if something's there, turns to whichever side is
## clear (trying the side it last turned to first, so it doesn't dither).
const LOOK_AHEAD := 1.3
const STEER_ANGLES := [0.6, 1.1, 1.6, 2.2]
var _steer_side := 1.0


func _steer(dir: Vector3) -> Vector3:
	if _clear(dir):
		return dir
	for angle in STEER_ANGLES:
		for side_sign in [_steer_side, -_steer_side]:
			var turned := dir.rotated(Vector3.UP, angle * side_sign)
			if _clear(turned):
				_steer_side = side_sign
				return turned
	return dir  # boxed in: push on and let the follow catch-up sort it out


func _clear(dir: Vector3) -> bool:
	var from := body.global_position + Vector3(0, 0.45, 0)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * LOOK_AHEAD, 1)
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if not _careless and _fire_ahead(from, dir):
		return false
	# Rising ground isn't in the way; tree trunks and rock faces are.
	return hit.is_empty() or (hit.normal as Vector3).y > 0.6


func _update_hop(delta: float) -> void:
	if _hop_v == 0.0 and _hop == 0.0:
		return
	_hop_v -= 12.0 * delta
	_hop = maxf(0.0, _hop + _hop_v * delta)
	if _hop == 0.0 and _hop_v < 0.0:
		_hop_v = 0.0


func _fire_ahead(from: Vector3, dir: Vector3) -> bool:
	for f in get_tree().get_nodes_in_group("campfires"):
		var c: Vector3 = (f as Node3D).global_position
		var along := clampf((c - from).dot(dir), 0.0, LOOK_AHEAD)
		var nearest := from + dir * along
		if Vector2(nearest.x - c.x, nearest.z - c.z).length() < 0.95:
			return true
	return false


# --- Fire ----------------------------------------------------------------------

## Out and about (not asleep, resting, or in a cutscene), so a fire can get him.
func can_burn() -> bool:
	return state == State.FOLLOWING or state == State.FORAGING


## Wandered into a fire: a yelp, a big hop back out, and a sooty smudge on
## the side that was nearest the flames.
func burn(from: Vector3) -> void:
	var away := Burns._away(from, body.global_position)
	_shove = away * 4.5
	health = maxf(10.0, health - 6.0)
	_hop_v = 4.2
	body.rotation.y = atan2(away.x, away.z)  # spins to look back at the fire
	Audio.play("elem_fire", body.global_position, -5.0, 1.3)
	FX.burst(body.global_position + Vector3.UP * 0.2, Color(1.0, 0.55, 0.15), 8, 2.0, 0.035)
	say([(Burns.FOX_LINES if who == "fox" else Burns.OTTER_LINES).pick_random()])
	var out := -away
	var spot: Vector3 = body.global_position + Vector3.UP * 0.3 + out * (0.12 if who == "fox" else 0.16)
	Burns.mark(body, spot, out, 0.06)


# --- Showing the way and sitting by the fire --------------------------------------

var _showing := false
var _sitting_fire: Node3D


## Trots over to `spot` and waits beside it until the hero comes to look.
func show_spot(spot: Vector3) -> void:
	state = State.RESTING
	_showing = true
	var d := spot - body.position
	d.y = 0.0
	var stand := spot - d.normalized() * 1.1
	stand.y = Game.ground_at(stand.x, stand.z)
	body.move_to(stand, maxf(d.length(), 0.5) / 3.2).tween_callback(func(): body.face(spot))


## Walks over and settles beside the fire, facing it, until follow().
func sit_by_fire(fire: Node3D, angle: float) -> void:
	_sitting_fire = fire
	_showing = false
	state = State.RESTING
	var spot := fire.global_position + Vector3(cos(angle), 0.0, sin(angle)) * 1.5
	spot.y = Game.ground_at(spot.x, spot.z)
	var d := spot - body.position
	body.move_to(spot, maxf(Vector2(d.x, d.z).length(), 0.5) / 3.0).tween_callback(func(): body.face(fire.global_position, 0.4))


# --- The raft --------------------------------------------------------------------
# A hop aboard when the hero climbs on, sitting in their spot as it goes (the
# Fox up front like a figurehead), and a hop off onto the dock or shore after him.

var _raft: Raft
var _raft_seat := Vector3.ZERO
var _board_from := Vector3.ZERO
var _board_t := 1.0


func ride(r: Raft, seat: Vector3) -> void:
	body.halt()
	_sitting_fire = null
	_showing = false
	_shake_timer = -1.0
	state = State.RIDING
	_raft = r
	_raft_seat = seat
	_board_from = body.position
	_board_t = 0.0
	body.moving = false


func hop_off(at: Vector3) -> void:
	_raft = null
	state = State.FOLLOWING
	body.position = Vector3(at.x, _floor_height(at.x, at.z), at.z)
	_hop_v = 2.6  # a little bounce as they land
	_idle_time = 0.0


func _update_riding(delta: float) -> void:
	if not is_instance_valid(_raft):
		state = State.FOLLOWING
		return
	_set_in_water(false)
	body.moving = false
	var seat := _raft.seat(_raft_seat)
	# A hop over (it can take a moment, from a few steps away), then ride along.
	_board_t = minf(1.0, _board_t + delta / 0.5)
	body.position = _board_from.lerp(seat, _board_t) + Vector3.UP * sin(_board_t * PI) * 0.7
	body.rotation.y = lerp_angle(body.rotation.y, _raft.rotation.y + (0.0 if who == "fox" else 0.4), 0.2)


## The ground, or a floor built over it (the little house's deck and boards).
func _floor_height(x: float, z: float) -> float:
	var h := Game.ground_at(x, z)
	for f in get_tree().get_nodes_in_group("floors"):
		h = maxf(h, f.floor_at(x, z))
	return h


func _update_showing(player: Player) -> void:
	if _showing and (player.global_position.distance_to(body.position) < 2.6 or Game.known.has("campfire")):
		_showing = false
		get_tree().create_timer(2.0).timeout.connect(func():
			if state == State.RESTING and not _sitting_fire:
				follow())


# --- Health and hunger -----------------------------------------------------------
# Shown on the HUD under the hero's needs. Hunger drains slowly while awake;
# fed, he heals over time. Starving never knocks him out (he's a kid's pet),
# it just wears his health down a little and he says so.

const HUNGER_TIME := 900.0  # seconds from full to empty
const FAVORITES := {
	"fox": ["Bird eggs", "Cooked eggs", "Grubs", "Toasted grubs"],
	"otter": ["Fish", "Roast fish", "Clams", "Steamed clams", "Crayfish", "Boiled crayfish"],
}
const HUNGRY_LINES := {
	"fox": ["My stomach is making whale noises. Feed me?", "I'm not saying I'm hungry. My stomach is saying it. Loudly."],
	"otter": ["I'm SO hungry... do we have any snacks?", "My tummy's grumbling. Grrr. That's my tummy, not me."],
}

var health := 100.0
var hunger := 100.0
var _hungry_nag := 30.0


func _update_needs(delta: float) -> void:
	if state == State.SLEEPING:
		return
	hunger = maxf(0.0, hunger - 100.0 / HUNGER_TIME * delta)
	if hunger > 30.0:
		health = minf(100.0, health + 1.0 * delta)
	elif hunger <= 0.0:
		health = maxf(25.0, health - 0.3 * delta)
	_hungry_nag -= delta
	if hunger < 30.0 and _hungry_nag <= 0.0 and state == State.FOLLOWING:
		_hungry_nag = 75.0
		say([HUNGRY_LINES[who].pick_random()])


## Eats `count` of a food: fills him up (favorites more) and heals a little.
## Returns whether it was a favorite.
func _eat(food: String, count := 1) -> bool:
	var fav: bool = FAVORITES[who].has(food)
	hunger = minf(100.0, hunger + Game.FOODS.get(food, 6.0) * count * (3.0 if fav else 2.0))
	health = minf(100.0, health + 8.0)
	Audio.play("gear_rustle", body.global_position, -8.0, 1.4)
	return fav


# Feeding themselves: you don't HAVE to feed them. Hungry, a pet eats the next
# thing he finds instead of bringing it back, and trots over to snack on food
# lying close by (theirs or anyone's). Handing them food still makes them
# happiest.

const SNACK_BELOW := 45.0  # hunger under this and he looks after himself
const SNACK_REACH := 12.0
const SNACK_KINDS := ["grubs", "mushrooms", "eggs", "fish", "crayfish", "clams"]
const SELF_FED_LINES := {
	"fox": ["Finders keepers. A growing fox needs snacks.", "I ate that one. Don't look at me like that. Next one's yours."],
	"otter": ["Sorry, I was SO hungry I ate it! I'll find you another one!", "Mmm! I saved you... none. Next one's yours, promise!"],
}
const SNACK_LINES := {
	"fox": ["Free snack on the ground. Five-second rule. ...Ish.", "Nobody was eating that. Now somebody is."],
	"otter": ["Ooh, leftovers! Yum!", "Snack time! Don't worry, I'm only having one."],
}
var _snack_check := 4.0

## The food he last brought you. Walk off and leave it, and he eats it himself.
var _gift: Gatherable
var _gift_snack := false  # this snack run is the gift you left behind
const GIFT_LEFT_AT := 16.0  # how far you get before it counts as left behind
const LEFT_BEHIND_LINES := {
	"fox": ["Fine. If you're not going to eat it, I'm not letting it go to waste.", "Your loss. Mmm. Very much your loss."],
	"otter": ["You forgot your snack! ...Okay, I'll eat it so it doesn't go to waste!", "Nobody leaves a good snack behind. Not on MY watch. Nom!"],
}


## You walked off without the food he brought you: he trots back and eats it.
func _gift_left_behind(player: Player) -> bool:
	if not is_instance_valid(_gift) or not _gift.available:
		_gift = null
		return false
	if _gift.global_position.distance_to(player.global_position) < GIFT_LEFT_AT:
		return false
	_snack = _gift
	_gift = null
	_gift_snack = true
	_snacking = true
	_run_spot = _snack.global_position
	_run = Run.GOING
	_run_time = 0.0
	state = State.FORAGING
	return true


## Heads for the nearest food lying close by. False if there's none.
func _go_snack() -> bool:
	var best: Gatherable = null
	var best_d := SNACK_REACH
	for node in get_tree().get_nodes_in_group("gatherables"):
		var g := node as Gatherable
		if not g.available or not SNACK_KINDS.has(g.kind):
			continue
		var d := g.global_position.distance_to(body.global_position)
		if d < best_d:
			best = g
			best_d = d
	if best == null:
		return false
	_snack = best
	_snacking = true
	_run_spot = best.global_position
	_run = Run.GOING
	_run_time = 0.0
	state = State.FORAGING
	return true


## At the snack (or it's gone): eats it and goes back to following. False
## when this run isn't a snack, so foraging carries on as usual.
func _snack_arrived() -> bool:
	if not _snacking:
		return false
	_snacking = false
	var g = _snack  # untyped: it may have been eaten (freed) already
	_snack = null
	body.moving = false
	state = State.FOLLOWING
	if is_instance_valid(g) and g.available:
		_eat(Gatherable.KINDS[g.kind].item, 2)
		g.queue_free()
		_hop_v = 3.0
		say([(LEFT_BEHIND_LINES if _gift_snack else SNACK_LINES)[who].pick_random()])
		_gift_snack = false
	else:
		_snack_check = 0.5  # beaten to it: look again soon
		_gift_snack = false
	return true


## Food in the backpack to hand over: [label, what happens] for the menu.
func feed_options() -> Array:
	var out := []
	for food in Game.FOODS:
		var count: int = Game.inventory.get(food, 0)
		if count > 0:
			var fav := " (his favorite!)" if FAVORITES[who].has(food) else ""
			out.append(["%s  (%d)%s" % [food, count, fav], func(): feed(food)])
	return out


func feed(food: String) -> void:
	if not Game.take_items(food, 1):
		return
	var fav := _eat(food)
	_hop_v = 3.0
	var cooked := Game.COOKS.values().has(food)
	var line: String
	if who == "fox":
		line = "Ooh, my favorite. You DO pay attention." if fav else ("Warm AND tasty? Fancy." if cooked else "Mmf. Not bad. Not bad at all.")
	else:
		line = "FISHY! You're the BEST!" if fav else ("Mmm, it's warm! Like a hug for my tummy!" if cooked else "Yum! Thank you!")
	say([line])


# --- Water -------------------------------------------------------------------------
# Deep enough and they swim: the Fox dog-paddles with just his head and back
# out; the Otter is at home in there, dives down alongside the hero when he
# swims under, and now and then just for fun. Climbing out they're soaked
# (dark, shiny fur, dripping) until they give a big shake.

const FOX_FLOAT := 0.42  # how far below the surface the Fox's paws hang
const OTTER_FLOAT := 0.2
const SHAKE_LINES := {
	"fox": ["Ugh. Wet fox smell. Nobody say anything.", "Fluffy again. Majestic, even."],
	"otter": ["Wheee! Again! Let's go again!", "Brrrr-r-r-r! Shaky shaky!"],
}
const SPLASHED_LINES := ["Hey! I was almost dry!", "Thanks. Really. I needed a second bath."]

var in_water := false
var wet := 0.0
var _swim_time := 0.0
var _shake_timer := -1.0
var _ripple_timer := 0.0
var _depth := 0.0  # the Otter: how far under the surface he is
var _dive_timer := 12.0
var _dive_left := 0.0


## Height the body rides at: the ground (plus any hop), or the water once
## it's too deep to stand.
func _ride_height(delta: float) -> float:
	var ground := _floor_height(body.position.x, body.position.z)
	var float_y := Game.WATER_LEVEL - (FOX_FLOAT if who == "fox" else OTTER_FLOAT)
	var swim := ground < float_y - 0.05
	_set_in_water(swim)
	if not swim:
		_depth = 0.0
		body.dive = 0.0
		return ground + _hop
	return float_y - (_otter_depth(delta, ground, float_y) if who == "otter" else 0.0)


## The Otter keeps the hero company under water, and dives for fun on his own.
func _otter_depth(delta: float, ground: float, float_y: float) -> float:
	var want := 0.0
	var p := Game.player
	if p and p.head_under() and body.position.distance_to(p.global_position) < 10.0:
		want = float_y - (p.global_position.y + 0.9)  # right alongside him
	elif state == State.FOLLOWING:
		_dive_timer -= delta
		if _dive_timer <= 0.0:
			_dive_timer = _rng.randf_range(10.0, 18.0)
			_dive_left = 2.4
			_hop_v = 0.0
			Audio.play("splash_in", body.global_position, -12.0, 1.5)
		if _dive_left > 0.0:
			_dive_left -= delta
			want = 1.3
	want = clampf(want, 0.0, maxf(0.0, float_y - ground - 0.3))
	var before := _depth
	_depth = move_toward(_depth, want, 2.2 * delta)
	body.dive = clampf((_depth - before) / maxf(delta, 0.0001) / 2.2, -1.0, 1.0)
	if _depth > 0.4 and _rng.randf() < delta * 1.5:
		FX.burst(body.global_position + Vector3.UP * 0.3, Color(0.85, 0.95, 1.0), 3, 0.8, 0.02)
	return _depth


func _set_in_water(swim: bool) -> void:
	if swim == in_water:
		return
	in_water = swim
	body.swimming = swim
	var surface := Vector3(body.position.x, Game.WATER_LEVEL, body.position.z)
	if swim:
		Audio.play("splash_in", surface, -8.0, 1.4)
		FX.burst(surface, Color(0.8, 0.95, 1.0), 10, 2.5, 0.05)
		Burns.wash_off(body)
		_hop_v = 0.0
		_hop = 0.0
	else:
		Audio.play("splash_out", surface, -6.0, 1.3)
		if _swim_time > 0.6:
			_shake_timer = 0.8  # a couple of steps up the bank, then the shake
	_swim_time = 0.0


func _update_wet(delta: float) -> void:
	if in_water:
		_swim_time += delta
		wet = 1.0
		_ripple_timer -= delta
		if body.moving and _ripple_timer <= 0.0 and _depth < 0.2:
			_ripple_timer = 0.35
			FX.burst(Vector3(body.position.x, Game.WATER_LEVEL, body.position.z), Color(0.8, 0.95, 1.0), 4, 1.2, 0.03)
	else:
		wet = maxf(0.0, wet - delta / 60.0)
		if wet > 0.5 and _rng.randf() < delta * 4.0:
			FX.burst(body.global_position + Vector3(0, 0.15, 0), Color(0.7, 0.85, 1.0), 1, 0.3, 0.02)
		if _shake_timer > 0.0:
			_shake_timer -= delta
			if _shake_timer <= 0.0:
				shake()
	body.set_wet(wet)


## A big shake from nose to tail. Anyone standing close gets sprayed.
func shake(talk := true) -> void:
	_shake_timer = -1.0
	body.shake_off()
	Audio.play("shake_off", body.global_position, 0.0, 1.0 if who == "fox" else 1.25)
	for k in 3:
		get_tree().create_timer(k * 0.25).timeout.connect(func():
			if is_instance_valid(body):
				FX.burst(body.global_position + Vector3.UP * 0.35, Color(0.75, 0.9, 1.0), 14, 3.5, 0.03))
	wet = minf(wet, 0.35)
	var p := Game.player
	if not talk:
		return
	if p and p.global_position.distance_to(body.position) < 2.2 and _rng.randf() < 0.6:
		get_tree().create_timer(0.9).timeout.connect(func(): hud.think([SPLASHED_LINES.pick_random()], 2.6))
	elif _rng.randf() < 0.4:
		say([SHAKE_LINES[who].pick_random()])


# --- Rescue --------------------------------------------------------------------
# The hero passed out under water: both swim out and take an arm each to tow
# him in. `offset` is where to swim beside him; `face` the way they pull.

var _rescue_offset := Vector3.ZERO
var _rescue_face := Vector3.FORWARD


func rescue(offset: Vector3, face: Vector3) -> void:
	state = State.RESCUING
	_sitting_fire = null
	_showing = false
	_shake_timer = -1.0
	body.halt()
	_rescue_offset = offset
	_rescue_face = face


func _update_rescue(delta: float, player: Player) -> void:
	var goal := player.global_position + _rescue_offset
	var step := goal - body.position
	step.y = 0.0
	var dist := step.length()
	if dist > 25.0:
		body.position = goal - step / dist * 6.0  # was off somewhere; comes running
		dist = 6.0
		step = goal - body.position
		step.y = 0.0
	var look := _rescue_face
	if dist > 0.2:
		var dir := step / dist
		body.position += dir * minf((6.0 if who == "otter" else 4.5) * delta, dist)
		body.moving = true
		if dist > 0.8:
			look = dir
	else:
		body.moving = false
	body.rotation.y = lerp_angle(body.rotation.y, atan2(-look.x, -look.z), 1.0 - exp(-8.0 * delta))
	body.position.y = _ride_height(delta)


## Fire is hot (they know): if one ends up too close (the hero walked them
## past it), they edge back out of it.
## A good spot to lie down: well clear of fires, torches and lean-tos.
func _comfy(spot: Vector3) -> bool:
	for group in [["campfires", 2.2], ["torches", 1.0], ["shelters", 2.0]]:
		for n in get_tree().get_nodes_in_group(group[0]):
			var c: Vector3 = (n as Node3D).global_position
			if Vector2(spot.x - c.x, spot.z - c.z).length() < group[1]:
				return false
	return true


func _keep_off_fires(delta: float) -> void:
	for f in get_tree().get_nodes_in_group("campfires") + get_tree().get_nodes_in_group("torches"):
		var c: Vector3 = (f as Node3D).global_position
		var off := Vector3(body.position.x - c.x, 0.0, body.position.z - c.z)
		var keep := 1.1 if f.is_in_group("campfires") else 0.5
		if off.length() < keep:
			body.position += (off.normalized() if off.length() > 0.01 else Vector3.RIGHT) * 2.5 * delta
