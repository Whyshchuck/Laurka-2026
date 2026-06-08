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

const CORRECT_ANSWER_COLOR: Color = Color.GREEN
const WRONG_ANSWER_COLOR: Color = Color.RED
const DEFAULT_FLASH_DURATION: float = 0.5

var _closing := false

func _ready() -> void:
	# Stan początkowy przed animacją wejścia.
	dim.color.a = 0.0
	panel.modulate.a = 0.0
	close_button.modulate.a = 0.0
	dim.gui_input.connect(_on_dim_input)
	close_button.pressed.connect(close)
	for i in answer_buttons.size():
		var button: Button = answer_buttons[i]
		button.pressed.connect(_on_answer_pressed.bind(button))

func open_for_pupil(pupil) -> void:
	var data: Dictionary = QuizRepository.get_pupil_question(pupil.name)
	
	# Portret = grafika klikniętego dziecka, ustawiona tam, gdzie stoi w klasie.
	var src: TextureRect = pupil.texture_rect
	portrait.texture = src.texture
	portrait.global_position = src.get_global_transform_with_canvas().origin

	# Dane pytania (na razie puste placeholdery).
	question_label.text = str(data.get("question", ""))
	
	var answers: Array = data.get("answers", [])
	var correct_index = data.get("correct", -1)
	for i in answer_buttons.size():
		var button: Button = answer_buttons[i]
		var answer_text: String = str(answers[i]) if i < answers.size() else ""
		button.text = "%s)  %s" % [LETTERS[i], answer_text]
		button.set_meta("is_correct", correct_index == i)
		_reset_button_styles(button)

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

func _on_answer_pressed(clicked_button: Button) -> void:
	# TODO (Faza 4): sprawdzenie poprawnej odpowiedzi (quiz_correct_answer) + punktacja/feedback.
	var is_correct: bool = clicked_button.get_meta("is_correct")
	
	if is_correct:
		print("Correct answer.")
		flash_button(clicked_button, CORRECT_ANSWER_COLOR)
		close()
	else:
		flash_button(clicked_button, WRONG_ANSWER_COLOR)
		print("Wrong answer. Try again.")

func _reset_button_styles(button: Button) -> void:
	button.remove_theme_stylebox_override("normal")
	button.remove_theme_stylebox_override("hover")
	button.remove_theme_stylebox_override("pressed")
	button.remove_theme_color_override("font_color")
	button.remove_theme_color_override("font_hover_color")
	button.remove_theme_color_override("font_pressed_color")

func flash_button(button: Button, flash_color: Color, flash_duration: float = DEFAULT_FLASH_DURATION) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = flash_color

	# Apply temporary override
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	
	var tween := button.create_tween()
	tween.tween_interval(flash_duration)

	tween.tween_callback(func():
		_reset_button_styles(button)
	)
	
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
