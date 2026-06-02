extends CanvasLayer

# Nakładka quizu "Jak dobrze nas znasz?".
# Po kliknięciu w dziecko: przyciemnia tło klasy, sprite dziecka wjeżdża w lewo,
# z prawej pojawia się panel z pytaniem i 3 odpowiedziami (A/B/C).
# Na razie pytania/odpowiedzi są PUSTE (placeholder) — chodzi o zobaczenie mechaniki.

@onready var dim: ColorRect = $Dim
@onready var portrait: TextureRect = $Portrait
@onready var panel: Panel = $Panel
@onready var question_label: Label = $Panel/QuestionLabel
@onready var answer_buttons: Array[Button] = [
	$Panel/AnswerA,
	$Panel/AnswerB,
	$Panel/AnswerC,
]
@onready var close_button: Button = $CloseButton

const DIM_ALPHA := 0.65
const ANIM_TIME := 0.45
const PORTRAIT_TARGET := Vector2(60.0, 360.0)  # docelowa pozycja sprite'a (lewa strona)
const LETTERS := ["A", "B", "C"]

var _closing := false

func _ready() -> void:
	# Stan początkowy przed animacją wejścia.
	dim.color.a = 0.0
	panel.modulate.a = 0.0
	close_button.modulate.a = 0.0
	dim.gui_input.connect(_on_dim_input)
	close_button.pressed.connect(close)
	for i in answer_buttons.size():
		answer_buttons[i].pressed.connect(_on_answer_pressed.bind(i))

func open_for_pupil(pupil) -> void:
	var data: Dictionary = QuizRepository.get_pupil_question(pupil.name)
	
	# Portret = grafika klikniętego dziecka, ustawiona tam, gdzie stoi w klasie.
	var src: TextureRect = pupil.texture_rect
	portrait.texture = src.texture
	portrait.global_position = src.get_global_transform_with_canvas().origin

	# Dane pytania (na razie puste placeholdery).
	question_label.text = str(data.get("question", ""))
	
	var answers: Array = data.get("answers", [])
	
	for i in answer_buttons.size():
		var ans := ""
		if i < answers.size():
			ans = str(answers[i])
		answer_buttons[i].text = "%s)  %s" % [LETTERS[i], ans]

	_animate_in()

func _animate_in() -> void:
	var t := create_tween().set_parallel(true)
	t.tween_property(dim, "color:a", DIM_ALPHA, ANIM_TIME).set_trans(Tween.TRANS_SINE)
	t.tween_property(portrait, "global_position", PORTRAIT_TARGET, ANIM_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(panel, "modulate:a", 1.0, ANIM_TIME).set_delay(0.15)
	t.tween_property(close_button, "modulate:a", 1.0, ANIM_TIME).set_delay(0.15)

func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()

func _on_answer_pressed(_index: int) -> void:
	# TODO (Faza 4): sprawdzenie poprawnej odpowiedzi (quiz_correct_answer) + punktacja/feedback.
	close()

func close() -> void:
	if _closing:
		return
	_closing = true
	var t := create_tween().set_parallel(true)
	t.tween_property(dim, "color:a", 0.0, ANIM_TIME)
	t.tween_property(panel, "modulate:a", 0.0, ANIM_TIME)
	t.tween_property(close_button, "modulate:a", 0.0, ANIM_TIME)
	t.tween_property(portrait, "modulate:a", 0.0, ANIM_TIME)
	await t.finished
	queue_free()
