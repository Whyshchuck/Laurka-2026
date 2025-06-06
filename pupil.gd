extends CharacterBody2D

enum CharacterState {
	STOPPED,
	MOVING,
	RETURNING,
	LOCKED
}

@export var speed := 300.0

var character_state: CharacterState = CharacterState.STOPPED

var direction := Vector2.ZERO
var start_position := Vector2.ZERO
var nav_map_rid: RID
@onready var agent := $NavigationAgent2D

func _ready():
	start_position = global_position
	var nav_region: NavigationRegion2D = get_node("/root/Classroom/NavigationRegion2D")
	nav_map_rid = nav_region.get_navigation_map()

	pick_new_target()

func _unhandled_input(event: InputEvent) -> void:
	if character_state in [CharacterState.LOCKED, CharacterState.RETURNING]:
		return
		
	if event is InputEventMouseButton and event.pressed:
		var mouse_pos: Vector2 = get_global_mouse_position()
		var rect: Rect2 = get_node("TextureRect").get_global_rect()
		if rect.has_point(mouse_pos):
			return_to_start()

func _physics_process(delta):
	if character_state == CharacterState.LOCKED:
		direction = Vector2.ZERO
		global_position = start_position
		return

	if character_state == CharacterState.RETURNING:
		move_along_agent(delta)
		if global_position.distance_to(start_position) < 5:
			character_state = CharacterState.LOCKED
			direction = Vector2.ZERO
		return

	if agent.is_navigation_finished():
		pick_new_target()
	if Global.current_mode == Global.GameMode.EASY:
		return
	move_along_agent(delta)

func move_along_agent(_delta):
	var next_pos = agent.get_next_path_position()
	direction = (next_pos - global_position).normalized()
	velocity = direction * speed
	move_and_slide()

func pick_new_target():
	agent.target_position = NavigationServer2D.map_get_random_point(nav_map_rid, 1, false)
	character_state = CharacterState.MOVING

func return_to_start():
	character_state = CharacterState.RETURNING
	agent.target_position = start_position

func is_available() -> bool:
	"""Check that pupil is not locked or returning"""
	return character_state == CharacterState.STOPPED
