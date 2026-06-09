extends Node

var current_scene: Node
var fade_layer: CanvasLayer
var is_transitioning := false


func _ready():
	call_deferred("_init_scene_manager")

func _init_scene_manager():
	var fade_scene = preload("res://scenes/ui/FadeLayer.tscn")
	fade_layer = fade_scene.instantiate()
	get_tree().root.add_child(fade_layer)

	current_scene = get_tree().current_scene
	
func change_scene(scene_path: String, duration: float = 1.0) -> void:
	if is_transitioning:
		return

	is_transitioning = true

	await fade_layer.fade_out(duration)

	if current_scene:
		current_scene.queue_free()

	var new_scene = load(scene_path).instantiate()
	get_tree().root.add_child(new_scene)
	get_tree().current_scene = new_scene
	current_scene = new_scene

	await get_tree().process_frame

	await fade_layer.fade_in(duration)

	is_transitioning = false
