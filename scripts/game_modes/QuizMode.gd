extends GameMode
class_name QuizMode

const QuizOverlayScene := preload("res://scenes/ui/overlays/QuizOverlay.tscn")

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
	open_quiz(pupil)

func open_quiz(pupil) -> void:
	# Otwórz nakładkę quizu dla klikniętego dziecka (tylko jedna naraz).
	if _classroom.quiz_overlay and is_instance_valid(_classroom.quiz_overlay):
		return
	# Prevent reopening quiz for a pupil that's already been answered
	if GameState.has_pupil_been_answered(pupil.name):
		print("Pupil %s already answered." % pupil.name)
		return
		
	var quiz_overlay := QuizOverlayScene.instantiate()
	_classroom.add_child(quiz_overlay)
	_classroom.quiz_overlay = quiz_overlay
	quiz_overlay.open_for_pupil(pupil)
	quiz_overlay.quiz_completed.connect(update_quiz_score_label)

func update_quiz_score_label() -> void:
	if not _classroom.score_label:
		return
	_classroom.score_label.visible = GameState.current_type == GameState.GameType.QUIZ
	_classroom.score_label.text = GameState.get_quiz_score_text()
