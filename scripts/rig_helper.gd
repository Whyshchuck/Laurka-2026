class_name RigHelper
extends RefCounted

# Wspólny mechanizm pokazywania rigów postaci:
#   - rig postaci = res://rig/<znormalizowana-nazwa>_rig.tscn
#     (małe litery, bez polskich znaków; kilka plików ma nieregularne nazwy -> _OVERRIDE),
#   - poza "stand" = własna "k/stoi" (biblioteka "k") jeśli rig ją ma, inaczej uniwersalna "stoi".

const _PL := {
	"ą": "a", "ć": "c", "ę": "e", "ł": "l", "ń": "n",
	"ó": "o", "ś": "s", "ż": "z", "ź": "z",
}
# Nazwy rigów, które nie wynikają wprost z imienia ucznia.
const _OVERRIDE := {
	"oliwka": "oliwia",
	"kazikr": "kazik_r",
	"michal": "michal_k",   # uwaga: który Michał — jeśli zły, popraw tu
}


static func _norm(s: String) -> String:
	var t := s.to_lower()
	for pl in _PL:
		t = t.replace(pl, _PL[pl])
	return t


static func scene_for(character_name: String) -> PackedScene:
	# Rig danej postaci albo null, gdy go nie ma.
	var n: String = _OVERRIDE.get(_norm(character_name), _norm(character_name))
	var path := "res://rig/%s_rig.tscn" % n
	if ResourceLoader.exists(path):
		return load(path) as PackedScene
	return null


static func bbox(rig: Node2D) -> Rect2:
	# Prostokąt otaczający mesh rigu (w przestrzeni lokalnej rigu).
	var poly := rig.get_node_or_null("Polygon2D") as Polygon2D
	if poly == null or poly.polygon.is_empty():
		return Rect2()
	var pts := poly.polygon
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return Rect2(poly.position + r.position * poly.scale, r.size * poly.scale)


static func fit(rig: Node2D, target: Rect2) -> void:
	# Wpasuj rig w prostokąt: skala wg wysokości, stopy na dole, wyśrodkowane.
	var b := bbox(rig)
	if b.size.y <= 0.0:
		return
	var s := target.size.y / b.size.y
	rig.scale = Vector2(s, s)
	var bottom_center := Vector2(b.position.x + b.size.x * 0.5, b.end.y)
	var target_bottom := Vector2(target.position.x + target.size.x * 0.5, target.end.y)
	rig.global_position = target_bottom - s * bottom_center


static func play(rig: Node2D, base: String) -> void:
	# Odtwórz animację: własną z osobnej biblioteki (np. "k/hura"); inaczej "<base>".
	var ap := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		return
	var anim := ""
	for a in ap.get_animation_list():
		if a.ends_with("/" + base):   # własna biblioteka, np. "k/stoi", "k/hura"
			anim = a
			break
	if anim == "" and ap.has_animation(base):
		anim = base
	if anim == "":
		return
	ap.play(anim)
	ap.seek(0.0, true)  # od razu 1. klatka (też w edytorze, gdzie nie ma _process)


static func play_stand(rig: Node2D) -> void:
	# Własna poza "stand" = "k/stoi"; gdy brak — uniwersalna "stoi".
	play(rig, "stoi")
