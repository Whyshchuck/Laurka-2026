extends SceneTree

# Pełny przebud riga: ★ ZRÓB WSZYSTKO (normalizacja skali, rozstaw kości,
# obrys, wagi). Scena MUSI być zamknięta w edytorze.
# Uruchomienie: godot --headless --script res://rig/apply_all.gd -- <scena>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path: String = args[0]
	var root := (load(scene_path) as PackedScene).instantiate()
	get_root().add_child(root)
	var poly: Polygon2D = root.get_node("Polygon2D")
	poly._do_everything()

	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, scene_path)
	print("zapis: ", "OK" if err == OK else str(err))
	quit()
