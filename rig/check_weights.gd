extends SceneTree

# Diagnostyka wag riga: godot --headless --script res://rig/check_weights.gd
# Sprawdza: rozmiary tablic wag, wierzchołki bez wag, najniższy punkt głowy,
# wagi innych kości powyżej brody oraz trójkąty łączące głowę z rękami.

const SCENE_DEFAULT := "res://rig/michal_rig.tscn"

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := args[0] if args.size() > 0 else SCENE_DEFAULT
	var poly: Polygon2D = (load(scene_path) as PackedScene).instantiate().get_node("Polygon2D")
	var pts: PackedVector2Array = poly.polygon
	var n := pts.size()
	print("Wierzcholkow: %d (w tym internal: %d)" % [n, poly.internal_vertex_count])

	var nb := poly.get_bone_count()
	var names: Array[String] = []
	var weights: Array = []
	for b in nb:
		names.append(str(poly.get_bone_path(b)))
		weights.append(poly.get_bone_weights(b))
		if weights[b].size() != n:
			print("!!! %s: tablica wag %d != %d wierzcholkow (deformacja wylaczona!)"
				% [names[b], weights[b].size(), n])

	# Wierzcholki bez zadnej wagi + statystyka per kosc.
	var zero: Array[int] = []
	for v in n:
		var s := 0.0
		for b in nb:
			s += weights[b][v]
		if s < 0.001:
			zero.append(v)
	print("Wierzcholki bez wag: %d %s" % [zero.size(), str(zero)])

	# Najnizszy (najwiekszy y) wierzcholek z waga Glowy = broda.
	var glowa := -1
	for b in nb:
		if names[b].ends_with("Glowa"):
			glowa = b
	var chin_y := -1e9
	var chin_v := -1
	for v in n:
		if weights[glowa][v] > 0.01 and pts[v].y > chin_y:
			chin_y = pts[v].y
			chin_v = v
	print("Broda (najnizszy punkt z waga Glowy): wierzcholek %d, y=%.0f" % [chin_v, chin_y])

	# Czy jakakolwiek inna kosc ma wage POWYZEJ brody?
	var found := false
	for b in nb:
		if b == glowa:
			continue
		for v in n:
			if weights[b][v] > 0.01 and pts[v].y < chin_y - 0.5:
				print("  %s: wierzcholek %d (%.0f, %.0f) waga %.2f"
					% [names[b], v, pts[v].x, pts[v].y, weights[b][v]])
				found = true
	if not found:
		print("Zadna inna kosc nie ma wagi powyzej brody.")

	# Trojkaty laczace okolice glowy z wierzcholkami ciagnietymi przez rece.
	if poly.internal_vertex_count == 0:
		var tris := Geometry2D.triangulate_polygon(pts)
		var arm_w: Array[float] = []
		arm_w.resize(n)
		for b in nb:
			if "Ramie" in names[b] or "Dlon" in names[b]:
				for v in n:
					arm_w[v] = max(arm_w[v], weights[b][v])
		var bad := 0
		for t in range(0, tris.size(), 3):
			var ids := [tris[t], tris[t + 1], tris[t + 2]]
			var has_head := false
			var has_arm := false
			for v in ids:
				if weights[glowa][v] > 0.3 or pts[v].y < chin_y:
					has_head = true
				if arm_w[v] > 0.3:
					has_arm = true
			if has_head and has_arm:
				bad += 1
				print("  trojkat glowa<->reka: %s  (%s / %s / %s)"
					% [str(ids), str(pts[ids[0]]), str(pts[ids[1]]), str(pts[ids[2]])])
		if bad == 0:
			print("Brak trojkatow laczacych glowe z recami.")

	# Pelny rozklad wag dla wierzcholkow okolic szyi/glowy (do recznej oceny).
	print("\nWagi wierzcholkow z podejrzanych trojkatow:")
	for v in [10, 11, 12, 13, 110, 111, 112, 113, 114, 129]:
		var parts := ""
		for b in nb:
			if weights[b][v] > 0.01:
				parts += "%s=%.2f  " % [names[b].get_file(), weights[b][v]]
		print("  %3d (%4.0f, %4.0f): %s" % [v, pts[v].x, pts[v].y, parts])

	quit()
