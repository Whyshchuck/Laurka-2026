extends Node

# This script acts as a global QuizRepository (autoload/singleton).
# It is responsible for loading quiz data from a JSON file
# and providing questions for a specific pupil.

var _data: Dictionary = {}        # surowe dane z JSON (klucz jak w pliku)
var _index: Dictionary = {}       # znormalizowany klucz -> pytania (dopasowanie)

# Dopasowanie imion ignoruje wielkość liter i polskie znaki, więc klucze w JSON
# mogą być bez ogonków (np. "Lucja", "Michal", "Milosz").
const _PL := {
	"ą": "a", "ć": "c", "ę": "e", "ł": "l", "ń": "n",
	"ó": "o", "ś": "s", "ż": "z", "ź": "z",
}

# Safe fallback question returned when:
# - pupil has no entry
# - entry is invalid
# - data is missing

const EMPTY_QUESTION := [
	{
		"question": "",
		"answers": ["", "", ""],
		"correct": 0
	}
]

func _init() -> void:
	load_quiz_data()

func load_quiz_data(path: String = "res://data/quiz_data.json") -> void:
	"""Loads quiz data from a JSON file."""
	var file := FileAccess.open(path, FileAccess.READ)

	if file == null:
		push_error("Cannot open file: " + path)
		return

	var parsed = JSON.parse_string(file.get_as_text())

	if parsed is Dictionary:
		_data = parsed
		_rebuild_index()
	else:
		push_error("QuizRepository: Invalid JSON format")

static func _norm(s: String) -> String:
	# Klucz dopasowania: małe litery + zdjęte polskie znaki.
	var t := s.to_lower()
	for pl in _PL:
		t = t.replace(pl, _PL[pl])
	return t

func _rebuild_index() -> void:
	_index = {}
	for key in _data:
		_index[_norm(key)] = _data[key]

func get_pupil_questions(pupil_name: String) -> Array:
	"""Returns an array of questions for the given pupil name."""
	return _index.get(_norm(pupil_name), EMPTY_QUESTION)

func has_real_questions(pupil_name: String) -> bool:
	"""True, gdy uczeń ma wpis z co najmniej jednym NIEPUSTYM pytaniem."""
	var questions: Array = _index.get(_norm(pupil_name), [])
	for q in questions:
		if q is Dictionary and str(q.get("question", "")).strip_edges() != "":
			return true
	return false

func get_pupil_question(pupil_name: String, index: int = 0) -> Dictionary:
	"""
	Returns a specific question for the given pupil name and index. 
	Out of bounds index will return the first question.
	"""
	var questions = get_pupil_questions(pupil_name)
	#TODO: Should it return an empty array or the fallback question?
	if questions.size() == 0:
		push_warning("No quiz for: " + pupil_name)
		return EMPTY_QUESTION[0]

	if index < 0 or index >= questions.size():
		push_warning("Question index out of bounds for: %s (%d)" % [pupil_name, index])
		return questions[0]

	return questions[index]
	
func get_pupil_questions_count(pupil_name: String) -> int:
	"""Returns the number of questions available for the given pupil name."""
	return get_pupil_questions(pupil_name).size()
