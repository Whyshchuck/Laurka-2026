extends SceneTree

# Test scen dekoru literek: czy "ó" w napisie dostaje scenę z dekorem
# (letters/decor/o_pol.tscn), czy element jeździ po krzywej i czy dekor
# przesuwa się razem z literką przy zmianach układu (CYCLE).
# Uruchomienie: godot --headless --script res://rig/check_decor.gd

func _init() -> void:
	var demo := (load("res://letters/letter_decor_demo.tscn") as PackedScene).instantiate()
	root.add_child(demo)
	var label := demo.get_node("Napis")
	await create_timer(0.2).timeout  # _ready odpala dopiero po starcie pętli głównej

	var dekor := label.get_node_or_null("DekorO")
	if dekor == null:
		print("BLAD: scena dekoru nie zostala wstawiona za 'ó'")
		quit(1)
		return
	print("dekor wstawiony, pozycja slotu: ", dekor.position.round(),
		" skala: %.2f" % dekor.scale.x)

	# Ruch elementu po krzywej (pozycja lokalna w dekorze).
	var elem: Sprite2D = dekor.get_node("Ozdoba/Element")
	var samples: Array[Vector2] = []
	var slot_positions: Array[float] = []
	for i in 4:
		await create_timer(0.4).timeout
		samples.append(elem.position)
		slot_positions.append(dekor.position.x)
	var moved := 0.0
	for i in samples.size() - 1:
		moved += samples[i].distance_to(samples[i + 1])
	print("droga elementu w ~1.6s: %.0f px (lokalnie)" % moved)
	print("x slotu dekoru w czasie (CYCLE przesuwa uklad): ", slot_positions)

	# Dekor "ż": mucha lata osemki nad litera.
	var dekor_z := label.get_node_or_null("DekorZ")
	if dekor_z == null:
		print("BLAD: brak dekoru za 'ż'")
		quit(1)
		return
	var mucha: Sprite2D = dekor_z.get_node("Ozdoba/Element")
	var prev: Vector2 = mucha.position
	var total := 0.0
	var xs_seen := {}
	for i in 5:
		await create_timer(0.3).timeout
		total += prev.distance_to(mucha.position)
		xs_seen[signf(mucha.position.x)] = true
		prev = mucha.position
	print("mucha: droga %.0f px, strony osemki: %s" % [total, str(xs_seen.keys())])
	quit()
