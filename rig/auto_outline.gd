@tool
extends Polygon2D

# Automatyczny obrys sprite'a po kanale alpha (to samo, co edytorowe
# "Convert to Polygon2D", ale w miejscu — wpisuje obrys do tego Polygon2D).
# Po obrysowaniu trzeba jeszcze ręcznie dodać Internal Vertices przy stawach
# (UV -> Points) i pomalować wagi (UV -> Bones) — tego automat nie zrobi.

# JEDEN PRZYCISK: rozstawia kości z obrysu, obrysowuje gęsto + punkty
# wewnętrzne, trianguluje, liczy wagi i ustawia kolejność — cały rig naraz.
@export_tool_button("★ ZRÓB WSZYSTKO (kości → obrys → wagi)", "PlayStart") var _all_in_one := _do_everything

# Tolerancja upraszczania obrysu (px): mniejsza = wierniej, więcej punktów.
@export_range(0.5, 30.0, 0.5) var epsilon := 4.0
# Maks. długość krawędzi obrysu (px): dłuższe są dzielone — gęstszy, równy obrys.
@export_range(20.0, 120.0, 5.0) var max_edge := 45.0
# Próg alfa obrysu: piksel należy do sylwetki, gdy alfa > prog. Wyżej (np. 0.35)
# = ignoruje blade, rozwiane kosmyki (włosy ołówkiem), czystszy kontur.
@export_range(0.05, 0.9, 0.05) var prog_alfa := 0.1
# Domknięcie luk (px): rozszerza maskę i ściąga z powrotem (domknięcie morfolog.).
# Dla rozwianych/rzadkich włosów scala kosmyki w jedną bryłę — znika dziurawy,
# kolczasty obrys. 0 = wyłączone (sprajty z pełnym, gęstym wypełnieniem).
@export_range(0, 40, 1) var domknij_luki := 0
@export_tool_button("Obrysuj sprite'a", "CurveEdit") var _trace_btn := _trace
# Po dodaniu Internal Vertices automatyczna triangulacja Godota się wyłącza
# (sprite znika) — ten przycisk buduje pod-poligony (trójkąty) automatycznie.
@export_tool_button("Triangulacja (po dodaniu punktów)", "MeshInstance2D") var _tri_btn := _triangulate
# Edycja obrysu w głównym viewporcie zmienia TYLKO `polygon` — uv i wagi
# zostają stare (różne długości = Godot nic nie rysuje). Ten przycisk je
# dopasowuje: uv = polygon, stare wierzchołki trzymają wagi, nowe dziedziczą
# po najbliższym starym.
@export_tool_button("Napraw UV i wagi (po edycji obrysu)", "Tools") var _repair_btn := _repair
# Automatyczne wagi z geometrii szkieletu: wierzchołek należy do najbliższej
# kości, a wokół stawów wagi rozmywają się z kością sąsiednią (przy stawie
# 50/50, zanik liniowy w promieniu blend_radius).
@export_range(20.0, 150.0, 5.0) var blend_radius := 60.0
@export_tool_button("Auto-wagi (ze szkieletu)", "Bone2D") var _weights_btn := _auto_weights

# Połowa "grubości" kości (px): tułów i głowa to szerokie bryły — ich boki
# mają należeć do nich, a nie do przebiegającej bliżej kreski ramienia.
# Wartości to fallback — dla tułowia i głowy realna szerokość jest mierzona
# z obrysu (scanline) w _auto_weights. Kończyny: wartość wąska.
const BONE_HALF_WIDTH := { "Biodra": 60.0, "Tulow": 60.0, "Glowa": 45.0 }
const LIMB_HALF_WIDTH := 12.0

# Kolejność rysowania trójkątów wg dominującej kości (większa = na wierzchu).
# Przy pozach z rękami przed tułowiem decyduje o tym, co kogo zasłania.
const DRAW_LAYER := {
	"Ramie": 2.0, "Przedramie": 3.0, "Dlon": 4.0,  # ręce nad tułowiem
}
const DRAW_LAYER_DEFAULT := 0.0

# Automatyczne rozstawienie kości na podstawie obrysu: skrajne punkty to
# czubek głowy / dłonie / stopy, krocze z wcięcia między nogami (fallback:
# proporcja), łokcie i kolana w połowie kończyn. Wynik to szkic — stawy
# dociąga się ręcznie, potem "Przelicz siatkę i wagi".
@export_tool_button("Rozstaw kości ze sprite'a", "Skeleton2D") var _skel_btn := _auto_skeleton

# Kombajn po każdej zmianie punktów lub kości: triangulacja (jeśli są punkty
# wewnętrzne) + auto-wagi. Obrys zostaje, jaki jest.
@export_tool_button("Przelicz siatkę i wagi", "Reload") var _all_btn := _rebuild_all
# Sortuje trójkąty wg DRAW_LAYER — ręce/dłonie rysowane na wierzchu. Potrzebne,
# gdy w animacji ręce składają się przed tułowiem (inaczej tułów je zasłania).
@export_tool_button("Ręce na wierzch (kolejność)", "Sort") var _order_btn := _order_draw

# Sync rest POJEDYNCZEJ kości: ustawia jej rest = aktualny transform (jak
# "Overwrite Rest Pose" w menu Skeleton2D, ale tylko dla wskazanej kości).
# Użycie: przesuń kość w viewporcie, przeciągnij ją do pola 'Sync Rest Bone'
# poniżej, kliknij — sprajt wraca do nieodkształconego, wagi zostają (dzieci
# kości też, bo rest jest względem rodzica). Konwencja rigu: rest rotacja 0,
# więc przesuwaj przeguby (pozycja), nie obracaj kości.
@export var sync_rest_bone: Bone2D
@export_tool_button("Sync rest wskazanej kości", "BoneAttachment2D") var _sync_one_btn := _sync_rest_one

# TRYB: edycja szkieletu na NIERUCHOMYM sprajcie. Gdy włączony, rest każdej
# kości podąża na bieżąco za jej transformem, więc deformacja = (transform vs
# rest) = 0 — możesz przeciągać dowolne kości w odpowiednie miejsca, a sprajt
# stoi. Tego Godot nie ma natywnie (deformuje na żywo). Po ustawieniu kości:
# WYŁĄCZ tryb, potem "Przelicz siatkę i wagi" (żeby wierzchołki trafiły do
# nowych kości). Działa tylko w edytorze.
@export var edytuj_szkielet_bez_deformacji := false:
	set(v):
		edytuj_szkielet_bez_deformacji = v
		if v:
			print("auto_outline: TRYB edycji szkieletu WŁĄCZONY — przesuwaj kości, "
				+ "sprajt zamrożony. Po ustawieniu: wyłącz tryb i 'Przelicz siatkę i wagi'.")

