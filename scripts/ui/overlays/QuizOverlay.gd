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
@onready var name_label: LetterLabel = $NameLabel  # imię dziecka z naszych literek

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
	name_label.modulate.a = 0.0
	dim.gui_input.connect(_on_dim_input)
	close_button.pressed.connect(close)
	for button in answer_buttons:
		button.pressed.connect(_on_answer_pressed.bind(button))

func _input(event: InputEvent) -> void:
	# ESC zamyka quiz (i nie wyrzuca do wyboru trybu).
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()

func open_for_pupil(pupil) -> void:
	_pupil_name = pupil.name

	# Nagłówek z imieniem dziecka, złożony z naszych literek (tryb RANDOM).
	# Obcinamy końcowy inicjał nazwiska (np. "MichałA" -> "Michał", "KazikR" -> "Kazik").
	name_label.text = _strip_surname_initial(_pupil_name)

	# Portret = grafika klikniętego dziecka, ustawiona tam, gdzie stoi w klasie.
	var src: TextureRect = pupil.texture_rect
	portrait.texture = src.texture
	portrait.global_position = src.get_global_transform_with_canvas().origin
	
	_questions_count = QuizManager.get_pupil_questions_count(_pupil_name)
	
	_show_current_question()
	_animate_in()

func _strip_surname_initial(n: String) -> String:
	# Imiona dzieci o tym samym imieniu są odróżniane końcową wielką literą
	# (inicjałem nazwiska): "KazikR", "KazikL", "MichałA". Zwykłe imiona kończą się
	# małą literą, więc obcinamy tylko końcową WIELKĄ literę.
	if n.length() > 1:
		var last := n.substr(n.length() - 1)
		if last == last.to_upper() and last != last.to_lower():
			return n.substr(0, n.length() - 1)
	return n


func _show_current_question() -> void:
	var progress_text := ""
	var question_data = QuizManager.get_pupil_question(_pupil_name, _question_index)
	
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
	t.tween_property(name_label, "modulate:a", 1.0, ANIM_TIME).set_delay(0.15)

func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()

func _on_answer_pressed(clicked_button: Button) -> void:
	var is_correct: bool = clicked_button.get_meta("is_correct")
	# Każde kliknięcie to udzielona odpowiedź (y); prawidłowe zwiększa też x.
	GameState.register_answer(is_correct)

	if is_correct:
		await flash_button(clicked_button, CORRECT_ANSWER_COLOR)
		if _question_index + 1 < _questions_count:
			_question_index += 1
			_show_current_question()
		else:
			# Mark this pupil as answered so they cannot be quizzed again
			GameState.mark_pupil_answered(_pupil_name)
			await close()
	else:
		await flash_button(clicked_button, WRONG_ANSWER_COLOR)

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
	t.tween_property(name_label, "modulate:a", 0.0, ANIM_TIME)
	await t.finished
	# Odśwież licznik x/y (po każdym zamknięciu — także przez X lub kliknięcie w tło).
	if get_parent() and get_parent().has_method("update_quiz_score_label"):
		get_parent().update_quiz_score_label()
	queue_free()
