extends Node

# This script acts as a global QuizRepository (autoload/singleton).
# It is responsible for loading quiz data from a JSON file
# and providing questions for a specific pupil.


var _data: Dictionary = {}

# Safe fallback question returned when:
# - pupil has no entry
# - entry is invalid
# - data is missing

const EMPTY_QUESTION := {
	"question": "",
	"answers": ["", "", ""],
	"correct": 0
}

func _init() -> void:
	load_quiz_data()

func load_quiz_data(path: String = "res://quiz/quiz_data.json") -> void:
	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		push_error("Cannot open file: " + path)
		return

	var parsed = JSON.parse_string(file.get_as_text())

	if parsed is Dictionary:
		_data = parsed
	else:
		push_error("QuizRepository: Invalid JSON format")

func get_pupil_question(pupil_name: String) -> Dictionary:

	if _data.has(pupil_name):
		return _data[pupil_name]
	
	push_warning("No quiz for: " + pupil_name)
	return EMPTY_QUESTION	
	
