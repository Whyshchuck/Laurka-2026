extends Node2D

@onready var pupils_node: Node = null
@onready var status_timer := $StatusTimer
@onready var moving_pupils_counter : Label = $MovingPupilsCounter
@onready var time_label: Label = $TimeLabel

var game_started := false

var total_pupils := 0
var sitting_count := 0

const QuizOverlayScene := preload("res://quiz/quiz_overlay.tscn")
var quiz_overlay: CanvasLayer = null

func _ready():
	pupils_node = get_node("Pupils")  # Adjust path if Pupils is not a direct child
	print("Current mode: ", Global.get_current_mode_name())

	# Tryb "ganianie" (dawny HARD) wycofany — klasa startuje spokojnie w obu trybach.
	# TODO (Faza 1): usunąć resztę kodu chase (countdown, respawn, timer, licznik).
	# TODO (Faza 4): zachowanie trybu QUIZ (klik w dziecko -> pytania a/b/c).
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
	
	if Global.current_mode == Global.GameMode.QUIZ:
		open_quiz(top_character)
	else:
		top_character.on_click()
	

func open_quiz(pupil) -> void:
	# Otwórz nakładkę quizu dla klikniętego dziecka (tylko jedna naraz).
	if quiz_overlay and is_instance_valid(quiz_overlay):
		return
	quiz_overlay = QuizOverlayScene.instantiate()
	add_child(quiz_overlay)
	quiz_overlay.open_for_pupil(pupil)


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
