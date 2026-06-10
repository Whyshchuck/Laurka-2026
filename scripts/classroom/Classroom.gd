extends Node2D
class_name Classroom

@onready var pupils_node: Node = null
@onready var status_timer := $StatusTimer
@onready var moving_pupils_counter : Label = $MovingPupilsCounter
@onready var time_label: Label = $TimeLabel
@onready var score_label: LetterLabel = $ScoreLetterLabel

var game_started := false

var total_pupils := 0
var sitting_count := 0

const AlphabetOverlayScene := preload("res://minigames/alphabet_overlay.tscn")
var quiz_overlay: CanvasLayer = null
var alphabet_overlay: CanvasLayer = null

func _ready():
	print("Current game type: ", GameState.get_current_game_type_name())
	GameState.game_mode.on_enter(self)
	# Tryb "ganianie" (dawny HARD) wycofany — klasa startuje spokojnie w obu trybach.
	# TODO (Faza 1): usunąć resztę kodu chase (countdown, respawn, timer, licznik).
	# TODO (Faza 4): zachowanie trybu QUIZ (klik w dziecko -> pytania a/b/c).
	$PKamila/AnimationPlayer.play('idle')

	for pupil in get_pupils():
		total_pupils += 1


func _unhandled_input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				GameFlow.go_to_mode_selection()
			KEY_0:
				GameFlow.go_to_final_scene()
	
	if game_started and sitting_count == 24:
		GameFlow.go_to_final_scene()
	

	if not (event is InputEventMouseButton and event.pressed):
		return

	var mouse_pos = get_global_mouse_position()
	var clicked_characters := []

	var arrow_node = $ReturnArrow
	if Geometry2D.is_point_in_polygon(mouse_pos, arrow_node.polygon):
		GameFlow.go_to_mode_selection()
		return

	if clicked_characters.is_empty():
		# Pani Kamila nie jest w $Pupils — klik w nią otwiera minigrę alfabetu.
		# Rect liczony ręcznie, bo get_global_rect() nie uwzględnia scale.
		var kamila: TextureRect = $PKamila/TextureRect3
		var kamila_rect := Rect2(
			kamila.get_global_transform_with_canvas().origin, kamila.size * kamila.scale)
		if kamila_rect.has_point(mouse_pos):
			open_alphabet()
		return
	
func get_pupils() -> Array[Pupil]:
	var result: Array[Pupil] = []
	pupils_node = get_node("Pupils")
	
	for pupil in pupils_node.get_children():
		if pupil is Pupil:
			result.append(pupil)
	return result

func open_alphabet() -> void:
	# Otwórz minigrę alfabetu (klik w panią Kamilę, tylko jedna nakładka naraz).
	if alphabet_overlay and is_instance_valid(alphabet_overlay):
		return
	alphabet_overlay = AlphabetOverlayScene.instantiate()
	add_child(alphabet_overlay)
	alphabet_overlay.open_from($PKamila/TextureRect3)


func activate_pupils():
	status_timer.start()
	
	if not pupils_node:
		return

	for pupil in get_pupils():
		if pupil.is_available():
			pupil.pick_new_target()

func update_moving_pupil_count():
	if not pupils_node:
		return
	
	sitting_count = total_pupils

	for pupil in get_pupils():
		if pupil.is_moving():
			sitting_count -= 1
		
	var status_text := "Uczniowie na miejscach: %d / %d" % [sitting_count, total_pupils]
	
	moving_pupils_counter.text = status_text
	
	if not game_started:
		game_started = true
