extends CharacterBody2D

@export var speed := 300.0

var direction := Vector2.ZERO
var locked := false
var returning_to_start := false
var start_position := Vector2.ZERO
var rng := RandomNumberGenerator.new()

@onready var agent := $NavigationAgent2D

func _ready():
	rng.randomize()
	start_position = global_position
	pick_new_target()

func _input(event):
	if locked or returning_to_start:
		return
	if event is InputEventMouseButton and event.pressed:
		var mouse_pos = get_global_mouse_position()
		var rect = get_node("TextureRect").get_global_rect()
		if rect.has_point(mouse_pos):
			return_to_start()

func _physics_process(delta):
	if locked:
		direction = Vector2.ZERO
		global_position = start_position
		return

	if returning_to_start:
		move_along_agent(delta)
		if global_position.distance_to(start_position) < 5:
			locked = true
			returning_to_start = false
			direction = Vector2.ZERO
		return

	if agent.is_navigation_finished():
		pick_new_target()

	move_along_agent(delta)

func move_along_agent(delta):
	var next_pos = agent.get_next_path_position()
	direction = (next_pos - global_position).normalized()
	velocity = direction * speed
	move_and_slide()

func pick_new_target():
	var area_min = Vector2(130, 219)
	var area_max = Vector2(909, 1302)

	for _i in range(20):
		var random_point = Vector2(
			rng.randi_range(area_min.x, area_max.x),
			rng.randi_range(area_min.y, area_max.y)
		)
		agent.target_position = random_point
		return

	direction = Vector2.ZERO

func return_to_start():
	returning_to_start = true
	agent.target_position = start_position