# Kalibracja "stoi" + AUTOMATYCZNE wygenerowanie wszystkich animacji postaci.
# Użycie: obróć kości tak, by postać stała prosto (ręce wzdłuż ciała, nogi
# pionowo), kliknij — przycisk: 1) zapisuje rotacje (metadane stoi_calib),
# 2) retargetuje wspólne animacje pod te proporcje (rotacja = stoi +
# (wspólna − wspólne_stoi); skale kopiuje; RESET zostawia; siad dokłada
# opuszczenie bioder; piłka — tor na podłodze), 3) zapisuje <postać>_anims.tres
# i wpina jako 'k' do AnimationPlayera. Potem Ctrl+S. (Scena musi być wcześniej
# zapisana, żeby znać ścieżkę pliku.)
@export_tool_button("Zapisz stoi i wygeneruj animacje (k)", "Save") var _save_stoi_btn := _save_stoi
const SHARED_LIB := "res://rig/pupil_anims.tres"


func _bone_path_of(track_path: String) -> String:
	var p := track_path
	if p.begins_with("Skeleton2D/"):
		p = p.substr("Skeleton2D/".length())
	var c := p.find(":")
	return p.substr(0, c) if c >= 0 else p


func _save_stoi() -> void:
	var skel := get_node_or_null(skeleton) as Skeleton2D
	if skel == null:
		push_warning("auto_outline: brak Skeleton2D")
		return
	# 1) złap kalibrację stoi z obecnych rotacji kości
	var bl: Array = []
	_collect_bones(skel, bl)
	var calib := {}
	var nonzero := 0
	for b in bl:
		calib[str(skel.get_path_to(b))] = b.rotation
		if absf(b.rotation) > 0.001:
			nonzero += 1
	# Bezpiecznik: przycisk łapie BIEŻĄCE rotacje. Jeśli wszystkie są 0, to znaczy
	# że kości nie są obrócone do stoi (albo zresetowały się) — nie nadpisujemy
	# dobrej kalibracji zerami. Najpierw obróć kości, kliknij gdy są obrócone.
	if nonzero == 0:
		push_warning("auto_outline: kości na rotacji 0 — najpierw obróć je do pozy "
			+ "'stoi', kliknij gdy SĄ obrócone. Nic nie zapisano.")
		return
	set_meta("stoi_calib", calib)
	# 2) ścieżka biblioteki z nazwy sceny: <katalog>/<nazwa bez _rig>_anims.tres
	var scene_path: String = owner.scene_file_path if owner else ""
	if scene_path == "":
		push_warning("auto_outline: zapisz scenę (Ctrl+S), potem kliknij ponownie")
		return
	var base := scene_path.get_file().get_basename().trim_suffix("_rig")
	var lib_path := scene_path.get_base_dir().path_join(base + "_anims.tres")
	# 3) retarget do biblioteki (istniejącą wczytujemy — zachowa ręczne anim, np. piłki)
	var lib: AnimationLibrary
	if ResourceLoader.exists(lib_path):
		lib = load(lib_path)
	else:
		lib = AnimationLibrary.new()
	_retarget_into(lib, calib, skel)
	var err := ResourceSaver.save(lib, lib_path)
	if err != OK:
		push_warning("auto_outline: zapis biblioteki nieudany: " + str(err))
		return
	# 4) wepnij jako 'k' do AnimationPlayera
	var ap := owner.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap:
		var saved: AnimationLibrary = load(lib_path)
		if ap.has_animation_library("k"):
			ap.remove_animation_library("k")
		ap.add_animation_library("k", saved)
	print("auto_outline: stoi (%d kości z obrotem) → animacje zretargetowane do %s, wpięte jako 'k'. Graj k/stoi, k/machanie… Teraz Ctrl+S."
		% [nonzero, lib_path])


func _retarget_into(lib: AnimationLibrary, calib: Dictionary, skel: Skeleton2D) -> void:
	var shared := load(SHARED_LIB) as AnimationLibrary
	var biodra: Vector2 = (skel.get_node("Biodra") as Bone2D).rest.origin
	var bottom := -1e9
	for p in polygon:
		bottom = maxf(bottom, p.y)
	var sit_drop := roundf(0.5 * (bottom - biodra.y))
	# wspólne stoi — referencja rotacji
	var sref := {}
	var sstoi := shared.get_animation("stoi") as Animation
	for ti in sstoi.get_track_count():
		var sp := str(sstoi.track_get_path(ti))
		if sp.ends_with(":rotation"):
			sref[_bone_path_of(sp)] = float(sstoi.track_get_key_value(ti, 0))
	# piłka (jeśli postać ją ma) — pozycja na podłodze
	var has_pilka: bool = owner and owner.has_node("Pilka")
	var floor_pos := Vector2.ZERO
	if has_pilka:
		var pilka := owner.get_node("Pilka") as Sprite2D
		var bh := pilka.texture.get_height() * pilka.scale.y * 0.5
		floor_pos = Vector2(biodra.x + 90, bottom - bh)
	var sit := {"siedzi": [1.0, 1.0], "siadanie": [0.0, 1.0], "wstawanie": [1.0, 0.0]}
	var up := biodra
	var down := biodra + Vector2(0, sit_drop)
	for name in shared.get_animation_list():
		var anim := (shared.get_animation(name) as Animation).duplicate(true)
		var length: float = maxf(anim.length, 0.0001)
		if name != "RESET":
			for ti in anim.get_track_count():
				var ap := str(anim.track_get_path(ti))
				if ap.ends_with(":rotation") and anim.track_get_type(ti) == Animation.TYPE_VALUE:
					var off: float = float(calib.get(_bone_path_of(ap), 0.0)) - float(sref.get(_bone_path_of(ap), 0.0))
					if absf(off) > 0.0001:
						for ki in anim.track_get_key_count(ti):
							anim.track_set_key_value(ti, ki, float(anim.track_get_key_value(ti, ki)) + off)
		if has_pilka:
			var tp: int = anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(tp, NodePath("Pilka:position"))
			anim.track_insert_key(tp, 0.0, floor_pos)
			anim.track_insert_key(tp, length, floor_pos)
		if sit.has(name):
			var fr: Array = sit[name]
			var tb: int = anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(tb, NodePath("Skeleton2D/Biodra:position"))
			anim.track_insert_key(tb, 0.0, up.lerp(down, fr[0]))
			anim.track_insert_key(tb, length, up.lerp(down, fr[1]))
		if lib.has_animation(name):
			lib.remove_animation(name)
		lib.add_animation(name, anim)


