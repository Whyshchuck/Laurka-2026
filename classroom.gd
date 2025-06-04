extends Node2D

@export var interval_seconds: float = 1.0
var timer := 0.0
var rng := RandomNumberGenerator.new()
var pupils_node: Node = null

func _ready():
	rng.randomize()
	pupils_node = get_node("Pupils")  # Adjust path if Pupils is not a direct child

func _process(delta):
	timer += delta
	if timer >= interval_seconds:
		timer = 0
		activate_random_pupil()

func activate_random_pupil():
	if not pupils_node:
		return

	var available_pupils := []
	for pupil in pupils_node.get_children():
		# Check that pupil is CharacterBody2D and not locked or returning
		if pupil is CharacterBody2D and not pupil.locked and not pupil.returning_to_start:
			available_pupils.append(pupil)

	if available_pupils.size() > 0:
		var chosen = available_pupils[rng.randi_range(0, available_pupils.size() - 1)]
		chosen.pick_new_target()
