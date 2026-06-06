extends SceneTree

# Test auto-rozstawienia kości (bez zapisu): porównuje pozycje proponowane
# przez _auto_skeleton() z obecnymi (ręcznie ustawionymi) w scenie.
# Uruchomienie: godot --headless --script res://rig/check_skeleton.gd [-- scena]

const SCENE_DEFAULT := "res://rig/michal_rig.tscn"

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := args[0] if args.size() > 0 else SCENE_DEFAULT
	var root := (load(scene_path) as PackedScene).instantiate()
	get_root().add_child(root)
	var skel: Skeleton2D = root.get_node("Skeleton2D")
	var poly: Polygon2D = root.get_node("Polygon2D")

	var bones: Array = []
	poly._collect_bones(skel, bones)
	var before := {}
	for bone in bones:
		before[String(bone.name)] = bone.global_position

	poly._auto_skeleton()

	print("\nkosc            | recznie        | automat        | roznica")
	for bone in bones:
		var name := String(bone.name)
		var now: Vector2 = bone.global_position
		var old: Vector2 = before[name]
		print("%-15s | (%4.0f, %4.0f) | (%4.0f, %4.0f) | %.0f px"
			% [name, old.x, old.y, now.x, now.y, old.distance_to(now)])
	quit()