func _do_everything() -> void:
	# Cały rig jednym kliknięciem. Kolejność ma znaczenie:
	# 1) wstępny obrys (auto-rozstaw kości potrzebuje konturu do wykrycia
	#    głowy/dłoni/stóp), 2) rozstaw kości z tego konturu, 3) właściwy obrys
	#    (gęsty + punkty wewnętrzne na już ustawionych kościach) — _trace sam
	#    domyka triangulację, wagi i kolejność rysowania.
	if texture == null:
		push_warning("auto_outline: Polygon2D nie ma tekstury")
		return
	if get_node_or_null(skeleton) == null:
		push_warning("auto_outline: ustaw właściwość 'skeleton' (Skeleton2D) i powtórz")
		return
	# Normalizuj skalę Polygon2D do 1 — rig liczymy w pikselach sprajta. Po
	# sklonowaniu riga na inny sprajt skala bywa rozjechana (rozciąga ciało
	# i rozsypuje kości). Powiększanie do gry rób na węźle-korzeniu.
	if scale != Vector2.ONE:
		print("auto_outline: normalizuję skalę Polygon2D %s -> (1,1)" % str(scale))
		scale = Vector2.ONE
	if polygon.size() < 8:
		_trace()        # potrzebny kontur do auto-rozstawienia kości
	_auto_skeleton()    # rozstaw kości z obrysu
	_trace()            # gęsty obrys + punkty wewnętrzne + triangulacja + wagi + kolejność
	print("auto_outline: ★ gotowe — rig złożony (kości, siatka, wagi, kolejność)")


func _rebuild_all() -> void:
	_neutralize(get_node_or_null(skeleton) as Skeleton2D)
	_sync_rests()
	_triangulate()   # zawsze jawne trójkąty (potrzebne do kolejności rysowania)
	_auto_weights()
	_order_draw()


func _sync_rests() -> void:
	# Konwencja rigu: rest = pozycja kości, rotacja w spoczynku 0.
	# Po przesuwaniu kości w viewporcie nie trzeba pamiętać o "Set Rest".
	var skel := get_node_or_null(skeleton) as Skeleton2D
	if skel == null:
		return
	var bones_list: Array = []
	_collect_bones(skel, bones_list)
	for bone in bones_list:
		# Wymuś spoczynek: rotacja 0. Wagi/siatkę liczymy ZAWSZE na pozie
		# spoczynkowej — inaczej (np. podgląd animacji) odcinki kości się
		# rozjeżdżają i wagi wychodzą bez sensu.
		if absf(bone.rotation) > 0.001:
			print("auto_outline: zeruję rotację kości %s (%.2f -> 0)" % [bone.name, bone.rotation])
			bone.rotation = 0.0
		# Konwencja: rest = identyczność (rotacja 0, skala 1) + origin = pozycja
		# kości. Wymuszamy też rotację 0 w SAMYM REST — gdyby coś ją zabakeowało
		# (np. tryb edycji szkieletu odpalony podczas pozy/scrubu animacji),
		# inaczej animacje (liczone względem rest=0) byłyby przekręcone.
		var want := Transform2D(0.0, bone.position)
		if not bone.rest.is_equal_approx(want):
			if not bone.rest.x.is_equal_approx(Vector2(1, 0)):
				print("auto_outline: czyszczę zabakeowaną rotację w rest kości %s" % bone.name)
			bone.rest = want


func _sync_rest_one() -> void:
	# Nadpisuje rest TYLKO wskazanej kości jej aktualnym transformem — sprajt
	# wraca do nieodkształconego (deformacja = aktualny vs rest), wagi bez zmian.
	# Reszta szkieletu nietknięta; dzieci tej kości też się prostują (rest jest
	# względem rodzica). NIE da się cofnąć (Skeleton2D nie wspiera undo restu).
	if sync_rest_bone == null:
		push_warning("auto_outline: wskaż kość w polu 'Sync Rest Bone'")
		return
	sync_rest_bone.rest = sync_rest_bone.transform
	print("auto_outline: rest kości '%s' = jej transform %s (sprajt wyprostowany, wagi bez zmian)"
		% [sync_rest_bone.name, str(sync_rest_bone.position)])


func _process(_delta: float) -> void:
	# Tryb edycji szkieletu: rest każdej kości goni jej transform, więc ruch
	# kości nie odkształca sprajta. Guard (rest != transform) → zapis tylko gdy
	# kość faktycznie się ruszy. Tylko w edytorze i tylko przy włączonym trybie.
	if not edytuj_szkielet_bez_deformacji or not Engine.is_editor_hint():
		return
	var skel := get_node_or_null(skeleton) as Skeleton2D
	if skel == null:
		return
	var bl: Array = []
	_collect_bones(skel, bl)
	for b in bl:
		# Sync TYLKO pozycji (rest rotacja zawsze 0): przesuwanie kości nie
		# deformuje, ale obrót już tak — świadomie, bo w spoczynku kości się NIE
		# obraca (rotacje są dla animacji). Dzięki temu nic się nie zabakeuje do
		# rest, gdyby tryb był włączony podczas pozy/scrubu animacji.
		var want := Transform2D(0.0, b.position)
		if not b.rest.is_equal_approx(want):
			b.rest = want


func _ready() -> void:
	# Tryb edycji szkieletu jest PRZEJŚCIOWY — resetujemy go do false przy każdym
	# wczytaniu sceny, żeby nie został włączony po cichu (zamrożony sprajt =
	# "sprajt nie idzie za szkieletem"). Włączasz go ręcznie na czas rozstawiania.
	if Engine.is_editor_hint() and edytuj_szkielet_bez_deformacji:
		edytuj_szkielet_bez_deformacji = false


