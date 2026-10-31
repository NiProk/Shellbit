class_name ScreenKeyboard
extends Control
## Экранная клавиатура для геймпада.
##
## Печатает в указанное поле LineEdit. Текст в поле меняется сразу,
## поэтому, например, поиск фильтрует карточки прямо по ходу набора.
##
## Управление (как на игровых приставках):
##   A (Enter)      — нажать клавишу под курсором
##   B (Esc)        — стереть букву; если поле пустое — закрыть клавиатуру
##   X              — пробел
##   Y              — сменить раскладку: латиница ↔ кириллица
##   Start (F1)     — «Найти»: закрыть клавиатуру и перейти к результатам
## Буквы с настоящей клавиатуры тоже печатаются.
##
## Использование:
##   var keyboard := ScreenKeyboard.new()
##   add_child(keyboard)
##   keyboard.open(%Search)
##   keyboard.closed.connect(…)   # куда поставить фокус после закрытия

## Клавиатуру закрыли (кнопкой «Найти», Start или B на пустом поле).
signal closed

const ButtonHintsScene := preload("res://scenes/components/ButtonHints.tscn")

## Раскладки: строки клавиш сверху вниз. Последний ряд (пробел, стереть…)
## добавляется отдельно в _build().
const LAYOUTS := {
	"latin": ["1234567890", "QWERTYUIOP", "ASDFGHJKL'", "ZXCVBNM-.&"],
	"cyrillic": ["1234567890", "ЙЦУКЕНГШЩЗХ", "ФЫВАПРОЛДЖЭ", "ЯЧСМИТЬБЮЁЪ"],
	# Для кодов читов: только латиница, цифры и знаки из кодов —
	# «7E0DBE:09» (Action Replay), «SXIOPO+AEIOZA» (несколько кодов сразу).
	"code": ["1234567890", "QWERTYUIOP", "ASDFGHJKL:", "ZXCVBNM+-."],
}
const KEY_SIZE := Vector2(56, 50)

## Надпись на главной клавише. Для поиска — «Найти», для имени — «Сохранить».
## (Пишем по-русски, переводит клавиатура сама.)
var done_text := "Найти"
## Режим «код чита»: раскладка "code", буквы — ЗАГЛАВНЫЕ (так коды и пишут),
## кириллицы нет. Обычный режим — false.
var code_mode := false

## Какая раскладка была в прошлый раз. static — общая для всех клавиатур,
## поэтому выбор сохраняется, пока программа запущена.
static var _layout := "latin"

var _target: LineEdit
var _hints: Control
var _rows: VBoxContainer


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Слой на весь экран ловит мышь: пока клавиатура открыта, мышь не должна
	# выделять карточки под ней.
	mouse_filter = Control.MOUSE_FILTER_STOP
	# z_index — «этаж» рисования. Он действует на весь экран, а не только
	# среди соседей: выделенная карточка поднимается на этаж 1 и иначе
	# оказалась бы ПОВЕРХ клавиатуры. Ставим клавиатуру заметно выше.
	z_index = 10

	# Панель внизу по центру, над строкой подсказок (её высота 56).
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = UiTheme.PANEL
	box.set_corner_radius_all(18)
	box.set_content_margin_all(20)
	box.shadow_color = Color(0, 0, 0, 0.5)
	box.shadow_size = 24
	panel.add_theme_stylebox_override("panel", box)
	add_child(panel)
	# Привязка: середина нижнего края экрана. set_anchors_preset() пересчитывает
	# отступы (offset_*) так, чтобы панель осталась на старом месте, — поэтому
	# сразу задаём все четыре отступа сами.
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = 0
	panel.offset_right = 0
	panel.offset_top = -68
	panel.offset_bottom = -68
	# Размер панели — по содержимому. grow говорит, в какую сторону
	# ей расти: в ширину — в обе стороны от центра, в высоту — вверх.
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	panel.add_child(_rows)

	# Свои подсказки внизу — поверх подсказок экрана.
	_hints = ButtonHintsScene.instantiate()
	add_child(_hints)


## Показать клавиатуру и печатать в поле line_edit.
func open(line_edit: LineEdit) -> void:
	_target = line_edit
	# Подсказки — здесь, а не в _ready: надпись главной клавиши (done_text)
	# могли поменять уже после создания клавиатуры.
	var hints := [["accept", "Ввести"], ["cancel", "Стереть"], ["details", "Пробел"]]
	if not code_mode:
		hints.append(["favorite", "Раскладка"])  # у кодов раскладка одна
	hints.append(["menu", done_text])
	_hints.set_hints(hints)
	_build()
	visible = true
	_focus_key(1, 0)  # первая буква (ряд 0 — цифры)


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


# =====================================================================
# Клавиши
# =====================================================================

# Собрать клавиши текущей раскладки.
func _build() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()

	for keys: String in LAYOUTS["code" if code_mode else _layout]:
		var row := _new_row()
		for letter in keys:  # строку можно перебирать по буквам
			row.add_child(_key(letter, _type.bind(letter)))

	# Нижний ряд: раскладка, пробел, стереть, найти.
	var bottom := _new_row()
	if not code_mode:
		bottom.add_child(_key("АБВ" if _layout == "latin" else "ABC", _switch_layout, 96))
	bottom.add_child(_key(tr("Пробел"), _type.bind(" "), 280))
	bottom.add_child(_key("⌫", _backspace, 96))
	var find := _key(tr(done_text), _finish, 140)
	_paint(find, UiTheme.ACCENT, UiTheme.BG)  # главная кнопка — акцентная
	bottom.add_child(find)

	# Соседей можно расставить, только когда Godot разложит клавиши
	# по местам (нужны их координаты), — поэтому ждём один кадр.
	await get_tree().process_frame
	_link_keys()


