extends SceneTree

# Test auto-wag bez zapisu: woła _auto_weights() i raportuje jakość
# (wierzchołki bez wag + rozkład udziału lewej ręki jak w check_arm.gd).
# Uruchomienie: godot --headless --script res://rig/check_autoweights.gd

func _init() -> void:
	var root := (load("res://rig/michal_rig.tscn") as PackedScene).instantiate()
	get_root().add_child(root)  # to_local/global_position wymagają drzewa
	var poly: Polygon2D = root.get_node("Polygon2D")

	# Debug: pozycje kości widziane przez algorytm.
	var skel: Skeleton2D = root.get_node("Skeleton2D")
	var bl: Array = []
	poly._collect_bones(skel, bl)
	for bone in bl:
		print("KOSC %s global=%s" % [bone.name, str(bone.global_position)])

	poly._auto_weights()

	var pts: PackedVector2Array = poly.polygon
	var n := pts.size()
	var nb := poly.get_bone_count()
	var names: Array[String] = []
	var weights: Array = []
	for b in nb:
		names.append(str(poly.get_bone_path(b)))
		weights.append(poly.get_bone_weights(b))

	var zero := 0
	for v in n:
		var s := 0.0
		for b in nb:
			s += weights[b][v]
		if s < 0.001:
			zero += 1
	print("kosci: %d, wierzcholki: %d, bez wag: %d" % [nb, n, zero])

	for arm in [["RamieL", Vector2(220, 327)], ["RamieP", Vector2(364, 323)]]:
		var rows := []
		for v in n:
			var total := 0.0
			var aw := 0.0
			for b in nb:
				total += weights[b][v]
				if arm[0] in names[b]:
					aw += weights[b][v]
			if aw > 0.01:
				rows.append({ "v": v, "pos": pts[v], "frac": aw / total,
					"dist": pts[v].distance_to(arm[1]) })
		rows.sort_custom(func(a, b): return a.dist < b.dist)
		print("\n%s: %d wierzcholkow z waga" % [arm[0], rows.size()])
		for r in rows:
			print("  %3d (%4.0f, %4.0f) dist=%3.0f udzial=%.2f"
				% [r.v, r.pos.x, r.pos.y, r.dist, r.frac])
	quit()
