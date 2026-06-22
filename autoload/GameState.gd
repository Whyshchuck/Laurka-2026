extends Node

# Rename it to free up GameMode
enum GameType { WELCOME, QUIZ }

var current_type: GameType = GameType.WELCOME
var time_elapsed: float = 0
var quiz_correct: int = 0   # x — odpowiedzi prawidłowe
var quiz_answered: int = 0  # y — udzielone odpowiedzi (wszystkie)
var _answered_pupils := {} # set of pupil names answered this run

func reset() -> void:
	quiz_correct = 0
	quiz_answered = 0
	_answered_pupils.clear()
	time_elapsed = 0

func set_game_type(type: GameType) -> void:
	current_type = type
	
func get_current_game_type_name() -> String: 
	return GameType.keys()[current_type]

func register_answer(correct: bool) -> void:
	quiz_answered += 1
	if correct:
		quiz_correct += 1

func has_pupil_been_answered(pupil_name: String) -> bool:
	return _answered_pupils.has(pupil_name)

func mark_pupil_answered(pupil_name: String) -> void:
	_answered_pupils[pupil_name] = true

func get_quiz_score_text() -> String:
	# Wynik: x/y — prawidłowe / wszystkie udzielone odpowiedzi.
	return "Wynik: %d/%d" % [quiz_correct, quiz_answered]
