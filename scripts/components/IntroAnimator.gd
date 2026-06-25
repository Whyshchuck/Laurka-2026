extends Node

# Intro strony tytułowej.
# Kaskada napisu "dziękujemy": pojawia się jeden po drugim, co drobną część
# sekundy kolejny pod spodem, a górne znikają (strumień płynący w dół).
# Na koniec zostaje "Dziękujemy" u góry i "klasa 2a" u dołu, potem przyciski.
# (Dawne miganie losowymi kolorami usunięte.)

@export var step_interval := 0.12   # co ile pojawia się kolejny napis
@export var step_y := 100.0         # odstęp pionowy między kolejnymi
@export var band := 4               # ile naraz widocznych (potem górne znikają)
@export var top_y := 0.0            # y pierwszego napisu kaskady (jak finalne "Dziękujemy")
@export var bottom_y := 860.0       # y ostatniego napisu kaskady (przy "klasa 2a")
@export var fade_time := 0.18

var _target_node: Node     # $Node — zawiera finalne "Dziękujemy" i "klasa 2a"
var _buttons_node: Node


func play(target_node: Node, buttons_node: Node) -> void:
	_target_node = target_node
	_buttons_node = buttons_node
	_run()


func _run() -> void:
	var top_label := _target_node.get_node_or_null("LetterLabel2") as LetterLabel    # Dziękujemy
	var bottom_label := _target_node.get_node_or_null("LetterLabel3") as LetterLabel  # klasa 2a

	# Na czas kaskady ukrywamy finalne napisy i przyciski.
	if top_label:
		top_label.modulate.a = 0.0
	if bottom_label:
		bottom_label.modulate.a = 0.0
	for b in _buttons_node.get_children():
		if b is CanvasItem:
			b.visible = false

	if top_label == null:
		_reveal_finale(top_label, bottom_label)
		return

	# Kontener na kopie kaskady — łatwo potem sprzątnąć.
	var holder := Node2D.new()
	holder.name = "Cascade"
	_target_node.add_child(holder)

	# Pozycje pasma: najpierw w dół (top_y -> bottom_y), potem z powrotem w górę.
	var steps := int((bottom_y - top_y) / step_y) + 1
	var ys: Array = []
	for i in range(steps):                 # zjazda w dół
		ys.append(top_y + i * step_y)
	for i in range(steps - 2, -1, -1):     # powrót w górę (bez powtórki dołu)
		ys.append(top_y + i * step_y)

	var copies: Array = []
	for i in range(ys.size()):
		var c := _make_word(top_label)
		c.position = Vector2(top_label.position.x, ys[i])
		c.modulate.a = 0.0
		holder.add_child(c)   # _ready zbuduje literki świeżo
		copies.append(c)
		_fade(c, 1.0)                       # nowy pojawia się na czole pasma
		if i >= band:
			_fade_out_free(copies[i - band])  # tylny koniec pasma znika
		await get_tree().create_timer(step_interval).timeout

	# Reszta widocznych kopii znika.
	for j in range(maxi(0, ys.size() - band), ys.size()):
		_fade_out_free(copies[j])
	await get_tree().create_timer(fade_time).timeout

	_reveal_finale(top_label, bottom_label)

	# Sprzątanie kontenera kaskady.
	await get_tree().create_timer(fade_time + 0.1).timeout
	if is_instance_valid(holder):
		holder.queue_free()


func _reveal_finale(top_label: Node2D, bottom_label: Node2D) -> void:
	# "Dziękujemy" u góry, "klasa 2a" u dołu, potem przyciski.
	if top_label:
		_fade(top_label, 1.0)
	if bottom_label:
		_fade(bottom_label, 1.0)
	await get_tree().create_timer(fade_time + 0.1).timeout
	for b in _buttons_node.get_children():
		if b is CanvasItem:
			b.visible = true
			b.modulate.a = 0.0
			_fade(b, 1.0)


func _make_word(template: LetterLabel) -> LetterLabel:
	# Świeża kopia napisu (te same proporcje co finalne "Dziękujemy"),
	# bez cyklowania wariantów. Literki zbuduje własne _ready po add_child.
	var c := LetterLabel.new()
	c.text = template.text
	c.letter_height = template.letter_height
	c.letter_spacing = template.letter_spacing
	c.space_width = template.space_width
	c.centered = template.centered
	c.variant_mode = LetterLabel.VariantMode.RANDOM
	c.scale = template.scale
	return c


func _fade(node: CanvasItem, to_a: float) -> void:
	var t := create_tween()
	t.tween_property(node, "modulate:a", to_a, fade_time).set_trans(Tween.TRANS_SINE)


func _fade_out_free(node: CanvasItem) -> void:
	if not is_instance_valid(node):
		return
	var t := create_tween()
	t.tween_property(node, "modulate:a", 0.0, fade_time).set_trans(Tween.TRANS_SINE)
	t.tween_callback(node.queue_free)
