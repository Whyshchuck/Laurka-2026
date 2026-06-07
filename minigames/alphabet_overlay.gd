extends CanvasLayer

# Minigra alfabetu (klik w panią Kamilę).
# Tło klasy się przyciemnia (jak w quizie), pani Kamila wjeżdża w lewo,
# a po prawej w losowej kolejności ustawiają się wszystkie 32 literki
# polskiego alfabetu na siatce 4x8. Zadanie: ułożyć je alfabetycznie
# (drag and drop — przeciągnięta literka zamienia się miejscem z literką
# w komórce, na którą ją upuścimy). Komórki z literką na dobrym miejscu
# podświetlają się na zielono.

@onready var dim: ColorRect = $Dim
@onready var portrait: TextureRect = $Portrait
@onready var cells_root: Control = $Cells
@onready var letters_root: Node2D = $Letters
@onready var win_label: Node2D = $WinLabel
@onready var win_audio: AudioStreamPlayer = $WinAudio
@onready var close_button: Button = $CloseButton

const DIM_ALPHA := 0.65
const ANIM_TIME := 0.45
const PORTRAIT_TARGET := Vector2(80.0, 260.0)   # docelowa pozycja pani Kamili (lewa strona)
const PORTRAIT_MAX := Vector2(460.0, 860.0)     # maksymalny rozmiar portretu po powiększeniu

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


func open_from(src: TextureRect) -> void:
	# Portret = grafika pani Kamili; startuje tam, gdzie stoi w klasie,
	# w rozmiarze, w jakim jest tam wyświetlana (size * scale, bo TextureRect3
	# ma niejednolitą skalę, której get_global_rect() nie uwzględnia),
	# a przy przesunięciu tylko jednolicie się powiększa.
	var rect := Rect2(src.get_global_transform_with_canvas().origin, src.size * src.scale)
	portrait.texture = src.texture
	portrait.global_position = rect.position
	portrait.size = rect.size
	_spawn_letters(rect.get_center())
	_animate_in()


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

		# Literka ze sceną dekoru (ruchome elementy) — jak w LetterLabel.
		# Scena trafia do "uchwytu" przesuniętego tak, żeby środek literki
		# wypadał w (0,0) — kafle są pozycjonowane środkiem na komórce.
		var decor := LetterLabel.get_decor(ch)
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
			var variants: Array = LetterLabel.get_variants(ch)
			if variants.is_empty():
				push_warning("AlphabetOverlay: brak sprite'a dla znaku '%s'" % ch)
				continue
			var sprite := Sprite2D.new()
			sprite.texture = variants[randi() % variants.size()]
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
	t.tween_property(portrait, "global_position", PORTRAIT_TARGET, ANIM_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var zoom: float = min(PORTRAIT_MAX.x / portrait.size.x, PORTRAIT_MAX.y / portrait.size.y)
	t.tween_property(portrait, "size", portrait.size * zoom, ANIM_TIME) \
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
