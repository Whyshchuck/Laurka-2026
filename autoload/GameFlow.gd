extends Node

const CLASSROOM_SCENE_PATH: String = "res://scenes/classroom/Classroom.tscn"
const MODE_SELECTION_SCENE_PATH: String = "res://scenes/ui/ModeSelection.tscn"
const FINAL_SCENE_PATH: String = "res://scenes/ui/Final.tscn"

func start_game(mode: int) -> void:
	GameState.time_elapsed = 0
	GameState.set_mode(mode)
	if mode == GameState.GameMode.QUIZ:
		GameState.reset()
	await SceneManager.change_scene(CLASSROOM_SCENE_PATH, 0.5)



func go_to_mode_selection() -> void:
	await SceneManager.change_scene(MODE_SELECTION_SCENE_PATH, 0.5)

func go_to_final_scene() -> void:
	await SceneManager.change_scene(FINAL_SCENE_PATH, 0.5)
