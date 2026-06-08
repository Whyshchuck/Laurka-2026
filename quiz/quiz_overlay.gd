extends CanvasLayer

# Nakładka quizu "Jak dobrze nas znasz?".
# Po kliknięciu w dziecko: przyciemnia tło klasy, sprite dziecka wjeżdża w lewo,
# z prawej pojawia się panel z pytaniem i 3 odpowiedziami (A/B/C).
# Obsługuje teraz wiele pytań dla jednego ucznia.

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

var _closing := false
var _pupil_name := ""
var _question_index: int = 0
var _questions_count: int = 0

func _ready() -> void:
	# Stan początkowy przed animacją wejścia.
	dim.color.a = 0.0
	panel.modulate.a = 0.0
	close_button.modulate.a = 0.0
	dim.gui_input.connect(_on_dim_input)
	close_button.pressed.connect(close)
	for button in answer_buttons:
		button.pressed.connect(_on_answer_pressed.bind(button))

func open_for_pupil(pupil) -> void:
	_pupil_name = pupil.name

	# Portret = grafika klikniętego dziecka, ustawiona tam, gdzie stoi w klasie.
	var src: TextureRect = pupil.texture_rect
	portrait.texture = src.texture
	portrait.global_position = src.get_global_transform_with_canvas().origin
	
	_questions_count = QuizRepository.get_pupil_questions_count(_pupil_name)
	
	_show_current_question()
	_animate_in()

func _show_current_question() -> void:
	var progress_text := ""
	var question_data = QuizRepository.get_pupil_question(_pupil_name, _question_index)
	
	if _questions_count > 1:
		progress_text = "[%d / %d]\n" % [_question_index + 1, _questions_count]
	question_label.text = "%s%s" % [progress_text, str(question_data.get("question", ""))]

	var answers: Array = question_data.get("answers", [])
	var correct_index = question_data.get("correct", -1)
	for i in answer_buttons.size():
		var button: Button = answer_buttons[i]
		var answer_text: String = str(answers[i]) if i < answers.size() else ""
		button.text = "%s)  %s" % [LETTERS[i], answer_text]
		button.set_meta("is_correct", correct_index == i)
		_reset_button_styles(button)

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
	var is_correct: bool = clicked_button.get_meta("is_correct")

	if is_correct:
		print("Correct answer.")
		await flash_button(clicked_button, CORRECT_ANSWER_COLOR)
		if _question_index + 1 < _questions_count:
			_question_index += 1
			_show_current_question()
		else:
			close()
	else:
		await flash_button(clicked_button, WRONG_ANSWER_COLOR)
		print("Wrong answer. Try again.")

func _reset_button_styles(button: Button) -> void:
	button.remove_theme_stylebox_override("normal")
	button.remove_theme_stylebox_override("hover")
	button.remove_theme_stylebox_override("pressed")
	button.remove_theme_color_override("font_color")
	button.remove_theme_color_override("font_hover_color")
	button.remove_theme_color_override("font_pressed_color")

func flash_button(button: Button, flash_color: Color, flash_duration: float = ANIM_TIME) -> Signal:
	"""Temporarily overrides the button's style to flash a color, then resets it after the duration."""
	var style := StyleBoxFlat.new()
	style.bg_color = flash_color

	# Apply temporary override
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)

	var tween := create_tween()
	tween.tween_interval(flash_duration)
	tween.tween_callback(_reset_button_styles.bind(button))

	return tween.finished
	

func close() -> void:
	"""Closes the quiz overlay with an animation, then frees it."""
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
