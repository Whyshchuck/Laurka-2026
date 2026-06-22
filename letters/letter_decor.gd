class_name LetterDecor
extends Path2D

# Ruchome ozdoby na literkach (i nie tylko): dzieci tego node'a (sprite'y,
# inne LetterLabel itp.) wędrują po krzywej od punktu do punktu z łagodnym
# startem i hamowaniem (ease-in/out).
#
# Użycie:
#   1. Dodaj node LetterDecor (to Path2D — krzywą rysujesz w edytorze
#      zwykłymi narzędziami Path2D).
#   2. Punkty kontrolne krzywej to "przystanki" ruchu.
#   3. Dodaj dzieci (np. Sprite2D) — każde rusza w trasę po _ready.
#   4. Pętla: zamknij krzywą (ostatni punkt w miejscu pierwszego) albo
#      włącz ping_pong, żeby element wracał po własnych śladach.

@export_range(0.05, 10.0, 0.05) var segment_time := 0.8   # czas punkt -> punkt
@export_range(0.0, 10.0, 0.05) var pause_time := 0.0      # postój na punkcie
@export var ping_pong := false       # true: tam i z powrotem, false: pętla

enum Orient {
	UPRIGHT,         # bez obrotu — zawsze pionowo (jak dotąd)
	BOTTOM_TO_LINE,  # spód elementu jedzie po linii, przechyla się z jej nachyleniem
	PERPENDICULAR,   # element sterczy prostopadle, w bok od linii
}
# Jak obracać element jadący po krzywej. BOTTOM_TO_LINE = „dołem do linii".
@export var orient: Orient = Orient.UPRIGHT
# Dodatkowy obrót elementu w stopniach — dostrojenie, gdy „dół" grafiki nie leży
# na osi +Y (np. żeby obrócić zwierzaka o 180° albo lekko podkręcić).
@export_range(-180.0, 180.0, 5.0) var orient_offset := 0.0

@export var stagger := true          # kolejne dzieci startują z kolejnych punktów
@export var transition := Tween.TRANS_SINE  # kształt ease-in/out

@export_group("Przypięcie do literki")
# Ozdoba trzyma się środka KONKRETNEJ literki w LetterLabel — także gdy
# układ się przesuwa (losowe warianty mają różne szerokości, a tryb CYCLE
# przebudowuje napis w locie). Krzywą rysuj wokół (0,0) tego node'a.
@export var follow_label: NodePath  # ścieżka do LetterLabel
@export var letter_char := ""   # znak do znalezienia (pierwsze wystąpienie)...
@export var letter_index := 0   # ...albo indeks literki, gdy znak pusty

var _label: LetterLabel = null

# Offsety (długość łuku) punktów kontrolnych na krzywej.
var _offsets: PackedFloat32Array


func _ready() -> void:
	if curve == null or curve.point_count < 2 or curve.get_baked_length() <= 0.0:
		push_warning("LetterDecor: narysuj krzywą z co najmniej 2 punktami")
		return
	_offsets = PackedFloat32Array()
	for i in curve.point_count:
		_offsets.append(curve.get_closest_offset(curve.get_point_position(i)))

	if not follow_label.is_empty():
		_label = get_node_or_null(follow_label) as LetterLabel
		if _label == null:
			push_warning("LetterDecor: follow_label nie wskazuje na LetterLabel")
		else:
			_label.layout_changed.connect(_snap_to_letter)
			_snap_to_letter()

	var k := 0
	for child in get_children():
		if child is CanvasItem:
			_travel(child, (k % curve.point_count) if stagger else 0)
			k += 1


func _snap_to_letter() -> void:
	var idx := letter_index
	if letter_char != "":
		idx = _label.find_letter(letter_char)
		if idx == -1:
			push_warning("LetterDecor: znaku '%s' nie ma w \"%s\"" % [letter_char, _label.text])
			return
	global_position = _label.to_global(_label.get_letter_center(idx))


func _travel(node: CanvasItem, start_point: int) -> void:
	# Nieskończona wędrówka: tween offsetu po łuku między przystankami.
	var i := start_point
	var dir := 1
	_place(node, _offsets[i], 1.0)

	while is_instance_valid(node) and is_inside_tree():
		var j := i + dir
		if ping_pong and (j >= curve.point_count or j < 0):
			dir = -dir
			j = i + dir
		var from_off := _offsets[i]
		var to_off: float
		if j >= curve.point_count:
			j = 0
			to_off = curve.get_baked_length()  # domknięcie pętli przez koniec krzywej
		elif j < 0:
			j = curve.point_count - 1
			to_off = _offsets[j]
		else:
			to_off = _offsets[j]

		var facing := 1.0 if to_off >= from_off else -1.0
		var t := create_tween()
		t.tween_method(
			func(off: float) -> void: _place(node, off, facing),
			from_off, to_off, segment_time) \
			.set_trans(transition).set_ease(Tween.EASE_IN_OUT)
		await t.finished
		if not is_instance_valid(node) or not is_inside_tree():
			return
		if pause_time > 0.0:
			await get_tree().create_timer(pause_time).timeout
			if not is_instance_valid(node) or not is_inside_tree():
				return
		i = j


func _place(node: CanvasItem, off: float, facing: float) -> void:
	if not is_instance_valid(node):
		return
	var pos := curve.sample_baked(off)
	node.position = pos
	if orient == Orient.UPRIGHT:
		return
	# Styczna do krzywej w kierunku jazdy (przy ruchu wstecz krzywej — odwrotnie).
	var ahead := curve.sample_baked(off + 2.0 * facing)
	if ahead == pos:
		return
	var tangent := (ahead - pos) if facing > 0.0 else (pos - ahead)
	var ang := tangent.angle()
	if orient == Orient.PERPENDICULAR:
		# Obróć o 90°, żeby element sterczał prostopadle do linii.
		ang += PI / 2.0
	node.rotation = ang + deg_to_rad(orient_offset)
