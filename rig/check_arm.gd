extends SceneTree

# Diagnostyka lewej ręki: dla każdego wierzchołka z wagą łańcucha RamieL
# wypisuje znormalizowany udział ręki (0..1) i odległość od barku.
# Wierzchołki daleko od barku z udziałem między 0 a 1 obracają się tylko
# częściowo — to one "pogrubiają" ramię przy machaniu.
# Uruchomienie: godot --headless --script res://rig/check_arm.gd

const SCENE_DEFAULT := "res://rig/michal_rig.tscn"

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := args[0] if args.size() > 0 else SCENE_DEFAULT
	var root := (load(scene_path) as PackedScene).instantiate()
	get_root().add_child(root)  # global_position kości wymaga drzewa
	var poly: Polygon2D = root.get_node("Polygon2D")
	# Pozycje barków prosto ze szkieletu (działa dla każdego ucznia).
	var skel: Skeleton2D = root.get_node("Skeleton2D")
	_check_arm(poly, "RamieL", skel.get_node("Biodra/Tulow/RamieL").global_position)
	_check_arm(poly, "RamieP", skel.get_node("Biodra/Tulow/RamieP").global_position)
	quit()


func _check_arm(poly: Polygon2D, chain: String, shoulder: Vector2) -> void:
	var pts: PackedVector2Array = poly.polygon
	var n := pts.size()

	var nb := poly.get_bone_count()
	var names: Array[String] = []
	var weights: Array = []
	for b in nb:
		names.append(str(poly.get_bone_path(b)))
		weights.append(poly.get_bone_weights(b))

	var rows := []
	for v in n:
		var total := 0.0
		var arm := 0.0
		var parts := ""
		for b in nb:
			var w: float = weights[b][v]
			if w <= 0.0:
				continue
			total += w
			if chain in names[b]:  # łapie też Przedramie i Dlon tej ręki
				arm += w
			if w > 0.01:
				parts += "%s=%.2f " % [names[b].get_file(), w]
		if arm <= 0.0:
			continue
		rows.append({
			"v": v, "pos": pts[v],
			"frac": arm / total,
			"dist": pts[v].distance_to(shoulder),
			"parts": parts,
		})

	rows.sort_custom(func(a, b): return a.dist < b.dist)
	print("\nWierzcholki z waga %s (udzial reki po normalizacji):" % chain)
	for r in rows:
		var flag := ""
		if r.dist > 50.0 and r.frac < 0.95:
			flag = "  <-- OBRACA SIE TYLKO CZESCIOWO"
		print("  %3d (%4.0f, %4.0f) dist=%3.0f  udzial=%.2f   %s%s"
			% [r.v, r.pos.x, r.pos.y, r.dist, r.frac, r.parts, flag])
