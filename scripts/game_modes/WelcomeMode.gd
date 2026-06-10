extends GameMode

class_name WelcomeMode

func on_enter(classroom: Classroom) -> void:
	_classroom = classroom
	for pupil in classroom.get_pupils():
		pupil.pupil_clicked.connect(on_pupil_clicked)

func on_exit() -> void:
	for pupil in _classroom.get_pupils():
		if pupil.pupil_clicked.is_connected(on_pupil_clicked):
			pupil.pupil_clicked.disconnect(on_pupil_clicked)
	_classroom = null

func on_pupil_clicked(pupil: Pupil) -> void:
	# Reakcja na klik: głos + (jeśli uczeń ją ma) proceduralna przemiana.
	var audio: AudioStreamPlayer = pupil.get_node_or_null("AudioStreamPlayer")
	if audio:
		audio.play()
	if pupil.transform_textures.size() >= 2 and pupil.transform_state != pupil.TransformState.RUNNING:
		_run_transform(pupil)


# --- przemiana (np. Łucja -> brontozaur) ------------------------------------

func _run_transform(pupil: Pupil) -> void:
	# Każde stadium miga na żółto na zmianę z następnym, aż zostaje ostatnie.
	# Przy odwrotnej przemianie sekwencja leci od końca i wraca oryginalny sprite.
	var reverse := pupil.transform_state == pupil.TransformState.TRANSFORMED
	pupil.transform_state = pupil.TransformState.RUNNING

	if pupil._transform_orig.is_empty():
		_save_transform_orig(pupil)

	var anim: AnimationPlayer = pupil.get_node_or_null("AnimationPlayer")
	if anim and anim.is_playing():
		pupil._transform_orig.anim = anim.current_animation
		anim.stop()

	var target: CanvasItem = pupil.sprite if pupil.sprite else pupil.texture_rect
	var seq := pupil.transform_textures.duplicate()
	if reverse:
		seq.reverse()

	# Stopniowe rozszerzanie: po pierwszym stadium szerokość rośnie z każdym
	# mignięciem od szerokości wyjściowej do naturalnej szerokości tekstury
	# (trans_2/bronto zaczynają wąskie jak Łucja i puchną do brontozaura).
	var total_steps := (seq.size() - 1) * pupil.FLASH_SWAPS
	var step := 0
	for phase in seq.size() - 1:
		for j in pupil.FLASH_SWAPS:
			var width_p := clampf(
				float(step + 1 - pupil.FLASH_SWAPS) / float(total_steps - pupil.FLASH_SWAPS), 0.0, 1.0)
			if reverse:
				width_p = 1.0 - width_p
			_set_transform_texture(pupil, seq[phase + (j % 2)], width_p)
			target.modulate = pupil.FLASH_COLOUR if j % 2 == 0 else pupil.COLOUR_NORMAL
			step += 1
			await pupil.get_tree().create_timer(pupil.FLASH_TIME).timeout
			if not pupil.is_inside_tree():
				return

	target.modulate = pupil.COLOUR_NORMAL
	if reverse:
		_restore_transform_orig(pupil)
		pupil.transform_state = pupil.TransformState.NORMAL
	else:
		pupil.transform_state = pupil.TransformState.TRANSFORMED


func _save_transform_orig(pupil: Pupil) -> void:
	# Wygląd sprzed przemiany + wspólna skala: pierwsza tekstura przemiany ma być
	# tak wysoka, jak klatka, którą uczeń wyświetla na co dzień. Wysokości rysunków
	# stadiów są spójne, więc jeden mnożnik wystarcza (bronto wychodzi szerszy).
	var sprite:= pupil.sprite
	if sprite:
		pupil._transform_orig = {
			"texture": sprite.texture,
			"hframes": sprite.hframes,
			"vframes": sprite.vframes,
			"scale": sprite.scale,
			"position": sprite.position,
			"anim": "",
		}
		var frame_h := float(sprite.texture.get_height()) / sprite.vframes
		var display_h := frame_h * sprite.scale.y
		pupil._transform_scale = display_h / pupil.transform_textures[0].get_height()
		pupil._transform_bottom = sprite.position.y + display_h / 2.0
		pupil._transform_base_w = pupil.transform_textures[0].get_width() * pupil._transform_scale
	else:
		pupil._transform_orig = { "texture": pupil.texture_rect.texture, "anim": "" }


func _set_transform_texture(pupil: Pupil, tex: Texture2D, width_p := 1.0) -> void:
	var sprite:= pupil.sprite
	if sprite:
		sprite.texture = tex
		sprite.hframes = 1
		sprite.vframes = 1
		sprite.frame = 0
		# Szerokość na ekranie: między szerokością stadium wyjściowego
		# a naturalną szerokością tej tekstury, wg postępu przemiany.
		var natural_w := tex.get_width() * pupil._transform_scale
		var w := lerpf(minf(pupil._transform_base_w, natural_w), natural_w, width_p)
		sprite.scale = Vector2(pupil._transform_scale * w / natural_w, pupil._transform_scale)
		sprite.position = Vector2(
			pupil._transform_orig.position.x,
			pupil._transform_bottom - tex.get_height() * pupil._transform_scale / 2.0)
	else:
		pupil.texture_rect.texture = tex


func _restore_transform_orig(pupil: Pupil) -> void:
	var sprite:= pupil.sprite
	if sprite:
		sprite.texture = pupil._transform_orig.texture
		sprite.hframes = pupil._transform_orig.hframes
		sprite.vframes = pupil._transform_orig.vframes
		sprite.frame = 0
		sprite.scale = pupil._transform_orig.scale
		sprite.position = pupil._transform_orig.position
	else:
		pupil.texture_rect.texture = pupil._transform_orig.texture
	var anim: AnimationPlayer = pupil.get_node_or_null("AnimationPlayer")
	if anim and pupil._transform_orig.anim != "":
		anim.play(pupil._transform_orig.anim)
