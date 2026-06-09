extends Control

# Menu wyboru trybu (Laurka 2026).
# Dwa tryby: "To my!" (eksploracja klasy) i "Jak dobrze nas znasz?" (quiz).
# Napisy na przyciskach są PLACEHOLDERAMI — docelowo zastąpią je rysunki-napisy dzieci.

@onready var to_my_button: Button = $Buttons/ToMyButton
@onready var quiz_button: Button = $Buttons/QuizButton

@onready var animator = $IntroAnimator
@onready var animated_node = $Node
@onready var buttons_node = $Buttons

func _ready():
	to_my_button.pressed.connect(_on_to_my_pressed)
	quiz_button.pressed.connect(_on_quiz_pressed)
	animator.play(animated_node, buttons_node)


func _on_to_my_pressed():
	# Tryb "To my!" — eksploracja klasy (klik w dziecko -> mówi + animacja).
	GameFlow.start_game(GameState.GameMode.WELCOME)

func _on_quiz_pressed():
	# Tryb "Jak dobrze nas znasz?" — quiz o dzieciach.
	# Wchodzi do tej samej klasy; zachowanie quizu dochodzi w Fazie 4.
	GameFlow.start_game(GameState.GameMode.QUIZ)
