extends Node2D

@onready var pupils_node: Node = null
@onready var status_timer := $StatusTimer
@onready var moving_pupils_counter : Label = $MovingPupilsCounter
@onready var time_label: Label = $TimeLabel
@onready var score_label: LetterLabel = $ScoreLetterLabel
@onready var score_backdrop: Sprite2D = $ScoreBackdrop
@onready var kamila_rig: Node2D = $PKamila/Rig
@onready var camera: Camera2D = $Camera2D

var game_started := false

const INTRO_WAVE_TIME := 2.2  # ile sekund uczniowie machają, zanim usiądą
const SCORE_LETTERS_RELOAD := 15.0  # co ile sekund licznik (quiz) cyklicznie losuje literki

# --- Pinch-zoom (mobile) ---
const ZOOM_MIN := 1.0          # 1.0 = pełny kadr klasy
const ZOOM_MAX := 3.0          # maks. przybliżenie
const TAP_MOVE_MAX := 24.0     # ruch palca > to = przeciąg, nie tap
var _use_touch := false        # po 1. dotyku przechodzimy na obsługę dotykową
var _touches := {}             # index palca -> pozycja (ekran)
var _pinch_prev_dist := 0.0
var _pinch_prev_mid := Vector2.ZERO
var _tap_candidate := false
var _tap_start := Vector2.ZERO
var _cam_home := Vector2.ZERO  # bazowa pozycja kamery (kadr przy zoomie 1)

var total_pupils := 0
var sitting_count := 0

const QuizOverlayScene := preload("res://scenes/ui/overlays/QuizOverlay.tscn")
const AlphabetOverlayScene := preload("res://minigames/alphabet_overlay.tscn")
var quiz_overlay: CanvasLayer = null
var alphabet_overlay: CanvasLayer = null
var alphabet_sfx: AudioStreamPlayer = null  # jingiel przy otwarciu minigry alfabetu

func _ready():
	_cam_home = camera.position
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
		pupil.setup_rig()  # uczeń z rigiem -> pokaż rig w pozie "stand"
		# Start klasy: macha własną animacją, potem siada (i potem wstaje on hover).
		pupil.intro_wave_then_sit(INTRO_WAVE_TIME)

	_report_missing_quiz()

func _unhandled_input(event):
	# Dotyk (mobile): dwa palce = pinch-zoom, jeden palec = tap (=klik).
	if event is InputEventScreenTouch:
		_use_touch = true
		_handle_touch(event)
		return
	if event is InputEventScreenDrag:
		_handle_drag(event)
		return

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
	if _use_touch:
		return  # na dotyku klik obsługuje tap (_handle_touch), nie emulowana mysz

	_do_click(get_global_mouse_position())


# --- Dotyk: pinch-zoom + tap -------------------------------------------------

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_tap_candidate = true
			_tap_start = event.position
		elif _touches.size() >= 2:
			_tap_candidate = false      # dwa palce -> to nie klik, tylko pinch
			_pinch_prev_dist = 0.0
			_update_pinch()             # zapamiętaj startowy rozstaw/środek
	else:
		_touches.erase(event.index)
		if _touches.is_empty():
			if _tap_candidate:
				# tap = klik; pozycję ekranu przeliczamy na świat (uwzględnia zoom)
				var world := get_viewport().get_canvas_transform().affine_inverse() * event.position
				_do_click(world)
			_tap_candidate = false
		_pinch_prev_dist = 0.0          # przelicz pinch od nowa po zmianie liczby palców


func _handle_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	_touches[event.index] = event.position
	if _touches.size() >= 2:
		_update_pinch()
	elif _tap_candidate and event.position.distance_to(_tap_start) > TAP_MOVE_MAX:
		_tap_candidate = false          # palec się przesunął -> nie tap


