extends CharacterBody2D
class_name Pupil

enum CharacterState {
	READY,
	MOVING,
	RETURNING,
	LOCKED,
	RESPAWNING
}

@export var speed := 300.0

# Reakcja na klik (tryb WELCOME): kolejne stadia przemiany,
# np. dla Łucji [norm, trans_1, trans_2, bronto]. Puste = uczeń się nie zmienia.
# Drugi klik odwraca przemianę.
@export var transform_textures: Array[Texture2D] = []

enum TransformState { NORMAL, RUNNING, TRANSFORMED }

const COLOUR_NORMAL := Color(1, 1, 1, 1)
const COLOUR_RESPAWN := Color(1, 0.3, 0.3, 1)
const COLOUR_CANCEL_RESPAWN := Color(0, 1, 0, 1)
const COLOUR_LOCKED := Color(0.326, 0.532, 1.0, 1)

const RESPAWN_TIMEOUT := 4
const MAX_RESPAWN_COUNT := 3

const FLASH_COLOUR := Color(1.6, 1.5, 0.4, 1)  # żółty błysk przemiany
const FLASH_SWAPS := 6    # ile podmian tekstur na jedno stadium przemiany
const FLASH_TIME := 0.09  # czas jednej podmiany

var character_state: CharacterState = CharacterState.READY
var direction := Vector2.ZERO
var start_position := Vector2.ZERO
var nav_map_rid: RID
var respawn_count := 0
var blink_tween: Tween = null

var transform_state := TransformState.NORMAL
var _transform_orig := {}      # zapamiętany wygląd sprite'a sprzed przemiany
var _transform_scale := 1.0    # wspólna skala tekstur przemiany
var _transform_bottom := 0.0   # y dolnej krawędzi — stopy/łapy zawsze na ziemi
var _transform_base_w := 0.0   # szerokość stadium wyjściowego na ekranie

@onready var agent := $NavigationAgent2D
@onready var respawn_timer: Timer = $RespawnTimer
@onready var texture_rect: TextureRect = $TextureRect
@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")  # nie każdy uczeń ma Sprite2D

signal pupil_clicked(pupil: Pupil)

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
		# Dawna mechanika "ganianie" (odprowadzanie uciekinierów) wycofana.
		# Klik obsługuje classroom.gd -> on_click(). TODO Faza 1/2: usunąć resztę chase.
		on_click()
				
func on_click():
	pupil_clicked.emit(self)

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
			elif GameState.current_type == GameState.GameType.QUIZ:
				move_along_agent(delta) # legacy chase (uśpione — patrz Faza 1)

func move_along_agent(_delta):
	var next_pos = agent.get_next_path_position()
	direction = (next_pos - global_position).normalized()
	if $AnimationPlayer:
		$AnimationPlayer.play('walk')
	velocity = direction * speed
	move_and_slide()

func pick_new_target():
	agent.target_position = NavigationServer2D.map_get_random_point(nav_map_rid, 1, false)
	character_state = CharacterState.MOVING

func return_to_start():
	character_state = CharacterState.RETURNING
	agent.target_position = start_position

func enter_locked_state():
	if $AnimationPlayer:
		$AnimationPlayer.play('idle')
	character_state = CharacterState.LOCKED
	direction = Vector2.ZERO
	start_respawn_timer()

	if respawn_count > MAX_RESPAWN_COUNT:
		blink(COLOUR_LOCKED, 0, 0.5)

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
		blink(COLOUR_LOCKED, 0, 0.5)
	else:
		blink(COLOUR_CANCEL_RESPAWN, 0, 0.5)
		await get_tree().create_timer(0.5).timeout
		start_respawn_timer()

func _on_respawn_timer_timeout():
	if character_state == CharacterState.LOCKED and respawn_count <= MAX_RESPAWN_COUNT:
		character_state = CharacterState.RESPAWNING
		blink(COLOUR_RESPAWN, 1, 0)
		await get_tree().create_timer(1).timeout

		if character_state == CharacterState.RESPAWNING:
			pick_new_target()
	#elif respawn_count > MAX_RESPAWN_COUNT:
		#texture_rect.modulate = COLOUR_LOCKED

func blink(highlight_colour: Color, fade_in: float = 0.3, fade_out: float = 0.3):
	if blink_tween and blink_tween.is_running():
		blink_tween.kill()
		texture_rect.modulate = COLOUR_NORMAL
		
	if sprite:
		blink_tween = create_tween()
		blink_tween.tween_property(sprite, "modulate", highlight_colour, fade_in)
		blink_tween.tween_property(sprite, "modulate", COLOUR_NORMAL, fade_out)
	
	else:

		blink_tween = create_tween()
		blink_tween.tween_property(texture_rect, "modulate", highlight_colour, fade_in)
		blink_tween.tween_property(texture_rect, "modulate", COLOUR_NORMAL, fade_out)


func is_available() -> bool:
	return character_state == CharacterState.READY

func is_moving() -> bool:
	return character_state == CharacterState.MOVING