func _neutralize(skel: Skeleton2D) -> void:
	# Rig do liczenia MUSI być w stanie spoczynkowym: Polygon2D bez offsetu
	# (animacja skoku wsadu ustawia Polygon2D:position!) i kości bez rotacji.
	# Inaczej obrys/kości/wagi liczą się na przesuniętej/wygiętej pozie.
	if position != Vector2.ZERO:
		print("auto_outline: zeruję offset Polygon2D %s (zostało po animacji)" % str(position))
		position = Vector2.ZERO
	if scale != Vector2.ONE:
		push_warning("auto_outline: Polygon2D ma skalę %s — rig powinien być w skali 1 "
			% str(scale) + "(powiększanie rób na węźle-korzeniu). Użyj '★ ZRÓB WSZYSTKO', "
			+ "który normalizuje skalę i przelicza rig od nowa.")
	if skel:
		var bl: Array = []
		_collect_bones(skel, bl)
		for b in bl:
			b.rotation = 0.0


func _trace() -> void:
	if texture == null:
		push_warning("auto_outline: Polygon2D nie ma tekstury")
		return
	_neutralize(get_node_or_null(skeleton) as Skeleton2D)

	var img := texture.get_image()
	var bm := BitMap.new()
	bm.create_from_image_alpha(img, prog_alfa)
	var rect := Rect2i(Vector2i.ZERO, img.get_size())
	if domknij_luki > 0:
		bm.grow_mask(domknij_luki, rect)    # rozszerz — mostki między kosmykami
		bm.grow_mask(-domknij_luki, rect)   # ściągnij — zostaje domknięta bryła
	var polys := bm.opaque_to_polygons(rect, epsilon)
	if polys.is_empty():
		push_warning("auto_outline: nie znalazłem nieprzezroczystych pikseli")
		return

	# Największy obrys = postać; mniejsze to zwykle śmieci/odpryski rysunku.
	var best: PackedVector2Array = polys[0]
	for p in polys:
		if p.size() > best.size():
			best = p

	# Gęstszy obrys: podziel długie krawędzie (równe, drobne odcinki).
	var outline := _densify(best, max_edge)
	var outline_n := outline.size()

	# Punkty wewnętrzne: najpierw stawy/połowy kończyn (geometria na zgięciach),
	# potem GĘSTA SIATKA wypełniająca całe wnętrze — bez niej wnętrze ciała to
	# kilka długich trójkątów, które przy animacji rozrywają teksturę.
	var skel := get_node_or_null(skeleton) as Skeleton2D
	var internals := _limb_internal_points(skel, outline) if skel else PackedVector2Array()
	var seeded := PackedVector2Array(outline)
	seeded.append_array(internals)
	internals.append_array(_grid_internal_points(outline, seeded, max_edge))

	var all := PackedVector2Array(outline)
	all.append_array(internals)

	polygon = all
	uv = all
	internal_vertex_count = internals.size()
	polygons = []

	print("auto_outline: obrys %d pkt + %d wewnętrznych (stawy, kończyny, siatka)"
		% [outline_n, internals.size()])

	# Mając szkielet, od razu policz siatkę i wagi (gotowe w jednym kliknięciu).
	if skel:
		_rebuild_all()
	else:
		push_warning("auto_outline: brak szkieletu — pominięto punkty wewnętrzne "
			+ "i wagi; rozstaw kości i kliknij 'Przelicz siatkę i wagi'")


func _grid_internal_points(outline: PackedVector2Array, existing: PackedVector2Array,
		spacing: float) -> PackedVector2Array:
	# Siatka punktów co `spacing` wypełniająca wnętrze obrysu (pomija punkty
	# poza obrysem i zbyt blisko już istniejących). Daje drobne, równe trójkąty.
	var pmin := outline[0]
	var pmax := outline[0]
	for p in outline:
		pmin = pmin.min(p)
		pmax = pmax.max(p)
	var added := PackedVector2Array()
	var accepted := PackedVector2Array(existing)
	var min_d := spacing * 0.6
	var y := pmin.y + spacing * 0.5
	while y < pmax.y:
		var x := pmin.x + spacing * 0.5
		while x < pmax.x:
			var c := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(c, outline):
				var ok := true
				for e in accepted:
					if e.distance_squared_to(c) < min_d * min_d:
						ok = false
						break
				if ok:
					added.append(c)
					accepted.append(c)
			x += spacing
		y += spacing
	return added


func _densify(pts: PackedVector2Array, max_len: float) -> PackedVector2Array:
	# Wstawia punkty na krawędziach dłuższych niż max_len (równo rozłożone).
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		out.append(a)
		var d := a.distance_to(b)
		if d > max_len:
			var steps := int(ceil(d / max_len))
			for s in range(1, steps):
				out.append(a.lerp(b, float(s) / steps))
	return out


func _limb_internal_points(skel: Skeleton2D, outline: PackedVector2Array) -> PackedVector2Array:
	# Dla kości kończyn dodaje punkt w stawie (początek) i w połowie odcinka
	# do następnego stawu. Tułów/głowa dostają środek dla gęstości. Punkty poza
	# obrysem albo zbyt blisko istniejących są pomijane.
	const LIMB := ["RamieL", "PrzedramieL", "DlonL", "RamieP", "PrzedramieP", "DlonP",
		"UdoL", "LydkaL", "StopaL", "UdoP", "LydkaP", "StopaP"]
	const MIN_SPACING := 18.0
	var bones: Array = []
	_collect_bones(skel, bones)
	var added := PackedVector2Array()
	var accepted := PackedVector2Array(outline)

	for bone in bones:
		var name := String(bone.name)
		var joint := to_local(_bone_gpos(skel, bone))
		# Koniec odcinka kości: następny staw (dziecko) albo czubek po bone_angle.
		var tip := joint
		var child: Bone2D = null
		for c in bone.get_children():
			if c is Bone2D:
				child = c
				break
		if child:
			tip = to_local(_bone_gpos(skel, child))
		else:
			tip = to_local(_bone_gpos(skel, bone) + _bone_gxform(skel, bone) \
				.basis_xform(Vector2.from_angle(bone.bone_angle)) * bone.length)

		var candidates: Array[Vector2] = []
		if name in LIMB:
			# Staw + punkty wzdłuż kończyny (1/3 i 2/3) — w tym połowa.
			# Gęsta geometria na zgięciach = mniej rozmazywania tekstury.
			candidates.append(joint)
			candidates.append(joint.lerp(tip, 0.34))
			candidates.append(joint.lerp(tip, 0.67))
			# Dla ramion dodatkowy punkt przy pasze (lekko ku tułowiowi),
			# bo tam siatka rozciąga się najmocniej przy uniesieniu ręki.
			if name.begins_with("Ramie"):
				candidates.append(joint.lerp(tip, 0.18) + (joint - tip).normalized() * 0.0)
		elif name in ["Tulow", "Glowa", "Biodra"]:
			candidates.append(joint.lerp(tip, 0.4))
			candidates.append(joint.lerp(tip, 0.7))

		for c in candidates:
			if not Geometry2D.is_point_in_polygon(c, outline):
				continue
			var too_close := false
			for e in accepted:
				if e.distance_to(c) < MIN_SPACING:
					too_close = true
					break
			if not too_close:
				added.append(c)
				accepted.append(c)
	return added


