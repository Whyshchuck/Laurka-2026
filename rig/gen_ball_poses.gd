extends SceneTree

# Generator: dla postaci z piłką tworzy w jej bibliotece własne wersje
# uniwersalnych póz (ruch szkieletu + stały tor Pilka:position na podłodze).
# Dla póz SIADU dokłada też opuszczenie kości Biodra (siad na podłodze) —
# to robione kością (nie węzłem Skeleton2D), więc render_pose pokazuje to
# natywnie, bez przesuwania sprajta poza animacją (jak skok).
# Można uruchomić ponownie — nadpisuje kopie, nie rusza ręcznych animacji
# (kozlowanie, trzyma, wsad, podnosi).
#
#   godot --headless --script res://rig/gen_ball_poses.gd -- \
#       <shared.tres> <char.tres> <floor_x> <floor_y> <biodra_x> <biodra_y> <sit_drop>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var shared_path: String = args[0]
	var char_path: String = args[1]
	var floor_pos := Vector2(float(args[2]), float(args[3]))
	var biodra_x := float(args[4])
	var biodra_y := float(args[5])
	var sit_drop := float(args[6])

	var shared := load(shared_path) as AnimationLibrary
	var klib := load(char_path) as AnimationLibrary

	# Pozy siadu: jak biodra schodzą w trakcie (na początku/końcu rest vs niżej).
	var sit := {"siedzi": [1.0, 1.0], "siadanie": [0.0, 1.0], "wstawanie": [1.0, 0.0]}
	var up := Vector2(biodra_x, biodra_y)
	var down := Vector2(biodra_x, biodra_y + sit_drop)

	for name in shared.get_animation_list():
		var anim := (shared.get_animation(name) as Animation).duplicate(true)
		var length: float = maxf(anim.length, 0.0001)

		var tp: int = anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(tp, NodePath("Pilka:position"))
		anim.value_track_set_update_mode(tp, Animation.UPDATE_CONTINUOUS)
		anim.track_insert_key(tp, 0.0, floor_pos)
		anim.track_insert_key(tp, length, floor_pos)

		if sit.has(name):
			var fr: Array = sit[name]
			var tb: int = anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(tb, NodePath("Skeleton2D/Biodra:position"))
			anim.track_insert_key(tb, 0.0, up.lerp(down, fr[0]))
			anim.track_insert_key(tb, length, up.lerp(down, fr[1]))

		if klib.has_animation(name):
			klib.remove_animation(name)
		klib.add_animation(name, anim)
		print("  + k/", name, (" (siad: biodra w dół)" if sit.has(name) else ""))

	var err := ResourceSaver.save(klib, char_path)
	print("zapis ", char_path, ": ", "OK" if err == OK else str(err))
	quit()
