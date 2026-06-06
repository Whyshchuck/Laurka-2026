@tool
extends Polygon2D

# Automatyczny obrys sprite'a po kanale alpha (to samo, co edytorowe
# "Convert to Polygon2D", ale w miejscu — wpisuje obrys do tego Polygon2D).
# Po obrysowaniu trzeba jeszcze ręcznie dodać Internal Vertices przy stawach
# (UV -> Points) i pomalować wagi (UV -> Bones) — tego automat nie zrobi.

# Tolerancja upraszczania obrysu (px): mniejsza = wierniej, więcej punktów.
@export_range(0.5, 30.0, 0.5) var epsilon := 4.0
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

# Automatyczne rozstawienie kości na podstawie obrysu: skrajne punkty to
# czubek głowy / dłonie / stopy, krocze z wcięcia między nogami (fallback:
# proporcja), łokcie i kolana w połowie kończyn. Wynik to szkic — stawy
# dociąga się ręcznie, potem "Przelicz siatkę i wagi".
@export_tool_button("Rozstaw kości ze sprite'a", "Skeleton2D") var _skel_btn := _auto_skeleton

# Kombajn po każdej zmianie punktów lub kości: triangulacja (jeśli są punkty
# wewnętrzne) + auto-wagi. Obrys zostaje, jaki jest.
@export_tool_button("Przelicz siatkę i wagi", "Reload") var _all_btn := _rebuild_all


func _rebuild_all() -> void:
	_sync_rests()
	if internal_vertex_count > 0:
		_triangulate()
	else:
		polygons = []  # czysty obrys — wraca automatyczna triangulacja Godota
	_auto_weights()


func _sync_rests() -> void:
	# Konwencja rigu: rest = pozycja kości, rotacja w spoczynku 0.
	# Po przesuwaniu kości w viewporcie nie trzeba pamiętać o "Set Rest".
	var skel := get_node_or_null(skeleton) as Skeleton2D
	if skel == null:
		return
	var bones_list: Array = []
	_collect_bones(skel, bones_list)
	for bone in bones_list:
		if absf(bone.rotation) > 0.001:
			push_warning("auto_outline: kość %s ma rotację %.2f — w spoczynku powinna być 0 "
				% [bone.name, bone.rotation]
				+ "(wyzeruj albo odpal animację RESET przed przeliczeniem)")
		var r: Transform2D = bone.rest
		if r.origin != bone.position:
			print("auto_outline: rest %s %s -> %s" % [bone.name, str(r.origin), str(bone.position)])
			r.origin = bone.position
			bone.rest = r


