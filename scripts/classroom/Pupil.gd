@tool
extends CharacterBody2D
class_name Pupil

enum CharacterState {
	READY,
	MOVING,
	RETURNING,
	LOCKED,
	RESPAWNING
}

@export var speed := 300.0

# Reakcja na klik (tryb WELCOME): kolejne stadia przemiany,
# np. dla Łucji [norm, trans_1, trans_2, bronto]. Puste = uczeń się nie zmienia.
# Drugi klik odwraca przemianę.
@export var transform_textures: Array[Texture2D] = []

enum TransformState { NORMAL, RUNNING, TRANSFORMED }

const COLOUR_NORMAL := Color(1, 1, 1, 1)
const COLOUR_RESPAWN := Color(1, 0.3, 0.3, 1)
const COLOUR_CANCEL_RESPAWN := Color(0, 1, 0, 1)
const COLOUR_LOCKED := Color(0.326, 0.532, 1.0, 1)

const RESPAWN_TIMEOUT := 4
const MAX_RESPAWN_COUNT := 3

const FLASH_COLOUR := Color(1.6, 1.5, 0.4, 1)  # żółty błysk przemiany
const FLASH_SWAPS := 6    # ile podmian tekstur na jedno stadium przemiany
const FLASH_TIME := 0.09  # czas jednej podmiany

var character_state: CharacterState = CharacterState.READY
var direction := Vector2.ZERO
var start_position := Vector2.ZERO
var nav_map_rid: RID
var respawn_count := 0
var blink_tween: Tween = null

var transform_state := TransformState.NORMAL
var _transform_orig := {}      # zapamiętany wygląd sprite'a sprzed przemiany
var _transform_scale := 1.0    # wspólna skala tekstur przemiany
var _transform_bottom := 0.0   # y dolnej krawędzi — stopy/łapy zawsze na ziemi
var _transform_base_w := 0.0   # szerokość stadium wyjściowego na ekranie

@onready var agent := $NavigationAgent2D
@onready var respawn_timer: Timer = $RespawnTimer
@onready var texture_rect: TextureRect = $TextureRect
@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")  # nie każdy uczeń ma Sprite2D

var _rig: Node2D = null  # rig ucznia (jeśli go ma) — zastępuje płaską grafikę
var _rig_ap: AnimationPlayer = null  # AnimationPlayer rigu (cache)
var _intro_done := false  # czy intro (macha -> siada) się skończyło
var _seated := false       # czy uczeń aktualnie siedzi
var _busy := false         # trwa przejście (machanie/siadanie/wstawanie)
var _click_pending := false  # klik w trakcie hover-przejścia — odpal po jego końcu

const HOVER_MARGIN := 18.0  # zapas prostokąta hover, żeby nie migotało na krawędzi
const FALLBACK_ANIM_LEN := 0.6

signal pupil_clicked(pupil: Pupil)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		# W edytorze AnimationPlayer nie chodzi sam — popychamy go dla podglądu.
		if _rig:
			var ap := _rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
			if ap and ap.is_playing():
				ap.advance(delta)
		return
	# Gra: po intrze — wstawanie pod kursorem, siadanie po zjechaniu myszą.
	# Na dotyku (mobile) hover nie ma sensu — sterujemy pinch/tap, nie kursorem.
	if DisplayServer.is_touchscreen_available():
		return
	# Otwarta nakładka (np. minigra alfabetu) wstrzymuje hover — uczeń zostaje
	# w obecnej pozie, dopóki nakładka żyje.
	if get_tree().get_first_node_in_group("blocks_pupil_hover") != null:
		return
	if not _intro_done or _rig == null or _busy:
		return
	var inside := _hover_rect().has_point(get_global_mouse_position())
	if inside and _seated:
		_stand_up()
	elif not inside and not _seated:
		_sit_down()


func setup_rig() -> void:
	# Jeśli uczeń ma rig — pokaż rig zamiast płaskiej grafiki, w pozie "stand".
	var scene := RigHelper.scene_for(String(name))
	if scene == null:
		return
	var old := get_node_or_null("Rig")  # usuń poprzedni podgląd (np. przeładowanie @tool)
	if old:
		old.free()
	_rig = scene.instantiate() as Node2D
	_rig.name = "Rig"
	add_child(_rig)
	_rig_ap = _rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	_rig.z_as_relative = false  # jak dawne TextureRect/Sprite2D (warstwa wg y-sort)
	RigHelper.fit(_rig, _display_rect())
	# Chowamy płaską grafikę (TextureRect zostaje — niewidoczny — do wykrywania klików).
	if sprite:
		sprite.visible = false
	texture_rect.visible = false
	RigHelper.play_stand(_rig)


func _display_rect() -> Rect2:
	# Obszar, w którym uczeń jest rysowany: Sprite2D jeśli go ma (to on jest grafiką),
	# inaczej TextureRect. Nie patrzymy na .visible (po schowaniu byłoby zawodne).
	# Współrzędne sceny (get_global_transform), żeby działało też w edytorze.
	if sprite and sprite.texture:
		var frame := Vector2(
			sprite.texture.get_width() / float(maxi(sprite.hframes, 1)),
			sprite.texture.get_height() / float(maxi(sprite.vframes, 1)))
		var disp := frame * sprite.scale.abs()
		return Rect2(sprite.global_position - disp * 0.5, disp)
	return Rect2(
		texture_rect.get_global_transform().origin,
		texture_rect.size * texture_rect.scale)


func _ready():
	if Engine.is_editor_hint():
		setup_rig()  # tylko podgląd rigu w edytorze
		return
	start_position = global_position
	var nav_region: NavigationRegion2D = get_node("/root/Classroom/NavigationRegion2D")
	nav_map_rid = nav_region.get_navigation_map()
	respawn_timer.timeout.connect(_on_respawn_timer_timeout)

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if character_state in [CharacterState.LOCKED, CharacterState.RETURNING]:
		return

	if not (event is InputEventMouseButton and event.pressed):
		return

	var mouse_pos: Vector2 = get_global_mouse_position()
	if texture_rect.get_global_rect().has_point(mouse_pos):
		# Dawna mechanika "ganianie" (odprowadzanie uciekinierów) wycofana.
		# Klik obsługuje classroom.gd -> on_click(). TODO Faza 1/2: usunąć resztę chase.
		pass
				
func on_click():
	match GameState.current_type:
		GameState.GameType.WELCOME:
			react()
		GameState.GameType.QUIZ:
			
			pass # TODO (Faza 4): klik -> tło szarzeje, slide sprite'a, pytania a/b/c


func react() -> void:
	# Reakcja na klik (tryb WELCOME): interakcja danego dziecka.
	# (Czytanie własnego imienia na klik usunięte na życzenie.)
	if _busy:
		# Klik w trakcie hover-przejścia (wstawanie/siadanie) — zapamiętaj i odpal
		# interakcję, gdy się skończy. _intro_done==true => to hover, nie interakcja.
		if _intro_done:
			_click_pending = true
		return
	# Interakcja per uczeń (docelowo każde dziecko ma własną).
	match String(name):
		"Jasiek":
			_interaction_jasiek()
			return
		"Oliwka":
			_interaction_oliwia()
			return
		"Łucja":
			_interaction_lucja()
			return
		"Michał":
			_interaction_michal()
			return
		"Miłosz":
			_interaction_milosz()
			return
		"Anabiya":
			_interaction_anabiya()
			return
		"Maja":
			_interaction_maja()
			return
		"Hania":
			_interaction_hania()
			return
		"Amelka":
			_interaction_amelka()
			return
		"KazikL":
			_interaction_kazik_l()
			return
		"Kuba":
			_interaction_kuba()
			return
		"Wojtek":
			_interaction_wojtek()
			return
	# Domyślnie: uczeń z rigiem reaguje machnięciem; bez rigu — dawna przemiana tekstur.
	if _rig:
		_interaction_default()
		return
	if transform_textures.size() >= 2 and transform_state != TransformState.RUNNING:
		_run_transform()


func _interaction_default() -> void:
	# Brak własnej interakcji — uczeń po prostu macha, a potem wraca do swojej pozy.
	if _rig == null or _busy or not _has_full_own_set():
		return
	_busy = true
	_intro_done = false
	var was_seated := _seated
	if _seated:
		_play_own("wstawanie")
		await get_tree().create_timer(_anim_len("wstawanie")).timeout
		if not is_inside_tree() or _rig == null:
			return
		_seated = false
	_play_own("machanie")
	await get_tree().create_timer(_anim_len("machanie")).timeout
	if not is_inside_tree() or _rig == null:
		return
	if was_seated:
		_play_own("siadanie")
		await get_tree().create_timer(_anim_len("siadanie")).timeout
		if is_inside_tree() and _rig:
			_play_own("siedzi")
		_seated = true
	else:
		_play_own("stoi")
	_busy = false
	_intro_done = true


# --- interakcja Kazika_L: wskok na ławkę -> break -> mikrofon -> „pyk" i powrót ---

const KAZIK_BENCH_POINT := Vector2(109, 640)  # STOPY Kazika_L na ławce (do strojenia)
const KAZIK_MIC_HOLD := 3.0       # ile jest mikrofonem (kręci się), zanim „pyk" i wraca
const KAZIK_MIC_SPRITE := "res://sprites/kazik_mic.png"
var _kazik_home_origin := Vector2.ZERO