func _repair() -> void:
	var pts := polygon
	var old_pts := uv  # uv == stary polygon (konwencja tego riga: uv w pikselach)
	if old_pts.is_empty():
		old_pts = pts

	for b in get_bone_count():
		var w := get_bone_weights(b)
		if w.size() == pts.size():
			continue
		var nw := PackedFloat32Array()
		nw.resize(pts.size())
		for i in pts.size():
			if w.size() > 0:
				nw[i] = w[_nearest(old_pts, pts[i], w.size())]
		set_bone_weights(b, nw)

	uv = pts
	if internal_vertex_count == 0:
		polygons = []  # wraca automatyczna triangulacja
	print("auto_outline: naprawiono — %d wierzcholków, uv i wagi dopasowane"
		% pts.size())


func _nearest(old_pts: PackedVector2Array, p: Vector2, limit: int) -> int:
	# Indeks najbliższego starego punktu (stare punkty mają identyczne pozycje,
	# więc dla nich dystans = 0; nowe dostają wagi najbliższego sąsiada).
	var best := 0
	var best_d := INF
	for k in mini(old_pts.size(), limit):
		var d := p.distance_squared_to(old_pts[k])
		if d < best_d:
			best_d = d
			best = k
	return best


func _auto_weights() -> void:
	# Wagi z geometrii: odległość wierzchołka do odcinka każdej kości.
	# Wierzchołek dostaje 1-3 najbliższe kości; wynik znormalizowany do 1.
	# UWAGA: szkielet musi stać w pozie spoczynkowej (świeżo otwarta scena).
	var skel := get_node_or_null(skeleton) as Skeleton2D
	if skel == null:
		push_warning("auto_outline: właściwość 'skeleton' nie wskazuje na Skeleton2D")
		return
	_neutralize(skel)  # offset Polygon2D (skok wsadu) rozjechałby wagi
	var pts := polygon
	if pts.is_empty():
		push_warning("auto_outline: brak obrysu — najpierw 'Obrysuj sprite'a'")
		return

	# Zbierz kości z drzewa (get_bone_count() bywa puste tuż po załadowaniu).
	var bones_list: Array = []
	_collect_bones(skel, bones_list)
	if bones_list.is_empty():
		push_warning("auto_outline: szkielet nie ma kości Bone2D")
		return

	# Segmenty kości w układzie Polygon2D.
	# joint = prawdziwy początek kości (staw z kością nadrzędną);
	# a/b = odcinek do mierzenia odległości, z początkiem ściągniętym ku
	# końcowi, żeby bok tułowia nie "łapał się" do ramienia.
	var segs: Array = []
	var node_to_idx: Dictionary = {}
	for bone in bones_list:
		var joint := to_local(_bone_gpos(skel, bone))
		var b := joint
		var child: Bone2D = null
		for c in bone.get_children():
			if c is Bone2D:
				child = c
				break
		if child:
			b = to_local(_bone_gpos(skel, child))
		else:
			b = to_local(_bone_gpos(skel, bone) + _bone_gxform(skel, bone) \
				.basis_xform(Vector2.from_angle(bone.bone_angle)) * bone.length)
		var a := joint
		if bone.get_parent() is Bone2D:
			a = joint.lerp(b, 0.25)
		node_to_idx[bone] = segs.size()
		segs.append({ "path": skel.get_path_to(bone), "a": a, "b": b,
			"joint": joint, "bone": bone, "parent": -1, "child": -1,
			"half_width": BONE_HALF_WIDTH.get(String(bone.name), LIMB_HALF_WIDTH) })
	for si in segs.size():
		var bone: Bone2D = segs[si].bone
		if bone.get_parent() is Bone2D:
			segs[si].parent = node_to_idx[bone.get_parent()]
		for c in bone.get_children():
			if c is Bone2D:
				segs[si].child = node_to_idx[c]
				break

	# Grubość tułowia i głowy z obrysu: najbliższe przecięcia scanline wokół
	# osi kości (dla tułowia mierzone przy szerszym, dolnym końcu segmentu).
	# Bez tego przy rękach wzdłuż ciała bok koszulki "należy" do ramienia.
	var outline := polygon.slice(0, polygon.size() - internal_vertex_count)
	for si in segs.size():
		var name := String(segs[si].bone.name)
		if not (name in ["Biodra", "Tulow", "Glowa"]):
			continue
		var scan_y: float
		if name == "Glowa":
			scan_y = (segs[si].a.y + segs[si].b.y) / 2.0
		else:
			scan_y = maxf(segs[si].a.y, segs[si].b.y)
		var inner_w := _scan_inner_width(outline, scan_y, (segs[si].a.x + segs[si].b.x) / 2.0)
		if inner_w > 0.0:
			segs[si].half_width = clampf(0.42 * inner_w, 30.0, 160.0)

	var n := pts.size()
	var all: Array = []
	for s in segs:
		var w := PackedFloat32Array()
		w.resize(n)
		all.append(w)

	for v in n:
		# Właściciel = najbliższa kość (odległość liczona od BOKU kości,
		# czyli pomniejszona o jej połowę grubości)...
		var owner := 0
		var best_d := INF
		for si in segs.size():
			var raw := _dist_to_segment(pts[v], segs[si].a, segs[si].b)
			# Grubość kości skraca dystans, ALE nie poniżej 35% rzeczywistego —
			# inaczej szeroki tułów/biodra "zassałyby" odległe wierzchołki barku
			# czy uda, które należą do kończyny.
			var d: float = maxf(raw - segs[si].half_width, raw * 0.42)
			if d < best_d:
				best_d = d
				owner = si
		# ...a przy stawach oddaje część wagi sąsiadowi (50/50 na samym
		# stawie, liniowy zanik do zera w promieniu blend_radius).
		var shares: Dictionary = {}
		var seg: Dictionary = segs[owner]
		if seg.parent != -1:
			var s := clampf(0.5 * (1.0 - pts[v].distance_to(seg.joint) / blend_radius),
				0.0, 0.5)
			if s > 0.01:
				shares[seg.parent] = s
		if seg.child != -1:
			var s2 := clampf(0.5 * (1.0 - pts[v].distance_to(segs[seg.child].joint) \
				/ blend_radius), 0.0, 0.5)
			if s2 > 0.01:
				shares[seg.child] = shares.get(seg.child, 0.0) + s2
		var given := 0.0
		for k in shares:
			given += shares[k]
			all[k][v] += shares[k]
		all[owner][v] += 1.0 - given

	clear_bones()
	for si in segs.size():
		add_bone(segs[si].path, all[si])
	print("auto_outline: auto-wagi gotowe (%d kości x %d wierzchołków, promień %d px)"
		% [segs.size(), n, int(blend_radius)])


