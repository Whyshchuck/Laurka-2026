@tool
class_name LetterLabel
extends Node2D

# Napis budowany ze sprite'ów literek narysowanych przez dzieci.
#
# Pliki literek leżą w res://letters/ i nazywają się: <kod>_<wariant>.png
#   np. a_1.png, a_2.png, b_1.png, a_pol_1.png
# Kody polskich znaków (wspólny przyrostek _pol):
#   a_pol=ą  c_pol=ć  e_pol=ę  l_pol=ł  n_pol=ń
#   o_pol=ó  s_pol=ś  z_pol=ż  zi_pol=ź
# Znaki specjalne: pytajnik=?  wykrzyknik=!
# Każda literka może mieć dowolnie wiele wariantów (_1, _2, _3...).
#
# Tryby:
#   RANDOM — przy budowie napisu każda literka dostaje losowy wariant
#   CYCLE  — dodatkowo warianty podmieniają się co cycle_interval sekund

enum VariantMode { RANDOM, CYCLE }

# Emitowany po każdym przeliczeniu układu literek (zmiana tekstu, rozmiaru,
# wariantów w trybie CYCLE) — np. LetterDecor trzyma się wtedy swojej literki.
signal layout_changed

const LETTERS_DIR := "res://letters"
# Udekorowane literki: scena res://letters/decor/<kod>.tscn (np. o_pol.tscn)
# zastępuje zwykły sprite znaku w KAŻDYM napisie. Konwencja sceny:
#   - dziecko Sprite2D o nazwie "Litera" (centered=false, pozycja (0,0))
#     z teksturą literki — wyznacza rozmiar w układzie napisu,
#   - dowolne LetterDecor/sprite'y obok, w pikselach tej tekstury.
const DECOR_DIR := "res://letters/decor"
const CODE_TO_CHAR := {
	"a_pol": "ą", "c_pol": "ć", "e_pol": "ę", "l_pol": "ł", "n_pol": "ń",
	"o_pol": "ó", "s_pol": "ś", "z_pol": "ż", "zi_pol": "ź",
	"pytajnik": "?", "wykrzyknik": "!",
}

@export var text := "": set = set_text
@export_range(10.0, 600.0, 1.0, "or_greater") var letter_height := 120.0: set = set_letter_height
@export var variant_mode := VariantMode.RANDOM: set = set_variant_mode
@export_range(0.1, 10.0, 0.05, "or_greater") var cycle_interval := 1.0: set = set_cycle_interval
@export var letter_spacing := 8.0: set = set_letter_spacing
@export var space_width := 50.0: set = set_space_width
@export var centered := true: set = set_centered
# Przycisk w Inspektorze: przeładowuje literki z dysku (po dorzuceniu nowych plików).
@export_tool_button("Przeładuj literki", "Reload") var _reload_btn := _on_reload_pressed

# Wspólny cache tekstur: znak -> Array[Texture2D] (po restarcie edytora odświeża się sam;
# po dorzuceniu nowych plików w trakcie pracy można wywołać LetterLabel.reload_letters()).
static var _atlas: Dictionary = {}
# Cache dekorów: znak -> Array wyrównana z _atlas[znak]; element to PackedScene
# dla wariantu z dekorem albo null. Dzięki temu dekor obejmuje tylko wybrane
# warianty (np. tylko a_3), a nie każde wystąpienie znaku.
static var _decor: Dictionary = {}

# Sloty napisu: { sprite: Sprite2D, char: String, idx: int, spaces_before: int }
var _slots: Array = []
var _timer: Timer = null


func _ready() -> void:
	_rebuild()
	_timer = Timer.new()
	_timer.timeout.connect(_on_cycle_timeout)
	add_child(_timer)
	_update_timer()


static func reload_letters() -> void:
	_atlas = {}
	_decor = {}


static func get_variants(ch: String) -> Array:
	# Tekstury wszystkich wariantów znaku — do użycia poza LetterLabel
	# (np. minigra alfabetu buduje z nich własne sprite'y).
	if _atlas.is_empty():
		_load_atlas()
	return _atlas.get(ch, [])


static func get_variant_decor(ch: String, idx: int) -> PackedScene:
	# Scena dekoru dla KONKRETNEGO wariantu znaku (albo null, gdy ten wariant
	# jest zwykłym sprite'em). idx to indeks w get_variants(ch).
	if _atlas.is_empty():
		_load_atlas()
	var arr: Array = _decor.get(ch, [])
	if idx < 0 or idx >= arr.size():
		return null
	return arr[idx]


func _on_reload_pressed() -> void:
	reload_letters()
	_rebuild()


