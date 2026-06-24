extends SceneTree

# Podgląd POZY (z zastosowaną animacją) na tle sprite'a: rysuje kości + piłkę.
# Uruchomienie:
#   godot --headless --script res://rig/render_pose.gd -- <scena> <animacja> <czas>
# np. ... -- res://rig/michal_k_rig.tscn k/kozlowanie 0.25

const OUT := "res://rig/debug_pose.png"
const HEADROOM := 440  # zapas u góry obrazu, żeby widać było wysoki wyskok

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path: String = args[0]
	var anim_name: String = args[1] if args.size() > 1 else ""
	var t: float = float(args[2]) if args.size() > 2 else 0.0

	var root := (load(scene_path) as PackedScene).instantiate()
	get_root().add_child(root)
	var poly: Polygon2D = root.get_node("Polygon2D")
	var skel: Skeleton2D = root.get_node("Skeleton2D")

	# Pozycje bind (z czasu wiązania skóry, przed animacją). Opad ciała robimy
	# torami Polygon2D:position + Skeleton2D:position; w prawdziwym Godocie to
	# czysta translacja całej skóry o offset. Tu liczymy skinning BEZ opadu
	# (kości w bind), a wynik przesuwamy o opad — inaczej rest liczone z
	# opuszczonym szkieletem skasowałoby translację (znana rozbieżność).
	var poly_bind := poly.position
	var skel_bind := skel.position

	if anim_name != "":
		var ap: AnimationPlayer = root.get_node("AnimationPlayer")
		ap.play(anim_name)
		ap.seek(t, true)

	# Opad ciała z animacji (Polygon2D:position względem bind) i reset do bind,
	# by skinning policzył tylko deformację pozy (rotacje/skale), bez translacji.
	var body_drop := poly.position - poly_bind
	poly.position = poly_bind
	skel.position = skel_bind

	var tex: Image = poly.texture.get_image()
	if tex.is_compressed():
		tex.decompress()
	tex.convert(Image.FORMAT_RGBA8)

	var off := Vector2(0, HEADROOM)  # zapas u góry obrazu
	# Sprite i kości rysujemy przesunięte o opad ciała; piłka ma własną pozycję.
	var body_off := off + body_drop

	# Zdeformowany podgląd: CPU-skinning siatki Polygon2D (bez opadu), przesunięty.
	var img := _skin_render(poly, skel, tex, body_off)

	var bones: Array = []
	poly._collect_bones(skel, bones)
	for bone in bones:
		_dot(img, bone.global_position + body_off, Color(0, 0.6, 1), 4)

	# Druk pozycji dłoni — tylko jeśli rig humanoidalny ma te kości (kot/zwierz nie ma).
	var dln_l := skel.get_node_or_null("Biodra/Tulow/RamieL/PrzedramieL/DlonL") as Bone2D
	var dln_p := skel.get_node_or_null("Biodra/Tulow/RamieP/PrzedramieP/DlonP") as Bone2D
	if dln_l and dln_p:
		print("dlonL @ ", (dln_l.global_position + body_drop).round(),
			"  dlonP @ ", (dln_p.global_position + body_drop).round())

	# Piłka: wrysuj jej teksturę w aktualnej pozycji (i kółko konturu).
	var ball := root.get_node_or_null("Pilka") as Sprite2D
	if ball and ball.texture:
		var bp := ball.global_position + off
		var bt := ball.texture.get_image()
		if bt.is_compressed():
			bt.decompress()
		bt.convert(Image.FORMAT_RGBA8)
		var bw := bt.get_width() * ball.scale.x
		var bh := bt.get_height() * ball.scale.y
		for yy in range(int(bh)):
			for xx in range(int(bw)):
				var col := bt.get_pixel(
					int(xx / ball.scale.x), int(yy / ball.scale.y))
				if col.a > 0.3:
					var px := int(bp.x - bw * 0.5 + xx)
					var py := int(bp.y - bh * 0.5 + yy)
					if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
						img.set_pixel(px, py, col)
		print("pilka @ ", bp.round(), " r=", int(bw * 0.5))

	img.save_png(ProjectSettings.globalize_path(OUT))
	print("zapisano: ", OUT)
	quit()


