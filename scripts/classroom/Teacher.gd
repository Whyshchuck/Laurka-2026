extends CharacterBody2D
class_name Teacher

signal teacher_clicked(teacher: Teacher)

@onready var texture_rect: TextureRect = $TextureRect3
@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")
@onready var anim: AnimationPlayer = $AnimationPlayer

func _ready():
	anim.play('idle')

func _unhandled_input(event):
	if not (event is InputEventMouseButton and event.pressed):
		return

	var mouse_pos = get_global_mouse_position()
	# Rect liczony ręcznie, bo get_global_rect() nie uwzględnia scale.
	if texture_rect.get_global_rect().has_point(mouse_pos):
		teacher_clicked.emit(self)
