extends Control

@onready var restart_button = $RestartButton

func _ready() -> void:
	restart_button.pressed.connect(_on_restart_button_pressed)
	$AudioTadam.play()
	
func _on_restart_button_pressed() -> void:
	Global.go_to_mode_selection()
