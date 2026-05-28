extends Node2D

@onready var pupils_node: Node = null

const QuizOverlayScene := preload("res://quiz/quiz_overlay.tscn")
var quiz_overlay: CanvasLayer = null

func _ready():
	pupils_node = get_node("Pupils")
	print("Current mode: ", Global.get_current_mode_name())

	# TODO (Faza 4): zachowanie trybu QUIZ (klik w dziecko -> pytania a/b/c).
	if has_node("PKamila/AnimationPlayer"):
		$PKamila/AnimationPlayer.play('idle')

func _unhandled_input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				Global.go_to_mode_selection()
	
	if not (event is InputEventMouseButton and event.pressed):
		return

	var mouse_pos = get_global_mouse_position()
	var clicked_characters := []

	var arrow_node = get_node_or_null("ReturnArrow")
	if arrow_node and Geometry2D.is_point_in_polygon(mouse_pos, arrow_node.polygon):
		Global.go_to_mode_selection()
		return

	for node in $Pupils.get_children():
		if node is CharacterBody2D and node.texture_rect.get_global_rect().has_point(mouse_pos):
			clicked_characters.append(node)

	if clicked_characters.is_empty():
		return

	# Sortuj po z_index malejąco (czyli najwyższy na początku)
	clicked_characters.sort_custom(func(a, b): return a.position.y > b.position.y)
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
