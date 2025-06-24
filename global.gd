extends Node

enum GameMode { EASY, HARD }

var current_mode: GameMode = GameMode.EASY

func get_current_mode_name() -> String:
	return GameMode.keys()[current_mode]

func start_game(game_mode: GameMode) -> void:
	Global.current_mode = game_mode
	await Fader.fade_to_scene("res://classroom.tscn", 0.5)

func go_to_mode_selection() -> void:
	await Fader.fade_to_scene("res://mode_selection.tscn", 0.5)

func go_to_final_scene() -> void:
	await Fader.fade_to_scene("res://final.tscn", 0.5)
