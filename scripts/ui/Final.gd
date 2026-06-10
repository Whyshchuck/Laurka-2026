extends Control

@onready var restart_button = $RestartButton

func _ready() -> void:
	restart_button.pressed.connect(_on_restart_button_pressed)
	$AudioTadam.play()
	if GameState.current_type == GameState.GameType.QUIZ and GameState.time_elapsed:
		var time_elapsed: float = GameState.time_elapsed
		var minutes := int(time_elapsed) / 60
		var seconds := int(time_elapsed) % 60
		var milliseconds := int((time_elapsed - int(time_elapsed)) * 1000)

		$ResultLabel.text = "Twój wynik to: " + "%02d:%02d.%03d" % [minutes, seconds, milliseconds]
	
func _on_restart_button_pressed() -> void:
	SceneManager.go_to_mode_selection()
