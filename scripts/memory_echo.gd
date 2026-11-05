class_name MemoryEcho
extends CanvasLayer
## A Memory Echo played over the world: the screen washes white, a short
## half-remembered scene from the dream plays (the dream scene, in its own
## little world), then it washes back to where you stood. Any key skips.

signal finished(skipped: bool)

const DREAM := preload("res://scenes/dream.tscn")

var echo := ""
var _white: ColorRect
var _view: SubViewportContainer
var _started := false
var _done := false
var _mouse := Input.MOUSE_MODE_CAPTURED


static func play(parent: Node, which: String) -> MemoryEcho:
	var e := MemoryEcho.new()
	e.layer = 60
	e.echo = which
	parent.add_child(e)
	return e


func _ready() -> void:
	_mouse = Input.mouse_mode
	_white = ColorRect.new()
	_white.color = Color(1.0, 0.98, 0.93, 0.0)
	_white.set_anchors_preset(Control.PRESET_FULL_RECT)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_white)
	var tw := create_tween()
	tw.tween_property(_white, "color:a", 1.0, 1.6)
	tw.tween_callback(_start_dream)


func _start_dream() -> void:
	_view = SubViewportContainer.new()
	_view.stretch = true
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	move_child(_view, 0)  # under the white, which fades away once it's running
	var sub := SubViewport.new()
	sub.own_world_3d = true
	_view.add_child(sub)
	var dream := DREAM.instantiate()
	dream.set_meta("echo", echo)
	dream.connect("echo_done", _end.bind(false))
	sub.add_child(dream)
	_started = true
	# The dream starts on its own white, so this hand-over can't be seen.
	create_tween().tween_property(_white, "color:a", 0.0, 0.4)


func _input(event: InputEvent) -> void:
	var key := event is InputEventKey and event.is_pressed() and not event.is_echo()
	var click := event is InputEventMouseButton and event.is_pressed()
	if key or click:
		get_viewport().set_input_as_handled()
		if _started:
			_end(true)


func _end(skipped: bool) -> void:
	if _done:
		return
	_done = true
	var tw := create_tween()
	tw.tween_property(_white, "color:a", 1.0, 0.5 if skipped else 0.2)
	tw.tween_callback(func():
		_view.queue_free()
		Input.mouse_mode = _mouse
		finished.emit(skipped))
	tw.tween_property(_white, "color:a", 0.0, 2.2).set_delay(0.3)
	tw.tween_callback(queue_free)
