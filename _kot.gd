extends SceneTree
func _init():
	var img := (load("res://sprites/oliwia_kot_biega.png") as Texture2D).get_image()
	var w := img.get_width(); var h := img.get_height()
	print("rozmiar: ", w, "x", h)
	# sylwetka: dla każdej kolumny min/max y (z alfą>0.3)
	var top := []; var bot := []
	var minx := w; var maxx := 0; var miny := h; var maxy := 0
	for x in range(0, w, 8):
		var t := -1; var b := -1
		for y in h:
			if img.get_pixel(x, y).a > 0.3:
				if t < 0: t = y
				b = y
		top.append([x, t]); bot.append([x, b])
		if t >= 0:
			minx = min(minx, x); maxx = max(maxx, x); miny = min(miny, t); maxy = max(maxy, b)
	print("bbox: x[", minx, "..", maxx, "] y[", miny, "..", maxy, "]")
	# dolna krawędź co 8px -> gdzie nogi (lokalne maksima głębokości)
	print("--- dolna krawedz (x: spod) ---")
	var line := ""
	for e in bot:
		if e[1] > 0: line += "%d:%d " % [e[0], e[1]]
	print(line)
	quit()
