extends Node

var duration: float= 3.0
var interval: float = 0.1

var _time_elapsed: float= 0.0
var _timer: Timer = null

var _target_node: Node
var _buttons_node: Node


func play(target_node: Node, buttons_node: Node) -> void:
	_target_node = target_node
	_buttons_node = buttons_node

	_start_timer()

func _start_timer() -> void:
	
	_time_elapsed = 0.0
	_timer = Timer.new()
	_timer.wait_time = interval
	_timer.one_shot = false
	
	add_child(_timer)
	
	_timer.timeout.connect(_on_timer_timeout)
	
	_timer.start()

func _on_timer_timeout():
	for child in _target_node.get_children():
		if child is CanvasItem:
			child.modulate = Color(randf(), randf(), randf(), 1.0)
	_time_elapsed += interval
	
	if _time_elapsed >= duration:
		_stop_timer()
		
		_fade_out(_target_node)
		_fade_in(_buttons_node)

func _stop_timer() -> void:
	if _timer:
		_timer.stop()
		_timer.queue_free()
		_timer = null

func _fade_out(node:Node) -> void:
	for child in node.get_children():
		if child is CanvasItem:
			var tween := create_tween()
			tween.tween_property(child, "modulate:a", 0.0, 1.0)\
				.set_trans(Tween.TRANS_SINE)\
				.set_ease(Tween.EASE_IN_OUT)

func _fade_in(node: Node):
	for child in node.get_children():
		if child is CanvasItem:
			child.visible = true
			child.modulate.a = 0.0
			var tween := create_tween()
			tween.tween_property(child, "modulate:a", 1.0, 1.0)\
				.set_trans(Tween.TRANS_SINE)\
				.set_ease(Tween.EASE_IN_OUT)