func _auto_skeleton() -> void:
	var skel := get_node_or_null(skeleton) as Skeleton2D
	if skel == null:
		push_warning("auto_outline: właściwość 'skeleton' nie wskazuje na Skeleton2D")
		return
	_neutralize(skel)  # wyzeruj offset Polygon2D (skok wsadu) i pozę kości
	var pts := polygon.slice(0, polygon.size() - internal_vertex_count)
	if pts.size() < 8:
		push_warning("auto_outline: najpierw 'Obrysuj sprite'a'")
		return

	# Ramka i skrajne punkty obrysu.
	var pmin := pts[0]
	var pmax := pts[0]
	for p in pts:
		pmin = pmin.min(p)
		pmax = pmax.max(p)
	var h := pmax.y - pmin.y
	var w := pmax.x - pmin.x

	var top := pts[0]      # czubek głowy
	var hand_l := pts[0]   # skrajnie lewy = dłoń L
	var hand_p := pts[0]   # skrajnie prawy = dłoń P
	for p in pts:
		if p.y < top.y:
			top = p
		if p.x < hand_l.x:
			hand_l = p
		if p.x > hand_p.x:
			hand_p = p

	var bbox_cx := (pmin.x + pmax.x) / 2.0

	# Krocze: najwyższy punkt obrysu w wąskim pasie przy środku ramki,
	# w dolnej części ciała (wcięcie między nogami). Pas wąski i nisko,
	# żeby nie złapać się na spodzie ręki. Nogi zrośnięte = proporcja.
	var crotch_y := pmin.y + 0.62 * h
	for p in pts:
		if absf(p.x - bbox_cx) < 0.10 * w and p.y > pmin.y + 0.55 * h \
				and p.y < pmin.y + 0.88 * h:
			crotch_y = minf(crotch_y, p.y)

	# Środek głowy ze skanu sylwetki (głowa to czysta bryła u góry).
	var head_cx := _scan_center_x(pts, top.y + 0.10 * h, bbox_cx, 0.35 * w, bbox_cx)

	# Stopy: najniższy punkt w lewej/prawej połowie (podział wg środka ramki),
	# szukany tylko w dolnych 25% ciała, żeby nie złapać zwisającej dłoni.
	var foot_l := Vector2(bbox_cx - 0.15 * w, pmax.y)
	var foot_p := Vector2(bbox_cx + 0.15 * w, pmax.y)
	var found_l := false
	var found_p := false
	for p in pts:
		if p.y < pmax.y - 0.25 * h:
			continue
		if p.x < bbox_cx and (not found_l or p.y > foot_l.y):
			foot_l = p
			found_l = true
		elif p.x >= bbox_cx and (not found_p or p.y > foot_p.y):
			foot_p = p
			found_p = true

	# Środek bioder = rozstaw stóp (są poniżej rąk, więc czyste). Skan sylwetki
	# na wysokości bioder łapie zwisające przedramiona i ściąga środek w bok —
	# stąd wcześniej kręgosłup uciekał na lewo przy asymetrycznej pozie.
	var hips_cx := (foot_l.x + foot_p.x) / 2.0
	var cx := hips_cx

	# Punkty szkieletu. Kręgosłup biegnie po linii hips_cx -> head_cx
	# (może być lekko skośny, jeśli rysunek jest przekrzywiony).
	var hips := Vector2(hips_cx, crotch_y - 0.02 * h)

	# Linia barków = tuż pod SZYJĄ, a szyja to najwęższe miejsce sylwetki
	# między głową a barkami. To odporne na proporcje: przy wielkiej głowie
	# czubek jest wysoko, ale przewężenie szyi i tak jest tam, gdzie trzeba.
	# (Próba mierzenia szerokości głowy u góry zawodzi — głowa rozszerza się
	# niżej i probe ramienia trafia w policzek/czapkę.)
	var neck_y := lerpf(top.y, hips.y, 0.32)  # fallback proporcjonalny
	var min_w := INF
	var yy := top.y + 0.10 * h
	var y_lo := hips.y - 0.12 * h
	while yy < y_lo:
		var ww := _scan_width(pts, yy, cx, 0.45 * w)
		if ww > 0.0 and ww < min_w:
			min_w = ww
			neck_y = yy
		yy += 0.01 * h
	var sh_y := neck_y + 0.08 * h  # staw barkowy jest niżej niż samo przewężenie

	# Tułów (Tulow) NA linii barków; szyja (Glowa) tuż nad nią, ku głowie.
	# x kręgosłupa interpolowane wzdłuż linii hips_cx -> head_cx.
	var sh_frac := clampf((hips.y - sh_y) / maxf(hips.y - top.y, 1.0), 0.0, 1.0)
	var chest := Vector2(lerpf(hips_cx, head_cx, sh_frac), sh_y)
	var neck := Vector2(lerpf(hips_cx, head_cx, minf(sh_frac + 0.12, 1.0)),
		sh_y - 0.12 * (sh_y - top.y))

	var sh_l := Vector2(chest.x + (hand_l.x - chest.x) * 0.25, sh_y)
	var sh_p := Vector2(chest.x + (hand_p.x - chest.x) * 0.25, sh_y)
	var elb_l := sh_l.lerp(hand_l, 0.5)   # łokieć = połowa bark->dłoń
	var elb_p := sh_p.lerp(hand_p, 0.5)
	var dlon_l := hand_l.lerp(elb_l, 0.25)
	var dlon_p := hand_p.lerp(elb_p, 0.25)
	# Stawy biodrowe rozstawione wg realnej szerokości miednicy (scanline
	# na wysokości bioder), nie wg pozycji stóp — szerokie/wąskie nogawki
	# przestają ściągać uda do środka.
	var pelvis_w := _scan_width(pts, hips.y, hips_cx, 0.30 * w)
	var udo_l := Vector2(hips.x + (foot_l.x - hips.x) * 0.12, hips.y + 0.02 * h)
	var udo_p := Vector2(hips.x + (foot_p.x - hips.x) * 0.12, hips.y + 0.02 * h)
	if pelvis_w > 0.0:
		udo_l.x = hips.x - 0.20 * pelvis_w
		udo_p.x = hips.x + 0.20 * pelvis_w
	var ankle_l := foot_l.lerp(udo_l, 0.12)
	var ankle_p := foot_p.lerp(udo_p, 0.12)
	var knee_l := udo_l.lerp(ankle_l, 0.5)  # kolano = połowa biodro->kostka
	var knee_p := udo_p.lerp(ankle_p, 0.5)

	var targets := {
		"Biodra": hips, "Tulow": chest, "Glowa": neck,
		"RamieL": sh_l, "PrzedramieL": elb_l, "DlonL": dlon_l,
		"RamieP": sh_p, "PrzedramieP": elb_p, "DlonP": dlon_p,
		"UdoL": udo_l, "LydkaL": knee_l, "StopaL": ankle_l,
		"UdoP": udo_p, "LydkaP": knee_p, "StopaP": ankle_p,
	}
	# Kość głowy celuje w środek głowy na wysokości czubka (sam czubek bywa
	# z boku — kępka włosów, kucyk — i pochylałby kość przez twarz).
	var tips := { "Glowa": Vector2(head_cx, top.y), "DlonL": hand_l, "DlonP": hand_p,
		"StopaL": foot_l, "StopaP": foot_p }

	# Cele liczone były w układzie Polygon2D — przelicz na układ Skeleton2D
	# (Polygon2D mógł zostać przesunięty względem szkieletu).
	for k in targets:
		targets[k] = skel.to_local(to_global(targets[k]))
	for k in tips:
		tips[k] = skel.to_local(to_global(tips[k]))

	# Pozycje są względem rodzica; rotacje zostają 0 (konwencja rigu).
	var bones_list: Array = []
	_collect_bones(skel, bones_list)
	for bone in bones_list:
		var name := String(bone.name)
		if not targets.has(name):
			push_warning("auto_outline: kość %s poza konwencją — pomijam" % name)
			continue
		var parent_abs := Vector2.ZERO
		if bone.get_parent() is Bone2D:
			parent_abs = targets.get(String(bone.get_parent().name), Vector2.ZERO)
		bone.position = (targets[name] as Vector2) - parent_abs
		bone.rotation = 0.0
		var r: Transform2D = bone.rest
		r.origin = bone.position
		bone.rest = r
		# Kości-liście: celuj w skrajny punkt kończyny/głowy.
		if tips.has(name):
			var dir: Vector2 = (tips[name] as Vector2) - (targets[name] as Vector2)
			bone.auto_calculate_length_and_angle = false
			bone.bone_angle = dir.angle()
			bone.length = maxf(dir.length(), 10.0)

	print("auto_outline: kości rozstawione (głowa %s, dłonie %s/%s, stopy %s/%s)"
		% [str(top), str(hand_l), str(hand_p), str(foot_l), str(foot_p)]
		+ " — dociągnij stawy i kliknij 'Przelicz siatkę i wagi'")