func _update_pinch() -> void:
	var keys := _touches.keys()
	if keys.size() < 2:
		return
	var p0: Vector2 = _touches[keys[0]]
	var p1: Vector2 = _touches[keys[1]]
	var dist := p0.distance_to(p1)
	var mid := (p0 + p1) * 0.5
	if _pinch_prev_dist > 0.0 and dist > 0.0:
		var z_old := camera.zoom.x
		var z_new := clampf(z_old * dist / _pinch_prev_dist, ZOOM_MIN, ZOOM_MAX)
		var half := get_viewport_rect().size * 0.5
		# Punkt świata pod poprzednim środkiem zostaje, potem dosuwamy do bieżącego.
		var world_anchor := (_pinch_prev_mid - half) / z_old + camera.position
		var pos_new := world_anchor - (mid - half) / z_new
		# Pan tylko w obrębie pierwotnego kadru (przy zoomie 1 kamera stoi w domu).
		var max_pan := half * (1.0 - 1.0 / z_new)
		pos_new.x = clampf(pos_new.x, _cam_home.x - max_pan.x, _cam_home.x + max_pan.x)
		pos_new.y = clampf(pos_new.y, _cam_home.y - max_pan.y, _cam_home.y + max_pan.y)
		camera.zoom = Vector2(z_new, z_new)
		camera.position = pos_new
	_pinch_prev_dist = dist
	_pinch_prev_mid = mid


func _do_click(mouse_pos: Vector2) -> void:
	var clicked_characters := []

	var arrow_node = $ReturnArrow
	# polygon jest w LOKALNYCH współrzędnych węzła (a węzeł ma offset position),
	# więc mysz przeliczamy do tej samej przestrzeni — inaczej klik jest przesunięty.
	if Geometry2D.is_point_in_polygon(arrow_node.to_local(mouse_pos), arrow_node.polygon):
		GameFlow.go_to_mode_selection()
		return

	# Klik w kota Oliwki (siedzi na biurku Kamili) — odsyła go z powrotem.
	# Sprawdzamy przed Kamilą, bo kot siedzi w obrębie jej klikalnego prostokąta.
	var oliwka := get_node_or_null("Pupils/Oliwka")
	if oliwka and oliwka.has_method("try_click_cat") and oliwka.try_click_cat(mouse_pos):
		return

	# Klik w iglo -> parada pingwinów (wychodzą drzwiami, obchodzą salę, kryją się za iglo).
	var igloo := get_node_or_null("Igloo") as Sprite2D
	if igloo and igloo.texture:
		var ig_size := igloo.texture.get_size() * igloo.scale.abs()
		if Rect2(igloo.global_position - ig_size * 0.5, ig_size).has_point(mouse_pos):
			_penguin_parade()
			return

	for node in get_pupils():
		if node.texture_rect.get_global_rect().has_point(mouse_pos):
			clicked_characters.append(node)

	if clicked_characters.is_empty():
		# Pani Kamila nie jest w $Pupils — klik w nią otwiera minigrę alfabetu.
		# Rect liczony ręcznie, bo get_global_rect() nie uwzględnia scale.
		var kamila: TextureRect = $PKamila/TextureRect3
		# Rect w przestrzeni ŚWIATA (jak mouse_pos i uczniowie), ze skalą.
		# NIE _with_canvas — to dawało piksele EKRANU (po transformacie canvas),
		# więc w HTML5/przy skalowaniu okna klik się rozjeżdżał i Kamila była
		# nieklikalna. get_global_transform() = świat + skala.
		var kt := kamila.get_global_transform()
		var kamila_rect := Rect2(kt.origin, kamila.size * kt.get_scale())
		if kamila_rect.has_point(mouse_pos):
			open_alphabet()
		return

	# Sortuj po z_index malejąco (czyli najwyższy na początku)
	clicked_characters.sort_custom(func(a, b): return a.position.y > b.position.y)
	var top_character = clicked_characters[0]
	
	if GameState.current_type == GameState.GameType.QUIZ:
		open_quiz(top_character)
	else:
		top_character.on_click()
	
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
	# W quizie literki licznika cyklicznie losują się co 15 s (CYCLE zamiast RANDOM).
	score_label.cycle_interval = SCORE_LETTERS_RELOAD
	score_label.variant_mode = LetterLabel.VariantMode.CYCLE if is_quiz else LetterLabel.VariantMode.RANDOM
	score_label.text = GameState.get_quiz_score_text()
	if score_backdrop:
		score_backdrop.visible = is_quiz


# --- parada pingwinów (klik w iglo) ------------------------------------------
# Trzy pingwiny wychodzą drzwiami w 3-sekundowych odstępach, obchodzą salę po
# zadanych punktach i na końcu chowają się ZA iglo (z-index pod iglo) i znikają.

