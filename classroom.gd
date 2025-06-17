extends Node2D

var pupils_node: Node = null

func _ready():
	pupils_node = get_node("Pupils")  # Adjust path if Pupils is not a direct child
	print("Current mode: ", Global.get_current_mode_name())
	
	# Load the on-screen countdown only in Hard mode 
	if Global.current_mode == Global.GameMode.HARD:
		var countdown_scene = preload("res://countdown.tscn")
		var new_scene = countdown_scene.instantiate()
		get_tree().current_scene.add_child(new_scene)

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://mode_selection.tscn")

func activate_pupils():
	
	if not pupils_node:
		return

	for pupil in pupils_node.get_children():
		if pupil is CharacterBody2D and pupil.is_available():
			pupil.pick_new_target()
