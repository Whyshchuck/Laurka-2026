extends CharacterBody2D
@export var seat_position: Vector2

func _select_direction():
	#tu będzie lista punktów w klasie, spośród których uczeń bedzie wybierał kolejny losowo
	pass

func _go_back_and_sit():
	pass

func runa_away():
	#wywołuje select_direction i robi tam walk_and_slide
	pass
	

func _on_button_pressed() -> void:
	_go_back_and_sit()
	pass # Replace with function body.

#potrzebujemy jeszcze sygnału, kiedy siądzie, żeby liczył czas
