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
#
# Skakanie (np. kozica po literce): ustaw kilka PUNKTÓW LĄDOWANIA (nie obrysowuj
# całej litery), włącz jump_straight i daj hop_height > 0 — element przeskakuje
# parabolą z punktu na punkt. flip_to_direction obraca grafikę w stronę skoku.

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

@export_group("Skakanie")
# Wysokość parabolicznego skoku między punktami (px, w stronę góry ekranu).
# 0 = brak skoku (ślizg po linii). Dla "skaczącej kozicy" daj np. 80–160.
@export_range(0.0, 600.0, 5.0) var hop_height := 0.0
# true: skacz w LINII PROSTEJ między kolejnymi punktami (ignoruj kształt krzywej
# między nimi) — punkty stają się "kamieniami do skakania". Wtedy rysuj krzywą
# jako kilka miejsc lądowania, nie obrysowuj całej litery.
@export var jump_straight := false
# Odbij grafikę w poziomie w stronę ruchu (zakłada, że domyślnie patrzy w prawo).
@export var flip_to_direction := false
# Steruj KLATKĄ dziecka (Sprite2D-arkusz) wg fazy skoku: klatka 0 = "na dole"
# (nogi razem, tuż przed wybiciem), ostatnia = w apogeum (rozprostowany w locie).
@export var sync_pose_to_hop := false

@export_group("Przypięcie do literki")
# Ozdoba trzyma się środka KONKRETNEJ literki w LetterLabel — także gdy
# układ się przesuwa (losowe warianty mają różne szerokości, a tryb CYCLE
# przebudowuje napis w locie). Krzywą rysuj wokół (0,0) tego node'a.
@export var follow_label: NodePath  # ścieżka do LetterLabel
@export var letter_char := ""   # znak do znalezienia (pierwsze wystąpienie)...
@export var letter_index := 0   # ...albo indeks literki, gdy znak pusty

var _label: LetterLabel = null

# Offsety (długość łuku) i pozycje przystanków na krzywej.
var _offsets: PackedFloat32Array
var _points: PackedVector2Array


func _ready() -> void:
	if curve == null or curve.point_count < 2 or curve.get_baked_length() <= 0.0:
		push_warning("LetterDecor: narysuj krzywą z co najmniej 2 punktami")
		return
	# Liczba przystanków. Jeśli krzywa jest domknięta (ostatni punkt leży w miejscu
	# pierwszego — tak robi przycisk „Close Curve" w edytorze Path2D), pomijamy ten
	# zdublowany punkt: domknięcie i tak przejedzie łukiem do końca krzywej, a tak
	# unikamy odwiedzania tego samego miejsca dwa razy (pauza na szwie pętli).
	var stops := curve.point_count
	if stops >= 3 and curve.get_point_position(stops - 1).is_equal_approx(
			curve.get_point_position(0)):
		stops -= 1

	_offsets = PackedFloat32Array()
	_points = PackedVector2Array()
	for i in stops:
		_offsets.append(curve.get_closest_offset(curve.get_point_position(i)))
		_points.append(curve.get_point_position(i))

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
			_travel(child, (k % _offsets.size()) if stagger else 0)
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
	# Nieskończona wędrówka między przystankami; każdy segment to tween p: 0 -> 1,
	# na który nakładamy parabolę skoku i ustawiamy orientację wg kierunku lotu.
	var i := start_point
	var dir := 1
	_place(node, i, i, 0.0, false)

	var stops := _offsets.size()
	while is_instance_valid(node) and is_inside_tree():
		var j := i + dir
		if ping_pong and (j >= stops or j < 0):
			dir = -dir
			j = i + dir
		var wrap := false
		if j >= stops:
			j = 0
			wrap = true     # domknięcie pętli: lądowanie na punkcie startowym
		elif j < 0:
			j = stops - 1

		var from := i
		var to := j
		var t := create_tween()
		t.tween_method(
			func(p: float) -> void: _place(node, from, to, p, wrap),
			0.0, 1.0, segment_time) \
			.set_trans(transition).set_ease(Tween.EASE_IN_OUT)
		await t.finished
		if not is_instance_valid(node) or not is_inside_tree():
			return
		if pause_time > 0.0:
			await get_tree().create_timer(pause_time).timeout
			if not is_instance_valid(node) or not is_inside_tree():
				return
		i = j


func _seg_pos(from_i: int, to_i: int, p: float, wrap: bool, with_hop := true) -> Vector2:
	# Pozycja na segmencie dla p w [0,1]; with_hop dokłada parabolę skoku.
	var pos: Vector2
	if jump_straight:
		# Lot w linii prostej między punktami (kształt krzywej między nimi nieważny).
		var b := _points[0] if wrap else _points[to_i]
		pos = _points[from_i].lerp(b, p)
	else:
		# Lot po łuku krzywej.
		var to_off := curve.get_baked_length() if wrap else _offsets[to_i]
		pos = curve.sample_baked(lerpf(_offsets[from_i], to_off, p))
	if with_hop and hop_height > 0.0:
		pos.y -= sin(clampf(p, 0.0, 1.0) * PI) * hop_height
	return pos


func _place(node: CanvasItem, from_i: int, to_i: int, p: float, wrap: bool) -> void:
	if not is_instance_valid(node):
		return
	node.position = _seg_pos(from_i, to_i, p, wrap)

	# Kierunek LINII (bez paraboli skoku) — żeby stopy patrzyły na literkę,
	# a nie koziołkowały wzdłuż łuku lotu.
	var e := 0.02
	var vel := _seg_pos(from_i, to_i, minf(p + e, 1.0), wrap, false) \
		- _seg_pos(from_i, to_i, maxf(p - e, 0.0), wrap, false)

	if orient == Orient.UPRIGHT:
		node.rotation = deg_to_rad(orient_offset)
	elif vel.length_squared() > 0.0:
		var ang := vel.angle()
		if orient == Orient.PERPENDICULAR:
			ang += PI / 2.0
		node.rotation = ang + deg_to_rad(orient_offset)

	if flip_to_direction and absf(vel.x) > 0.001:
		node.scale.x = absf(node.scale.x) * signf(vel.x)

	# Poza wg fazy skoku: lift = 0 na dole (nogi razem), 1 w apogeum (rozprostowany).
	if sync_pose_to_hop and node is Sprite2D:
		var spr := node as Sprite2D
		var total := spr.hframes * spr.vframes
		if total > 1:
			var lift := sin(clampf(p, 0.0, 1.0) * PI)
			spr.frame = int(round((total - 1) * lift))
