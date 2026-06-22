extends SceneTree
# Retargeting animacji pod proporcje postaci. Wejście: wspólna biblioteka +
# kalibracja "stoi" (metadane stoi_calib na Polygon2D, ustawione przyciskiem).
# Dla każdego toru ROTACJI: nowa = stoi_postaci + (wspólna - wspólne_stoi).
# Skale kopiuje, RESET zostawia (rysunkowy zero). Dla póz siadu dokłada
# opuszczenie Biodra; dla postaci z piłką - tor piłki na podłodze.
# Na końcu wpina bibliotekę jako "k" do AnimationPlayer i ZAPISUJE scenę rigu,
# więc — jak w apply_all — scena MUSI być zamknięta w edytorze.
#  godot --headless --script res://rig/gen_retarget.gd -- \
#     <shared.tres> <char.tres> <scene.tscn> <sit_drop> [floor_x floor_y]

func _bp(track_path: String) -> String:
	var p := track_path
	if p.begins_with("Skeleton2D/"):
		p = p.substr("Skeleton2D/".length())
	var c := p.find(":")
	return p.substr(0, c) if c >= 0 else p

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var shared := load(a[0]) as AnimationLibrary
	var char_path: String = a[1]
	var klib := load(char_path) as AnimationLibrary
	var sit_drop := float(a[3])
	var has_floor := a.size() >= 6
	var floor_pos := Vector2(float(a[4]), float(a[5])) if has_floor else Vector2.ZERO

	var root := (load(a[2]) as PackedScene).instantiate()
	get_root().add_child(root)
	var poly: Polygon2D = root.get_node("Polygon2D")
	var skel: Skeleton2D = root.get_node("Skeleton2D")
	var stoi: Dictionary = poly.get_meta("stoi_calib", {})
	var biodra: Vector2 = skel.get_node("Biodra").rest.origin
	var has_pilka: bool = root.has_node("Pilka")

	# wspólne stoi - wartości referencyjne rotacji
	var sref := {}
	var sstoi := shared.get_animation("stoi") as Animation
	for ti in sstoi.get_track_count():
		var p := str(sstoi.track_get_path(ti))
		if p.ends_with(":rotation"):
			sref[_bp(p)] = float(sstoi.track_get_key_value(ti, 0))

	var sit := {"siedzi": [1.0, 1.0], "siadanie": [0.0, 1.0], "wstawanie": [1.0, 0.0]}
	var up := Vector2(biodra.x, biodra.y)
	var down := Vector2(biodra.x, biodra.y + sit_drop)

	for name in shared.get_animation_list():
		var anim := (shared.get_animation(name) as Animation).duplicate(true)
		var length: float = maxf(anim.length, 0.0001)
		# retarget rotacji (RESET zostawiamy = rysunkowy zero)
		if name != "RESET":
			for ti in anim.get_track_count():
				var p := str(anim.track_get_path(ti))
				if p.ends_with(":rotation") and anim.track_get_type(ti) == Animation.TYPE_VALUE:
					var bp := _bp(p)
					var off: float = float(stoi.get(bp, 0.0)) - float(sref.get(bp, 0.0))
					if absf(off) > 0.0001:
						for ki in anim.track_get_key_count(ti):
							anim.track_set_key_value(ti, ki, float(anim.track_get_key_value(ti, ki)) + off)
		# piłka na podłodze
		if has_pilka and has_floor:
			var tp: int = anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(tp, NodePath("Pilka:position"))
			anim.track_insert_key(tp, 0.0, floor_pos)
			anim.track_insert_key(tp, length, floor_pos)
		# siad: opuszczenie bioder
		if sit.has(name):
			var fr: Array = sit[name]
			var tb: int = anim.add_track(Animation.TYPE_VALUE)
			anim.track_set_path(tb, NodePath("Skeleton2D/Biodra:position"))
			anim.track_insert_key(tb, 0.0, up.lerp(down, fr[0]))
			anim.track_insert_key(tb, length, up.lerp(down, fr[1]))
		if klib.has_animation(name):
			klib.remove_animation(name)
		klib.add_animation(name, anim)
		print("  + k/", name)

	var err := ResourceSaver.save(klib, char_path)
	print("stoi_calib niezerowych: ", stoi.values().filter(func(v): return absf(v) > 0.001).size())
	print("zapis ", char_path, ": ", "OK" if err == OK else str(err))

	# Wepnij bibliotekę jako "k" do AnimationPlayer i ZAPISZ scenę rigu,
	# żeby nie trzeba było dodawać jej ręcznie w edytorze (libraries/k = char.tres).
	var ap := root.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap:
		if ap.has_animation_library("k"):
			ap.remove_animation_library("k")
		ap.add_animation_library("k", klib)
		var packed := PackedScene.new()
		packed.pack(root)
		var serr := ResourceSaver.save(packed, a[2])
		print("wpięto k/ + zapis sceny ", a[2], ": ", "OK" if serr == OK else str(serr))
	else:
		print("UWAGA: brak AnimationPlayer w scenie — k/ nie wpięte")
	quit()
