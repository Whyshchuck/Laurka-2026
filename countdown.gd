extends Node2D

@onready var label = $CountdownLabel
@onready var timer = $CountdownTimer

@export var current_count: int = 5
var zoom_duration = 0.8

func _ready():
	label.text = str(current_count)
	label.scale = Vector2(1, 1)
	label.modulate.a = 1.0
	label.pivot_offset = label.size / 2.0
	center_label()
	animate_number()
	timer.wait_time = 1.0
	timer.timeout.connect(_on_Timer_timeout)
	timer.start()

func _on_Timer_timeout():
	current_count -= 1
	if current_count == 0:
		timer.stop()
		label.hide()
		var parent = get_parent()
		# Call a function defined in the parent's script
		if parent.has_method("activate_pupils"):
			parent.activate_pupils()
	else:
		label.text = str(current_count)
		label.scale = Vector2(1, 1)
		label.modulate.a = 1.0
		center_label()
		animate_number()
	
func animate_number():
	var tween = create_tween()
	tween.tween_property(label, "scale", Vector2(20, 20), zoom_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, zoom_duration)

func center_label():
	label.position = get_viewport_rect().size / 2