func _scan_xs(pts: PackedVector2Array, y: float,
		x_guard_center: float, x_guard_half: float) -> PackedFloat32Array:
	# Przecięcia poziomej linii y z krawędziami obrysu (x rosnąco bez sortu
	# nie jest gwarantowane — zbieramy wszystkie). Strażnik x odcina
	# dłonie/stopy sterczące daleko od ciała.
	var xs := PackedFloat32Array()
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		if (a.y <= y) == (b.y <= y):
			continue
		var x := a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x)
		if absf(x - x_guard_center) <= x_guard_half:
			xs.append(x)
	return xs


func _scan_center_x(pts: PackedVector2Array, y: float,
		x_guard_center: float, x_guard_half: float, fallback: float) -> float:
	var xs := _scan_xs(pts, y, x_guard_center, x_guard_half)
	if xs.is_empty():
		return fallback
	var lo := xs[0]
	var hi := xs[0]
	for x in xs:
		lo = minf(lo, x)
		hi = maxf(hi, x)
	return (lo + hi) / 2.0


func _scan_inner_width(pts: PackedVector2Array, y: float, center_x: float) -> float:
	# Odległość między najbliższymi przecięciami obrysu po obu stronach osi
	# center_x — czyli szerokość samej bryły, w której biegnie kość
	# (zwisające obok ręce są dalszymi przecięciami i nie zawyżają wyniku).
	var xs := _scan_xs(pts, y, center_x, 1e9)
	var lo := -INF
	var hi := INF
	for x in xs:
		if x <= center_x and x > lo:
			lo = x
		if x >= center_x and x < hi:
			hi = x
	if lo == -INF or hi == INF:
		return 0.0
	return hi - lo


func _scan_ys(pts: PackedVector2Array, x: float,
		y_lo: float, y_hi: float) -> PackedFloat32Array:
	# Przecięcia pionowej linii x z krawędziami obrysu (w paśmie y_lo..y_hi).
	var ys := PackedFloat32Array()
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		if (a.x <= x) == (b.x <= x):
			continue
		var y := a.y + (x - a.x) / (b.x - a.x) * (b.y - a.y)
		if y >= y_lo and y <= y_hi:
			ys.append(y)
	return ys


