extends GameMode

class_name RunMode

var total_pupils := 0
var sitting_count := 0

var game_started := false

func on_enter(classroom: Classroom) -> void:
	_classroom = classroom
	for pupil in classroom.get_pupils():
		pupil.pupil_clicked.connect(on_pupil_clicked)

func on_exit() -> void:
	for pupil in _classroom.get_pupils():
		if pupil.pupil_clicked.is_connected(on_pupil_clicked):
			pupil.pupil_clicked.disconnect(on_pupil_clicked)
	_classroom = null


func on_pupil_clicked(pupil: Pupil) -> void:
	pass
	
func _unhandled_input(event: InputEvent) -> void:
	if game_started and sitting_count == 24:
		GameFlow.go_to_final_scene()
		
func activate_pupils():
	_classroom.status_timer.start()
	
	if not _classroom.all_pupils:
		return

	for pupil in _classroom.all_pupils:
		if pupil.is_available():
			pupil.pick_new_target()

func update_moving_pupil_count():
	if not _classroom.all_pupils:
		return
	
	sitting_count = total_pupils

	for pupil in _classroom.all_pupils:
		if pupil.is_moving():
			sitting_count -= 1
		
	var status_text := "Uczniowie na miejscach: %d / %d" % [sitting_count, total_pupils]
	
	_classroom.moving_pupils_counter.text = status_text
	
	if not game_started:
		game_started = true
