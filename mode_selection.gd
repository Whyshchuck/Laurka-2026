extends Control

@onready var easy_mode_button = get_node("EasyModeButton")
@onready var hard_mode_button = get_node("HardModeButton")

func _ready():
	easy_mode_button.pressed.connect(_on_easy_pressed)
	hard_mode_button.pressed.connect(_on_hard_pressed)

func _on_easy_pressed():
	Global.current_mode = Global.GameMode.EASY
	get_tree().change_scene_to_file("res://classroom.tscn")

func _on_hard_pressed():
	Global.current_mode = Global.GameMode.HARD
	get_tree().change_scene_to_file("res://classroom.tscn")
