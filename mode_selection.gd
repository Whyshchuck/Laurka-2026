extends Control

@onready var easy_mode_button = get_node("EasyModeButton")
@onready var hard_mode_button = get_node("HardModeButton")

func _ready():
	easy_mode_button.pressed.connect(_on_easy_pressed)
	hard_mode_button.pressed.connect(_on_hard_pressed)

func _on_easy_pressed():
	Global.start_game(Global.GameMode.EASY)

func _on_hard_pressed():
	Global.start_game(Global.GameMode.HARD)
