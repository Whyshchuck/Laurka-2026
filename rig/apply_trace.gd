extends SceneTree

# Re-trace: gęsty obrys + punkty wewnętrzne (stawy/połowy kończyn) + przelicz.
# Scena MUSI być zamknięta w edytorze.
# Uruchomienie: godot --headless --script res://rig/apply_trace.gd -- <scena>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path: String = args[0]
	var root := (load(scene_path) as PackedScene).instantiate()
	get_root().add_child(root)
	var poly: Polygon2D = root.get_node("Polygon2D")
	poly._trace()

	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, scene_path)
	print("zapis: ", "OK" if err == OK else str(err))
	quit()
