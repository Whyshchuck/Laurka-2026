@tool
extends Polygon2D

# Automatyczny obrys sprite'a po kanale alpha (to samo, co edytorowe
# "Convert to Polygon2D", ale w miejscu — wpisuje obrys do tego Polygon2D).
# Po obrysowaniu trzeba jeszcze ręcznie dodać Internal Vertices przy stawach
# (UV -> Points) i pomalować wagi (UV -> Bones) — tego automat nie zrobi.

# Tolerancja upraszczania obrysu (px): mniejsza = wierniej, więcej punktów.
@export_range(0.5, 30.0, 0.5) var epsilon := 4.0
@export_tool_button("Obrysuj sprite'a", "CurveEdit") var _trace_btn := _trace


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

	# Stare wagi pasują do starej liczby wierzchołków — niedopasowane wagi
	# po cichu wyłączają całą deformację, więc lepiej zacząć od zera.
	if not bones.is_empty():
		clear_bones()
		push_warning("auto_outline: obrys się zmienił — wagi wyczyszczone, "
			+ "kliknij ponownie 'Sync Bones to Polygon' i pomaluj je od nowa")

	polygon = best
	uv = best
	internal_vertex_count = 0
	print("auto_outline: obrys z %d punktów (znalezionych kształtów: %d)"
		% [best.size(), polys.size()])
