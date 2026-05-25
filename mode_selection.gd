extends Control

# Menu wyboru trybu (Laurka 2026).
# Dwa tryby: "To my!" (eksploracja klasy) i "Jak dobrze nas znasz?" (quiz).
# Napisy na przyciskach są PLACEHOLDERAMI — docelowo zastąpią je rysunki-napisy dzieci.

@onready var to_my_button: Button = $Buttons/ToMyButton
@onready var quiz_button: Button = $Buttons/QuizButton

var duration := 3.0
var interval := 0.1
var time_elapsed := 0.0
var timer: Timer = null

func _ready():
	to_my_button.pressed.connect(_on_to_my_pressed)
	quiz_button.pressed.connect(_on_quiz_pressed)
	rainbow_flash_and_hide()

func rainbow_flash_and_hide():
	time_elapsed = 0.0
	timer = Timer.new()
	timer.wait_time = interval
	timer.one_shot = false
	add_child(timer)
	timer.timeout.connect(_on_timer_timeout)
	timer.start()

func _on_timer_timeout():
	var node := $Node
	for child in node.get_children():
		if child is CanvasItem:
			child.modulate = Color(randf(), randf(), randf(), 1.0)
	time_elapsed += interval
	if time_elapsed >= duration:
		timer.stop()
		timer.queue_free()
		start_fade_out()
		start_fade_in()

func start_fade_out():
	var node := $Node
	for child in node.get_children():
		if child is CanvasItem:
			var tween := create_tween()
			tween.tween_property(
				child, "modulate:a", 0.0, 1.0
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func start_fade_in():
	var node := $Buttons
	for child in node.get_children():
		if child is CanvasItem:
			child.visible = true
			child.modulate.a = 0.0
			var tween := create_tween()
			tween.tween_property(
				child, "modulate:a", 1.0, 1.0
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _on_to_my_pressed():
	# Tryb "To my!" — eksploracja klasy (klik w dziecko -> mówi + animacja).
	Global.start_game(Global.GameMode.WELCOME)

func _on_quiz_pressed():
	# Tryb "Jak dobrze nas znasz?" — quiz o dzieciach.
	# Wchodzi do tej samej klasy; zachowanie quizu dochodzi w Fazie 4.
	Global.start_game(Global.GameMode.QUIZ)
