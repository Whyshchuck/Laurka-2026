extends Node

enum GameMode { EASY, HARD }

var current_mode: GameMode = GameMode.EASY

func get_current_mode_name() -> String:
	return GameMode.keys()[current_mode]
