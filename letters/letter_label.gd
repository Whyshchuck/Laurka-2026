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

const LETTERS_DIR := "res://letters"
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


static func get_variants(ch: String) -> Array:
	# Tekstury wszystkich wariantów znaku — do użycia poza LetterLabel
	# (np. minigra alfabetu buduje z nich własne sprite'y).
	if _atlas.is_empty():
		_load_atlas()
	return _atlas.get(ch, [])


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
		if not _atlas.has(ch):
			push_warning("LetterLabel: brak sprite'a dla znaku '%s' (w res://letters/)" % ch)
			continue
		var variants: Array = _atlas[ch]
		var sprite := Sprite2D.new()
		sprite.centered = false
		add_child(sprite)
		_slots.append({
			"sprite": sprite,
			"char": ch,
			"idx": randi() % variants.size(),
			"spaces_before": pending_spaces,
		})
		pending_spaces = 0

	_apply_variants()


func _apply_variants() -> void:
	for slot in _slots:
		var variants: Array = _atlas[slot.char]
		slot.sprite.texture = variants[clampi(slot.idx, 0, variants.size() - 1)]
	_layout()


func _layout() -> void:
	if _slots.is_empty():
		return

	var x := 0.0
	for slot in _slots:
		x += slot.spaces_before * space_width
		var tex: Texture2D = slot.sprite.texture
		var s := letter_height / tex.get_height()
		slot.sprite.scale = Vector2(s, s)
		slot.sprite.position = Vector2(x, 0.0)
		x += tex.get_width() * s + letter_spacing

	var total_width := x - letter_spacing
	if centered:
		var offset := Vector2(-total_width / 2.0, -letter_height / 2.0)
		for slot in _slots:
			slot.sprite.position += offset


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
		slot.idx = (slot.idx + 1 + randi() % (variants.size() - 1)) % variants.size()
	_apply_variants()


# --- wczytywanie literek ---------------------------------------------------

static func _load_atlas() -> void:
	_atlas = {}
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

	for ch in raw:
		var entries: Array = raw[ch]
		entries.sort_custom(func(a, b): return a.variant < b.variant)
		var textures: Array = []
		for e in entries:
			textures.append(e.tex)
		_atlas[ch] = textures
