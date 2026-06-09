extends Node

enum GameMode { WELCOME, QUIZ }

var current_mode: GameMode = GameMode.WELCOME
var time_elapsed: float = 0
var total_score: int = 0
var _answered_pupils := {} # set of pupil names answered this run


func get_current_mode_name() -> String:
	return GameMode.keys()[current_mode]

func start_game(game_mode: GameMode) -> void:
	time_elapsed = 0
	Global.current_mode = game_mode
	if game_mode == GameMode.QUIZ:
		reset()
	await SceneManager.change_scene("res://scenes/classroom/Classroom.tscn", 0.5)

func go_to_mode_selection() -> void:
	await SceneManager.change_scene("res://mode_selection.tscn", 0.5)

func go_to_final_scene() -> void:
	await SceneManager.change_scene("res://scenes/ui/Final.tscn", 0.5)

func add_quiz_point() -> void:
	total_score += 1


func has_pupil_been_answered(pupil_name: String) -> bool:
	return _answered_pupils.has(pupil_name)


func mark_pupil_answered(pupil_name: String) -> void:
	_answered_pupils[pupil_name] = true

func get_quiz_score_text() -> String:
	return "Wynik: %d" % total_score

func reset() -> void:
	total_score = 0
	_answered_pupils.clear()
