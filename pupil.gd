extends CharacterBody2D

enum CharacterState {
	STOPPED,
	MOVING,
	RETURNING,
	LOCKED
}

@export var speed := 300.0

const COLOR_NORMAL := Color(1, 1, 1, 1)
const COLOUR_RESPAWN := Color(1, 0.3, 0.3, 1)
const RESPAWN_TIMEOUT := 5
const MAX_RESPAWN_COUNT = 3

var character_state: CharacterState = CharacterState.STOPPED
var direction := Vector2.ZERO
var start_position := Vector2.ZERO
var nav_map_rid: RID
var respawn_count := 0

@onready var agent := $NavigationAgent2D
@onready var respawn_timer : Timer= $RespawnTimer
@onready var texture_rect : TextureRect = $TextureRect


func _ready():
	start_position = global_position
	var nav_region: NavigationRegion2D = get_node("/root/Classroom/NavigationRegion2D")
	nav_map_rid = nav_region.get_navigation_map()
	respawn_timer.timeout.connect(_on_respawn_timer_timeout)

func _unhandled_input(event: InputEvent) -> void:
	if character_state in [CharacterState.LOCKED, CharacterState.RETURNING]:
		return
		
	if not (event is InputEventMouseButton and event.pressed):
		return
	
	
	var mouse_pos: Vector2 = get_global_mouse_position()
	if texture_rect.get_global_rect().has_point(mouse_pos):
		match Global.current_mode:
			Global.GameMode.EASY:
				if $AudioStreamPlayer:
					$AudioStreamPlayer.play()
		
			Global.GameMode.HARD:
				return_to_start()

func _physics_process(delta):
	if character_state == CharacterState.STOPPED:
		return
	
	z_index = 10+self.position.y
	if character_state == CharacterState.LOCKED:
		direction = Vector2.ZERO
		global_position = start_position
		return

	if character_state == CharacterState.RETURNING:
		move_along_agent(delta)
		if global_position.distance_to(start_position) < 5:
			character_state = CharacterState.LOCKED
			direction = Vector2.ZERO
			
			respawn_timer.start(RESPAWN_TIMEOUT + respawn_count)
			respawn_count += 1
		return

	if agent.is_navigation_finished():
		pick_new_target()
		
	if Global.current_mode == Global.GameMode.HARD:
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
	"""True if the character is stopped."""
	return character_state == CharacterState.STOPPED

func is_moving() -> bool:
	"""True if the character is actively moving."""
	return character_state == CharacterState.MOVING

func _on_respawn_timer_timeout():
	if character_state == CharacterState.LOCKED and respawn_count <= MAX_RESPAWN_COUNT:
		blink()
		await get_tree().create_timer(0.6).timeout
		pick_new_target()

func blink():
	var tween := create_tween()
	tween.tween_property(texture_rect, "modulate", COLOUR_RESPAWN, 0.3)
	tween.tween_property(texture_rect, "modulate", COLOR_NORMAL, 0.3)
