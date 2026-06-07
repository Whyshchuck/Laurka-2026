extends SceneTree

# Test dekorów w minigrze alfabetu: kafle znaków z dekorem (ż, ó) mają
# dostać scenę z ruchomymi elementami zamiast zwykłego sprite'a.
# Uruchomienie: godot --headless --script res://rig/check_alpha_decor.gd

func _init() -> void:
	var src := TextureRect.new()
	src.texture = load("res://letters/o_pol_1.png")
	root.add_child(src)

	var ov := (load("res://minigames/alphabet_overlay.tscn") as PackedScene).instantiate()
	root.add_child(ov)
	await create_timer(0.1).timeout  # _ready po starcie pętli głównej
	ov.open_from(src)
	await create_timer(2.0).timeout  # intro (literki wlatują ~1.4s)

	var letters: Node2D = ov.get_node("Letters")
	print("kafli: ", letters.get_child_count())

	var decored: Array[Node2D] = []
	for tile in letters.get_children():
		for c in tile.get_children():
			if c.has_node("Ozdoba"):
				decored.append(c)
	print("kafli z dekorem: ", decored.size())

	for inst in decored:
		var elem: Node2D = inst.get_node("Ozdoba").get_child(0)
		var p1: Vector2 = elem.position
		await create_timer(0.5).timeout
		print("  %s: element przesunal sie o %.0f px"
			% [inst.name, p1.distance_to(elem.position)])
	quit()
