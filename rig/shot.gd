extends Node
const TARGET_W := 2000
func _ready() -> void:
	var c := (load("res://scenes/classroom/Classroom.tscn") as PackedScene).instantiate()
	c.name = "Classroom"
	get_tree().root.add_child.call_deferred(c)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var pupils := get_node_or_null("/root/Classroom/Pupils")
	if pupils:
		for pupil in pupils.get_children():
			var rig := pupil.get_node_or_null("Rig")
			if rig == null: continue
			var ap := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
			if ap == null: continue
			for a in ap.get_animation_list():
				if a.ends_with("/stoi"): ap.play(a); ap.seek(0.0, true); break
	var z := float(TARGET_W) / 1080.0
	get_window().content_scale_size = Vector2i(TARGET_W, int(round(1200.0*z)))
	var cam := get_node_or_null("/root/Classroom/Camera2D") as Camera2D
	if cam: cam.zoom = Vector2(z, z)
	for i in 10: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://_chk.png"))
	print("OK")
	get_tree().quit()
