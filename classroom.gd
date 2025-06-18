extends Node2D

@onready var pupils_node: Node = null
@onready var status_timer := $StatusTimer
@onready var moving_pupils_counter : Label = $MovingPupilsCounter

var total_pupils := 0
func _ready():
	pupils_node = get_node("Pupils")  # Adjust path if Pupils is not a direct child
	print("Current mode: ", Global.get_current_mode_name())
	
	# Load the on-screen countdown only in Hard mode 
	if Global.current_mode == Global.GameMode.HARD:
		var countdown_scene = preload("res://countdown.tscn")
		var new_scene = countdown_scene.instantiate()
		get_tree().current_scene.add_child(new_scene)
		
		status_timer.timeout.connect(update_moving_pupil_count)
		
	
	for pupil in pupils_node.get_children():
		if pupil is CharacterBody2D:
			total_pupils += 1

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://mode_selection.tscn")

func activate_pupils():
	status_timer.start()
	if not pupils_node:
		return

	for pupil in pupils_node.get_children():
		if pupil is CharacterBody2D and pupil.is_available():
			pupil.pick_new_target()

func update_moving_pupil_count():
	if not pupils_node:
		return
	
	
	var moving_count := 0

	for pupil in pupils_node.get_children():
		if pupil is CharacterBody2D and pupil.is_moving():
			moving_count += 1

	var status_text := "%d / %d" % [moving_count, total_pupils]
	#print(status_text)
	moving_pupils_counter.text = status_text