const PENGUIN_TEX := [
	"res://sprites/pingwin_1.png",
	"res://sprites/pingwin_2.png",
	"res://sprites/pingwin_3.png",
]
const PENGUIN_PATH := [
	Vector2(818, 488),   # drzwi — pojawienie się
	Vector2(729, 1063),
	Vector2(300, 1101),
	Vector2(304, 239),
	Vector2(806, 246),
	Vector2(818, 391),   # za iglo — zniknięcie
]
const PENGUIN_SFX := "res://audio/sondangsirait419-pinguin-220042.mp3"
const PENGUIN_INTERVAL := 3.0   # odstęp między kolejnymi pingwinami
const PENGUIN_SPEED := 220.0    # prędkość marszu (px/s)
const PENGUIN_HEIGHT := 150.0   # wysokość pingwina na ekranie
const PENGUIN_WADDLE_DEG := 10.0  # kąt kołysania na boki (jak pingwin)
const PENGUIN_WADDLE_T := 0.18    # czas jednego przechyłu (mniejszy = szybsze dreptanie)

var _penguins_marching := false


func _penguin_parade() -> void:
	if _penguins_marching:
		return  # parada już trwa — nie dubluj
	_penguins_marching = true
	for i in PENGUIN_TEX.size():
		_spawn_penguin(i)
		await get_tree().create_timer(PENGUIN_INTERVAL).timeout
		if not is_inside_tree():
			return
	_penguins_marching = false  # wszystkie wystartowały (idą własnymi korutynami)


func _spawn_penguin(idx: int) -> void:
	var tex: Texture2D = load(PENGUIN_TEX[idx % PENGUIN_TEX.size()])
	if tex == null:
		return
	var p := Sprite2D.new()
	p.texture = tex
	# offset w górę o pół wysokości: node.position = STOPY (dół sprajta), nie środek.
	# Dzięki temu punkty trasy to pozycje stóp, y-sort liczy się po stopach, a
	# kołysanie obraca się wokół stóp.
	p.offset = Vector2(0.0, -tex.get_height() * 0.5)
	var base_scale := PENGUIN_HEIGHT / float(maxi(tex.get_height(), 1))
	p.scale = Vector2(base_scale, base_scale)
	p.position = PENGUIN_PATH[0]
	p.modulate.a = 0.0
	# Do węzła Pupils (y_sort_enabled) — pingwiny sortują się głębią z uczniami:
	# wyżej (mniejszy y) = za uczniami, niżej = przed. Iglo (z=1) jest nad całym
	# Pupils (z=0), więc na końcu wchodzą „za iglo" same z siebie.
	$Pupils.add_child(p)
	_play_penguin_sfx()
	_walk_penguin(p, base_scale)


func _walk_penguin(p: Sprite2D, base_scale: float) -> void:
	# Pojawienie się w drzwiach.
	var fin := create_tween()
	fin.tween_property(p, "modulate:a", 1.0, 0.4)
	await fin.finished
	if not is_instance_valid(p):
		return
	# Kołysanie na boki jak pingwin — rotacja drepcze w lewo-prawo przez cały marsz.
	var waddle := create_tween().set_loops()
	waddle.tween_property(p, "rotation", deg_to_rad(PENGUIN_WADDLE_DEG), PENGUIN_WADDLE_T) \
		.set_trans(Tween.TRANS_SINE)
	waddle.tween_property(p, "rotation", deg_to_rad(-PENGUIN_WADDLE_DEG), PENGUIN_WADDLE_T) \
		.set_trans(Tween.TRANS_SINE)
	# Marsz po kolejnych punktach; pingwin domyślnie patrzy w prawo.
	for i in range(1, PENGUIN_PATH.size()):
		var from: Vector2 = PENGUIN_PATH[i - 1]
		var to: Vector2 = PENGUIN_PATH[i]
		if absf(to.x - from.x) > 1.0:
			p.scale.x = base_scale * signf(to.x - from.x)
		# Głębią steruje y_sort węzła Pupils (po bieżącym y) — sam ruch pozycji wystarcza.
		var seg := create_tween()
		seg.tween_property(p, "position", to, from.distance_to(to) / PENGUIN_SPEED)
		await seg.finished
		if not is_instance_valid(p):
			return
	# Za iglo — znika (kołysanie stop, rotacja do pionu).
	if waddle.is_valid():
		waddle.kill()
	p.rotation = 0.0
	var out := create_tween()
	out.tween_property(p, "modulate:a", 0.0, 0.4)
	await out.finished
	if is_instance_valid(p):
		p.queue_free()


func _play_penguin_sfx() -> void:
	var pl := AudioStreamPlayer.new()
	pl.stream = load(PENGUIN_SFX)
	add_child(pl)
	pl.play()
	pl.finished.connect(pl.queue_free)
