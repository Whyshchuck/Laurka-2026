extends CharacterBody2D

enum CharacterState {
	READY,
	MOVING,
	RETURNING,
	LOCKED,
	RESPAWNING
}

@export var speed := 300.0

const COLOUR_NORMAL := Color(1, 1, 1, 1)
const COLOUR_RESPAWN := Color(1, 0.3, 0.3, 1)
const COLOUR_YELLOW := Color(0.822, 0.556, 0.313)
const COLOUR_BLUE := Color(0.326, 0.532, 1.0)

const RESPAWN_TIMEOUT := 4
const MAX_RESPAWN_COUNT := 3

var character_state: CharacterState = CharacterState.READY
var direction := Vector2.ZERO
var start_position := Vector2.ZERO
var nav_map_rid: RID
var respawn_count := 0
var blink_tween: Tween = null

@onready var agent := $NavigationAgent2D
@onready var respawn_timer: Timer = $RespawnTimer
@onready var texture_rect: TextureRect = $TextureRect

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
				if character_state == CharacterState.RESPAWNING:
					cancel_respawn()
				else:
					return_to_start()

func _physics_process(delta):
	if character_state in [CharacterState.READY, CharacterState.RESPAWNING]:
		return

	z_index = 10 + position.y

	match character_state:
		CharacterState.LOCKED:
			direction = Vector2.ZERO
			global_position = start_position

		CharacterState.RETURNING:
			move_along_agent(delta)
			if global_position.distance_to(start_position) < 5:
				enter_locked_state()

		CharacterState.MOVING:
			if agent.is_navigation_finished():
				pick_new_target()
			elif Global.current_mode == Global.GameMode.HARD:
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

func enter_locked_state():
	character_state = CharacterState.LOCKED
	direction = Vector2.ZERO
	start_respawn_timer()

	if respawn_count > MAX_RESPAWN_COUNT:
		texture_rect.modulate = COLOUR_BLUE

func start_respawn_timer():
	respawn_timer.start(RESPAWN_TIMEOUT + respawn_count)
	respawn_count += 1

func cancel_respawn():
	if blink_tween and blink_tween.is_running():
		blink_tween.kill()
		texture_rect.modulate = COLOUR_NORMAL

	respawn_timer.stop()
	character_state = CharacterState.LOCKED
	if respawn_count >= MAX_RESPAWN_COUNT:
		texture_rect.modulate = COLOUR_BLUE
	else:
		blink(COLOUR_YELLOW)
		start_respawn_timer()

func _on_respawn_timer_timeout():
	if character_state == CharacterState.LOCKED and respawn_count <= MAX_RESPAWN_COUNT:
		character_state = CharacterState.RESPAWNING
		blink(COLOUR_RESPAWN)
		await get_tree().create_timer(1.3).timeout

		if character_state == CharacterState.RESPAWNING:
			pick_new_target()
	elif respawn_count > MAX_RESPAWN_COUNT:
		texture_rect.modulate = COLOUR_BLUE

func blink(highlight_colour: Color, fade_in: float = 0.3, fade_out: float = 0.3):
	if blink_tween and blink_tween.is_running():
		blink_tween.kill()
		texture_rect.modulate = COLOUR_NORMAL

	blink_tween = create_tween()
	blink_tween.tween_property(texture_rect, "modulate", highlight_colour, fade_in)
	blink_tween.tween_property(texture_rect, "modulate", COLOUR_NORMAL, fade_out)

func is_available() -> bool:
	return character_state == CharacterState.READY

func is_moving() -> bool:
	return character_state == CharacterState.MOVING
