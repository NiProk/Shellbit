class_name VirtualGrid
extends Control
## Сетка карточек игр для БОЛЬШИХ коллекций — «виртуальная».
##
## Обычный GridContainer создаёт по карточке на каждую игру. На 2000 игр
## это 2000 карточек (и 14 000 узлов внутри них): экран открывается
## секунды, а прокрутка тормозит, потому что Godot двигает их все.
##
## Здесь карточек столько, сколько ВИДНО на экране (+ ряд сверху и снизу
## про запас) — около 30. Когда список прокручивают, ушедшие за край
## карточки не удаляются, а переезжают на новое место и показывают
## другую игру. Как в барабане игрового автомата: барабан крутится,
## а картинок на нём ограниченное число.
##
## Сама сетка просто очень высокая (столько рядов, сколько игр), чтобы
## ScrollContainer показал правильную полосу прокрутки.
##
## Использование:
##   %Grid.card_pressed.connect(...)    # A на карточке
##   %Grid.card_focused.connect(...)    # фокус перешёл на игру
##   %Grid.set_items(groups)            # какие игры показывать
##   %Grid.select(index)                # выделить игру номер index

## Нажали карточку (A или мышь).
signal card_pressed(group: Dictionary)
## Фокус перешёл на игру — например, чтобы показать её данные справа.
signal card_focused(group: Dictionary)

const GameCardScene := preload("res://scenes/components/GameCard.tscn")
const CARD_SIZE := Vector2(168, 224)  # размер вертикальной карточки (GameCard.Style.COVER)
const GAP := 18                       # расстояние между карточками
const COLUMNS := 4
const SPARE_ROWS := 1                 # рядов про запас сверху и снизу

var items: Array = []        # игры (группы), которые показываем, по порядку
var selected := -1           # номер выделенной игры в items (-1 — нет)

var _scroll: ScrollContainer  # окно, через которое видно сетку
var _cards: Array[GameCard] = []
var _first_shown := -1       # номер игры в первой карточке барабана


func _ready() -> void:
	# Сетку прокручивает ScrollContainer — ищем его среди родителей.
	var parent := get_parent()
	while parent != null and not parent is ScrollContainer:
		parent = parent.get_parent()
	_scroll = parent
	# Прокрутили (колесом, полосой или из кода) — переставить карточки.
	_scroll.get_v_scroll_bar().value_changed.connect(func(_value: float) -> void: _layout())
	_scroll.resized.connect(_layout)
	custom_minimum_size.x = COLUMNS * (CARD_SIZE.x + GAP) - GAP


## Показать игры. Выделение сбрасывается.
func set_items(new_items: Array) -> void:
	items = new_items
	selected = -1
	var rows := ceili(items.size() / float(COLUMNS))
	custom_minimum_size.y = maxf(0.0, rows * (CARD_SIZE.y + GAP) - GAP)
	_first_shown = -1  # всё перерисовать
	_layout()


## Карточка, которая сейчас показывает игру index (null — она за краем экрана).
func card_for(index: int) -> GameCard:
	for card in _cards:
		if card.visible and card.get_meta("index") == index:
			return card
	return null


## Выделить игру index: прокрутить к ней и поставить на неё фокус.
## center = true — поставить посередине экрана (при возвращении к игре),
## иначе — прокрутить ровно настолько, чтобы её стало видно.
func select(index: int, center := false) -> void:
	if index < 0 or index >= items.size():
		return
	selected = index
	var top := _row_top(index / COLUMNS) + _offset_in_scroll()
	var bottom := top + CARD_SIZE.y
	var view_top := _scroll.scroll_vertical
	var view_height := _scroll.size.y
	var margin := GAP + 8  # запас, чтобы рамка выделения не обрезалась
	if center:
		_scroll.scroll_vertical = int(top - (view_height - CARD_SIZE.y) / 2.0)
	elif top - margin < view_top:
		_scroll.scroll_vertical = int(top - margin)
	elif bottom + margin > view_top + view_height:
		_scroll.scroll_vertical = int(bottom + margin - view_height)
	_layout()
	var card := card_for(index)
	if card:
		card.grab_focus()


## Обновить надписи карточек (например, после добавления в избранное).
func refresh_cards() -> void:
	for card in _cards:
		if card.visible:
			card.refresh()


