extends SceneTree

# Diagnostyka wag kończyna po kończynie: dla każdej kości sprawdza, czy
# wierzchołki o znaczącej wadze leżą blisko jej odcinka. Wypisuje wierzchołki-
# odstające (waga na kości daleko od tej kości) — np. dłoń z wagą na biodrze.
# Uruchomienie: godot --headless --script res://rig/check_weight_limbs.gd [-- scena]

const SCENE_DEFAULT := "res://rig/michal_k_rig.tscn"

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := args[0] if args.size() > 0 else SCENE_DEFAULT
	var root := (load(scene_path) as PackedScene).instantiate()
	get_root().add_child(root)
	var poly: Polygon2D = root.get_node("Polygon2D")
	var skel: Skeleton2D = root.get_node("Skeleton2D")

	# Wymuś spoczynek (autoplay/animacja zgina kości i myli odcinki).
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap:
		ap.stop()
	var bones: Array = []
	poly._collect_bones(skel, bones)
	for b in bones:
		b.rotation = 0.0

	# Odcinki kości (poza spoczynkowa) w przestrzeni Polygon2D — FK, bez cache'a.
	var segs := {}
	for bone in bones:
		var a := poly.to_local(poly._bone_gpos(skel, bone))
		var b := a
		var child: Bone2D = null
		for c in bone.get_children():
			if c is Bone2D:
				child = c
				break
		if child:
			b = poly.to_local(poly._bone_gpos(skel, child))
		else:
			b = poly.to_local(poly._bone_gpos(skel, bone) + poly._bone_gxform(skel, bone) \
				.basis_xform(Vector2.from_angle(bone.bone_angle)) * bone.length)
		segs[String(bone.name)] = [a, b]

	var pts: PackedVector2Array = poly.polygon
	var nb := poly.get_bone_count()
	var names: Array[String] = []
	var weights: Array = []
	for bi in nb:
		names.append(str(poly.get_bone_path(bi)).get_file())
		weights.append(poly.get_bone_weights(bi))

	print("=== Wierzcholki przypisane DALEKO od swojej kosci (waga>0.4, dystans>120px) ===")
	var bad := 0
	for v in pts.size():
		for bi in nb:
			var w: float = weights[bi][v]
			if w < 0.4:
				continue
			var seg = segs.get(names[bi], null)
			if seg == null:
				continue
			var d := _dist_seg(pts[v], seg[0], seg[1])
			# Najblizsza kosc do tego wierzcholka:
			var best_name := ""
			var best_d := INF
			for bn in segs:
				var dd := _dist_seg(pts[v], segs[bn][0], segs[bn][1])
				if dd < best_d:
					best_d = dd
					best_name = bn
			if d > 120.0 and best_name != names[bi]:
				print("  v%d %s waga=%.2f na %-12s d=%.0f  (najblizej: %s d=%.0f)"
					% [v, str(pts[v].round()), w, names[bi], d, best_name, best_d])
				bad += 1
	if bad == 0:
		print("  (brak)")

	# Podsumowanie per kosc: ile wierzcholkow, sredni i max dystans.
	print("\n=== Podsumowanie per kosc (waga>0.3) ===")
	for bi in nb:
		var seg = segs.get(names[bi], null)
		if seg == null:
			continue
		var cnt := 0
		var sum_d := 0.0
		var max_d := 0.0
		for v in pts.size():
			if weights[bi][v] > 0.3:
				var d := _dist_seg(pts[v], seg[0], seg[1])
				cnt += 1
				sum_d += d
				max_d = maxf(max_d, d)
		var avg := (sum_d / cnt) if cnt > 0 else 0.0
		print("  %-12s wierzch=%2d  sredni_d=%5.0f  max_d=%5.0f" % [names[bi], cnt, avg, max_d])
	quit()


func _dist_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	if ab.length_squared() < 0.001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)
