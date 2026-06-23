extends CharacterBody2D

@onready var area: Area2D = $Area2D


func _ready():
	if area:
		area.input_event.connect(_on_area_input_event)

func _on_area_input_event(_viewport: Viewport,event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed:
		if GameState.current_type == GameState.GameType.WELCOME:
			get_node("/root/Classroom").open_alphabet()
