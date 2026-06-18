extends SceneTree
# Przelicza siatkę+wagi (auto-wagi do najbliższych kości) i kolejność rysowania,
# bez ruszania szkieletu. Naprawia np. rękę przyklejoną wagą do tułowia.
func _init() -> void:
	var scene_path: String = OS.get_cmdline_user_args()[0]
	var root := (load(scene_path) as PackedScene).instantiate()
	get_root().add_child(root)
	var poly: Polygon2D = root.get_node("Polygon2D")
	poly._rebuild_all()
	poly._order_draw()
	var packed := PackedScene.new()
	packed.pack(root)
	var err := ResourceSaver.save(packed, scene_path)
	print("zapis: ", "OK" if err == OK else str(err))
	quit()
