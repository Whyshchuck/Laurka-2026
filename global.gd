extends Node

enum GameMode { EASY, HARD }

var current_mode: GameMode = GameMode.EASY

func get_current_mode_name() -> String:
	return GameMode.keys()[current_mode]

func start_game(game_mode: GameMode) -> void:
	Global.current_mode = game_mode
	get_tree().change_scene_to_file("res://classroom.tscn")

func go_to_mode_selection() -> void:
	get_tree().change_scene_to_file("res://mode_selection.tscn")

func go_to_final_scene() -> void:
	get_tree().change_scene_to_file("res://final.tscn")