func _arm_center_y(pts: PackedVector2Array, x: float, top_y: float, bottom_y: float,
		min_thick: float) -> float:
	# Środek najwyższego SENSOWNEGO pasma materiału na kolumnie x = środek
	# ramienia w okolicy barku (-1 gdy brak). Próg grubości jest proporcjonalny
	# do ciała (min_thick) — inaczej na dużym sprajcie łapie cienki kosmyk
	# włosów przy głowie zamiast ramienia (próg absolutny był wrażliwy na rozmiar).
	var ys := _scan_ys(pts, x, top_y, bottom_y)
	if ys.size() < 2:
		return -1.0
	ys.sort()
	for i in range(0, ys.size() - 1, 2):
		var thick := ys[i + 1] - ys[i]
		if thick > min_thick:
			return (ys[i] + ys[i + 1]) / 2.0  # najwyższe odpowiednio grube pasmo = ramię
	return -1.0


func _scan_width(pts: PackedVector2Array, y: float,
		x_guard_center: float, x_guard_half: float) -> float:
	var xs := _scan_xs(pts, y, x_guard_center, x_guard_half)
	if xs.size() < 2:
		return 0.0
	var lo := xs[0]
	var hi := xs[0]
	for x in xs:
		lo = minf(lo, x)
		hi = maxf(hi, x)
	return hi - lo


func _order_draw() -> void:
	# Sortuje listę trójkątów tak, by te „wyżej w hierarchii rysowania"
	# (ręce, dłonie) były na końcu — czyli rysowane na wierzchu. Warstwę
	# trójkąta wyznacza dominująca kość jego wierzchołków.
	if polygons.is_empty():
		_triangulate()
		if polygons.is_empty():
			return
	var nb := get_bone_count()
	if nb == 0:
		push_warning("auto_outline: brak wag — najpierw 'Auto-wagi'")
		return

	# Warstwa rysowania per wierzchołek = warstwa jego najcięższej kości.
	var n := polygon.size()
	var names: Array[String] = []
	var weights: Array = []
	for b in nb:
		names.append(str(get_bone_path(b)).get_file())
		weights.append(get_bone_weights(b))
	var vlayer := PackedFloat32Array()
	vlayer.resize(n)
	for v in n:
		var best_w := -1.0
		var lay := DRAW_LAYER_DEFAULT
		for b in nb:
			var w: float = weights[b][v] if v < weights[b].size() else 0.0
			if w > best_w:
				best_w = w
				lay = DRAW_LAYER_DEFAULT
				for prefix in DRAW_LAYER:
					if names[b].begins_with(prefix):
						lay = DRAW_LAYER[prefix]
						break
		vlayer[v] = lay

	# Stabilne sortowanie trójkątów po maksymalnej warstwie wierzchołków.
	var tris: Array = []
	for i in polygons.size():
		var tri: PackedInt32Array = polygons[i]
		var lay: float = maxf(vlayer[tri[0]], maxf(vlayer[tri[1]], vlayer[tri[2]]))
		tris.append({ "tri": tri, "lay": lay, "ord": i })
	tris.sort_custom(func(a, b):
		if a.lay != b.lay:
			return a.lay < b.lay
		return a.ord < b.ord)
	var ordered: Array = []
	for e in tris:
		ordered.append(e.tri)
	polygons = ordered
	print("auto_outline: kolejność rysowania ustawiona (%d trójkątów, ręce na wierzchu)"
		% ordered.size())


func _bone_gxform(skel: Skeleton2D, bone: Bone2D) -> Transform2D:
	# Globalna transformata kości liczona ANALITYCZNIE z bone.position/rotation.
	# NIE używamy bone.global_position/get_global_transform() — Skeleton2D je
	# cache'uje, więc tuż po ustawieniu kości (bez klatki) zwracają stare wartości
	# (inaczej w edytorze, inaczej headless). FK jest natychmiastowe i pewne.
	var t := Transform2D(bone.rotation, bone.position)
	var p := bone.get_parent()
	while p is Bone2D:
		t = Transform2D(p.rotation, p.position) * t
		p = p.get_parent()
	return skel.global_transform * t


func _bone_gpos(skel: Skeleton2D, bone: Bone2D) -> Vector2:
	return _bone_gxform(skel, bone).origin


func _collect_bones(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is Bone2D:
			out.append(c)
			_collect_bones(c, out)


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	if ab.length_squared() < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _triangulate() -> void:
	var pts := polygon
	if pts.size() < 3:
		push_warning("auto_outline: brak punktów do triangulacji")
		return
	var outline_n := pts.size() - internal_vertex_count
	var outline := pts.slice(0, outline_n)

	# Delaunay wszystkich punktów (równe, niewydłużone trójkąty), a potem
	# odrzuć trójkąty poza obrysem (mostki przez pachy/między nogami). Przy
	# gęstej siatce wnętrza daje to ładną, drobną i równą siatkę deformacji.
	var idx := Geometry2D.triangulate_delaunay(pts)
	if idx.is_empty():
		push_warning("auto_outline: Delaunay zwrócił pustkę — sprawdź punkty")
		return
	var packed: Array = []
	for t in range(0, idx.size(), 3):
		var a := pts[idx[t]]
		var b := pts[idx[t + 1]]
		var c := pts[idx[t + 2]]
		var centroid := (a + b + c) / 3.0
		# Trójkąt zostaje, jeśli środek i (lekko ściągnięte do środka) środki
		# boków leżą w obrysie — to odcina trójkąty mostkujące wklęsłości.
		if not Geometry2D.is_point_in_polygon(centroid, outline):
			continue
		var ok := true
		for pair in [[a, b], [b, c], [c, a]]:
			var mid: Vector2 = ((pair[0] + pair[1]) * 0.5).lerp(centroid, 0.06)
			if not Geometry2D.is_point_in_polygon(mid, outline):
				ok = false
				break
		if ok:
			packed.append(PackedInt32Array([idx[t], idx[t + 1], idx[t + 2]]))

	if packed.is_empty():
		push_warning("auto_outline: triangulacja pusta — sprawdź obrys")
		return
	polygons = packed
	print("auto_outline: %d trójkątów (%d punktów, w tym %d wewnętrznych)"
		% [packed.size(), pts.size(), internal_vertex_count])
