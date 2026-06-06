extends SceneTree

# Pełny pipeline na pliku sceny (gdy edytor ma zamkniętą scenę!):
# 1) rest każdej kości = jej position (naprawa "Set Rest"),
# 2) triangulacja, jeśli są punkty wewnętrzne,
# 3) auto-wagi,
# 4) zapis sceny.
# Uruchomienie: godot --headless --script res://rig/apply_autoweights.gd

# Scenę można podać po "--", np.:
#   godot --headless --script res://rig/apply_autoweights.gd -- res://rig/wojtek_rig.tscn
# Z dodatkowym argumentem "szkielet" najpierw rozstawia kości z obrysu:
#   godot --headless --script res://rig/apply_autoweights.gd -- res://rig/wojtek_rig.tscn szkielet
const SCENE_DEFAULT := "res://rig/michal_rig.tscn"

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := args[0] if args.size() > 0 else SCENE_DEFAULT
	print("scena: ", scene_path)
	var root := (load(scene_path) as PackedScene).instantiate()
	get_root().add_child(root)

	var poly: Polygon2D = root.get_node("Polygon2D")
	if "szkielet" in args:
		poly._auto_skeleton()
	poly._rebuild_all()  # rest sync + triangulacja + auto-wagi

	# 4) zapis
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		print("BLAD pack: ", err)
		quit(1)
		return
	err = ResourceSaver.save(packed, scene_path)
	print("zapis: ", "OK" if err == OK else str(err))
	quit()
