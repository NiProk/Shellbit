class_name DropdownList
extends Control
## Выпадающий список: появляется под кнопкой, из него выбирают один вариант.
##
## Работает и с геймпадом, и с мышью:
##   ▲▼ — выбрать вариант, A — подтвердить, B — закрыть без изменений.
##   Мышью: клик по варианту — выбрать, клик мимо списка — закрыть.
##
## Использование:
##   var dropdown := DropdownList.new()
##   add_child(dropdown)
##   dropdown.chosen.connect(func(value): ...)     # выбрали вариант
##   dropdown.closed.connect(button.grab_focus)    # закрыли (в любом случае)
##   dropdown.open([["ru", "Русский"], ["en", "English"]], "ru", button)
##
## Почему не готовый OptionButton из Godot: его список — отдельное окно
## со своим оформлением, и с геймпадом им неудобно пользоваться.
## Свой список выглядит как остальной интерфейс Shellbit.

## Выбрали вариант (value — первый элемент пары [значение, надпись]).
signal chosen(value: Variant)
## Список закрылся — после выбора или без него.
signal closed

const ButtonHintsScene := preload("res://scenes/components/ButtonHints.tscn")
const ROW_HEIGHT := 50
const MARGIN := 10        # отступ внутри панели
const HINTS_HEIGHT := 56  # строка подсказок внизу экрана

var _panel: PanelContainer
var _scroll: ScrollContainer
var _list: VBoxContainer


func _ready() -> void:
	visible = false
	# Слой на весь экран ловит мышь: клик мимо списка закрывает его,
	# а кнопки под списком не нажимаются. z_index — поверх карточек и рамок.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 10

	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BG, 0.45)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(_on_dim_input)

	_panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = UiTheme.PANEL
	box.set_corner_radius_all(16)
	box.set_content_margin_all(MARGIN)
	box.border_color = Color(UiTheme.ACCENT, 0.35)
	box.set_border_width_all(1)
	box.shadow_color = Color(0, 0, 0, 0.55)
	box.shadow_size = 22
	_panel.add_theme_stylebox_override("panel", box)
	add_child(_panel)

	# Если вариантов много и они не влезают по высоте — список прокручивается.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true  # выбранный вариант всегда виден
	_panel.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	_scroll.add_child(_list)

	var hints := ButtonHintsScene.instantiate()
	add_child(hints)
	hints.set_hints([["accept", "Выбрать"], ["cancel", "Назад"]])


## Открыть список. items — пары [значение, надпись], current — что выбрано
## сейчас (отмечено галочкой), anchor — кнопка, под которой появиться.
func open(items: Array, current: Variant, anchor: Control) -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	var focus_button: Button = null
	for item: Array in items:
		var button := _item_button(item[1], item[0] == current)
		button.pressed.connect(_choose.bind(item[0]))
		_list.add_child(button)
		if item[0] == current:
			focus_button = button

	_link_focus()
	_place(anchor, items.size())
	visible = true
	if focus_button == null:
		focus_button = _list.get_child(0)
	focus_button.grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _choose(value: Variant) -> void:
	visible = false
	chosen.emit(value)
	closed.emit()


# Одна строка списка. Выбранный сейчас вариант отмечен «✓» и цветом.
func _item_button(text: String, selected: bool) -> Button:
	var button := Button.new()
	button.text = ("✓  " if selected else "     ") + text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = ROW_HEIGHT
	# Надписи уже готовы (названия языков пишутся на самих языках).
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0) if state == "normal" else UiTheme.CARD_HOVER
		box.set_corner_radius_all(10)
		box.content_margin_left = 16
		box.content_margin_right = 16
		button.add_theme_stylebox_override(state, box)
	# Рамка фокуса — поуже, чем у больших кнопок: список плотный.
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(3)
	focus.border_color = UiTheme.ACCENT
	focus.set_corner_radius_all(10)
	button.add_theme_stylebox_override("focus", focus)
	var color := UiTheme.ACCENT if selected else UiTheme.TEXT
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		button.add_theme_color_override(state, color)
	button.mouse_entered.connect(button.grab_focus)
	return button


# Фокус ходит по кругу: с последнего варианта вниз — на первый.
# Влево и вправо — никуда, чтобы не «выпасть» из списка.
func _link_focus() -> void:
	var buttons := _list.get_children()
	for i in buttons.size():
		var button: Button = buttons[i]
		button.focus_neighbor_top = button.get_path_to(buttons[i - 1])  # [-1] — последний
		button.focus_neighbor_bottom = button.get_path_to(buttons[(i + 1) % buttons.size()])
		button.focus_neighbor_left = button.get_path_to(button)
		button.focus_neighbor_right = button.get_path_to(button)


# Поставить панель под кнопкой anchor. Если снизу не хватает места —
# поднять её, а если список выше экрана — оставить прокрутку.
func _place(anchor: Control, count: int) -> void:
	var screen := get_viewport_rect().size
	var area := anchor.get_global_rect()
	# Координаты нашего слоя совпадают с экранными: он на весь экран.
	var width := maxf(area.size.x, 320.0)
	var content := count * ROW_HEIGHT + (count - 1) * 4
	var max_height := screen.y - HINTS_HEIGHT - 32
	var height := minf(content + MARGIN * 2, max_height)
	var top := area.end.y + 8
	if top + height > screen.y - HINTS_HEIGHT - 16:
		top = maxf(16, screen.y - HINTS_HEIGHT - 16 - height)
	_scroll.custom_minimum_size = Vector2(width - MARGIN * 2, height - MARGIN * 2)
	# Кнопка у правого края экрана (как «Жанр» в библиотеке) — список
	# не помещается справа. Тогда сдвигаем его влево, чтобы правый край
	# списка совпал с правым краем кнопки (но не дальше левого края экрана).
	var left := area.position.x
	if left + width > screen.x - 16:
		left = maxf(16, area.end.x - width)
	_panel.position = Vector2(left, top)
	_panel.size = Vector2(width, height)


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		close()


# B (Esc) закрывает список. Ловим в _input — раньше экрана под списком,
# иначе тот принял бы B за «Назад».
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