func _trace() -> void:
	if texture == null:
		push_warning("auto_outline: Polygon2D nie ma tekstury")
		return

	var img := texture.get_image()
	var bm := BitMap.new()
	bm.create_from_image_alpha(img)
	var polys := bm.opaque_to_polygons(Rect2i(Vector2i.ZERO, img.get_size()), epsilon)
	if polys.is_empty():
		push_warning("auto_outline: nie znalazłem nieprzezroczystych pikseli")
		return

	# Największy obrys = postać; mniejsze to zwykle śmieci/odpryski rysunku.
	var best: PackedVector2Array = polys[0]
	for p in polys:
		if p.size() > best.size():
			best = p

	# Przenieś stare wagi na nowy obrys (każdy nowy punkt dziedziczy po
	# najbliższym starym) zamiast je kasować.
	var old_pts := uv
	var old_bones: Array = []
	for b in get_bone_count():
		old_bones.append([get_bone_path(b), get_bone_weights(b)])

	polygon = best
	uv = best
	internal_vertex_count = 0
	polygons = []

	if not old_bones.is_empty() and not old_pts.is_empty():
		clear_bones()
		for ob in old_bones:
			var w: PackedFloat32Array = ob[1]
			var nw := PackedFloat32Array()
			nw.resize(best.size())
			if w.size() > 0:
				for i in best.size():
					nw[i] = w[_nearest(old_pts, best[i], w.size())]
			add_bone(ob[0], nw)
		print("auto_outline: wagi przeniesione na nowy obrys (najbliższy sąsiad)")

	print("auto_outline: obrys z %d punktów (znalezionych kształtów: %d)"
		% [best.size(), polys.size()])


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
		var joint := to_local(bone.global_position)
		var b := joint
		var child: Bone2D = null
		for c in bone.get_children():
			if c is Bone2D:
				child = c
				break
		if child:
			b = to_local(child.global_position)
		else:
			b = to_local(bone.global_position + bone.get_global_transform() \
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
			var d: float = maxf(
				_dist_to_segment(pts[v], segs[si].a, segs[si].b) - segs[si].half_width,
				0.0)
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

	# Środek ciała mierzony z obrysu (środek między lewą a prawą krawędzią
	# konturu): osobno na wysokości głowy i tuż nad kroczem. Pomiar przecina
	# poziomą linię z krawędziami obrysu (scanline) — wierzchołki bywają
	# rozmieszczone rzadko i jednostronnie, więc ich próbkowanie kłamie.
	var head_cx := _scan_center_x(pts, top.y + 0.10 * h, bbox_cx, 0.35 * w, bbox_cx)
	var hips_cx := _scan_center_x(pts, crotch_y - 0.07 * h, bbox_cx, 0.30 * w, bbox_cx)
	var cx := hips_cx

	var foot_l := Vector2(cx - 0.15 * w, pmax.y)
	var foot_p := Vector2(cx + 0.15 * w, pmax.y)
	var found_l := false
	var found_p := false
	for p in pts:
		if p.x < cx and (not found_l or p.y > foot_l.y):
			foot_l = p
			found_l = true
		elif p.x >= cx and (not found_p or p.y > foot_p.y):
			foot_p = p
			found_p = true

	# Punkty szkieletu. Kręgosłup biegnie po linii hips_cx -> head_cx
	# (może być lekko skośny, jeśli rysunek jest przekrzywiony).
	var hips := Vector2(hips_cx, crotch_y - 0.02 * h)
	var chest := Vector2(lerpf(hips_cx, head_cx, 0.42), lerpf(hips.y, top.y, 0.42))
	var neck := Vector2(lerpf(hips_cx, head_cx, 0.54), chest.y - 0.12 * (hips.y - top.y))
	# Linia barków z sylwetki: od szyi w dół, pierwsze miejsce, gdzie kontur
	# robi się wyraźnie szerszy od głowy (działa i dla rąk odstających,
	# i opuszczonych wzdłuż ciała).
	var head_w := _scan_width(pts, top.y + 0.10 * h, bbox_cx, 0.35 * w)
	var sh_y := chest.y + 0.015 * h  # fallback: tuż pod klatką
	if head_w > 0.0:
		var yy := neck.y
		while yy < hips.y:
			if _scan_width(pts, yy, cx, 0.45 * w) > head_w * 1.35:
				sh_y = yy + 0.015 * h
				break
			yy += 0.015 * h

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

	# Baza: triangulacja samego konturu (earcut) — szanuje granicę obrysu,
	# więc nie robi ani dziur, ani mostków przez wklęsłości.
	var ear := Geometry2D.triangulate_polygon(outline)
	if ear.is_empty():
		push_warning("auto_outline: kontur się nie trianguluje — sprawdź obrys")
		return
	var tris: Array = []
	for t in range(0, ear.size(), 3):
		tris.append([ear[t], ear[t + 1], ear[t + 2]])

	# Punkty wewnętrzne wszywamy w siatkę: trójkąt, w którym leży punkt,
	# dzielimy na 3 mniejsze (punkt łączy się z jego wierzchołkami).
	for vi in range(outline_n, pts.size()):
		var found := -1
		for ti in tris.size():
			if Geometry2D.point_is_inside_triangle(
					pts[vi], pts[tris[ti][0]], pts[tris[ti][1]], pts[tris[ti][2]]):
				found = ti
				break
		if found == -1:
			push_warning("auto_outline: punkt wewnętrzny %d leży poza obrysem — pomijam" % vi)
			continue
		var tr: Array = tris[found]
		tris.remove_at(found)
		tris.append([tr[0], tr[1], vi])
		tris.append([tr[1], tr[2], vi])
		tris.append([tr[2], tr[0], vi])

	var packed: Array = []
	for t in tris:
		packed.append(PackedInt32Array(t))
	polygons = packed
	print("auto_outline: %d trójkątów (%d punktów, w tym %d wewnętrznych)"
		% [packed.size(), pts.size(), internal_vertex_count])
