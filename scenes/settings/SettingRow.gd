class_name SettingRow
extends Button
## Одна строка на экране настроек: название слева, значение справа.
##
## Бывает четырёх видов (Kind):
##   CHOICE — выбор из списка: ‹ ЭЛТ-телевизор ›. Меняется стрелками ◀ ▶ или A.
##   TOGGLE — переключатель вкл/выкл.
##   ACTION — кнопка-действие («Добавить папку…»). Срабатывает по A.
##   INFO   — просто сведения, ничего не меняет.
##
## CHOICE и TOGGLE сами читают и записывают своё значение в Settings
## (раздел section, ключ key), поэтому экрану не нужно за ними следить.
##
## Тексты (title, description, надписи вариантов) можно передавать по-русски —
## строка сама переведёт их через tr().
##
## Свойства (kind, title, options…) нужно задать ДО add_child():
## строка собирает свои надписи в _ready(), а он срабатывает при добавлении.

enum Kind { CHOICE, TOGGLE, ACTION, INFO }

## Значение поменялось (для CHOICE и TOGGLE).
signal value_changed(value: Variant)

const WARN_COLOR := Color("e05252")

var kind := Kind.INFO
var title := ""
## Текст справа под предпросмотром. У CHOICE описание может быть своё
## для каждого варианта (третий элемент в options).
var description := ""
var section := ""        # раздел в Settings
var key := ""            # ключ в Settings
## Для CHOICE: варианты [значение, "Надпись"] или [значение, "Надпись", "Описание"].
var options: Array = []
## Для CHOICE: после последнего варианта перейти к первому (true)
## или остановиться (false — удобно для громкости).
var wrap := true
var info_text := ""      # для INFO и ACTION: текст справа
var warn := false        # покрасить текст справа в красный

var _value_label: Label
var _left_arrow: Label
var _right_arrow: Label
var _switch: SwitchIcon


func _ready() -> void:
	custom_minimum_size.y = 64
	focus_mode = Control.FOCUS_ALL
	_style()
	_build()
	refresh()
	focus_entered.connect(refresh)
	focus_exited.connect(refresh)
	# Мышь и геймпад работают одинаково: навели мышью — строка в фокусе.
	mouse_entered.connect(grab_focus)
	pressed.connect(_on_pressed)


## Описание для правой колонки (с учётом выбранного варианта).
func current_description() -> String:
	if kind == Kind.CHOICE:
		var option: Array = options[_option_index()]
		if option.size() > 2:
			return tr(option[2])
	return tr(description)


## Обновить надписи — например, после изменения info_text или warn.
func refresh() -> void:
	if _value_label == null:
		return  # ещё не собрана
	var focused := has_focus()

	match kind:
		Kind.CHOICE:
			_value_label.text = tr(options[_option_index()][1])
		Kind.TOGGLE:
			_switch.on = bool(Settings.get_value(section, key))
			_switch.queue_redraw()
		_:
			_value_label.text = tr(info_text)

	# Стрелки ‹ › видны только у выбранной строки-списка, как на макете.
	# У остальных строк значение стоит вплотную к правому краю.
	_left_arrow.visible = focused and kind == Kind.CHOICE
	_right_arrow.visible = focused and kind == Kind.CHOICE

	var color := UiTheme.TEXT if focused and kind == Kind.CHOICE else UiTheme.TEXT_DIM
	if warn:
		color = WARN_COLOR
	_value_label.add_theme_color_override("font_color", color)


## Сдвинуть значение: direction = −1 (влево), +1 (вправо), 0 (нажали A).
func change(direction: int) -> void:
	if kind == Kind.TOGGLE:
		var current := bool(Settings.get_value(section, key))
		# A переключает туда-обратно, ◀ выключает, ▶ включает.
		_store(not current if direction == 0 else direction > 0)
	elif kind == Kind.CHOICE:
		var step := direction if direction != 0 else 1
		var index := _option_index() + step
		if wrap:
			index = wrapi(index, 0, options.size())  # по кругу
		else:
			index = clampi(index, 0, options.size() - 1)  # упереться в край
		_store(options[index][0])


# _gui_input получает нажатия, пока строка в фокусе, — РАНЬШЕ, чем Godot
# успеет перевести фокус стрелкой на соседнюю кнопку.
# accept_event() говорит: «нажатие обработано, дальше не передавай».
func _gui_input(event: InputEvent) -> void:
	if kind != Kind.CHOICE and kind != Kind.TOGGLE:
		return
	# true — разрешить «повтор»: если держать стрелку, значение листается.
	if event.is_action_pressed("ui_left", true):
		change(-1)
		accept_event()
	elif event.is_action_pressed("ui_right", true):
		change(1)
		accept_event()


func _on_pressed() -> void:
	if kind == Kind.CHOICE or kind == Kind.TOGGLE:
		change(0)


func _store(value: Variant) -> void:
	if value == Settings.get_value(section, key):
		return  # уже такое
	Settings.set_value(section, key, value)
	refresh()
	value_changed.emit(value)


# Номер текущего варианта в списке options (0, если не нашли).
func _option_index() -> int:
	var value: Variant = Settings.get_value(section, key)
	for i in options.size():
		if options[i][0] == value:
			return i
	return 0


# --- Внешний вид ------------------------------------------------------------

func _style() -> void:
	add_theme_stylebox_override("normal", _box(UiTheme.CARD))
	add_theme_stylebox_override("hover", _box(UiTheme.CARD_HOVER))
	add_theme_stylebox_override("pressed", _box(UiTheme.CARD_HOVER))
	# Рамка фокуса (бирюзовая со свечением) приходит из темы UiTheme.


func _box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(14)
	return box


# Собираем содержимое: [Название ............ ‹ Значение › / переключатель]
func _build() -> void:
	# Button не умеет раскладывать детей сам, поэтому кладём внутрь
	# MarginContainer на весь размер кнопки, а в него — строку HBox.
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var title_label := Label.new()
	title_label.text = tr(title)
	title_label.theme_type_variation = &"CardTitleLabel"
	title_label.add_theme_font_size_override("font_size", 19)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # занять всё свободное место
	title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # длинное — с «…»
	row.add_child(title_label)

	_left_arrow = _arrow("‹")
	row.add_child(_left_arrow)

	_value_label = Label.new()
	_value_label.add_theme_font_size_override("font_size", 18)
	_value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_value_label.visible = kind != Kind.TOGGLE
	row.add_child(_value_label)

	_right_arrow = _arrow("›")
	row.add_child(_right_arrow)

	_switch = SwitchIcon.new()
	_switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_switch.visible = kind == Kind.TOGGLE
	row.add_child(_switch)


func _arrow(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.visible = false  # покажем в refresh(), когда строка в фокусе
	return label


# Переключатель-«таблетка»: включён — бирюзовый, кружок справа;
# выключен — серый, кружок слева.
class SwitchIcon extends Control:
	var on := false

	func _init() -> void:
		custom_minimum_size = Vector2(64, 34)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var pill := StyleBoxFlat.new()
		pill.bg_color = UiTheme.ACCENT if on else Color("2a3344")
		pill.set_corner_radius_all(int(size.y / 2))
		draw_style_box(pill, Rect2(Vector2.ZERO, size))
		var radius := size.y / 2.0 - 5.0
		var x := size.x - size.y / 2.0 if on else size.y / 2.0
		draw_circle(Vector2(x, size.y / 2.0), radius, UiTheme.BG if on else UiTheme.TEXT_DIM)
