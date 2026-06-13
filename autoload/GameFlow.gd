extends Node

const CLASSROOM_SCENE_PATH: String = "res://scenes/classroom/Classroom.tscn"
const MODE_SELECTION_SCENE_PATH: String = "res://scenes/ui/ModeSelection.tscn"
const FINAL_SCENE_PATH: String = "res://scenes/ui/Final.tscn"

func start_game(game_type: int) -> void:
	GameState.time_elapsed = 0
	GameState.set_game_type(game_type)
	if game_type == GameState.GameType.QUIZ:
		GameState.game_mode = QuizMode.new()
		GameState.reset()
	if game_type == GameState.GameType.WELCOME:
		GameState.game_mode = WelcomeMode.new()
		
	await SceneManager.change_scene(CLASSROOM_SCENE_PATH, 0.5)


func go_to_mode_selection() -> void:
	if GameState.game_mode:
		GameState.game_mode.on_exit()
	await SceneManager.change_scene(MODE_SELECTION_SCENE_PATH, 0.5)
	

func go_to_final_scene() -> void:
	#if GameState.game_mode:
		#GameState.game_mode.on_exit()
	await SceneManager.change_scene(FINAL_SCENE_PATH, 0.5)
