extends Control

@onready var easy_mode_button = get_node("EasyModeButton")
@onready var hard_mode_button = get_node("HardModeButton")

var duration := 3.0
var interval := 0.1
var time_elapsed := 0.0
var timer = null

func _ready():
	easy_mode_button.pressed.connect(_on_easy_pressed)
	hard_mode_button.pressed.connect(_on_hard_pressed)
	rainbow_flash_and_hide()

func rainbow_flash_and_hide():
	time_elapsed = 0.0
	var node := $Node

	timer = Timer.new()
	timer.wait_time = interval
	timer.one_shot = false
	add_child(timer)
	timer.timeout.connect(_on_timer_timeout)
	timer.start()

func _on_timer_timeout():
	var node := $Node
	for child in node.get_children():
		if child is CanvasItem:
			child.modulate = Color(
				randf(), randf(), randf(), 1.0
			)
	time_elapsed += interval
	if time_elapsed >= duration:
		timer.stop()
		timer.queue_free()
		start_fade_out()
		start_fade_in()

func start_fade_out():
	var node := $Node
	for child in node.get_children():
		if child is CanvasItem:
			var tween := create_tween()
			tween.tween_property(
				child, "modulate:a", 0.0, 1.0  # znikanie przez 1 sekundę
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func start_fade_in():
	var node := $Buttons
	for child in node.get_children():
		if child is CanvasItem:
			child.visible = true  # Upewnij się, że jest widoczny
			child.modulate.a = 0.0  # Start z pełną przezroczystością

			var tween := create_tween()
			tween.tween_property(
				child, "modulate:a", 1.0, 1.0  # pojawianie przez 1 sekundę
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _on_easy_pressed():
	Global.start_game(Global.GameMode.EASY)

func _on_hard_pressed():
	Global.start_game(Global.GameMode.HARD)


func _on_texture_rect_mouse_entered() -> void:
	var node := $Skulls
	for child in node.get_children():
		if child is CanvasItem:
			if not child.has_meta("original_scale"):
				child.set_meta("original_scale", child.scale)
			child.visible = true
			child.modulate.a = 0.0  # start od przezroczystości

			# Fade-in
			var tween := create_tween()
			tween.tween_property(
				child, "modulate:a", 1.0, 0.5
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

			# Pulsowanie (skala)
			tween.set_loops()  # nieskończone
			var original_scale = child.get_meta("original_scale")
			tween.tween_property(child, "scale", original_scale * 1.2, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tween.tween_property(child, "scale", original_scale, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

			# Zapisujemy tween w dziecku, by potem go zatrzymać
			child.set_meta("pulse_tween", tween)
	# Powiększenie samego napisu (czyli tego TextureRect, który wysyła sygnał)
	var label = $Buttons/HardTexture  # lub EasyTexture jeśli inny
	var orig = label.scale
	label.set_meta("original_scale", orig)  # zapisz oryginalną skalę

	var tween := create_tween()
	tween.tween_property(
		label, "scale", orig * 1.02, 0.3
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_texture_rect_mouse_exited() -> void:
	if not $Buttons/HardTexture.visible == true:
		return
	var node := $Skulls
	for child in node.get_children():
		if child is CanvasItem:
			# Zatrzymanie pulsowania
			if child.has_meta("pulse_tween"):
				var tween: Tween = child.get_meta("pulse_tween")
				if is_instance_valid(tween):
					tween.kill()  # zatrzymaj animację
				child.remove_meta("pulse_tween")

			# Fade-out
			var tween := create_tween()
			tween.tween_property(
				child, "modulate:a", 0.0, 0.5
			).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

			# Ukryj po zniknięciu
			tween.tween_callback(func(): child.visible = false)
	var label = $Buttons/HardTexture  # lub EasyTexture jeśli inny
	var original_scale = label.scale
	if label.has_meta("original_scale"):
		var orig = label.get_meta("original_scale")
		var tween := create_tween()
		tween.tween_property(
			label, "scale", orig, 0.3
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _on_hard_texture_gui_input(event: InputEventMouseButton) -> void:
	if event is InputEventMouseButton and event.pressed:
		Global.start_game(Global.GameMode.HARD)


func _on_easy_texture_gui_input(event: InputEventMouseButton) -> void:
	if event is InputEventMouseButton and event.pressed:
		Global.start_game(Global.GameMode.EASY)


func _on_easy_texture_mouse_entered() -> void:
	var label = $Buttons/EasyTexture  # lub EasyTexture jeśli inny
	var orig = label.scale
	label.set_meta("original_scale", orig)  # zapisz oryginalną skalę

	var tween := create_tween()
	tween.tween_property(
		label, "scale", orig * 1.02, 0.3
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_easy_texture_mouse_exited() -> void:
	var label = $Buttons/EasyTexture  # lub EasyTexture jeśli inny
	var original_scale = label.scale
	if label.has_meta("original_scale"):
		var orig = label.get_meta("original_scale")
		var tween := create_tween()
		tween.tween_property(
			label, "scale", orig, 0.3
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
