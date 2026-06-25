extends SceneTree
func _init():
	var img := (load("res://_chk.png") as Texture2D).get_image()
	img.convert(Image.FORMAT_RGBA8)
	print("img ", img.get_size())
	var r := Rect2i(60, 150, 1000, 900)
	img.get_region(r).save_png(ProjectSettings.globalize_path("res://rig/_c.png"))
	print("saved")
	quit()
