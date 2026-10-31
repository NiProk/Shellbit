extends TestCase
## Долгое нажатие на карточку игры — меню, а не запуск игры.

const GameCardScene := preload("res://scenes/components/GameCard.tscn")


func test_long_press_opens_menu_not_game() -> void:
	about("Карточка: держим палец — меню; отпустили после этого — игра не открывается")
	var card: GameCard = GameCardScene.instantiate()
	add_child(card)
	await frames(1)
	var fired := [0]
	card.long_pressed.connect(func() -> void: fired[0] += 1)
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(20, 20)
	card._gui_input(touch)
	await get_tree().create_timer(GameCard.LONG_PRESS + 0.15).timeout
	check_eq(fired[0], 1, "меню открылось")
	check(card.consume_long_press(), "отпускание после меню — не запуск игры")
	check(not card.consume_long_press(), "а следующее нажатие — уже обычное")

	# Быстрое касание — обычное нажатие.
	card._gui_input(touch)
	var release := InputEventScreenTouch.new()
	release.pressed = false
	card._gui_input(release)
	await get_tree().create_timer(GameCard.LONG_PRESS + 0.15).timeout
	check_eq(fired[0], 1, "быстрое касание меню не открывает")
	card.queue_free()