func _interaction_kazik_l() -> void:
	if _rig == null or _busy or get_node_or_null("Mikrofon"):
		return
	_busy = true
	_intro_done = false

	# 1. Wstaje i wskakuje na ławkę (z-index nad ławką).
	if _seated:
		_play_own("wstawanie")
		await get_tree().create_timer(_anim_len("wstawanie")).timeout
		if not is_inside_tree() or _rig == null:
			return
		_seated = false
	_kazik_home_origin = _rig.global_position
	var feet0 := _display_rect()
	var home_feet := Vector2(feet0.get_center().x, feet0.end.y)
	var base_h := feet0.size.y
	var bench_origin := _kazik_home_origin + (KAZIK_BENCH_POINT - home_feet)
	_rig.z_index = BBALL_BENCH_Z
	_play_own("stoi")
	await _hop_rig(bench_origin, BBALL_HOP_HEIGHT, BBALL_HOP_TIME)
	if not is_inside_tree() or _rig == null:
		return

	# 2. Tańczy breaka: ruch kończyn (taniec) + wirowanie i stanie na rękach (obrót 180°).
	var pivot := Vector2(KAZIK_BENCH_POINT.x, KAZIK_BENCH_POINT.y - base_h * 0.5)
	_play_own("taniec")
	await _spin_node(_rig, pivot, TAU * 2.0, 1.0)   # wiruje (2 obroty)
	if not is_inside_tree() or _rig == null:
		return
	await _spin_node(_rig, pivot, PI, 0.45)         # przewrót do góry nogami — staje na rękach
	if not is_inside_tree() or _rig == null:
		return
	await get_tree().create_timer(0.8).timeout      # chwila na rękach
	if not is_inside_tree() or _rig == null:
		return
	await _spin_node(_rig, pivot, PI, 0.45)          # z powrotem na nogi
	if not is_inside_tree() or _rig == null:
		return
	await _spin_node(_rig, pivot, TAU * 2.0, 1.0)    # jeszcze wiruje
	if not is_inside_tree() or _rig == null:
		return
	_rig.rotation = 0.0
	_rig.global_position = bench_origin

	# 3. Zamienia się w mikrofon: miganie rig <-> mikrofon, kończy na mikrofonie.
	var mic := Sprite2D.new()
	mic.name = "Mikrofon"
	mic.top_level = true
	mic.z_index = 1000
	mic.z_as_relative = false
	mic.visible = false
	add_child(mic)
	var mic_tex := load(KAZIK_MIC_SPRITE) as Texture2D
	if mic_tex:
		_set_floor_sprite(mic, mic_tex, base_h, KAZIK_BENCH_POINT)
	_play_sfx(LUCJA_MAGIC_SFX)  # czar przemiany
	for j in FLASH_SWAPS:
		var show_mic := (j % 2 == 1)
		mic.visible = show_mic
		mic.modulate = FLASH_COLOUR if show_mic else COLOUR_NORMAL
		if _rig:
			_rig.visible = not show_mic
			_rig.modulate = FLASH_COLOUR if not show_mic else COLOUR_NORMAL
		await get_tree().create_timer(FLASH_TIME).timeout
		if not is_inside_tree():
			return
	if _rig:
		_rig.modulate = COLOUR_NORMAL
		_rig.visible = false
	mic.visible = true
	mic.modulate = COLOUR_NORMAL

	# 4. Mikrofon się kręci; po KAZIK_MIC_HOLD — „pyk" (kork), znika, Kazik wraca i siada.
	var spin := create_tween()
	spin.tween_property(mic, "rotation", TAU * 3.0, KAZIK_MIC_HOLD)
	await spin.finished
	if not is_inside_tree():
		return
	if is_instance_valid(mic):
		mic.queue_free()
	_play_sound(KORK_SFX)
	if _rig:
		_rig.global_position = _kazik_home_origin
		_rig.z_index = 0
		_rig.visible = true
		_play_own("siadanie")
		await get_tree().create_timer(_anim_len("siadanie")).timeout
		if is_inside_tree() and _rig:
			_play_own("siedzi")
		_seated = true
	_busy = false
	_intro_done = true


# --- pokaz koszykówki (Michał_K i Miłosz) na ławce ----------------------------
# Klik -> wstaje, podnosi piłkę, WSKAKUJE NA SWOJĄ ŁAWKĘ, pokazuje piłkę,
# kozłuje, wsad do kosza, znów kozłuje, zeskakuje i siada.

const BBALL_SHOW := 1.5          # ile trwa „pokazanie" piłką (anim w pętli)
const BBALL_DRIBBLE_1 := 3.0     # pierwsze kozłowanie (kilka sekund)
const BBALL_DRIBBLE_2 := 2.0     # drugie kozłowanie po wsadzie
const BBALL_BENCH_Z := 50        # z-index rigu na ławce (nad ławką — Pupils ma y-sort)
const BBALL_HOP_TIME := 0.5      # czas wskoku/zeskoku
const BBALL_HOP_HEIGHT := 110.0  # wysokość łuku wskoku
const MICHAL_BENCH_POINT := Vector2(215, 455)  # STOPY Michała na ławce (do strojenia)
const MILOSZ_BENCH_POINT := Vector2(661, 780)  # STOPY Miłosza na ławce (do strojenia)


func _interaction_michal() -> void:
	await _basketball_show(MICHAL_BENCH_POINT)


func _interaction_milosz() -> void:
	await _basketball_show(MILOSZ_BENCH_POINT)


func _basketball_show(bench_point: Vector2) -> void:
	if _rig == null or _busy:
		return
	_busy = true
	_intro_done = false  # wstrzymaj hover na czas pokazu

	# 1. Wstaje (jeśli siedzi).
	if _seated:
		_play_own("wstawanie")
		await get_tree().create_timer(_anim_len("wstawanie")).timeout
		if not is_inside_tree() or _rig == null:
			return
		_seated = false

	# 2. Podnosi piłkę (na podłodze).
	_play_own("podnosi")
	await get_tree().create_timer(_anim_len("podnosi")).timeout
	if not is_inside_tree() or _rig == null:
		return

	# 3. Wskakuje na swoją ławkę. z-index w górę, by był NAD ławką (Pupils ma y-sort,
	#    więc bez tego niższy y = za ławką). Przesunięcie liczymy po STOPACH.
	var home_origin := _rig.global_position
	var feet := _display_rect()
	var home_feet := Vector2(feet.get_center().x, feet.end.y)
	var bench_origin := home_origin + (bench_point - home_feet)
	_rig.z_index = BBALL_BENCH_Z
	_play_own("trzyma")  # trzyma piłkę w trakcie wskoku
	await _hop_rig(bench_origin, BBALL_HOP_HEIGHT, BBALL_HOP_TIME)
	if not is_inside_tree() or _rig == null:
		return

	# 4. Pokazuje piłkę (na ławce).
	var show_anim := "wskazuje" if _own_anim("wskazuje") != "" else "trzyma"
	_play_own(show_anim)
	await get_tree().create_timer(BBALL_SHOW).timeout
	if not is_inside_tree() or _rig == null:
		return

	# 5. Kozłuje kilka sekund.
	_play_own("kozlowanie")
	await get_tree().create_timer(BBALL_DRIBBLE_1).timeout
	if not is_inside_tree() or _rig == null:
		return

	# 6. Pakuje piłkę do kosza (wsad).
	_play_own("wsad")
	await get_tree().create_timer(_anim_len("wsad")).timeout
	if not is_inside_tree() or _rig == null:
		return

	# 7. Znów kozłuje.
	_play_own("kozlowanie")
	await get_tree().create_timer(BBALL_DRIBBLE_2).timeout
	if not is_inside_tree() or _rig == null:
		return

	# 8. Zeskakuje z ławki na swoje miejsce, z-index wraca.
	_play_own("trzyma")
	await _hop_rig(home_origin, BBALL_HOP_HEIGHT, BBALL_HOP_TIME)
	if not is_inside_tree() or _rig == null:
		return
	_rig.z_index = 0

	# 9. Siada.
	_play_own("siadanie")
	await get_tree().create_timer(_anim_len("siadanie")).timeout
	if is_inside_tree() and _rig:
		_play_own("siedzi")
	_seated = true
	_busy = false
	_intro_done = true  # hover wraca


# --- interakcja Anabii: maluje obrazek -----------------------------------------
# Rig ma już w dłoniach: kartka (DlonL) z elementami rysunek/rysunek2-4 oraz pędzel
# (DlonP) — wszystko visible=false. Klik: rekwizyty pojawiają się w dłoniach, gra
# k/maluje (poza malowania + dabowanie pędzlem), a elementy obrazka KOLEJNO zyskują
# alpha (0 -> 1), jakby były domalowywane.

const ANABIA_PAINT_TIME := 4.0   # łączny czas, na który rozkłada się odsłanianie elementów
const ANABIA_SHOW_TIME := 0.35   # czas pojawiania się kartki i pędzla w dłoniach
const ANABIA_CHEER := "res://audio/dragon-studio-crowd-cheer-and-applause-406644.mp3"  # owacja (jak dobra odpowiedź)
const ANABIA_RAISE_TIME := 0.6   # czas unoszenia obrazu nad głowę
const ANABIA_RAISE_RAMIE_L := 1.9   # lewe ramię uniesione (obraz nad głowę) — do strojenia
const ANABIA_RAISE_FORE_L := 0.2    # lewe przedramię przy uniesieniu — do strojenia
const ANABIA_HOLD_TIME := 3.0       # jak długo trzyma uniesiony obraz, zanim opuści ręce i siada
var _anabia_painted := false