# Где сетка начинается внутри прокручиваемой области (отступы Pad сверху).
func _offset_in_scroll() -> float:
	var content: Control = _scroll.get_child(0)
	return global_position.y - content.global_position.y


func _row_top(row: int) -> float:
	return row * (CARD_SIZE.y + GAP)


## Главное: какие игры сейчас видны, и какие карточки их покажут.
func _layout() -> void:
	if _scroll == null:
		return
	var row_height := CARD_SIZE.y + GAP
	var visible_rows := ceili(_scroll.size.y / row_height) + 1 + SPARE_ROWS * 2
	if _cards.size() < visible_rows * COLUMNS:
		# Окно стало выше (или это первый раз) — нужны ещё карточки.
		_ensure_cards(visible_rows * COLUMNS)
		_first_shown = -1  # и всё расставить заново

	# Первый видимый ряд: сколько рядов «уехало» вверх за край окна.
	var scrolled := _scroll.scroll_vertical - _offset_in_scroll()
	var first_row := maxi(0, floori(scrolled / row_height) - SPARE_ROWS)
	var first := first_row * COLUMNS
	if first == _first_shown:
		return  # видны те же ряды — ничего не меняем
	_first_shown = first

	for i in _cards.size():
		var card := _cards[i]
		var index := first + i
		if index >= items.size():
			card.visible = false
			card.set_meta("index", -1)
			continue
		card.visible = true
		card.position = Vector2((index % COLUMNS) * (CARD_SIZE.x + GAP), _row_top(index / COLUMNS))
		if card.get_meta("index", -1) != index:
			card.set_meta("index", index)
			card.setup(items[index], GameCard.Style.COVER)

	# Барабан повернулся, и фокус оказался на карточке, которая теперь
	# показывает другую игру? Переносим фокус туда, где выделенная игра.
	var focused := get_viewport().gui_get_focus_owner()
	if focused is GameCard and focused.get_parent() == self and focused.get_meta("index") != selected:
		var card := card_for(selected)
		if card:
			card.grab_focus()
		else:
			focused.release_focus()  # выделенная игра ушла за край — фокуса нет


# Создать недостающие карточки барабана (лишние — спрятать).
func _ensure_cards(count: int) -> void:
	while _cards.size() < count:
		var card: GameCard = GameCardScene.instantiate()
		add_child(card)
		# В сцене у карточки минимальный размер широкой (300×190) — размер
		# не может быть меньше минимального, поэтому сначала меняем минимум.
		card.custom_minimum_size = CARD_SIZE
		card.size = CARD_SIZE
		card.set_meta("index", -1)
		card.pressed.connect(func() -> void: card_pressed.emit(items[card.get_meta("index")]))
		card.focus_entered.connect(_on_card_focused.bind(card))
		card.gui_input.connect(_on_card_input.bind(card))
		_cards.append(card)


func _on_card_focused(card: GameCard) -> void:
	var index: int = card.get_meta("index")
	if index >= 0:
		selected = index
		card_focused.emit(items[index])


## Стрелки и стик на карточке. Сами решаем, какая игра следующая:
## соседней карточки за краем экрана может не быть — она ещё не создана.
func _on_card_input(event: InputEvent, card: GameCard) -> void:
	var index: int = card.get_meta("index")
	var target := -1
	if event.is_action_pressed("ui_right", true) and index % COLUMNS < COLUMNS - 1:
		target = index + 1
	elif event.is_action_pressed("ui_left", true) and index % COLUMNS > 0:
		target = index - 1
	elif event.is_action_pressed("ui_down", true):
		# В последнем неполном ряду — на последнюю игру.
		if index / COLUMNS < (items.size() - 1) / COLUMNS:
			target = mini(index + COLUMNS, items.size() - 1)
		else:
			accept_event()  # ниже ничего нет — остаёмся на месте
			return
	elif event.is_action_pressed("ui_up", true) and index >= COLUMNS:
		target = index - COLUMNS
	# Вверх из первого ряда не перехватываем: Godot сам уведёт фокус
	# на поиск и сортировку над сеткой.
	if target >= 0 and target < items.size():
		accept_event()  # «нажатие обработано» — Godot не будет искать соседа сам
		select(target)
