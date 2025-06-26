extends Node2D

@onready var pupils_node: Node = null
@onready var status_timer := $StatusTimer
@onready var moving_pupils_counter : Label = $MovingPupilsCounter
@onready var time_label: Label = $TimeLabel

var game_started := false

var total_pupils := 0
var sitting_count := 0

func _ready():
	pupils_node = get_node("Pupils")  # Adjust path if Pupils is not a direct child
	print("Current mode: ", Global.get_current_mode_name())
	
	# Load the on-screen countdown only in Hard mode 
	if Global.current_mode == Global.GameMode.HARD:
		var countdown_scene = preload("res://countdown.tscn")
		var new_scene = countdown_scene.instantiate()
		get_tree().current_scene.add_child(new_scene)
		$AudioIntro.play()
		$PKamila/AnimationPlayer.play('freak_out')
		status_timer.timeout.connect(update_moving_pupil_count)
	else:
		$PKamila/AnimationPlayer.play('idle')	
	
	for pupil in pupils_node.get_children():
		if pupil is CharacterBody2D:
			total_pupils += 1

func _unhandled_input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				Global.go_to_mode_selection()
			KEY_0:
				Global.go_to_final_scene()
	
	if game_started and sitting_count == 24:
		Global.go_to_final_scene()
	

	if not (event is InputEventMouseButton and event.pressed):
		return

	var mouse_pos = get_global_mouse_position()
	var clicked_characters := []

	var arrow_node = $ReturnArrow
	if Geometry2D.is_point_in_polygon(mouse_pos, arrow_node.polygon):
		Global.go_to_mode_selection()
		return

	for node in $Pupils.get_children():
		if node is CharacterBody2D and node.texture_rect.get_global_rect().has_point(mouse_pos):
			clicked_characters.append(node)

	if clicked_characters.is_empty():
		return

	# Sortuj po z_index malejąco (czyli najwyższy na początku)
	clicked_characters.sort_custom(func(a, b): return a.position.y > b.position.y)
	print(clicked_characters)
	var top_character = clicked_characters[0]
	
	top_character.on_click()
	

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
	
	sitting_count = 24

	for pupil in pupils_node.get_children():
		if pupil is CharacterBody2D and pupil.is_moving():
			sitting_count -= 1
		
	var status_text := "Uczniowie na miejscach: %d / %d" % [sitting_count, total_pupils]
	
	moving_pupils_counter.text = status_text
	
	if not game_started:
		game_started = true


func _process(delta: float) -> void:
	if Global.current_mode == Global.GameMode.HARD and game_started:
		Global.time_elapsed += delta
		#var minutes := int(Global.time_elapsed) / 60
		#var seconds := int(Global.time_elapsed) % 60
		#var milliseconds := int((Global.time_elapsed - int(Global.time_elapsed)) * 1000)
#
		#time_label.text = "%02d:%02d.%03d" % [minutes, seconds, milliseconds]
		
