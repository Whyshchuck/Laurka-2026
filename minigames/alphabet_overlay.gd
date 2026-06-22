extends CanvasLayer

# Minigra alfabetu (klik w panią Kamilę).
# Tło klasy się przyciemnia (jak w quizie), pani Kamila wjeżdża w lewo,
# a po prawej w losowej kolejności ustawiają się wszystkie 32 literki
# polskiego alfabetu na siatce 4x8. Zadanie: ułożyć je alfabetycznie
# (drag and drop — przeciągnięta literka zamienia się miejscem z literką
# w komórce, na którą ją upuścimy). Komórki z literką na dobrym miejscu
# podświetlają się na zielono.

@onready var dim: ColorRect = $Dim
# Portrait to "uchwyt" (Node2D) — wkładamy do niego rig pani Kamili, a tweenujemy
# pozycję i skalę uchwytu (rig centrowany tak, by jego środek leżał w (0,0)).
@onready var portrait: Node2D = $Portrait
@onready var cells_root: Control = $Cells
@onready var letters_root: Node2D = $Letters
@onready var win_label: Node2D = $WinLabel
@onready var win_audio: AudioStreamPlayer = $WinAudio
@onready var close_button: Button = $CloseButton

const DIM_ALPHA := 0.65
const ANIM_TIME := 0.45
# Rig pani Kamili wpasowywany jest w ten prostokąt (lewa kolumna, z dala od siatki
# liter zaczynającej się na x=560). Skala dobierana tak, by mieścił się w całości
# — więc żeby zmienić wielkość Kamili, wystarczy zmienić rozmiar tego prostokąta.
const PORTRAIT_RECT := Rect2(50.0, 330.0, 340.0, 520.0)
const KamilaRig := preload("res://rig/p_kamila_rig.tscn")

# Lewa ręka "pod bokiem": dłoń sięga IK-iem do biodra, łokieć wychodzi w bok (<).
# Cel = biodro przesunięte w BOK (ku barkowi) i lekko w GÓRĘ, żeby dłoń siadła na
# boku biodra, a nie na środku. Ułamki odległości bark–biodro:
const AKIMBO_HIP_SIDE := 0.99   # w bok (większe = dłoń bardziej z boku)
const AKIMBO_HIP_UP := 0.3      # w górę

# Tupanie lewą (ekranowo) stopą: rotacja StopaL od pozy stojącej do ~TAP_MAX,
# z powrotem do 0 (uderzenie). TAP_HZ = liczba tupnięć na sekundę.
const TAP_MAX_DEG := 40.0
const TAP_HZ := 2.0

const ALPHABET := "aąbcćdeęfghijklłmnńoóprsśtuwyzźż"  # 32 litery
const COLS := 4
const ROWS := 8
const CELL := 116.0
const GRID_ORIGIN := Vector2(560.0, 120.0)
const LETTER_HEIGHT := CELL * 0.66
const MAX_LETTER_W := CELL * 0.85
const DRAG_SCALE := 3

# indeks komórki -> { sprite: Sprite2D, char: String, base_scale: Vector2, tween: Tween }
var _tiles: Array = []
var _cell_panels: Array[Panel] = []
var _style_normal: StyleBoxFlat
var _style_correct: StyleBoxFlat

var _portrait_target := Vector2.ZERO   # docelowa pozycja uchwytu (środek rigu)
var _portrait_scale := 1.0             # docelowa skala uchwytu

# Kości rigu pani Kamili (do pozowania ramion na żywo).
var _rig: Node2D = null
var _arm_r_upper: Bone2D = null   # prawe (ekranowo) górne ramię — wskazuje kursor
var _arm_r_fore: Bone2D = null
var _arm_l_upper: Bone2D = null   # lewe (ekranowo) górne ramię — pod bokiem
var _arm_l_fore: Bone2D = null
var _arm_l_hand: Bone2D = null    # lewa dłoń (cel IK = biodro)
var _hip: Bone2D = null           # biodro (Biodra)
var _foot_l: Bone2D = null        # lewa stopa (tupanie)
var _foot_l_base := 0.0           # rotacja stopy w pozie stoi (baza tupania)
var _tap_time := 0.0

var _drag_idx := -1
var _intro_done := false
var _won := false
var _closing := false


func _ready() -> void:
	# Stan początkowy przed animacją wejścia.
	dim.color.a = 0.0
	cells_root.modulate.a = 0.0
	close_button.modulate.a = 0.0
	dim.gui_input.connect(_on_dim_input)
	close_button.pressed.connect(close)

	_style_normal = _make_cell_style(Color(1.0, 1.0, 1.0, 0.18))
	_style_correct = _make_cell_style(Color(0.45, 0.9, 0.45, 0.35))
	_build_cells()


