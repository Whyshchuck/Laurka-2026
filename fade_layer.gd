extends CanvasLayer

@onready var rect = $ColorRect

func _ready():
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_in()

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

func fade_to_scene(scene_path: String, duration: float = 1.0) -> void:
	await fade_out(duration)
	get_tree().change_scene_to_file(scene_path)
	# Wait one frame to ensure the scene is fully switched
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await fade_in(duration)