# --- settery ---------------------------------------------------------------

func set_text(value: String) -> void:
	text = value
	if is_node_ready():
		_rebuild()

func set_letter_height(value: float) -> void:
	letter_height = value
	_layout()

func set_letter_spacing(value: float) -> void:
	letter_spacing = value
	_layout()

func set_space_width(value: float) -> void:
	space_width = value
	_layout()

func set_centered(value: bool) -> void:
	centered = value
	_layout()

func set_variant_mode(value: VariantMode) -> void:
	variant_mode = value
	_update_timer()

func set_cycle_interval(value: float) -> void:
	cycle_interval = value
	_update_timer()


# --- budowanie napisu ------------------------------------------------------

func _rebuild() -> void:
	for slot in _slots:
		slot.sprite.queue_free()
	_slots.clear()

	if _atlas.is_empty():
		_load_atlas()

	var pending_spaces := 0
	for ch in text.to_lower():
		if ch == " " or ch == "\t" or ch == "\n":
			pending_spaces += 1
			continue

		if not _atlas.has(ch) or (_atlas[ch] as Array).is_empty():
			push_warning("LetterLabel: brak sprite'a dla znaku '%s' (w res://letters/)" % ch)
			continue

		# Losowy wariant; jeśli ma dekor — wstaw scenę dekoru, inaczej zwykły sprite.
		var idx := randi() % (_atlas[ch] as Array).size()
		var slot := _make_node(ch, idx)
		slot["char"] = ch
		slot["idx"] = idx
		slot["spaces_before"] = pending_spaces
		_slots.append(slot)
		pending_spaces = 0

	_layout()


func _make_node(ch: String, idx: int) -> Dictionary:
	# Węzeł slotu: scena dekoru (gdy ten wariant ma dekor) albo zwykły Sprite2D.
	var scene: PackedScene = null
	if _decor.has(ch) and idx < (_decor[ch] as Array).size():
		scene = _decor[ch][idx]
	if scene != null:
		var inst := scene.instantiate() as Node2D
		var lit := inst.get_node_or_null("Litera") as Sprite2D
		if lit != null and lit.texture != null:
			add_child(inst)
			return { "sprite": inst, "is_decor": true, "size_tex": lit.texture }
		push_warning("LetterLabel: dekor znaku '%s' (wariant %d) bez Sprite2D 'Litera' z teksturą — używam zwykłego sprite'a" % [ch, idx])
		inst.free()

	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = _atlas[ch][idx]
	add_child(sprite)
	return { "sprite": sprite, "is_decor": false }


func _replace_slot_node(slot: Dictionary, new_idx: int) -> void:
	# Podmiana węzła slotu (przejście sprite <-> dekor w trybie CYCLE).
	slot.sprite.queue_free()
	var made := _make_node(slot.char, new_idx)
	slot.sprite = made.sprite
	slot.is_decor = made.is_decor
	if made.has("size_tex"):
		slot.size_tex = made.size_tex
	else:
		slot.erase("size_tex")
	slot.idx = new_idx


func _layout() -> void:
	if _slots.is_empty():
		return

	var x := 0.0
	for slot in _slots:
		x += slot.spaces_before * space_width
		var tex: Texture2D = _slot_tex(slot)
		var s := letter_height / tex.get_height()
		slot.sprite.scale = Vector2(s, s)
		slot.sprite.position = Vector2(x, 0.0)
		x += tex.get_width() * s + letter_spacing

	var total_width := x - letter_spacing
	if centered:
		var offset := Vector2(-total_width / 2.0, -letter_height / 2.0)
		for slot in _slots:
			slot.sprite.position += offset

	layout_changed.emit()


# --- pozycje literek (dla ozdób itp.) ---------------------------------------

func get_letter_count() -> int:
	return _slots.size()


func get_letter_center(idx: int) -> Vector2:
	# Środek literki o danym indeksie (w układzie LetterLabel).
	# Indeks ujemny liczy od końca (-1 = ostatnia).
	if _slots.is_empty():
		return Vector2.ZERO
	if idx < 0:
		idx += _slots.size()
	var slot: Dictionary = _slots[clampi(idx, 0, _slots.size() - 1)]
	var tex := _slot_tex(slot)
	if tex == null:
		return slot.sprite.position
	return slot.sprite.position + tex.get_size() * slot.sprite.scale * 0.5


func _slot_tex(slot: Dictionary) -> Texture2D:
	# Tekstura wyznaczająca rozmiar slotu (scena dekoru trzyma ją osobno).
	if slot.has("size_tex"):
		return slot.size_tex
	return slot.sprite.texture