func _input(event: InputEvent) -> void:
	# ESC zamyka minigrę (i nie wyrzuca do wyboru trybu).
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()


func _process(delta: float) -> void:
	if _rig == null or _closing:
		return
	# Lewa (ekranowo) ręka pod bokiem — dłoń sięga do biodra, łokieć w bok (<).
	if _arm_l_upper and _arm_l_fore and _arm_l_hand and _hip:
		_pose_akimbo(_arm_l_upper, _arm_l_fore, _arm_l_hand, _hip)
	# Tupanie lewą stopą: 0 -> ~40° -> 0 (abs(sin) daje ostry powrót = "tup").
	if _foot_l:
		_tap_time += delta
		var tap := absf(sin(_tap_time * PI * TAP_HZ))
		_foot_l.rotation = _foot_l_base + tap * deg_to_rad(TAP_MAX_DEG)
	# Prawa (ekranowo) ręka wskazuje kursor — proste ramię celuje w mysz.
	if _arm_r_upper and _arm_r_fore:
		_arm_r_fore.rotation = 0.0
		_aim_segment(_arm_r_upper, _arm_r_fore, _arm_r_upper.get_global_mouse_position())


func _aim_segment(bone: Bone2D, child: Bone2D, target: Vector2) -> void:
	# Obróć kość tak, by odcinek kość->dziecko celował w punkt świata `target`.
	var seg := child.global_position - bone.global_position
	if seg.length_squared() == 0.0:
		return
	bone.rotation += wrapf((target - bone.global_position).angle() - seg.angle(), -PI, PI)


func _pose_akimbo(upper: Bone2D, fore: Bone2D, hand: Bone2D, hip: Bone2D) -> void:
	# 2-kostny IK: dłoń (hand) ma sięgnąć biodra, z łokciem wypchniętym na zewnątrz.
	var s := upper.global_position
	var l1 := s.distance_to(fore.global_position)        # długości stałe (skala * rest)
	var l2 := fore.global_position.distance_to(hand.global_position)
	if l1 <= 0.0 or l2 <= 0.0:
		return
	# Cel: biodro przesunięte w bok (ku barkowi) i lekko w górę — dłoń na boku biodra.
	var sh_off := s - hip.global_position
	var t := hip.global_position + Vector2(sh_off.x * AKIMBO_HIP_SIDE, sh_off.y * AKIMBO_HIP_UP)
	var d := clampf(s.distance_to(t), absf(l1 - l2) + 1.0, l1 + l2 - 1.0)
	var base := (t - s).angle()
	var sh := acos(clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0))
	# Dwa rozwiązania (łokieć po dwóch stronach) — bierzemy łokieć bardziej w lewo
	# (na zewnątrz), żeby wyszedł kształt "<".
	var ea := s + l1 * Vector2.from_angle(base - sh)
	var eb := s + l1 * Vector2.from_angle(base + sh)
	var elbow := ea if ea.x <= eb.x else eb
	_aim_segment(upper, fore, elbow)
	_aim_segment(fore, hand, t)


func open_from(src: TextureRect) -> void:
	# Portret = rig pani Kamili. Startuje tam i w tym rozmiarze, w jakim stoi
	# w klasie (prostokąt liczony jak przy wykrywaniu kliknięć), a potem wjeżdża
	# w lewo i powiększa się, żeby wypełnić PORTRAIT_RECT.
	var rect := Rect2(src.get_global_transform_with_canvas().origin, src.size * src.scale)

	var rig := KamilaRig.instantiate() as Node2D
	var bbox := _rig_bbox(rig)
	# Wycentruj rig w uchwycie: jego środek (bbox) trafia w (0,0) uchwytu.
	rig.position = -bbox.get_center()
	portrait.add_child(rig)

	# Ciało w pozie "stoi" (zamrożonej), a ramiona pozujemy ręcznie w _process
	# (lewe pod bokiem, prawe wskazuje kursor) — dlatego seek+pause, żeby animacja
	# nie nadpisywała rąk co klatkę.
	_rig = rig
	var anim := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim:
		anim.play("k/stoi")
		anim.seek(0.0, true)
		anim.pause()
	_hip = rig.get_node_or_null("Skeleton2D/Biodra") as Bone2D
	var skel := "Skeleton2D/Biodra/Tulow/"
	_arm_r_upper = rig.get_node_or_null(skel + "RamieP") as Bone2D
	_arm_r_fore = rig.get_node_or_null(skel + "RamieP/PrzedramieP") as Bone2D
	_arm_l_upper = rig.get_node_or_null(skel + "RamieL") as Bone2D
	_arm_l_fore = rig.get_node_or_null(skel + "RamieL/PrzedramieL") as Bone2D
	_arm_l_hand = rig.get_node_or_null(skel + "RamieL/PrzedramieL/DlonL") as Bone2D
	_foot_l = rig.get_node_or_null("Skeleton2D/Biodra/UdoL/LydkaL/StopaL") as Bone2D
	if _foot_l:
		_foot_l_base = _foot_l.rotation  # poza "stoi" stopy = pozycja "0" tupania

	# Skala startowa: dopasowana wysokością do miejsca w klasie (jak w Classroom).
	var start_scale := 1.0
	if bbox.size.y > 0.0:
		start_scale = rect.size.y / bbox.size.y
	portrait.scale = Vector2(start_scale, start_scale)
	portrait.global_position = rect.get_center()

	# Cel: wpasowanie w PORTRAIT_RECT (cały rig, bez wychodzenia na siatkę liter).
	_portrait_scale = start_scale
	if bbox.size.x > 0.0 and bbox.size.y > 0.0:
		_portrait_scale = min(
			PORTRAIT_RECT.size.x / bbox.size.x, PORTRAIT_RECT.size.y / bbox.size.y)
	_portrait_target = PORTRAIT_RECT.get_center()

	_spawn_letters(rect.get_center())
	_animate_in()


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


