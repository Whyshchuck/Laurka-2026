extends SceneTree

# Debug przypięcia LetterDecor do literki.

func _init() -> void:
	var demo := (load("res://letters/letter_decor_demo.tscn") as PackedScene).instantiate()
	root.add_child(demo)
	await create_timer(0.2).timeout
	var decor := demo.get_node("Ozdoba")
	print("follow_label = ", decor.follow_label)
	print("letter_char = '", decor.letter_char, "'")
	print("curve points = ", decor.curve.point_count)
	var label := demo.get_node("Napis")
	print("label slots = ", label.get_letter_count(),
		" find('ó') = ", label.find_letter("ó"))
	if decor.follow_label == null:
		print("RAW property: ", decor.get("follow_label"))
	decor._snap_to_letter() if decor.follow_label else print("snap pominiety - null")
	print("decor.global_position = ", decor.global_position)
	quit()
