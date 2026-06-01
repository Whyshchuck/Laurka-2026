extends CharacterBody2D

enum CharacterState {
	IDLE,
	TALKING
}

@export_group("Quiz")
## Pytanie o tego ucznia (tryb "Jak dobrze nas znasz?"). Na razie puste — placeholder.
@export_multiline var quiz_question: String = ""
## Trzy odpowiedzi a/b/c. Na razie puste.
@export var quiz_answers: Array[String] = ["", "", ""]
## Indeks poprawnej odpowiedzi (0 = A, 1 = B, 2 = C).
@export var quiz_correct_answer: int = 0

var character_state: CharacterState = CharacterState.IDLE

@onready var texture_rect: TextureRect = $TextureRect
@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")  # nie każdy uczeń ma Sprite2D

func _ready():
	pass

func _unhandled_input(_event: InputEvent) -> void:
	pass
				
func on_click():
	match Global.current_mode:
		Global.GameMode.WELCOME:
			if has_node("AudioStreamPlayer"):
				$AudioStreamPlayer.play()
		Global.GameMode.QUIZ:
			pass # TODO (Faza 4): klik -> tło szarzeje, slide sprite'a, pytania a/b/c

func _physics_process(_delta):
	z_index = 10 + position.y