# --- budowanie siatki i literek ---------------------------------------------

func _make_cell_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(14)
	return sb


func _build_cells() -> void:
	for i in ALPHABET.length():
		var panel := Panel.new()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.position = _cell_center(i) - Vector2(CELL, CELL) * 0.5 + Vector2(4.0, 4.0)
		panel.size = Vector2(CELL - 8.0, CELL - 8.0)
		panel.add_theme_stylebox_override("panel", _style_normal)
		cells_root.add_child(panel)
		_cell_panels.append(panel)


func _spawn_letters(from: Vector2) -> void:
	# Losowa permutacja liter alfabetu na komórkach siatki.
	var order := range(ALPHABET.length())
	order.shuffle()

	_tiles.resize(ALPHABET.length())
	for i in ALPHABET.length():
		var ch := String(ALPHABET[order[i]])
		var node: Node2D = null
		var tex: Texture2D = null

		# Losuj wariant; jeśli ten wariant ma dekor (np. a_3) — animowana scena,
		# inaczej zwykły sprite. Dzięki temu dekor obejmuje tylko wybrany wariant.
		var variants: Array = LetterLabel.get_variants(ch)
		if variants.is_empty():
			push_warning("AlphabetOverlay: brak sprite'a dla znaku '%s'" % ch)
			continue
		var vi := randi() % variants.size()

		# Literka ze sceną dekoru (ruchome elementy) — jak w LetterLabel.
		# Scena trafia do "uchwytu" przesuniętego tak, żeby środek literki
		# wypadał w (0,0) — kafle są pozycjonowane środkiem na komórce.
		var decor := LetterLabel.get_variant_decor(ch, vi)
		if decor:
			var inst := decor.instantiate() as Node2D
			var lit := inst.get_node_or_null("Litera") as Sprite2D
			if lit != null and lit.texture != null:
				tex = lit.texture
				node = Node2D.new()
				node.add_child(inst)
				inst.position = -tex.get_size() / 2.0
			else:
				inst.free()

		if node == null:
			var sprite := Sprite2D.new()
			sprite.texture = variants[vi]
			tex = sprite.texture
			node = sprite

		node.position = from
		node.scale = Vector2.ZERO
		letters_root.add_child(node)

		var s := LETTER_HEIGHT / tex.get_height()
		if tex.get_width() * s > MAX_LETTER_W:
			s = MAX_LETTER_W / tex.get_width()
		_tiles[i] = {
			"sprite": node,
			"char": ch,
			"base_scale": Vector2(s, s),
			"tween": null,
		}


func _cell_center(i: int) -> Vector2:
	var col := i % COLS
	@warning_ignore("integer_division")
	var row := i / COLS
	return GRID_ORIGIN + Vector2(col + 0.5, row + 0.5) * CELL


func _cell_at(pos: Vector2) -> int:
	var local := (pos - GRID_ORIGIN) / CELL
	if local.x < 0.0 or local.y < 0.0 or local.x >= COLS or local.y >= ROWS:
		return -1
	return int(local.y) * COLS + int(local.x)


# --- animacja wejścia / wyjścia ----------------------------------------------

