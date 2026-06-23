extends Node2D

@onready var pupils_node: Node = null
@onready var status_timer := $StatusTimer
@onready var moving_pupils_counter : Label = $MovingPupilsCounter
@onready var time_label: Label = $TimeLabel
@onready var score_label: LetterLabel = $ScoreLetterLabel
@onready var score_backdrop: Sprite2D = $ScoreBackdrop
@onready var kamila_rig: Node2D = $PKamila/Rig

var game_started := false

var total_pupils := 0
var sitting_count := 0

const QuizOverlayScene := preload("res://scenes/ui/overlays/QuizOverlay.tscn")
const AlphabetOverlayScene := preload("res://minigames/alphabet_overlay.tscn")
var quiz_overlay: CanvasLayer = null
var alphabet_overlay: CanvasLayer = null
var alphabet_sfx: AudioStreamPlayer = null  # jingiel przy otwarciu minigry alfabetu

func _ready():
	update_quiz_score_label()

	# Dźwięk "tadadadam" przy otwarciu minigry alfabetu (klik w panią Kamilę).
	# load() z zabezpieczeniem: jeśli Godot jeszcze nie zaimportował ogg, gra
	# ruszy bez crasha, a dźwięk włączy się po imporcie.
	alphabet_sfx = AudioStreamPlayer.new()
	var sfx_stream: Resource = load("res://audio/tadadadam.ogg")
	if sfx_stream:
		alphabet_sfx.stream = sfx_stream
	add_child(alphabet_sfx)

	# Tryb "ganianie" (dawny HARD) wycofany — klasa startuje spokojnie w obu trybach.
	# TODO (Faza 1): usunąć resztę kodu chase (countdown, respawn, timer, licznik).
	# TODO (Faza 4): zachowanie trybu QUIZ (klik w dziecko -> pytania a/b/c).
	# Pani Kamila to teraz rig (Skeleton2D + mesh) zamiast sprite'a.
	# Dopasuj rig do obszaru, w którym dawniej stała (TextureRect3), i odpal idle.
	_fit_kamila_rig()
	var anim := kamila_rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim:
		anim.play("k/stoi")  # własna poza "stoi" pani Kamili (biblioteka "k")

	for pupil in get_pupils():
		total_pupils += 1
		pupil.pupil_clicked.connect(open_quiz)
		pupil.setup_rig()  # uczeń z rigiem -> pokaż rig w pozie "stand"

	_report_missing_quiz()


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

	var arrow_node = $ReturnArrow
	if Geometry2D.is_point_in_polygon(mouse_pos, arrow_node.polygon):
		GameFlow.go_to_mode_selection()
		return

func get_pupils() -> Array[Pupil]:
	var result: Array[Pupil] = []
	pupils_node = get_node("Pupils")
	
	for pupil in pupils_node.get_children():
		if pupil is Pupil:
			result.append(pupil)
	return result

func open_quiz(pupil) -> void:
	# Otwórz nakładkę quizu dla klikniętego dziecka (tylko jedna naraz).
	if quiz_overlay and is_instance_valid(quiz_overlay):
		return
	# Prevent reopening quiz for a pupil that's already been answered
	if GameState.has_pupil_been_answered(pupil.name):
		return
	quiz_overlay = QuizOverlayScene.instantiate()
	add_child(quiz_overlay)
	quiz_overlay.open_for_pupil(pupil)


func _report_missing_quiz() -> void:
	# Walidacja przy starcie: kto z uczniów nie ma jeszcze (niepustych) pytań.
	var missing: Array[String] = []
	for pupil in get_pupils():
		if not QuizManager.has_real_questions(pupil.name):
			missing.append(String(pupil.name))
	if missing.is_empty():
		print("[Quiz] Wszyscy uczniowie (%d) mają pytania ✔" % total_pupils)
	else:
		print("[Quiz] Brak pytań dla %d/%d: %s" % [
			missing.size(), total_pupils, ", ".join(missing)])


func _fit_kamila_rig() -> void:
	# Wpasuj rig pani Kamili tam, gdzie i w rozmiarze, w jakim był dawny widoczny
	# sprite ($PKamila/Sprite2D) — żeby Kamila była tej samej wielkości co wcześniej.
	# Skala wg wysokości, stopy na dole, wyśrodkowane w poziomie.
	if not kamila_rig:
		return
	var spr: Sprite2D = $PKamila/Sprite2D
	var frame := Vector2(
		spr.texture.get_width() / float(spr.hframes),
		spr.texture.get_height() / float(spr.vframes))
	var disp := frame * spr.scale.abs()       # rozmiar dawnego sprite'a na ekranie
	var target := Rect2(spr.global_position - disp * 0.5, disp)  # sprite jest wyśrodkowany
	var bbox := _rig_bbox(kamila_rig)
	if bbox.size.y <= 0.0:
		return
	var s := target.size.y / bbox.size.y
	kamila_rig.scale = Vector2(s, s)
	var bottom_center_local := Vector2(bbox.position.x + bbox.size.x * 0.5, bbox.end.y)
	var target_bottom_center := Vector2(target.position.x + target.size.x * 0.5, target.end.y)
	kamila_rig.global_position = target_bottom_center - s * bottom_center_local


static func _rig_bbox(rig: Node2D) -> Rect2:
	# Prostokąt otaczający mesh rigu (w przestrzeni lokalnej rigu).
	var poly := rig.get_node_or_null("Polygon2D") as Polygon2D
	if poly == null or poly.polygon.is_empty():
		return Rect2()
	var pts := poly.polygon
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return Rect2(poly.position + r.position * poly.scale, r.size * poly.scale)


func open_alphabet() -> void:
	# Otwórz minigrę alfabetu (klik w panią Kamilę, tylko jedna nakładka naraz).
	if alphabet_overlay and is_instance_valid(alphabet_overlay):
		return
	if alphabet_sfx and alphabet_sfx.stream:
		alphabet_sfx.play()
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

func update_quiz_score_label() -> void:
	if not score_label:
		return
	var is_quiz := GameState.current_type == GameState.GameType.QUIZ
	score_label.visible = is_quiz
	score_label.text = GameState.get_quiz_score_text()
	if score_backdrop:
		score_backdrop.visible = is_quiz
