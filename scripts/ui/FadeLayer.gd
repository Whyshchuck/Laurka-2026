extends CanvasLayer

#@onready var rect = $ColorRect
@onready var rect = get_node_or_null("ColorRect")

func _ready():
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate.a = 0.0

func fade_in(duration: float = 1.0) -> void:
	rect.modulate.a = 1.0
	var tween = create_tween()
	tween.tween_property(rect, "modulate:a", 0.0, duration)
	await tween.finished

func fade_out(duration: float = 1.0) -> void:
	rect.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(rect, "modulate:a", 1.0, duration)
	await tween.finished