func _animate_in() -> void:
	var t := create_tween().set_parallel(true)
	t.tween_property(dim, "color:a", DIM_ALPHA, ANIM_TIME).set_trans(Tween.TRANS_SINE)
	t.tween_property(portrait, "global_position", _portrait_target, ANIM_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(portrait, "scale", Vector2(_portrait_scale, _portrait_scale), ANIM_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(cells_root, "modulate:a", 1.0, ANIM_TIME).set_delay(0.15)
	t.tween_property(close_button, "modulate:a", 1.0, ANIM_TIME).set_delay(0.15)

	# Literki wylatują od pani Kamili na swoje komórki, jedna po drugiej.
	for i in _tiles.size():
		var tile = _tiles[i]
		if tile == null:
			continue
		var delay := 0.25 + i * 0.03
		t.tween_property(tile.sprite, "position", _cell_center(i), 0.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
		t.tween_property(tile.sprite, "scale", tile.base_scale, 0.4).set_delay(delay)

	await t.finished
	_intro_done = true
	_update_hints()


func close() -> void:
	if _closing:
		return
	_closing = true
	var t := create_tween().set_parallel(true)
	t.tween_property(dim, "color:a", 0.0, ANIM_TIME)
	t.tween_property(portrait, "modulate:a", 0.0, ANIM_TIME)
	t.tween_property(cells_root, "modulate:a", 0.0, ANIM_TIME)
	t.tween_property(letters_root, "modulate:a", 0.0, ANIM_TIME)
	t.tween_property(win_label, "modulate:a", 0.0, ANIM_TIME)
	t.tween_property(close_button, "modulate:a", 0.0, ANIM_TIME)
	await t.finished
	queue_free()


# --- drag and drop -----------------------------------------------------------

func _on_dim_input(event: InputEvent) -> void:
	if _closing or not _intro_done:
		return
	if _won:
		# Po wygranej klik gdziekolwiek zamyka minigrę.
		if event is InputEventMouseButton and event.pressed:
			close()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_start_drag(event.position)
		else:
			_end_drag(event.position)
	elif event is InputEventMouseMotion and _drag_idx != -1:
		_tiles[_drag_idx].sprite.position = event.position


func _start_drag(pos: Vector2) -> void:
	if _drag_idx != -1:
		return
	var idx := _cell_at(pos)
	if idx == -1 or _tiles[idx] == null:
		return
	_drag_idx = idx
	var tile: Dictionary = _tiles[idx]
	tile.sprite.z_index = 100
	tile.sprite.position = pos
	_kill_tween(tile)
	tile.tween = create_tween()
	tile.tween.tween_property(tile.sprite, "scale", tile.base_scale * DRAG_SCALE, 0.12)


func _end_drag(pos: Vector2) -> void:
	if _drag_idx == -1:
		return
	var src := _drag_idx
	_drag_idx = -1
	_tiles[src].sprite.z_index = 0

	var dst := _cell_at(pos)
	if dst != -1 and dst != src and _tiles[dst] != null:
		# Zamiana miejscami z literką w komórce docelowej.
		var tmp = _tiles[src]
		_tiles[src] = _tiles[dst]
		_tiles[dst] = tmp
		_settle(dst)
	_settle(src)

	_update_hints()
	_check_win()


func _settle(i: int) -> void:
	# Dosuń literkę (z animacją) na środek jej komórki.
	var tile = _tiles[i]
	if tile == null:
		return
	_kill_tween(tile)
	tile.tween = create_tween().set_parallel(true)
	tile.tween.tween_property(tile.sprite, "position", _cell_center(i), 0.18) \
		.set_trans(Tween.TRANS_SINE)
	tile.tween.tween_property(tile.sprite, "scale", tile.base_scale, 0.18)


func _kill_tween(tile: Dictionary) -> void:
	if tile.tween and tile.tween.is_valid():
		tile.tween.kill()


# --- podpowiedzi i wygrana -----------------------------------------------------

func _update_hints() -> void:
	# Komórki z literką na właściwym miejscu robią się zielone.
	for i in _tiles.size():
		var correct: bool = _tiles[i] != null and _tiles[i].char == String(ALPHABET[i])
		_cell_panels[i].add_theme_stylebox_override(
			"panel", _style_correct if correct else _style_normal)


func _check_win() -> void:
	for i in _tiles.size():
		if _tiles[i] == null or _tiles[i].char != String(ALPHABET[i]):
			return
	_won = true
	_celebrate()


func _celebrate() -> void:
	win_label.visible = true
	win_audio.play()
	# Fala radości: literki kolejno podskakują.
	for i in _tiles.size():
		var tile = _tiles[i]
		_kill_tween(tile)
		tile.tween = create_tween()
		tile.tween.tween_interval(i * 0.05)
		tile.tween.tween_property(tile.sprite, "scale", tile.base_scale * 1.35, 0.18) \
			.set_trans(Tween.TRANS_SINE)
		tile.tween.tween_property(tile.sprite, "scale", tile.base_scale, 0.18) \
			.set_trans(Tween.TRANS_SINE)
