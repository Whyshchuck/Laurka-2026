extends SceneTree

# Podgląd riga bez edytora: rysuje sprite + kości (linie i kwadraty stawów)
# do res://rig/debug_skeleton.png.
# Uruchomienie: godot --headless --script res://rig/render_skeleton.gd [-- scena]

const SCENE_DEFAULT := "res://rig/kazik_rig.tscn"
const OUT := "res://rig/debug_skeleton.png"

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var scene_path := args[0] if args.size() > 0 else SCENE_DEFAULT
	var root := (load(scene_path) as PackedScene).instantiate()
	get_root().add_child(root)
	var poly: Polygon2D = root.get_node("Polygon2D")
	var skel: Skeleton2D = root.get_node("Skeleton2D")
	if "auto" in args:  # podgląd propozycji automatu (bez zapisu sceny)
		poly._auto_skeleton()

	var img: Image = poly.texture.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)

	# Kości w układzie Polygon2D (tam, gdzie leży tekstura).
	var bones: Array = []
	poly._collect_bones(skel, bones)
	for bone in bones:
		var a := poly.to_local(bone.global_position)
		var b := a
		var child: Bone2D = null
		for c in bone.get_children():
			if c is Bone2D:
				child = c
				break
		if child:
			b = poly.to_local(child.global_position)
		else:
			b = poly.to_local(bone.global_position + bone.get_global_transform() \
				.basis_xform(Vector2.from_angle(bone.bone_angle)) * bone.length)
		_line(img, a, b, Color(1, 0, 0))
		_dot(img, a, Color(0, 0.6, 1))
		print("%-13s staw=(%4.0f, %4.0f)" % [bone.name, a.x, a.y])

	img.save_png(ProjectSettings.globalize_path(OUT))
	print("zapisano: ", OUT)
	quit()


func _line(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	var steps := int(a.distance_to(b)) + 1
	for i in steps + 1:
		_px(img, a.lerp(b, float(i) / steps), col, 2)


func _dot(img: Image, p: Vector2, col: Color) -> void:
	_px(img, p, col, 6)


func _px(img: Image, p: Vector2, col: Color, r: int) -> void:
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var x := int(p.x) + dx
			var y := int(p.y) + dy
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, col)
