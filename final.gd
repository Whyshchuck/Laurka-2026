extends Control

@onready var restart_button = $RestartButton

func _ready() -> void:
	restart_button.pressed.connect(_on_restart_button_pressed)
	$AudioTadam.play()
	if Global.current_mode == Global.GameMode.HARD and Global.time_elapsed:
		var minutes := int(Global.time_elapsed) / 60
		var seconds := int(Global.time_elapsed) % 60
		var milliseconds := int((Global.time_elapsed - int(Global.time_elapsed)) * 1000)

		$ResultLabel.text = "Twój wynik to: " + "%02d:%02d.%03d" % [minutes, seconds, milliseconds]
	
func _on_restart_button_pressed() -> void:
	Global.go_to_mode_selection()
