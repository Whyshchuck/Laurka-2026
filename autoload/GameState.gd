extends Node

enum GameMode { WELCOME, QUIZ }

var current_mode: GameMode = GameMode.WELCOME
var time_elapsed: float = 0
var total_score: int = 0
var _answered_pupils := {} # set of pupil names answered this run

func reset() -> void:
	total_score = 0
	_answered_pupils.clear()
	time_elapsed = 0

func set_mode(mode: GameMode) -> void:
	current_mode = mode
	
func get_current_mode_name() -> String: 
	return GameMode.keys()[current_mode]

func add_quiz_point() -> void:
	total_score += 1

func has_pupil_been_answered(pupil_name: String) -> bool:
	return _answered_pupils.has(pupil_name)

func mark_pupil_answered(pupil_name: String) -> void:
	_answered_pupils[pupil_name] = true

func get_quiz_score_text() -> String:
	return "Wynik: %d" % total_score