## Явно прописать каждой клавише соседей для стика и стрелок.
## Иначе Godot ищет «ближайшую кнопку в ту сторону» по всему экрану
## и уводит фокус на карточки игр под клавиатурой.
## Переходы — по кругу: вправо с последней клавиши ряда — на первую,
## вниз с нижнего ряда — на верхний.
func _link_keys() -> void:
	var rows: Array = []
	for row in _rows.get_children():
		if not row.is_queued_for_deletion():
			rows.append(row.get_children())
	for r in rows.size():
		var keys: Array = rows[r]
		var above: Array = rows[(r - 1 + rows.size()) % rows.size()]
		var below: Array = rows[(r + 1) % rows.size()]
		for i in keys.size():
			var key: Button = keys[i]
			key.focus_neighbor_left = key.get_path_to(keys[(i - 1 + keys.size()) % keys.size()])
			key.focus_neighbor_right = key.get_path_to(keys[(i + 1) % keys.size()])
			key.focus_neighbor_top = key.get_path_to(_nearest(above, key))
			key.focus_neighbor_bottom = key.get_path_to(_nearest(below, key))
			# Tab / Shift+Tab — тоже только по клавишам.
			key.focus_next = key.focus_neighbor_right
			key.focus_previous = key.focus_neighbor_left


# Клавиша из ряда keys, которая ближе всего по горизонтали к клавише from.
# Так «вверх» с широкого «Пробела» попадает на букву над его серединой.
func _nearest(keys: Array, from: Control) -> Control:
	var x := from.global_position.x + from.size.x / 2.0
	var best: Control = keys[0]
	for key: Control in keys:
		var key_x := key.global_position.x + key.size.x / 2.0
		if absf(key_x - x) < absf(best.global_position.x + best.size.x / 2.0 - x):
			best = key
	return best


func _new_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER  # ряды разной длины — по центру
	row.add_theme_constant_override("separation", 8)
	_rows.add_child(row)
	return row


# Одна клавиша. width — ширина для широких клавиш (пробел и т.п.).
func _key(text: String, action: Callable, width := 0) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(maxf(width, KEY_SIZE.x), KEY_SIZE.y)
	button.add_theme_font_size_override("font_size", 22)
	# Текст клавиш уже готов (буквы или переведённые надписи).
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_paint(button, UiTheme.CARD, UiTheme.TEXT)
	button.pressed.connect(action)
	button.mouse_entered.connect(button.grab_focus)
	return button


func _paint(button: Button, color: Color, text_color: Color) -> void:
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = color if state == "normal" else color.lightened(0.12)
		box.set_corner_radius_all(10)
		button.add_theme_stylebox_override(state, box)
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		button.add_theme_color_override(state, text_color)


# Поставить фокус на клавишу (ряд, номер в ряду). Если такой нет — на последнюю в ряду.
func _focus_key(row_index: int, key_index: int) -> void:
	var row: HBoxContainer = _rows.get_child(clampi(row_index, 0, _rows.get_child_count() - 1))
	row.get_child(clampi(key_index, 0, row.get_child_count() - 1)).grab_focus()


# =====================================================================
# Ввод текста
# =====================================================================

func _type(letter: String) -> void:
	# Для поиска регистр не важен, а строчные буквы читать приятнее.
	# Коды читов, наоборот, всегда пишут заглавными.
	_set_text(_target.text + (letter.to_upper() if code_mode else letter.to_lower()))


func _backspace() -> void:
	if _target.text.is_empty():
		close()  # стирать нечего — B закрывает клавиатуру
	else:
		_set_text(_target.text.left(-1))  # left(-1) — всё, кроме последнего символа


# Записать текст в поле. Когда текст меняют из кода, LineEdit НЕ сообщает
# сигналом text_changed (он только для набора руками), поэтому сообщаем сами —
# на этот сигнал подписан, например, фильтр поиска.
func _set_text(text: String) -> void:
	_target.text = text
	_target.caret_column = text.length()
	_target.text_changed.emit(text)


func _switch_layout() -> void:
	if code_mode:
		return
	# Запоминаем, где стоял фокус, чтобы после смены раскладки остаться там же.
	var focused := get_viewport().gui_get_focus_owner()
	var row_index := 0
	var key_index := 0
	if focused and focused.get_parent() and focused.get_parent().get_parent() == _rows:
		row_index = focused.get_parent().get_index()
		key_index = focused.get_index()
	_layout = "cyrillic" if _layout == "latin" else "latin"
	_build()
	_focus_key.call_deferred(row_index, key_index)  # новые клавиши появятся в конце кадра


func _finish() -> void:
	close()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	# Буквы и цифры с настоящей клавиатуры тоже печатаем.
	if event is InputEventKey and event.pressed and event.unicode >= 32:
		_type(char(event.unicode))
	elif event is InputEventKey and event.pressed and event.keycode == KEY_BACKSPACE:
		_backspace()
	elif event.is_action_pressed("ui_cancel"):
		_backspace()
	elif event.is_action_pressed("details"):
		_type(" ")
	elif event.is_action_pressed("favorite"):
		_switch_layout()
	elif event.is_action_pressed("menu"):
		_finish()

	# Пока клавиатура открыта, кнопки экрана под ней не должны срабатывать.
	if event.is_pressed():
		get_viewport().set_input_as_handled()