func _skin_render(poly: Polygon2D, skel: Skeleton2D, tex: Image, jump: Vector2) -> Image:
	# CPU-skinning: każdy wierzchołek przesuwany sumą ważonych transformat
	# kości (poza * odwrotność rest). Trójkąty rasteryzowane z próbkowaniem UV.
	var out := Image.create(tex.get_width(), tex.get_height() + HEADROOM, false, Image.FORMAT_RGBA8)
	var pts := poly.polygon
	var uv := poly.uv
	var n := pts.size()

	# Delta kości = poza * odwrotność rest (globalnie). Ruch kości — w tym
	# przesunięcie kości głównej Biodra (wyskok) — przenosi się na wierzchołki.
	# (Uwaga: przesunięcie samego Skeleton2D nic by nie dało — wiązanie jest
	# względne, więc skok robimy kością Biodra, nie węzłem szkieletu.)
	var bones: Array = []
	poly._collect_bones(skel, bones)
	var deltas: Array = []
	var weights: Array = []
	for bone in bones:
		# Pozę liczymy ręcznym FK z .transform (zawiera rotację I SKALĘ kości),
		# bo get_global_transform() w headless ma nieaktualny cache skali —
		# inaczej deformacje skalą (siad) nie były widać w podglądzie.
		deltas.append(_bone_posed_global(skel, bone) * _bone_rest_global(skel, bone).affine_inverse())
		weights.append(poly.get_bone_weights(_bone_index(poly, skel, bone)))

	var skinned := PackedVector2Array()
	skinned.resize(n)
	for i in n:
		var vw := poly.to_global(pts[i])
		var acc := Vector2.ZERO
		var wsum := 0.0
		for b in bones.size():
			var w: float = weights[b][i] if i < weights[b].size() else 0.0
			if w > 0.0:
				acc += (deltas[b] * vw) * w
				wsum += w
		if wsum > 0.001:
			skinned[i] = poly.to_local(acc / wsum) + jump
		else:
			skinned[i] = pts[i] + jump

	# Respektuj kolejność rysowania z poly.polygons (jeśli ustawiona) — inaczej
	# własna triangulacja. Kolejność decyduje, co zasłania co.
	if not poly.polygons.is_empty():
		for tri in poly.polygons:
			_raster_tri(out, tex,
				skinned[tri[0]], skinned[tri[1]], skinned[tri[2]],
				uv[tri[0]], uv[tri[1]], uv[tri[2]])
	else:
		var idx := Geometry2D.triangulate_polygon(pts)
		for t in range(0, idx.size(), 3):
			_raster_tri(out, tex,
				skinned[idx[t]], skinned[idx[t + 1]], skinned[idx[t + 2]],
				uv[idx[t]], uv[idx[t + 1]], uv[idx[t + 2]])
	return out


func _bone_index(poly: Polygon2D, skel: Skeleton2D, bone: Bone2D) -> int:
	var path := str(skel.get_path_to(bone))
	for b in poly.get_bone_count():
		if str(poly.get_bone_path(b)) == path:
			return b
	return 0


func _bone_rest_global(skel: Skeleton2D, bone: Bone2D) -> Transform2D:
	var t: Transform2D = bone.rest
	var p := bone.get_parent()
	while p is Bone2D:
		t = p.rest * t
		p = p.get_parent()
	return skel.global_transform * t


func _bone_posed_global(skel: Skeleton2D, bone: Bone2D) -> Transform2D:
	# FK z aktualnych .transform kości (pozycja+rotacja+skala z animacji).
	var t: Transform2D = bone.transform
	var p := bone.get_parent()
	while p is Bone2D:
		t = p.transform * t
		p = p.get_parent()
	return skel.global_transform * t


func _raster_tri(out: Image, tex: Image, a: Vector2, b: Vector2, c: Vector2,
		ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	var lo := a.min(b).min(c).floor()
	var hi := a.max(b).max(c).ceil()
	lo = lo.max(Vector2.ZERO)
	hi = hi.min(Vector2(out.get_width() - 1, out.get_height() - 1))
	var d := (b - a).cross(c - a)
	if absf(d) < 0.001:
		return
	var tw := tex.get_width()
	var th := tex.get_height()
	for y in range(int(lo.y), int(hi.y) + 1):
		for x in range(int(lo.x), int(hi.x) + 1):
			var p := Vector2(x, y)
			var w0 := (b - p).cross(c - p) / d
			var w1 := (c - p).cross(a - p) / d
			var w2 := 1.0 - w0 - w1
			if w0 < -0.01 or w1 < -0.01 or w2 < -0.01:
				continue
			var u := ua * w0 + ub * w1 + uc * w2
			var sx := clampi(int(u.x), 0, tw - 1)
			var sy := clampi(int(u.y), 0, th - 1)
			var col := tex.get_pixel(sx, sy)
			if col.a > 0.3:
				out.set_pixel(x, y, col)


func _line(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	var steps := int(a.distance_to(b)) + 1
	for i in steps + 1:
		_px(img, a.lerp(b, float(i) / steps), col, 2)


func _ring(img: Image, c: Vector2, r: float, col: Color) -> void:
	var n := int(r * 6.5) + 8
	for i in n:
		var ang := TAU * i / n
		_px(img, c + Vector2(cos(ang), sin(ang)) * r, col, 2)


func _dot(img: Image, p: Vector2, col: Color, r: int) -> void:
	_px(img, p, col, r)


func _px(img: Image, p: Vector2, col: Color, r: int) -> void:
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var x := int(p.x) + dx
			var y := int(p.y) + dy
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, col)