func find_letter(ch: String) -> int:
	# Indeks pierwszego wystąpienia znaku (spacje nie mają slotów); -1 = brak.
	var wanted := ch.to_lower()
	for i in _slots.size():
		if _slots[i].char == wanted:
			return i
	return -1


# --- tryb CYCLE ------------------------------------------------------------

func _update_timer() -> void:
	if _timer == null:
		return
	if variant_mode == VariantMode.CYCLE:
		_timer.start(cycle_interval)
	else:
		_timer.stop()


func _on_cycle_timeout() -> void:
	for slot in _slots:
		var variants: Array = _atlas.get(slot.char, [])
		if variants.size() < 2:
			continue
		# losowy wariant, ale zawsze inny niż obecny
		var new_idx: int = (slot.idx + 1 + randi() % (variants.size() - 1)) % variants.size()
		var new_decor: bool = _decor.has(slot.char) and _decor[slot.char][new_idx] != null
		if slot.is_decor or new_decor:
			# zmiana typu węzła (sprite <-> dekor) — przebuduj slot
			_replace_slot_node(slot, new_idx)
		else:
			slot.idx = new_idx
			slot.sprite.texture = variants[new_idx]
	_layout()


# --- wczytywanie literek ---------------------------------------------------

static func _load_atlas() -> void:
	_atlas = {}
	_decor = {}
	var dir := DirAccess.open(LETTERS_DIR)
	if dir == null:
		push_warning("LetterLabel: nie mogę otworzyć folderu %s" % LETTERS_DIR)
		return

	var raw: Dictionary = {}  # znak -> Array[{variant, tex}]
	for file_name in dir.get_files():
		var name := file_name
		# W eksporcie (web/pck) pliki widoczne są jako *.import / *.remap.
		if name.ends_with(".import") or name.ends_with(".remap"):
			name = name.substr(0, name.rfind("."))
		if not name.ends_with(".png"):
			continue

		var stem := name.get_basename()
		var sep := stem.rfind("_")
		if sep == -1:
			continue
		var code := stem.substr(0, sep)
		var variant := stem.substr(sep + 1)
		if not variant.is_valid_int():
			continue

		var ch := ""
		if code.length() == 1:
			ch = code
		elif CODE_TO_CHAR.has(code):
			ch = CODE_TO_CHAR[code]
		else:
			continue

		var tex: Texture2D = load(LETTERS_DIR + "/" + name)
		if tex == null:
			continue
		if not raw.has(ch):
			raw[ch] = []
		raw[ch].append({ "variant": int(variant), "tex": tex })

	# Sceny dekoru: <znak>.tscn = dekor każdego wariantu znaku;
	# <znak>_<wariant>.tscn = dekor TYLKO tego wariantu (np. a_3.tscn = a, wariant 3).
	# Kod znaku jak przy teksturach: 1 litera albo wpis z CODE_TO_CHAR (np. z_pol).
	var decor_map: Dictionary = {}  # znak -> { wariant:int  (-1 = każdy) : PackedScene }
	var ddir := DirAccess.open(DECOR_DIR)
	if ddir != null:
		for file_name in ddir.get_files():
			var dname := file_name
			if dname.ends_with(".remap"):
				dname = dname.substr(0, dname.rfind("."))
			if not dname.ends_with(".tscn"):
				continue
			var stem := dname.get_basename()
			var dcode := stem
			var dvariant := -1
			var dsep := stem.rfind("_")
			if dsep != -1 and stem.substr(dsep + 1).is_valid_int():
				dcode = stem.substr(0, dsep)
				dvariant = int(stem.substr(dsep + 1))
			var dch := ""
			if dcode.length() == 1:
				dch = dcode
			elif CODE_TO_CHAR.has(dcode):
				dch = CODE_TO_CHAR[dcode]
			else:
				continue
			var ps := load(DECOR_DIR + "/" + dname) as PackedScene
			if ps == null:
				continue
			if not decor_map.has(dch):
				decor_map[dch] = {}
			decor_map[dch][dvariant] = ps

	# Posortuj warianty i zbuduj listę dekorów wyrównaną z teksturami (scena/null).
	for ch in raw:
		var entries: Array = raw[ch]
		entries.sort_custom(func(a, b): return a.variant < b.variant)
		var cmap: Dictionary = decor_map.get(ch, {})
		var per_char = cmap.get(-1, null)
		var textures: Array = []
		var decor_aligned: Array = []
		for e in entries:
			textures.append(e.tex)
			decor_aligned.append(cmap.get(e.variant, per_char))
		_atlas[ch] = textures
		_decor[ch] = decor_aligned