func _interaction_anabiya() -> void:
	if _rig == null or _busy or _anabia_painted:
		return
	_busy = true
	_intro_done = false   # wstrzymaj hover; Anabia zostaje przy malowaniu

	# Wstaje (jeśli siedzi) — wtedy wyjmuje rekwizyty „spod biurka".
	if _seated:
		_play_own("wstawanie")
		await get_tree().create_timer(_anim_len("wstawanie")).timeout
		if not is_inside_tree() or _rig == null:
			return
		_play_own("stoi")
		_seated = false

	var dlon_l := "Skeleton2D/Biodra/Tulow/RamieL/PrzedramieL/DlonL/"
	var kartka := _rig.get_node_or_null(dlon_l + "kartka") as Sprite2D
	var pedzel := _rig.get_node_or_null(
		"Skeleton2D/Biodra/Tulow/RamieP/PrzedramieP/DlonP/pędzel") as Sprite2D
	var parts: Array[Sprite2D] = []
	for nm in ["kartka/rysunek", "kartka/rysunek2", "kartka/rysunek3", "kartka/rysunek4"]:
		var p := _rig.get_node_or_null(dlon_l + nm) as Sprite2D
		if p:
			parts.append(p)

	# 1. „Wyciąga spod biurka" — kartka i pędzel pojawiają się w dłoniach (fade in).
	await _fade_in_props([kartka, pedzel], ANABIA_SHOW_TIME)
	if not is_inside_tree() or _rig == null:
		return

	# 2. Zaczyna malować (poza malowania + dabowanie). Krótki blend dla płynnego wejścia.
	var maluje := _own_anim("maluje")
	if _rig_ap and maluje != "":
		_rig_ap.play(maluje, 0.3)

	# 3. W trakcie malowania kolejne elementy obrazka stopniowo zyskują alpha.
	var per := ANABIA_PAINT_TIME / float(maxi(parts.size(), 1))
	for p in parts:
		p.visible = true
		p.modulate.a = 0.0
		var t := create_tween()
		t.tween_property(p, "modulate:a", 1.0, per)
		await t.finished
		if not is_inside_tree() or _rig == null:
			return

	# 4. Gotowy obraz — Anabia unosi go nad głowę i słychać owację (jak dobra odpowiedź).
	if _rig_ap:
		_rig_ap.pause()   # zamroź pozę malowania; lewe ramię podnosimy ręcznie
	var ramie_l := _rig.get_node_or_null("Skeleton2D/Biodra/Tulow/RamieL") as Bone2D
	var przedramie_l := _rig.get_node_or_null(
		"Skeleton2D/Biodra/Tulow/RamieL/PrzedramieL") as Bone2D
	if ramie_l and przedramie_l:
		var t := create_tween().set_parallel(true)
		t.tween_property(ramie_l, "rotation", ANABIA_RAISE_RAMIE_L, ANABIA_RAISE_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(przedramie_l, "rotation", ANABIA_RAISE_FORE_L, ANABIA_RAISE_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await t.finished
		if not is_inside_tree():
			return
	_play_sound(ANABIA_CHEER)

	# Po 3 s opuszcza ręce (płynnie), chowa kartkę i pędzel, i siada.
	await get_tree().create_timer(ANABIA_HOLD_TIME).timeout
	if not is_inside_tree() or _rig == null:
		return
	if ramie_l and przedramie_l:
		var td := create_tween().set_parallel(true)
		td.tween_property(ramie_l, "rotation", 0.0, ANABIA_RAISE_TIME).set_trans(Tween.TRANS_SINE)
		td.tween_property(przedramie_l, "rotation", 0.0, ANABIA_RAISE_TIME).set_trans(Tween.TRANS_SINE)
		for s in [kartka, pedzel]:
			if s:
				td.tween_property(s, "modulate:a", 0.0, ANABIA_RAISE_TIME)
		await td.finished
		if not is_inside_tree() or _rig == null:
			return

	# Siada.
	_play_own("siadanie")
	await get_tree().create_timer(_anim_len("siadanie")).timeout
	if is_inside_tree() and _rig:
		_play_own("siedzi")
	_seated = true
	_anabia_painted = true
	_busy = false
	_intro_done = true   # hover wraca


func _play_sound(path: String) -> void:
	# Jednorazowy odtwarzacz dźwięku — sam się usuwa po zakończeniu.
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _schedule_magic_revert(creature: Node) -> void:
	# Po MAGIC_REVERT_DELAY magiczna postać sama znika („pyk"). Cofamy tylko, jeśli to
	# WCIĄŻ ta sama postać (nie nowa po ponownej przemianie) i nie cofnięto jej klikiem.
	var tree := get_tree()
	if tree == null:
		return
	tree.create_timer(MAGIC_REVERT_DELAY).timeout.connect(_auto_magic_revert.bind(creature))


func _auto_magic_revert(creature: Node) -> void:
	if not is_instance_valid(creature):
		return
	if get_node_or_null("Smok") == creature:
		_jasiek_revert()
	elif get_node_or_null("Bronto") == creature:
		_lucja_revert()
	elif get_node_or_null("Fortepian") == creature:
		_wojtek_revert()


# --- interakcja Mai: przemiana w maja_poke z deszczem gwiazdek --------------
# Klik -> sypią się dziesiątki gwiazdek (maja_blink): pojawiają się, mienią,
# mrugają i znikają, a w trakcie Maja zamienia się w stworka (maja_poke).
# Drugi klik -> znów gwiazdki i powrót do Mai.

const MAJA_POKE := "res://sprites/maja_poke.png"
const MAJA_STAR := "res://sprites/maja_blink.png"
const MAJA_STARS := 120          # ile gwiazdek sypie się na przemianę (gęsto, dynamicznie)
const MAJA_SHOWER_TIME := 1.6    # czas sypania gwiazdek
const MAJA_POKE_HEIGHT := 1.2    # wysokość stworka wzgl. Mai
const MAJA_STAR_MIN := 0.30      # min wysokość gwiazdki wzgl. Mai (5x większe niż dawniej)
const MAJA_STAR_MAX := 0.70      # max wysokość gwiazdki wzgl. Mai
const MAJA_CRY := "res://audio/freesound_community-pokemon-cry-parody-46225.mp3"  # okrzyk pokemona

func _interaction_maja() -> void:
	if _rig == null or _busy:
		return
	if get_node_or_null("MajaPoke"):
		_maja_revert()
		return
	_busy = true
	_intro_done = false

	if _seated:
		_play_own("wstawanie")
		await get_tree().create_timer(_anim_len("wstawanie")).timeout
		if not is_inside_tree() or _rig == null:
			return
		_play_own("stoi")
		_seated = false

	var rect := _display_rect()
	_star_shower(rect, MAJA_SHOWER_TIME)          # gwiazdki lecą równolegle
	await get_tree().create_timer(MAJA_SHOWER_TIME * 0.4).timeout  # chwila sypania
	if not is_inside_tree() or _rig == null:
		return
	# W szczycie sypania — przemiana: chowamy rig, okrzyk pokemona, pojawia się maja_poke.
	_rig.visible = false
	_play_sound(MAJA_CRY)
	_spawn_maja_poke(rect)
	await get_tree().create_timer(MAJA_SHOWER_TIME * 0.6).timeout
	_busy = false
	# Zostaje stworkiem; klik ponowny cofa.


func _maja_revert() -> void:
	if _busy:
		return
	var poke := get_node_or_null("MajaPoke")
	if poke == null:
		return
	_busy = true
	var rect := _display_rect()
	_star_shower(rect, MAJA_SHOWER_TIME * 0.8)
	await get_tree().create_timer(MAJA_SHOWER_TIME * 0.35).timeout
	if is_instance_valid(poke):
		poke.queue_free()
	if _rig:
		_rig.visible = true
		RigHelper.play_stand(_rig)
	await get_tree().create_timer(MAJA_SHOWER_TIME * 0.3).timeout
	_busy = false
	_intro_done = true


func _spawn_maja_poke(rect: Rect2) -> void:
	var tex := load(MAJA_POKE) as Texture2D
	if tex == null:
		return
	var poke := Sprite2D.new()
	poke.name = "MajaPoke"
	poke.texture = tex
	poke.top_level = true
	poke.z_index = 100
	poke.z_as_relative = false
	var s := (rect.size.y * MAJA_POKE_HEIGHT) / float(maxi(tex.get_height(), 1))
	poke.scale = Vector2(s, s)
	# stopy na podłodze (dół sprajta = dół obszaru Mai), środek x = środek Mai
	var foot := Vector2(rect.get_center().x, rect.position.y + rect.size.y)
	poke.global_position = foot - Vector2(0.0, tex.get_height() * s * 0.5)
	add_child(poke)
	# Niespodziewane „pyk": stworek wyskakuje skalą 0 -> pełna (z odbiciem), potem tańczy.
	poke.scale = Vector2.ZERO
	var pop := create_tween()
	pop.tween_property(poke, "scale", Vector2(s, s), 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await pop.finished
	if not is_instance_valid(poke):
		return
	_start_piano_bounce(poke)  # tańczy jak fortepian Wojtka (podskoki z boku na bok)


# --- interakcja Hani: jak Maja, ale dwa pokemony losowane przy każdej przemianie ---
# Gwiazdki: mieszanka blinka Mai + JEDEN losowy blink Amelki. Pokemony 2x mniejsze.
const HANIA_POKES := [
	"res://sprites/hania_poke_1.png",
	"res://sprites/henia_poke_2.png",
]
const HANIA_POKE_HEIGHT := 0.6   # MAJA_POKE_HEIGHT / 2 — pokemony Hani 2x mniejsze
const HANIA_CRY := "res://audio/freesound_community-eevee-voice-clips_128k-26100.mp3"  # głos Eevee

func _interaction_hania() -> void:
	if _rig == null or _busy:
		return
	if get_node_or_null("HaniaPoke"):
		_hania_revert()
		return
	_busy = true
	_intro_done = false

	if _seated:
		_play_own("wstawanie")
		await get_tree().create_timer(_anim_len("wstawanie")).timeout
		if not is_inside_tree() or _rig == null:
			return
		_play_own("stoi")
		_seated = false

	var rect := _display_rect()
	# Mieszanka: blink Mai + jeden losowy blink Amelki; gwiazdki 2x mniejsze.
	var blinks := [MAJA_STAR, AMELKA_BLINKS[randi() % AMELKA_BLINKS.size()]]
	_star_shower(rect, MAJA_SHOWER_TIME, blinks, 0.5)
	await get_tree().create_timer(MAJA_SHOWER_TIME * 0.4).timeout
	if not is_inside_tree() or _rig == null:
		return
	_rig.visible = false
	_play_sound(HANIA_CRY)
	_spawn_hania_poke(rect)
	await get_tree().create_timer(MAJA_SHOWER_TIME * 0.6).timeout
	_busy = false


func _hania_revert() -> void:
	if _busy:
		return
	var poke := get_node_or_null("HaniaPoke")
	if poke == null:
		return
	_busy = true
	var rect := _display_rect()
	var blinks := [MAJA_STAR, AMELKA_BLINKS[randi() % AMELKA_BLINKS.size()]]
	_star_shower(rect, MAJA_SHOWER_TIME * 0.8, blinks, 0.5)
	await get_tree().create_timer(MAJA_SHOWER_TIME * 0.35).timeout
	if is_instance_valid(poke):
		poke.queue_free()
	if _rig:
		_rig.visible = true
		RigHelper.play_stand(_rig)
	await get_tree().create_timer(MAJA_SHOWER_TIME * 0.3).timeout
	_busy = false
	_intro_done = true


func _spawn_hania_poke(rect: Rect2) -> void:
	# Dwa pokemony Hani — LOSUJEMY, który wyskoczy.
	var path: String = HANIA_POKES[randi() % HANIA_POKES.size()]
	var tex := load(path) as Texture2D
	if tex == null:
		return
	var poke := Sprite2D.new()
	poke.name = "HaniaPoke"
	poke.texture = tex
	poke.top_level = true
	poke.z_index = 100
	poke.z_as_relative = false
	var s := (rect.size.y * HANIA_POKE_HEIGHT) / float(maxi(tex.get_height(), 1))
	poke.scale = Vector2(s, s)
	# stopy podniesione o 40 px (pokemon Hani trochę wyżej).
	var foot := Vector2(rect.get_center().x, rect.position.y + rect.size.y - 40.0)
	poke.global_position = foot - Vector2(0.0, tex.get_height() * s * 0.5)
	add_child(poke)
	# Niespodziewane „pyk" + taniec (jak u Mai).
	poke.scale = Vector2.ZERO
	var pop := create_tween()
	pop.tween_property(poke, "scale", Vector2(s, s), 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await pop.finished
	if not is_instance_valid(poke):
		return
	_start_piano_bounce(poke)


# --- interakcja Amelki: jak Maja, ale 3 rodzaje blinków pomieszane w deszczu ---
const AMELKA_POKE := "res://sprites/amelka_poke.png"
const AMELKA_POKE_HEIGHT := 0.6   # MAJA_POKE_HEIGHT / 2 — pokemon Amelki 2x mniejszy
const AMELKA_BLINKS := [
	"res://sprites/amelka_blink_1.png",
	"res://sprites/amelka_blink_2.png",
	"res://sprites/amelka_blink_3.png",
]

func _interaction_amelka() -> void:
	if _rig == null or _busy:
		return
	if get_node_or_null("AmelkaPoke"):
		_amelka_revert()
		return
	_busy = true
	_intro_done = false

	if _seated:
		_play_own("wstawanie")
		await get_tree().create_timer(_anim_len("wstawanie")).timeout
		if not is_inside_tree() or _rig == null:
			return
		_play_own("stoi")
		_seated = false

	var rect := _display_rect()
	_star_shower(rect, MAJA_SHOWER_TIME, AMELKA_BLINKS, 0.5)  # 3 blinki pomieszane, 2x mniejsze
	await get_tree().create_timer(MAJA_SHOWER_TIME * 0.4).timeout
	if not is_inside_tree() or _rig == null:
		return
	_rig.visible = false
	_play_sound(MAJA_CRY)
	_spawn_amelka_poke(rect)
	await get_tree().create_timer(MAJA_SHOWER_TIME * 0.6).timeout
	_busy = false


func _amelka_revert() -> void:
	if _busy:
		return
	var poke := get_node_or_null("AmelkaPoke")
	if poke == null:
		return
	_busy = true
	var rect := _display_rect()
	_star_shower(rect, MAJA_SHOWER_TIME * 0.8, AMELKA_BLINKS, 0.5)
	await get_tree().create_timer(MAJA_SHOWER_TIME * 0.35).timeout
	if is_instance_valid(poke):
		poke.queue_free()
	if _rig:
		_rig.visible = true
		RigHelper.play_stand(_rig)
	await get_tree().create_timer(MAJA_SHOWER_TIME * 0.3).timeout
	_busy = false
	_intro_done = true


func _spawn_amelka_poke(rect: Rect2) -> void:
	var tex := load(AMELKA_POKE) as Texture2D
	if tex == null:
		return
	var poke := Sprite2D.new()
	poke.name = "AmelkaPoke"
	poke.texture = tex
	poke.top_level = true
	poke.z_index = 100
	poke.z_as_relative = false
	var s := (rect.size.y * AMELKA_POKE_HEIGHT) / float(maxi(tex.get_height(), 1))
	poke.scale = Vector2(s, s)
	var foot := Vector2(rect.get_center().x, rect.position.y + rect.size.y)
	poke.global_position = foot - Vector2(0.0, tex.get_height() * s * 0.5)
	add_child(poke)
	# Niespodziewane „pyk" + taniec (jak u Mai).
	poke.scale = Vector2.ZERO
	var pop := create_tween()
	pop.tween_property(poke, "scale", Vector2(s, s), 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await pop.finished
	if not is_instance_valid(poke):
		return
	_start_piano_bounce(poke)


func _star_shower(rect: Rect2, duration: float, stars: Array = [], size_mult: float = 1.0) -> void:
	# Sypie MAJA_STARS gwiazdek rozłożonych w czasie (każda żyje własnym życiem).
	# `stars` = lista ścieżek do tekstur gwiazdek (losowane); pusta => domyślny MAJA_STAR.
	# `size_mult` skaluje wielkość gwiazdek (1.0 = jak u Mai).
	var per := duration / float(maxi(MAJA_STARS, 1))
	for i in MAJA_STARS:
		_spawn_star(rect, stars, size_mult)
		await get_tree().create_timer(per).timeout
		if not is_inside_tree():
			return


func _spawn_star(rect: Rect2, stars: Array = [], size_mult: float = 1.0) -> void:
	# Losuje teksturę gwiazdki z puli (mieszanka kilku rodzajów blinków).
	var pool: Array = stars if not stars.is_empty() else [MAJA_STAR]
	var tex := load(pool[randi() % pool.size()]) as Texture2D
	if tex == null:
		return
	var star := Sprite2D.new()
	star.texture = tex
	star.top_level = true
	star.z_index = 1200          # gwiazdki nad wszystkim, też nad stworkiem
	star.z_as_relative = false
	# losowo w obrębie i nad Mają
	var x := rect.position.x + randf() * rect.size.x
	var y := rect.position.y - rect.size.y * 0.25 + randf() * rect.size.y * 1.1
	star.global_position = Vector2(x, y)
	var s := (rect.size.y * randf_range(MAJA_STAR_MIN, MAJA_STAR_MAX) * size_mult) / float(maxi(tex.get_height(), 1))
	star.scale = Vector2(s, s)
	star.rotation = randf() * TAU
	star.modulate.a = 0.0
	add_child(star)
	var life := randf_range(0.5, 0.9)
	var drop := star.global_position + Vector2(randf_range(-15.0, 15.0),
		rect.size.y * randf_range(0.2, 0.45))
	# opada + lekko się obraca (mienienie)
	var mv := create_tween().set_parallel(true)
	mv.tween_property(star, "global_position", drop, life)
	mv.tween_property(star, "rotation", star.rotation + randf_range(-PI, PI), life)
	# mruga: pojawia -> przygasa -> rozbłyska -> znika
	var bl := create_tween()
	bl.tween_property(star, "modulate:a", 1.0, life * 0.2)
	bl.tween_property(star, "modulate:a", 0.35, life * 0.2)
	bl.tween_property(star, "modulate:a", 1.0, life * 0.2)
	bl.tween_property(star, "modulate:a", 0.0, life * 0.4)
	bl.tween_callback(star.queue_free)


func _fade_in_props(props: Array, time: float) -> void:
	# Pokaż sprajty stopniowo (modulate.a 0 -> 1), równolegle.
	var valid: Array[CanvasItem] = []
	for s in props:
		if s:
			s.visible = true
			s.modulate.a = 0.0
			valid.append(s)
	if valid.is_empty():
		return
	var t := create_tween().set_parallel(true)
	for s in valid:
		t.tween_property(s, "modulate:a", 1.0, time)
	await t.finished


func _hop_rig(to_origin: Vector2, height: float, time: float) -> void:
	# Parabola: przesuwa _rig.global_position od bieżącej do to_origin po łuku.
	if _rig == null:
		return
	var from_origin := _rig.global_position
	var tw := create_tween()
	tw.tween_method(_set_rig_hop.bind(from_origin, to_origin, height), 0.0, 1.0, time)
	await tw.finished


func _set_rig_hop(t: float, from_origin: Vector2, to_origin: Vector2, height: float) -> void:
	if not is_instance_valid(_rig):
		return
	var p := from_origin.lerp(to_origin, t)
	p.y -= height * sin(t * PI)
	_rig.global_position = p


func _spin_node(node: Node2D, pivot: Vector2, total_angle: float, time: float) -> void:
	# Obrót sztywny węzła wokół punktu świata `pivot` o `total_angle` (orbita + rotacja).
	if node == null:
		return
	var start_pos := node.global_position
	var start_rot := node.rotation
	var tw := create_tween()
	tw.tween_method(_apply_spin.bind(node, pivot, start_pos, start_rot, total_angle), 0.0, 1.0, time)
	await tw.finished


func _apply_spin(t: float, node: Node2D, pivot: Vector2, start_pos: Vector2,
		start_rot: float, total_angle: float) -> void:
	if not is_instance_valid(node):
		return
	var ang := total_angle * t
	node.rotation = start_rot + ang
	node.global_position = pivot + (start_pos - pivot).rotated(ang)


func _hop_node(node: Node2D, from_pos: Vector2, to_pos: Vector2, height: float, time: float) -> void:
	# Skok parabolą dowolnego węzła (np. monety) od from_pos do to_pos.
	if node == null:
		return
	var tw := create_tween()
	tw.tween_method(_apply_hop.bind(node, from_pos, to_pos, height), 0.0, 1.0, time)
	await tw.finished


func _apply_hop(t: float, node: Node2D, from_pos: Vector2, to_pos: Vector2, height: float) -> void:
	if not is_instance_valid(node):
		return
	var p := from_pos.lerp(to_pos, t)
	p.y -= height * sin(t * PI)
	node.global_position = p


func _apply_coin_spin(a: float, coin: Sprite2D, s: float) -> void:
	# Obrót monety: szerokość = s*cos(a) — zwęża się do krawędzi (0) i poszerza z powrotem.
	if not is_instance_valid(coin):
		return
	coin.scale.x = s * cos(a)


# --- interakcja Kuby: podskok -> ding -> moneta 5 zł -> podskok -> ding -> człowiek ---

const KUBA_TABLE_POINT := Vector2(360, 800)  # STOPY/dół Kuby na stole (do strojenia); stoi w (360,812)
const KUBA_COIN_HOLD := 3.0          # ile kręci się jako moneta, zanim znów podskoczy
const KUBA_COIN_HEIGHT_FRAC := 0.55  # wielkość monety względem wzrostu Kuby
const KUBA_COIN_SPIN_PERIOD := 0.6   # czas jednego obrotu monety (zwężanie/poszerzanie scale.x)
const KUBA_COIN_SPRITE := "res://sprites/kuba_5zeta.png"
const KUBA_DING_SFX := "res://audio/dragon-studio-ding-sfx-472366.mp3"
var _kuba_home_origin := Vector2.ZERO


func _interaction_kuba() -> void:
	if _rig == null or _busy or get_node_or_null("Moneta"):
		return
	_busy = true
	_intro_done = false

	# Wstaje (jeśli siedzi).
	if _seated:
		_play_own("wstawanie")
		await get_tree().create_timer(_anim_len("wstawanie")).timeout
		if not is_inside_tree() or _rig == null:
			return
		_seated = false

	_kuba_home_origin = _rig.global_position
	var feet0 := _display_rect()
	var home_feet := Vector2(feet0.get_center().x, feet0.end.y)
	var base_h := feet0.size.y
	var table_origin := _kuba_home_origin + (KUBA_TABLE_POINT - home_feet)
	_rig.z_index = BBALL_BENCH_Z

	# 1. Podskakuje i ląduje na stole -> DING -> jest monetą (5 zł).
	_play_own("stoi")
	await _hop_rig(table_origin, BBALL_HOP_HEIGHT, BBALL_HOP_TIME)
	if not is_inside_tree() or _rig == null:
		return
	_play_sfx(KUBA_DING_SFX)
	_rig.visible = false
	var coin := Sprite2D.new()
	coin.name = "Moneta"
	coin.top_level = true
	coin.z_index = 1000
	coin.z_as_relative = false
	add_child(coin)
	var coin_tex := load(KUBA_COIN_SPRITE) as Texture2D
	if coin_tex:
		_set_floor_sprite(coin, coin_tex, base_h * KUBA_COIN_HEIGHT_FRAC, KUBA_TABLE_POINT)
	# Moneta się kręci: scale.x płynnie zwęża się i poszerza (iluzja obrotu 3D).
	# Tween pętli i działa przez cały czas — także w trakcie skoku.
	var spin := create_tween().set_loops()
	spin.tween_method(_apply_coin_spin.bind(coin, coin.scale.y), 0.0, TAU, KUBA_COIN_SPIN_PERIOD)

	# 2. Kręci się jako moneta na stole (3 s przed skokiem).
	await get_tree().create_timer(KUBA_COIN_HOLD).timeout
	if not is_inside_tree():
		return

	# 3. Moneta znów podskakuje (kręcąc się), ląduje na miejscu Kuby -> DING -> człowiek, siada.
	var coin_start := coin.global_position
	var coin_offset := coin_start - KUBA_TABLE_POINT
	var coin_end := home_feet + coin_offset
	await _hop_node(coin, coin_start, coin_end, BBALL_HOP_HEIGHT, BBALL_HOP_TIME)
	if not is_inside_tree():
		return
	spin.kill()
	_play_sfx(KUBA_DING_SFX)
	if is_instance_valid(coin):
		coin.queue_free()
	if _rig:
		_rig.global_position = _kuba_home_origin
		_rig.z_index = 0
		_rig.visible = true
		_play_own("siadanie")
		await get_tree().create_timer(_anim_len("siadanie")).timeout
		if is_inside_tree() and _rig:
			_play_own("siedzi")
		_seated = true
	_busy = false
	_intro_done = true


# --- przemiana (np. Łucja -> brontozaur) ------------------------------------

func _run_transform() -> void:
	# Każde stadium miga na żółto na zmianę z następnym, aż zostaje ostatnie.
	# Przy odwrotnej przemianie sekwencja leci od końca i wraca oryginalny sprite.
	var reverse := transform_state == TransformState.TRANSFORMED
	transform_state = TransformState.RUNNING

	if _transform_orig.is_empty():
		_save_transform_orig()

	var anim: AnimationPlayer = get_node_or_null("AnimationPlayer")
	if anim and anim.is_playing():
		_transform_orig.anim = anim.current_animation
		anim.stop()

	var target: CanvasItem = sprite if sprite else texture_rect
	var seq := transform_textures.duplicate()
	if reverse:
		seq.reverse()

	# Stopniowe rozszerzanie: po pierwszym stadium szerokość rośnie z każdym
	# mignięciem od szerokości wyjściowej do naturalnej szerokości tekstury
	# (trans_2/bronto zaczynają wąskie jak Łucja i puchną do brontozaura).
	var total_steps := (seq.size() - 1) * FLASH_SWAPS
	var step := 0
	for phase in seq.size() - 1:
		for j in FLASH_SWAPS:
			var width_p := clampf(
				float(step + 1 - FLASH_SWAPS) / float(total_steps - FLASH_SWAPS), 0.0, 1.0)
			if reverse:
				width_p = 1.0 - width_p
			_set_transform_texture(seq[phase + (j % 2)], width_p)
			target.modulate = FLASH_COLOUR if j % 2 == 0 else COLOUR_NORMAL
			step += 1
			await get_tree().create_timer(FLASH_TIME).timeout
			if not is_inside_tree():
				return

	target.modulate = COLOUR_NORMAL
	if reverse:
		_restore_transform_orig()
		transform_state = TransformState.NORMAL
	else:
		transform_state = TransformState.TRANSFORMED


func _save_transform_orig() -> void:
	# Wygląd sprzed przemiany + wspólna skala: pierwsza tekstura przemiany ma być
	# tak wysoka, jak klatka, którą uczeń wyświetla na co dzień. Wysokości rysunków
	# stadiów są spójne, więc jeden mnożnik wystarcza (bronto wychodzi szerszy).
	if sprite:
		_transform_orig = {
			"texture": sprite.texture,
			"hframes": sprite.hframes,
			"vframes": sprite.vframes,
			"scale": sprite.scale,
			"position": sprite.position,
			"anim": "",
		}
		var frame_h := float(sprite.texture.get_height()) / sprite.vframes
		var display_h := frame_h * sprite.scale.y
		_transform_scale = display_h / transform_textures[0].get_height()
		_transform_bottom = sprite.position.y + display_h / 2.0
		_transform_base_w = transform_textures[0].get_width() * _transform_scale
	else:
		_transform_orig = { "texture": texture_rect.texture, "anim": "" }


func _set_transform_texture(tex: Texture2D, width_p := 1.0) -> void:
	if sprite:
		sprite.texture = tex
		sprite.hframes = 1
		sprite.vframes = 1
		sprite.frame = 0
		# Szerokość na ekranie: między szerokością stadium wyjściowego
		# a naturalną szerokością tej tekstury, wg postępu przemiany.
		var natural_w := tex.get_width() * _transform_scale
		var w := lerpf(minf(_transform_base_w, natural_w), natural_w, width_p)
		sprite.scale = Vector2(_transform_scale * w / natural_w, _transform_scale)
		sprite.position = Vector2(
			_transform_orig.position.x,
			_transform_bottom - tex.get_height() * _transform_scale / 2.0)
	else:
		texture_rect.texture = tex


func _restore_transform_orig() -> void:
	if sprite:
		sprite.texture = _transform_orig.texture
		sprite.hframes = _transform_orig.hframes
		sprite.vframes = _transform_orig.vframes
		sprite.frame = 0
		sprite.scale = _transform_orig.scale
		sprite.position = _transform_orig.position
	else:
		texture_rect.texture = _transform_orig.texture
	var anim: AnimationPlayer = get_node_or_null("AnimationPlayer")
	if anim and _transform_orig.anim != "":
		anim.play(_transform_orig.anim)


# --- przemiana Łucji w brontozaura: sprajty przejściowe -> animowany rig -------
# Łucja ma rig, więc nie da się użyć dawnego _run_transform (działa na płaskim
# sprajcie). Tu: chowamy rig, migamy sprajtami przejściowymi (norm -> trans_1 ->
# trans_2 -> bronto) z żółtym błyskiem, a finał to animowany rig brontozaura.
# Drugi klik (w brontozaura) odwraca przemianę z powrotem do Łucji.

const LUCJA_BRONTO_RIG := "res://rig/lucja_bronto_rig.tscn"
const BRONTO_HEIGHT_MULT := 1.15   # brontozaur trochę wyższy niż Łucja
const LUCJA_BENCH_POINT := Vector2(644, 654)  # STOPY Łucji po wskoku (do strojenia)
const LUCJA_MAGIC_SFX := "res://audio/rescopicsound-elemental-magic-spell-cast-d-228349.mp3"
const JASIEK_MAGIC_SFX := "res://audio/freesound_community-magic-6976.mp3"
const KORK_SFX := "res://audio/kork.mp3"  # „kork" — magiczna postać znika, dziecko wraca
const MAGIC_REVERT_DELAY := 8.0  # po tylu sekundach magiczna postać sama znika (pyk)

var _lucja_home_origin := Vector2.ZERO  # pozycja rigu przed wskokiem (do powrotu)

func _interaction_lucja() -> void:
	if _rig == null or _busy:
		return
	if get_node_or_null("Bronto"):
		_lucja_revert()        # już jest brontozaurem -> wróć do Łucji
		return

	# transform_textures (ze sceny) = [norm, trans_1, trans_2, bronto].
	if transform_textures.size() < 2:
		return
	_busy = true
	_intro_done = false        # wstrzymaj hover

	# 1. Wstaje (jeśli siedzi) i WSKAKUJE NA ŁAWKĘ przed przemianą (z-index nad ławką).
	if _seated:
		_play_own("wstawanie")
		await get_tree().create_timer(_anim_len("wstawanie")).timeout
		if not is_inside_tree() or _rig == null:
			return
		_seated = false
	_lucja_home_origin = _rig.global_position
	var feet0 := _display_rect()
	var home_feet := Vector2(feet0.get_center().x, feet0.end.y)
	var base_h := feet0.size.y
	var bench_origin := _lucja_home_origin + (LUCJA_BENCH_POINT - home_feet)
	_rig.z_index = BBALL_BENCH_Z
	_play_own("stoi")
	await _hop_rig(bench_origin, BBALL_HOP_HEIGHT, BBALL_HOP_TIME)
	if not is_inside_tree() or _rig == null:
		return

	# 2. Przemiana NA ŁAWCE. Zamiast sprajta lucja_norm — JEJ RIG (stadium „rig").
	#    Miganie: rig (Łucja) <-> trans_1 <-> trans_2 <-> bronto.
	var stages: Array = ["rig"]
	for i in range(1, transform_textures.size()):
		stages.append(transform_textures[i])
	await _lucja_blink_stages(stages, base_h, LUCJA_BENCH_POINT)
	if not is_inside_tree():
		return
	# Finał: animowany rig brontozaura na ławce.
	if _rig:
		_rig.visible = false
	_spawn_bronto(LUCJA_BENCH_POINT, base_h)
	_busy = false


func _lucja_revert() -> void:
	if _busy:
		return
	# „Kork": brontozaur znika, a Łucja NAGLE pojawia się z powrotem na swoim miejscu.
	var bronto := get_node_or_null("Bronto")
	if bronto == null:
		return  # już cofnięte (np. klik tuż przed auto-pyk)
	bronto.queue_free()
	_play_sound(KORK_SFX)
	if _rig:
		_rig.global_position = _lucja_home_origin
		_rig.z_index = 0
		_rig.visible = true
		RigHelper.play_stand(_rig)
	_intro_done = true         # hover wraca


func _lucja_blink_stages(stages: Array, target_h: float, foot_pt: Vector2) -> void:
	# Miganie stadiami. Stadium "rig" = pokaż rig Łucji (błyska żółtym); pozostałe =
	# tymczasowy sprajt. Sprajt lucja_norm nieużywany — zastępuje go rig.
	_play_sfx(LUCJA_MAGIC_SFX)  # dźwięk czaru przy przemianie (w obie strony)
	var spr := Sprite2D.new()
	spr.name = "TransSprite"
	spr.top_level = true
	spr.z_index = 1000        # nad innymi uczniami (oni mają z = 10 + position.y)
	spr.z_as_relative = false
	spr.visible = false
	add_child(spr)
	for phase in stages.size() - 1:
		for j in FLASH_SWAPS:
			var stage = stages[phase + (j % 2)]
			var yellow := (j % 2) == 0
			if stage is String:               # "rig" = Łucja w rigu
				spr.visible = false
				if _rig:
					_rig.visible = true
					_rig.modulate = FLASH_COLOUR if yellow else COLOUR_NORMAL
			else:
				if _rig:
					_rig.visible = false
					_rig.modulate = COLOUR_NORMAL
				spr.visible = true
				_set_floor_sprite(spr, stage, target_h, foot_pt)
				spr.modulate = FLASH_COLOUR if yellow else COLOUR_NORMAL
			await get_tree().create_timer(FLASH_TIME).timeout
			if not is_inside_tree():
				return
	if _rig:
		_rig.modulate = COLOUR_NORMAL
	spr.queue_free()


func _set_floor_sprite(spr: Sprite2D, tex: Texture2D, target_h: float, foot_pt: Vector2) -> void:
	# Sprajt znormalizowany do wysokości target_h, wycentrowany, stopami w foot_pt.
	if tex == null:
		return
	spr.texture = tex
	var s := target_h / float(tex.get_height())
	spr.scale = Vector2(s, s)
	spr.global_position = foot_pt - Vector2(0.0, tex.get_height() * s * 0.5)


func _spawn_bronto(foot_pt: Vector2, base_h: float) -> void:
	var scene := load(LUCJA_BRONTO_RIG) as PackedScene
	if scene == null:
		if _rig:
			_rig.visible = true       # awaryjnie: pokaż z powrotem Łucję
		return
	var bronto := scene.instantiate() as Node2D
	bronto.name = "Bronto"
	bronto.top_level = true
	bronto.z_index = 1000     # nad innymi uczniami (oni mają z = 10 + position.y)
	bronto.z_as_relative = false
	add_child(bronto)
	var b := _rig_bbox(bronto)
	if b.size.y > 0.0:
		var s := (base_h * BRONTO_HEIGHT_MULT) / b.size.y
		bronto.scale = Vector2(s, s)
		# stopy na podłodze: dół bbox = foot_pt.y, środek bbox w foot_pt.x
		var bottom_center := Vector2(b.get_center().x, b.position.y + b.size.y)
		bronto.global_position = foot_pt - s * bottom_center
	# Po przemianie brontozaur staje dęba; gdyby brakło tej animacji — biega.
	var ap := bronto.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap:
		_play_first(ap, ["staje_deba", "biega"])
	_schedule_magic_revert(bronto)  # po MAGIC_REVERT_DELAY sam „pyk" i Łucja wraca


func _play_first(ap: AnimationPlayer, bases: Array) -> void:
	# Odtwórz pierwszą dostępną animację z listy baz (po nazwie lub jako "*/baza").
	for base in bases:
		for a in ap.get_animation_list():
			if a == base or a.ends_with("/" + base):
				ap.play(a)
				return


# --- intro (macha -> siada) + hover (wstaje/siada) — TYLKO własnymi animacjami ---

func _own_anim(base: String) -> String:
	# Nazwa WŁASNEJ animacji ucznia (z jego biblioteki, np. "k/machanie").
	# Nazwy bez "/" (uniwersalny fallback) celowo pomijamy — używamy tylko własnych.
	if _rig_ap == null:
		return ""
	for a in _rig_ap.get_animation_list():
		if a.ends_with("/" + base):
			return a
	return ""

func _play_own(base: String) -> bool:
	var a := _own_anim(base)
	if a == "":
		return false
	_rig_ap.play(a)
	_rig_ap.seek(0.0, true)
	return true

func _anim_len(base: String) -> float:
	var a := _own_anim(base)
	return _rig_ap.get_animation(a).length if a != "" else FALLBACK_ANIM_LEN

func _hover_rect() -> Rect2:
	return _display_rect().grow(HOVER_MARGIN)

func _has_full_own_set() -> bool:
	# Pełen własny zestaw potrzebny do macha->siada oraz hover wstaje/siada.
	if _rig == null:
		return false
	for base in ["machanie", "siadanie", "siedzi", "wstawanie", "stoi"]:
		if _own_anim(base) == "":
			return false
	return true

func intro_wave_then_sit(wave_time: float) -> void:
	# Start klasy: uczeń macha własną animacją, potem siada (i zostaje siedzieć).
	# Bez pełnego własnego zestawu — pomijamy (zostaje jak ustawiony, bez hover).
	if not _has_full_own_set():
		return
	_busy = true
	_play_own("machanie")
	await get_tree().create_timer(wave_time).timeout
	if not is_inside_tree() or _rig == null:
		return
	_play_own("siadanie")
	await get_tree().create_timer(_anim_len("siadanie")).timeout
	if not is_inside_tree() or _rig == null:
		return
	_play_own("siedzi")
	_seated = true
	_busy = false
	_intro_done = true

func _sit_down() -> void:
	_busy = true
	_play_own("siadanie")
	await get_tree().create_timer(_anim_len("siadanie")).timeout
	if not is_inside_tree() or _rig == null:
		return
	_play_own("siedzi")
	_seated = true
	_busy = false
	_consume_pending_click()

func _stand_up() -> void:
	_busy = true
	_play_own("wstawanie")
	await get_tree().create_timer(_anim_len("wstawanie")).timeout
	if not is_inside_tree() or _rig == null:
		return
	_play_own("stoi")
	_seated = false
	_busy = false
	_consume_pending_click()

func _consume_pending_click() -> void:
	# Klik, który padł w trakcie hover-przejścia — teraz odpalamy interakcję.
	if _click_pending:
		_click_pending = false
		react()


# --- interakcje per uczeń (tryb WELCOME) ------------------------------------

const BOOM_TIME := 1.0          # łączny czas „boomowania" (sypią się eksplozje-kręgi)
const BOOM_RIPPLES := 9         # ile eksplozji po kolei (3 tekstury x 3 cykle)
const BOOM_RIPPLE_LIFE := 0.45  # życie jednego kręgu: błyska, rośnie i zanika
const DRAGON_HEIGHT_MULT := 1.3 # wysokość smoka wzgl. Jaśka (i odniesienie dla eksplozji)
const DRAGON_OFFSET := Vector2(-200.0, -50.0)  # przesunięcie smoka (w lewo i w górę), by stał cały na ławce
const DRAGON_NARROW := 0.2      # smok pojawia się tak wąski (skala x), potem się rozszerza
const DRAGON_WIDEN_TIME := 0.6  # czas rozszerzania zwężonego smoka do pełnej szerokości

func _interaction_jasiek() -> void:
	# Klik -> wskazanie na stół -> "boom" -> bach, smok (rig "biega").
	# Drugi klik (w smoka) -> „kork": smok znika, Jasiek nagle wraca na miejsce.
	if _rig == null:
		return
	if get_node_or_null("Smok"):
		_jasiek_revert()
		return
	_busy = true
	_intro_done = false  # wstrzymaj hover na czas akcji

	# 1. Wskazanie na stół. Jeśli siedzi — najpierw wstań. Gest: własna "wskazuje",
	#    a gdy brak takiej animacji — "machanie" (placeholder, dorób k/wskazuje).
	if _seated:
		_play_own("wstawanie")
		await get_tree().create_timer(_anim_len("wstawanie")).timeout
		if not is_inside_tree() or _rig == null:
			return
	var gesture := "wskazuje" if _own_anim("wskazuje") != "" else "machanie"
	_play_own(gesture)
	await get_tree().create_timer(_anim_len(gesture)).timeout
	if not is_inside_tree() or _rig == null:
		return

	# 2. Boom -> smok.
	await _boom_to_dragon()


func _jasiek_revert() -> void:
	# „Kork": smok znika, a Jasiek NAGLE pojawia się z powrotem na swoim miejscu.
	if _busy:
		return
	var smok := get_node_or_null("Smok")
	if smok == null:
		return  # już cofnięte (np. klik tuż przed auto-pyk)
	smok.queue_free()
	_play_sound(KORK_SFX)
	if _rig:
		_rig.visible = true
		RigHelper.play_stand(_rig)
	_intro_done = true   # hover wraca


func _boom_to_dragon() -> void:
	_play_sfx(JASIEK_MAGIC_SFX)  # dźwięk magii przy przemianie w smoka
	var rect := _display_rect()
	var center := rect.get_center()
	var base_h := rect.size.y
	_rig.visible = false

	var booms := [
		load("res://sprites/jasiek_boom_1.png"),
		load("res://sprites/jasiek_boom_2.png"),
		load("res://sprites/jasiek_boom_3.png"),
	]

	# Eksplozje jak kręgi na wodzie: każda to osobny sprajt, który BŁYSKA, rośnie
	# od małego do docelowego i zanika (alpha -> 0). Bez obracania. Tekstury 3 po
	# kolei, rozmiary na zmianę mniejszy/większy, całość stroboskopowo (gęsto po
	# sobie). Duże kręgi rosną do rozmiaru smoka (i większego), żeby eksplozja
	# UZASADNIAŁA wielkość smoka, który z niej wyłazi.
	# Pod eksplozją Jasiek MRUGA jasnożółtym i POSZERZA się (jak stadia u Łucji) —
	# z tego rozdęcia „wyłazi" potem zwężony smok.
	var jas := Sprite2D.new()
	jas.texture = load("res://sprites/jasiek_2026.png")
	jas.top_level = true
	jas.z_index = 90          # pod kręgami (z=100)
	jas.z_as_relative = false
	jas.global_position = center
	add_child(jas)
	var jh := base_h / float(maxi(jas.texture.get_height(), 1))

	var dragon_h := base_h * DRAGON_HEIGHT_MULT
	var per := BOOM_TIME / float(BOOM_RIPPLES)
	for i in BOOM_RIPPLES:
		var tex: Texture2D = booms[i % booms.size()]
		var big := (i % 2) == 0
		var target_h := (dragon_h * 1.35) if big else (base_h * 0.8)
		_spawn_ripple(center, tex, target_h, BOOM_RIPPLE_LIFE)
		# Jasiek pod spodem: stroboskopowy żółty błysk + rosnąca szerokość.
		if is_instance_valid(jas):
			jas.modulate = FLASH_COLOUR if (i % 2 == 0) else COLOUR_NORMAL
			var wp := float(i + 1) / float(BOOM_RIPPLES)
			jas.scale = Vector2(jh * lerpf(0.5, 1.4, wp), jh)
		await get_tree().create_timer(per).timeout
		if not is_inside_tree():
			return

	if is_instance_valid(jas):
		jas.queue_free()

	# BACH: zwężony smok wyłania się i rozszerza, gdy ostatni (duży) krąg jest już
	# rozdmuchany — więc jego rozmiar wynika z eksplozji. Chwila, by krąg urósł.
	await get_tree().create_timer(BOOM_RIPPLE_LIFE * 0.45).timeout
	if not is_inside_tree():
		return
	_spawn_dragon(center, base_h)


func _spawn_ripple(center: Vector2, tex: Texture2D, target_h: float, life: float) -> void:
	# Jeden „krąg na wodzie": błyska (przejaskrawiony), rośnie od małego do target_h
	# i zanika do alpha 0, po czym sam się usuwa.
	if tex == null:
		return
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.top_level = true
	spr.z_index = 100
	spr.z_as_relative = false
	spr.global_position = center
	add_child(spr)
	var s0 := (target_h * 0.25) / float(maxi(tex.get_height(), 1))  # start mały
	var s1 := target_h / float(maxi(tex.get_height(), 1))           # koniec duży
	spr.scale = Vector2(s0, s0)
	spr.modulate = Color(2.2, 2.2, 2.2, 1.0)  # błysk (przejaskrawiony) na starcie
	var t := create_tween().set_parallel(true)
	t.tween_property(spr, "scale", Vector2(s1, s1), life) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(spr, "modulate", Color(1.0, 1.0, 1.0, 0.0), life) \
		.set_trans(Tween.TRANS_SINE)
	t.chain().tween_callback(spr.queue_free)


func _spawn_dragon(center: Vector2, base_h: float) -> void:
	var scene := load("res://rig/jasiek_smok_rig.tscn") as PackedScene
	if scene == null:
		_busy = false
		return
	var dragon := scene.instantiate() as Node2D
	dragon.name = "Smok"
	dragon.top_level = true
	dragon.z_index = 50
	dragon.z_as_relative = false
	add_child(dragon)
	var b := _rig_bbox(dragon)
	if b.size.y > 0.0:
		var s := (base_h * DRAGON_HEIGHT_MULT) / b.size.y   # smok trochę większy niż dziecko
		var anchor := center + DRAGON_OFFSET                # docelowy środek bbox (lewo+góra)
		var bc := b.get_center()
		dragon.scale = Vector2(s, s)
		dragon.global_position = anchor - s * bc
		# Zwężony smok -> rozszerza się do pełnej szerokości (jak stadia u Łucji),
		# zakotwiczony w środku bbox, żeby rósł symetrycznie i nie odpływał.
		var widen := func(sx: float) -> void:
			if not is_instance_valid(dragon):
				return
			dragon.scale.x = sx
			dragon.global_position.x = anchor.x - sx * bc.x
		var tw := create_tween()
		tw.tween_method(widen, s * DRAGON_NARROW, s, DRAGON_WIDEN_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var ap := dragon.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap:
		var anim := ""
		for a in ap.get_animation_list():
			if a == "biega" or a.ends_with("/biega"):  # smok ma "k/biega"
				anim = a
				break
		if anim != "":
			ap.play(anim)
	_schedule_magic_revert(dragon)  # po MAGIC_REVERT_DELAY sam „pyk" i Jasiek wraca
	_busy = false


# --- interakcja Wojtka: boom (skaluj+kręć+mrugaj wojtek_boom) -> fortepian -------
# Klik -> rig znika, uchwyt z grafiką wojtek_boom kręci się, rośnie i mruga (żółto),
# finał: fortepian (wojtek_piano) na miejscu Wojtka + ragtime. Po czasie sam wraca;
# klik w fortepian też cofa. Ragtime jest WYGASZANY na koniec (nie ucinany).

const PIANO_SPRITE := "res://sprites/wojtek_piano.png"
const WOJTEK_BOOM_SPRITE := "res://sprites/wojtek_boom.png"
const WOJTEK_NORMAL_SPRITE := "res://sprites/wojtek_2026.png"
const WOJTEK_MUSIC := "res://audio/faespencer-ragtime-193535.mp3"
const PIANO_HEIGHT_MULT := 2.0    # fortepian 2x większy niż Wojtek (do strojenia)
const PIANO_DROP := 60.0          # o ile px niżej spawnuje się fortepian
const PIANO_BOOM_TIME := 1.2      # łączny czas eksplozji (stroboskop)
const PIANO_BOOM_RIPPLES := 10    # ile wybuchów po kolei (różne rozmiary)
const PIANO_RIPPLE_LIFE := 0.45   # życie jednego wybuchu: błyska, rośnie i zanika
const PIANO_APPEAR_BLINKS := 3    # ile mignięć fortepianu przy pojawieniu
const PIANO_APPEAR_BLINK_TIME := 0.11
const PIANO_BOUNCE_DX_FRAC := 0.09  # bok podskoku jako % szerokości fortepianu
const PIANO_BOUNCE_HOP := 24.0      # wysokość podskoku
const PIANO_BOUNCE_TILT := 0.07     # przechył przy podskoku
const PIANO_BOUNCE_STEP := 0.42     # czas jednego podskoku (góra + lądowanie)

var _wojtek_music: AudioStreamPlayer = null


func _interaction_wojtek() -> void:
	if _rig == null:
		return
	if get_node_or_null("Fortepian"):
		_wojtek_revert()
		return
	if _busy:
		return
	_busy = true
	_intro_done = false
	await _boom_to_piano()


func _wojtek_revert() -> void:
	# Fortepian znika, ragtime się WYGASZA (nie ucina), Wojtek wraca na miejsce.
	if _busy:
		return
	var piano := get_node_or_null("Fortepian")
	if piano == null:
		return
	piano.queue_free()
	_fade_wojtek_music()
	if _rig:
		_rig.visible = true
		RigHelper.play_stand(_rig)
	_intro_done = true


func _boom_to_piano() -> void:
	_start_wojtek_music()  # ragtime gra przez przemianę i fazę fortepianu
	var rect := _display_rect()
	var center := rect.get_center()
	var base_h := rect.size.y
	_rig.visible = false

	var boom_tex := load(WOJTEK_BOOM_SPRITE) as Texture2D

	# Wojtek (NIE rośnie) w środku i podgląd fortepianu w pozycji docelowej —
	# PRZENIKAJĄ SIĘ stroboskopowo (na zmianę widoczne), z czasem coraz częściej fortepian.
	var woj := Sprite2D.new()
	woj.texture = load(WOJTEK_NORMAL_SPRITE)
	woj.top_level = true
	woj.z_index = 90          # pod wybuchami (z=100)
	woj.z_as_relative = false
	woj.global_position = center
	var wh := base_h / float(maxi(woj.texture.get_height(), 1))
	woj.scale = Vector2(wh, wh)
	add_child(woj)

	var pia := Sprite2D.new()
	pia.texture = load(PIANO_SPRITE)
	pia.top_level = true
	pia.z_index = 89
	pia.z_as_relative = false
	var psc := (base_h * PIANO_HEIGHT_MULT) / float(maxi(pia.texture.get_height(), 1))
	pia.scale = Vector2(psc, psc)
	pia.global_position = _piano_pos(center, base_h, pia.texture, psc)
	pia.visible = false
	add_child(pia)

	# Eksplozje stroboskopowo, w RÓŻNYCH rozmiarach: każda błyska, rośnie i zanika.
	var piano_h := base_h * PIANO_HEIGHT_MULT
	var per := PIANO_BOOM_TIME / float(PIANO_BOOM_RIPPLES)
	for i in PIANO_BOOM_RIPPLES:
		var big := (i % 2) == 0
		var target_h := (piano_h * 1.4) if big else (base_h * 0.9)
		_spawn_ripple(center, boom_tex, target_h, PIANO_RIPPLE_LIFE)
		# Przenikanie: coraz częściej widać fortepian, coraz rzadziej Wojtka.
		var p := float(i + 1) / float(PIANO_BOOM_RIPPLES)
		var show_pia := (i == PIANO_BOOM_RIPPLES - 1) or (randf() < p)
		if is_instance_valid(woj):
			woj.visible = not show_pia
		if is_instance_valid(pia):
			pia.visible = show_pia
		await get_tree().create_timer(per).timeout
		if not is_inside_tree():
			return

	if is_instance_valid(woj):
		woj.queue_free()
	if is_instance_valid(pia):
		pia.queue_free()
	# Chwila, by ostatni (duży) wybuch urósł — z niego wyłania się fortepian.
	await get_tree().create_timer(PIANO_RIPPLE_LIFE * 0.45).timeout
	if not is_inside_tree():
		return
	_spawn_piano(center, base_h)
	_busy = false


func _piano_pos(center: Vector2, base_h: float, tex: Texture2D, s: float) -> Vector2:
	# Pozycja (środek) fortepianu: dół na podłodze Wojtka, obniżony o PIANO_DROP.
	var foot := Vector2(center.x, center.y + base_h * 0.5 + PIANO_DROP)
	return foot - Vector2(0.0, tex.get_height() * s * 0.5)


func _spawn_piano(center: Vector2, base_h: float) -> void:
	var tex := load(PIANO_SPRITE) as Texture2D
	if tex == null:
		if _rig:
			_rig.visible = true
		return
	var piano := Sprite2D.new()
	piano.name = "Fortepian"
	piano.top_level = true
	piano.z_index = 50
	piano.z_as_relative = false
	piano.texture = tex
	var s := (base_h * PIANO_HEIGHT_MULT) / float(maxi(tex.get_height(), 1))
	piano.scale = Vector2(s, s)
	piano.global_position = _piano_pos(center, base_h, tex, s)
	add_child(piano)
	# Fortepian pojawia się STOPNIOWO mrugając (żółto <-> normalnie), potem zostaje.
	var blink := create_tween()
	for k in PIANO_APPEAR_BLINKS:
		blink.tween_property(piano, "modulate", FLASH_COLOUR, PIANO_APPEAR_BLINK_TIME)
		blink.tween_property(piano, "modulate", COLOUR_NORMAL, PIANO_APPEAR_BLINK_TIME)
	_start_piano_bounce(piano)     # tańczy: podskakuje z boku na bok z bouncem
	_schedule_magic_revert(piano)  # po MAGIC_REVERT_DELAY sam wraca


func _start_piano_bounce(piano: Sprite2D) -> void:
	# Lekki taniec fortepianu: podskakuje z boku na bok, ląduje z bouncem i przechyłem.
	# Tween związany z fortepianem -> sam ginie, gdy fortepian znika (revert).
	var base := piano.global_position
	var dx := piano.texture.get_width() * piano.scale.x * PIANO_BOUNCE_DX_FRAC
	var half := PIANO_BOUNCE_STEP * 0.5
	var tw := piano.create_tween().set_loops()
	# w prawo: w górę i w bok (z przechyłem), potem lądowanie z bouncem
	tw.tween_property(piano, "global_position", base + Vector2(dx, -PIANO_BOUNCE_HOP), half) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(piano, "rotation", PIANO_BOUNCE_TILT, half)
	tw.tween_property(piano, "global_position", base + Vector2(dx, 0.0), half) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	# w lewo
	tw.tween_property(piano, "global_position", base + Vector2(-dx, -PIANO_BOUNCE_HOP), half) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(piano, "rotation", -PIANO_BOUNCE_TILT, half)
	tw.tween_property(piano, "global_position", base + Vector2(-dx, 0.0), half) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _start_wojtek_music() -> void:
	if _wojtek_music and is_instance_valid(_wojtek_music):
		return
	var stream := load(WOJTEK_MUSIC)
	if stream == null:
		return
	_wojtek_music = AudioStreamPlayer.new()
	_wojtek_music.stream = stream
	add_child(_wojtek_music)
	_wojtek_music.play()


func _fade_wojtek_music() -> void:
	# Wygaś ragtime (nie ucinaj) na koniec animacji.
	if _wojtek_music == null or not is_instance_valid(_wojtek_music):
		_wojtek_music = null
		return
	var m := _wojtek_music
	_wojtek_music = null
	var fade := create_tween()
	fade.tween_property(m, "volume_db", -40.0, 0.8)
	fade.tween_callback(m.queue_free)


# --- interakcja Oliwii: macha -> kot wyskakuje, skacze na biurko Kamili -------
# Pierwszy klik w Oliwię: macha, kot miauczy i wyskakuje spod jej ławki, skacze
# przez klasę i siada na biurku pani Kamili (zostaje tam). Klik w kota: znów
# miauczy, skacze z powrotem pod ławkę Oliwki i znika.

const CAT_HOP_TIME := 0.5       # czas jednego skoku (= długość anim kota "skacze")
const CAT_HOP_HEIGHT := 80.0    # wysokość paraboli skoku
const CAT_HEIGHT_FRAC := 0.32   # wysokość skaczącego kota (rig) wzgl. wysokości Oliwii
const CAT_STOI_HEIGHT_FRAC := 0.42  # wysokość siedzącego kota (sprajt "stoi"); siedzi wyżej
const CAT_MEOW := "res://audio/dragon-studio-cat-meow-401729.mp3"
const CAT_RIG := "res://rig/oliwia_kot_rig.tscn"

var _cat_resting := false   # kot siedzi na biurku Kamili (klikalny, by go odesłać)


func _interaction_oliwia() -> void:
	if _rig == null or get_node_or_null("Kot") or _busy:
		return  # już jest kot, brak rigu albo trwa akcja
	_busy = true
	_intro_done = false  # wstrzymaj hover na czas akcji

	# 1. Jeśli siedzi — wstań, potem pomachaj.
	if _seated:
		_play_own("wstawanie")
		await get_tree().create_timer(_anim_len("wstawanie")).timeout
		if not is_inside_tree() or _rig == null:
			return
		_seated = false
	_play_own("machanie")
	await get_tree().create_timer(_anim_len("machanie")).timeout
	if not is_inside_tree() or _rig == null:
		return
	_play_own("stoi")

	# 2. Kot miauczy, wyskakuje spod ławki i skacze na biurko Kamili.
	await _cat_jumps_out()
	_busy = false
	_intro_done = true  # hover wraca


func _cat_jumps_out() -> void:
	var cat := _make_cat_rig()
	if cat == null:
		return
	_cat_meow()  # miauknięcie przy wyskoku
	var b := _rig_bbox(cat)
	var rect := _display_rect()
	var h := rect.size.y
	var base_scale := (h * CAT_HEIGHT_FRAC / b.size.y) if b.size.y > 0.0 else 1.0
	var ap := cat.get_node_or_null("AnimationPlayer") as AnimationPlayer

	var under := _oliwia_under_point()  # spod ławki Oliwki
	var desk := _kamila_desk_point()
	await _cat_hop_path(cat, b, base_scale, ap, under, desk)
	if not is_instance_valid(cat) or not is_inside_tree():
		return
	# Siada na biurku Kamili — osobny sprajt „stoi" (zostaje, dopóki się go nie kliknie).
	cat.name = "_kot_rig"   # zwolnij nazwę "Kot" dla sprajta stoi
	cat.queue_free()
	_spawn_cat_stoi(desk, h)
	_cat_resting = true


func _cat_returns() -> void:
	# Klik w siedzącego kota: miauczy, skacze z powrotem pod ławkę Oliwki i znika.
	if _busy:
		return
	_busy = true
	_cat_meow()
	var desk := _kamila_desk_point()
	var old := get_node_or_null("Kot")
	if old:
		old.name = "_kot_stoi"   # zwolnij nazwę dla rigu
		old.queue_free()

	var cat := _make_cat_rig()
	if cat == null:
		_busy = false
		_cat_resting = false
		return
	var b := _rig_bbox(cat)
	var rect := _display_rect()
	var h := rect.size.y
	var base_scale := (h * CAT_HEIGHT_FRAC / b.size.y) if b.size.y > 0.0 else 1.0
	var ap := cat.get_node_or_null("AnimationPlayer") as AnimationPlayer

	var under := _oliwia_under_point()
	await _cat_hop_path(cat, b, base_scale, ap, desk, under)
	if is_instance_valid(cat):
		cat.queue_free()   # chowa się pod ławkę Oliwki — znika
	_cat_resting = false
	_busy = false


func try_click_cat(world_pos: Vector2) -> bool:
	# Wywoływane przez Classroom przy kliknięciu: jeśli to klik w siedzącego kota
	# Oliwki — odsyłamy go i zwracamy true (klik „skonsumowany").
	if String(name) != "Oliwka" or not _cat_resting or _busy:
		return false
	var kot := get_node_or_null("Kot") as Sprite2D
	if kot == null or kot.texture == null:
		return false
	var sz := kot.texture.get_size() * kot.scale.abs()
	if not Rect2(kot.global_position - sz * 0.5, sz).has_point(world_pos):
		return false
	_cat_returns()
	return true


func _make_cat_rig() -> Node2D:
	var scene := load(CAT_RIG) as PackedScene
	if scene == null:
		return null
	var cat := scene.instantiate() as Node2D
	cat.name = "Kot"
	cat.top_level = true         # własne współrzędne świata — skacze po całej klasie
	cat.z_index = 500
	cat.z_as_relative = false
	add_child(cat)
	return cat


func _cat_hop_path(cat: Node2D, b: Rect2, base_scale: float, ap: AnimationPlayer,
		from_pt: Vector2, to_pt: Vector2) -> void:
	# Seria skoków w linii prostej od from_pt do to_pt; liczba skoków ~ co 220 px.
	var n := maxi(3, int(from_pt.distance_to(to_pt) / 220.0))
	_place_cat(cat, b, base_scale, true, from_pt)
	var prev := from_pt
	for i in range(1, n + 1):
		var next := from_pt.lerp(to_pt, float(i) / n)
		await _cat_hop(cat, b, base_scale, ap, prev, next)
		if not is_instance_valid(cat) or not is_inside_tree():
			return
		prev = next


func _kamila_desk_point() -> Vector2:
	# Punkt na blacie biurka pani Kamili, gdzie kot siada (stopy) — ustalony ręcznie.
	return Vector2(801.0, 991.0)


func _oliwia_under_point() -> Vector2:
	# Punkt spod ławki Oliwki = środek u dołu jej sylwetki. Bierzemy PRAWDZIWY
	# prostokąt świata grafiki (get_global_rect, ze skalą ucznia — czego _display_rect
	# dla uczniów bez Sprite2D nie uwzględnia), więc kot wyskakuje dokładnie spod niej.
	var r := texture_rect.get_global_rect()
	return Vector2(r.get_center().x, r.end.y + r.size.y * 0.10)


func _cat_meow() -> void:
	_play_sfx(CAT_MEOW)


func _play_sfx(path: String) -> void:
	# Jednorazowy dźwięk; AudioStreamPlayer sam się usuwa po odtworzeniu.
	var stream := load(path)
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _cat_hop(cat: Node2D, b: Rect2, base_scale: float, ap: AnimationPlayer,
		from_pt: Vector2, to_pt: Vector2) -> void:
	var face_left := to_pt.x <= from_pt.x   # kot domyślnie patrzy w lewo
	if ap:
		_cat_play(ap, "skacze")
	var hop := func(p: float) -> void:
		var pos := from_pt.lerp(to_pt, p)
		pos.y -= sin(p * PI) * CAT_HOP_HEIGHT
		_place_cat(cat, b, base_scale, face_left, pos)
	var t := create_tween()
	t.tween_method(hop, 0.0, 1.0, CAT_HOP_TIME)
	await t.finished


func _place_cat(cat: Node2D, b: Rect2, base_scale: float, face_left: bool,
		point: Vector2) -> void:
	# Ustaw kota tak, by środek jego bbox wypadł w `point`. Kot domyślnie patrzy
	# w lewo: w lewo = +skala, w prawo = lustro (-skala x).
	if not is_instance_valid(cat):
		return
	var sx := base_scale if face_left else -base_scale
	cat.scale = Vector2(sx, base_scale)
	cat.global_position = point - Vector2(sx, base_scale) * b.get_center()


func _spawn_cat_stoi(foot_pt: Vector2, oliwia_h: float) -> void:
	# Pozа spoczynkowa kota = osobny rysunek (oliwia_kot_stoi.png), nie animacja rigu.
	# Kot siedzi przodem (symetryczny) — bez lustrzenia. Dół sprajta = stopy na ławce.
	var rest := Sprite2D.new()
	rest.name = "Kot"
	rest.top_level = true
	rest.z_index = 500
	rest.z_as_relative = false
	rest.texture = load("res://sprites/oliwia_kot_stoi.png")
	if rest.texture == null:
		return
	var th := float(rest.texture.get_height())
	var s := oliwia_h * CAT_STOI_HEIGHT_FRAC / th
	rest.scale = Vector2(s, s)
	rest.global_position = foot_pt - Vector2(0, th * s * 0.5)
	add_child(rest)


func _cat_play(ap: AnimationPlayer, base: String) -> void:
	for a in ap.get_animation_list():
		if a == base or a.ends_with("/" + base):
			ap.play(a)
			ap.seek(0.0, true)
			return


static func _rig_bbox(rig: Node2D) -> Rect2:
	var poly := rig.get_node_or_null("Polygon2D") as Polygon2D
	if poly == null or poly.polygon.is_empty():
		return Rect2()
	var pts := poly.polygon
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return Rect2(poly.position + r.position * poly.scale, r.size * poly.scale)


func _physics_process(delta):
	if Engine.is_editor_hint():
		return
	if character_state in [CharacterState.READY, CharacterState.RESPAWNING]:
		return

	z_index = 10 + position.y

	match character_state:
		CharacterState.LOCKED:
			direction = Vector2.ZERO
			global_position = start_position

		CharacterState.RETURNING:
			move_along_agent(delta)
			if global_position.distance_to(start_position) < 5:
				enter_locked_state()

		CharacterState.MOVING:
			if agent.is_navigation_finished():
				pick_new_target()
			elif GameState.current_type == GameState.GameType.QUIZ:
				move_along_agent(delta) # legacy chase (uśpione — patrz Faza 1)

func move_along_agent(_delta):
	var next_pos = agent.get_next_path_position()
	direction = (next_pos - global_position).normalized()
	if $AnimationPlayer:
		$AnimationPlayer.play('walk')
	velocity = direction * speed
	move_and_slide()

func pick_new_target():
	agent.target_position = NavigationServer2D.map_get_random_point(nav_map_rid, 1, false)
	character_state = CharacterState.MOVING

func return_to_start():
	character_state = CharacterState.RETURNING
	agent.target_position = start_position

func enter_locked_state():
	if $AnimationPlayer:
		$AnimationPlayer.play('idle')
	character_state = CharacterState.LOCKED
	direction = Vector2.ZERO
	start_respawn_timer()

	if respawn_count > MAX_RESPAWN_COUNT:
		blink(COLOUR_LOCKED, 0, 0.5)

func start_respawn_timer():
	respawn_timer.start(RESPAWN_TIMEOUT + respawn_count)
	respawn_count += 1

func cancel_respawn():
	if blink_tween and blink_tween.is_running():
		blink_tween.kill()
		texture_rect.modulate = COLOUR_NORMAL

	respawn_timer.stop()
	character_state = CharacterState.LOCKED
	if respawn_count >= MAX_RESPAWN_COUNT:
		blink(COLOUR_LOCKED, 0, 0.5)
	else:
		blink(COLOUR_CANCEL_RESPAWN, 0, 0.5)
		await get_tree().create_timer(0.5).timeout
		start_respawn_timer()

func _on_respawn_timer_timeout():
	if character_state == CharacterState.LOCKED and respawn_count <= MAX_RESPAWN_COUNT:
		character_state = CharacterState.RESPAWNING
		blink(COLOUR_RESPAWN, 1, 0)
		await get_tree().create_timer(1).timeout

		if character_state == CharacterState.RESPAWNING:
			pick_new_target()
	#elif respawn_count > MAX_RESPAWN_COUNT:
		#texture_rect.modulate = COLOUR_LOCKED

func blink(highlight_colour: Color, fade_in: float = 0.3, fade_out: float = 0.3):
	if blink_tween and blink_tween.is_running():
		blink_tween.kill()
		texture_rect.modulate = COLOUR_NORMAL
		
	if sprite:
		blink_tween = create_tween()
		blink_tween.tween_property(sprite, "modulate", highlight_colour, fade_in)
		blink_tween.tween_property(sprite, "modulate", COLOUR_NORMAL, fade_out)
	
	else:

		blink_tween = create_tween()
		blink_tween.tween_property(texture_rect, "modulate", highlight_colour, fade_in)
		blink_tween.tween_property(texture_rect, "modulate", COLOUR_NORMAL, fade_out)


func is_available() -> bool:
	return character_state == CharacterState.READY

func is_moving() -> bool:
	return character_state == CharacterState.MOVING
