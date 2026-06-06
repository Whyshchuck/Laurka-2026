extends SceneTree

# Test triangulacji bez zapisu: ładuje rig, woła _triangulate() z auto_outline.gd
# i raportuje wynik. Uruchomienie: godot --headless --script res://rig/check_tri.gd

func _init() -> void:
	var poly: Polygon2D = (load("res://rig/michal_rig.tscn") as PackedScene) \
		.instantiate().get_node("Polygon2D")
	print("przed: punktow=%d internal=%d polygons=%d"
		% [poly.polygon.size(), poly.internal_vertex_count, poly.polygons.size()])
	poly._triangulate()
	print("po:    polygons=%d trojkatow" % poly.polygons.size())

	# Sanity: czy kazdy indeks miesci sie w zakresie i czy internal sa uzyte.
	var used := {}
	var max_idx := -1
	for tri in poly.polygons:
		for i in tri:
			used[i] = true
			max_idx = maxi(max_idx, i)
	var internal_used := 0
	for i in range(poly.polygon.size() - poly.internal_vertex_count, poly.polygon.size()):
		if used.has(i):
			internal_used += 1
	print("uzytych wierzcholkow: %d/%d, max indeks: %d, internal w siatce: %d/%d"
		% [used.size(), poly.polygon.size(), max_idx, internal_used, poly.internal_vertex_count])
	quit()
