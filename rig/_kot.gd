extends SceneTree
func _init():
	var img := (load("res://sprites/oliwia_kot_biega.png") as Texture2D).get_image()
	var w := img.get_width(); var h := img.get_height()
	var minx := w; var maxx := 0; var miny := h; var maxy := 0
	var bot := {}
	for x in range(0, w, 10):
		var t := -1; var b := -1
		for y in h:
			if img.get_pixel(x, y).a > 0.4:
				if t < 0: t = y
				b = y
		if t >= 0:
			minx = mini(minx, x); maxx = maxi(maxx, x); miny = mini(miny, t); maxy = maxi(maxy, b)
			bot[x] = b
	print("ROZMIAR ", w, "x", h, " BBOX x[", minx, "-", maxx, "] y[", miny, "-", maxy, "]")
	var s := "DOL "
	for x in bot: s += str(x) + ":" + str(bot[x]) + " "
	print(s)
	quit()
