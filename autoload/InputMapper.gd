extends Node
## InputMapper — всё, что связано с геймпадами и клавиатурой.
##
## 1. Добавляет в Input Map наши действия (favorite, details, page_left...).
##    Встроенные ui_accept, ui_cancel и стрелки уже есть в Godot,
##    но к A и B геймпада их приходится привязывать самим (см. _ready).
## 2. Следит, чем человек сейчас управляет: Xbox, PlayStation или клавиатура,
##    чтобы подсказки внизу экрана показывали правильные значки.
## 3. Переводит кнопки геймпада и клавиатуры в RetroPad для эмулятора.
## 4. Помнит раскладку кнопок для каждой приставки (data/pads.json
##    и настройки человека) — см. раздел «Раскладка по приставкам».

## Сигнал: сменился тип управления ("xbox", "playstation", "keyboard").
signal style_changed(style: String)

var style := "keyboard"


func _ready() -> void:
	# Встроенные ui_accept и ui_cancel в Godot привязаны ТОЛЬКО к клавиатуре
	# (Enter/Space и Esc). Кнопки геймпада добавляем сами, иначе A и B
	# в меню не работают. А вот стрелки (ui_up и т.д.) Godot уже связал
	# с крестовиной и стиком — их трогать не нужно.
	_add_joy_button(&"ui_accept", JOY_BUTTON_A)
	_add_joy_button(&"ui_cancel", JOY_BUTTON_B)

	_add_action(&"details", JOY_BUTTON_X, KEY_TAB)
	_add_action(&"favorite", JOY_BUTTON_Y, KEY_F)
	_add_action(&"page_left", JOY_BUTTON_LEFT_SHOULDER, KEY_Q)
	_add_action(&"page_right", JOY_BUTTON_RIGHT_SHOULDER, KEY_E)
	_add_action(&"menu", JOY_BUTTON_START, KEY_F1)
	# Меню паузы в игре: нажатие правого стика (R3) или Esc.
	# В играх NES, SNES и Sega правый стик не нужен, поэтому кнопка свободна.
	# Ещё работает Select + Start — см. Player.gd.
	# (Кнопку Guide с логотипом Xbox Windows забирает себе для Game Bar,
	# а через XInput вообще не передаёт программам — на неё надежды нет.)
	_add_action(&"game_menu", JOY_BUTTON_RIGHT_STICK, KEY_ESCAPE)
	_add_joy_button(&"game_menu", JOY_BUTTON_GUIDE)
	# Скриншот: F12 или кнопка Share («Поделиться»). В Godot она называется
	# JOY_BUTTON_MISC1: это Share на Xbox Series, Create на DualSense (PS5),
	# Capture на Switch Pro. У старых геймпадов её нет — для них есть пункт
	# «Скриншот» в меню паузы.
	_add_action(&"screenshot", JOY_BUTTON_MISC1, KEY_F12)
	# Полный экран ↔ окно: F11 или Alt+Enter, как во многих играх и плеерах.
	# Ловит это нажатие Settings (см. Settings._input).
	InputMap.add_action(&"fullscreen")
	var f11 := InputEventKey.new()
	f11.physical_keycode = KEY_F11
	InputMap.action_add_event(&"fullscreen", f11)
	var alt_enter := InputEventKey.new()
	alt_enter.physical_keycode = KEY_ENTER
	alt_enter.alt_pressed = true
	InputMap.action_add_event(&"fullscreen", alt_enter)

	_load_pads()
	# Поменяли раскладку в настройках — забываем готовые таблицы,
	# get_retropad_mask() соберёт их заново.
	Settings.changed.connect(func(section: String, _key: String) -> void:
		if section == "pads":
			_tables.clear())

	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	if not Input.get_connected_joypads().is_empty():
		_set_style(_style_for_pad(Input.get_connected_joypads()[0]))


# Создать действие и привязать к нему кнопку геймпада и клавишу.
func _add_action(action: StringName, joy_button: JoyButton, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

	var pad_event := InputEventJoypadButton.new()
	pad_event.button_index = joy_button
	InputMap.action_add_event(action, pad_event)

	var key_event := InputEventKey.new()
	key_event.physical_keycode = key
	InputMap.action_add_event(action, key_event)


# Добавить кнопку геймпада к уже существующему действию.
func _add_joy_button(action: StringName, joy_button: JoyButton) -> void:
	var pad_event := InputEventJoypadButton.new()
	pad_event.button_index = joy_button
	InputMap.action_add_event(action, pad_event)


# _input получает ВСЕ нажатия раньше всех остальных.
# Мы ничего не «съедаем», только смотрим, откуда пришло нажатие.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		_set_style("keyboard")
	elif event is InputEventJoypadButton and event.pressed:
		_set_style(_style_for_pad(event.device))


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		print("Геймпад подключён: ", Input.get_joy_name(device))
		_set_style(_style_for_pad(device))
	else:
		print("Геймпад отключён: ", device)


func _style_for_pad(device: int) -> String:
	var pad_name := Input.get_joy_name(device).to_lower()
	for word in ["playstation", "dualsense", "dualshock", "ps3", "ps4", "ps5"]:
		if pad_name.contains(word):
			return "playstation"
	return "xbox"


func _set_style(new_style: String) -> void:
	if new_style != style:
		style = new_style
		style_changed.emit(style)


# =====================================================================
# Кнопки для эмулятора (RetroPad)
# =====================================================================
#
# Ядро libretro понимает один «стандартный» геймпад — RetroPad.
# Каждая его кнопка — это номер бита (0..15). Мы собираем все нажатые
# кнопки в одно число-маску: если нажата кнопка №8 (A), то бит 8 = 1.
#
# Номера кнопок RetroPad (такие же, как RetroCore.BUTTON_*):
const PAD_B := 0
const PAD_Y := 1
const PAD_SELECT := 2
const PAD_START := 3
const PAD_UP := 4
const PAD_DOWN := 5
const PAD_LEFT := 6
const PAD_RIGHT := 7
const PAD_A := 8
const PAD_X := 9
const PAD_L := 10
const PAD_R := 11
const PAD_L2 := 12
const PAD_R2 := 13
const PAD_L3 := 14
const PAD_R3 := 15

# Кнопка реального геймпада → кнопка RetroPad. Общая раскладка для
# приставок, которых нет в data/pads.json. Крестовину и стик
# get_retropad_mask() проверяет отдельно.
# Раскладка «по положению»: нижняя кнопка Xbox (A) = нижняя кнопка SNES (B).
const JOY_TO_PAD := {
	JOY_BUTTON_A: PAD_B,
	JOY_BUTTON_B: PAD_A,
	JOY_BUTTON_X: PAD_Y,
	JOY_BUTTON_Y: PAD_X,
	JOY_BUTTON_BACK: PAD_SELECT,
	JOY_BUTTON_START: PAD_START,
	JOY_BUTTON_LEFT_SHOULDER: PAD_L,
	JOY_BUTTON_RIGHT_SHOULDER: PAD_R,
	JOY_BUTTON_LEFT_STICK: PAD_L3,
	# Правый стик (R3) не передаём в игру: это кнопка меню паузы.
}

# Клавиатура (только для игрока 1).
const KEY_TO_PAD := {
	KEY_UP: PAD_UP,
	KEY_DOWN: PAD_DOWN,
	KEY_LEFT: PAD_LEFT,
	KEY_RIGHT: PAD_RIGHT,
	KEY_Z: PAD_B,
	KEY_X: PAD_A,
	KEY_A: PAD_Y,
	KEY_S: PAD_X,
	KEY_Q: PAD_L,
	KEY_W: PAD_R,
	KEY_ENTER: PAD_START,
	KEY_SHIFT: PAD_SELECT,
}

const STICK_DEADZONE := 0.5
## Мёртвая зона стика, когда он передаётся в игру как стик: геймпад
## в покое редко показывает ровно 0 (0,03…0,08), и без этого персонаж
## потихоньку «ползёт» сам. Всё, что меньше 12% хода, считаем нулём.
const ANALOG_DEADZONE := 0.12

const ARROW_KEYS := [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]


## Маска нажатых кнопок для игрока port (0 = первый игрок).
## system_id — приставка, чтобы взять её раскладку кнопок геймпада.
## Без него (или для приставки без описания в pads.json) действует
## общая раскладка «по положению» — таблица JOY_TO_PAD.
func get_retropad_mask(port: int, system_id := "") -> int:
	var mask := 0

	# У Nintendo 64 крестовина и стик — разные вещи. Там левый стик
	# (и стрелки на клавиатуре) управляют стиком игры, а не крестовиной.
	var stick_is_dpad := stick_moves_dpad(system_id)

	if port == 0:
		for key: Key in KEY_TO_PAD:
			if not stick_is_dpad and key in ARROW_KEYS:
				continue  # стрелки уходят в стик — см. get_analog()
			if Input.is_physical_key_pressed(key):
				mask |= 1 << KEY_TO_PAD[key]

	var pads_list := Input.get_connected_joypads()
	if port < pads_list.size():
		var device: int = pads_list[port]
		if pads.has(system_id):
			# Back + курок — перемотка или ускорение (см. combo_trigger ниже).
			# Пока это сочетание зажато, ни Back, ни курки в игру не уходят.
			var combo := is_combo_held(device, system_id)
			# Таблица этой приставки: пары [кнопка геймпада, бит RetroPad].
			for pair: Array in _table(system_id):
				if combo and pair[0] in [COMBO_MODIFIER, "lt", "rt"]:
					continue
				if is_physical_pressed(device, pair[0]):
					mask |= 1 << pair[1]
		else:
			for button: JoyButton in JOY_TO_PAD:
				if Input.is_joy_button_pressed(device, button):
					mask |= 1 << JOY_TO_PAD[button]
			# Курки — это оси (от 0 до 1), а не кнопки.
			if Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT) > STICK_DEADZONE: mask |= 1 << PAD_L2
			if Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > STICK_DEADZONE: mask |= 1 << PAD_R2

		# Крестовина — всегда крестовина (её не переназначаем).
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP): mask |= 1 << PAD_UP
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN): mask |= 1 << PAD_DOWN
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT): mask |= 1 << PAD_LEFT
		if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT): mask |= 1 << PAD_RIGHT

		# Левый стик работает как крестовина (кроме Nintendo 64).
		if not stick_is_dpad:
			return mask
		var x := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
		var y := Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
		if x < -STICK_DEADZONE: mask |= 1 << PAD_LEFT
		if x > STICK_DEADZONE: mask |= 1 << PAD_RIGHT
		if y < -STICK_DEADZONE: mask |= 1 << PAD_UP
		if y > STICK_DEADZONE: mask |= 1 << PAD_DOWN

	return mask


# =====================================================================
# Стики
# =====================================================================
#
# У NES или Mega Drive стиков нет — там левый стик просто нажимает
# крестовину (это делает get_retropad_mask выше).
# У PlayStation и Nintendo 64 стики есть, и игре важно, НАСКОЛЬКО
# стик наклонён: чуть-чуть — Марио идёт, до упора — бежит.
# Такие приставки отмечены в data/systems.json строкой "analog": true.


## Передаёт ли Shellbit стики в игры этой приставки.
func has_analog(system_id: String) -> bool:
	return CoreManager.get_system(system_id).get("analog", false)


## Нажимает ли левый стик крестовину. Да — везде, кроме приставок
## с "stick_dpad": false (Nintendo 64: там у стика своя работа).
func stick_moves_dpad(system_id: String) -> bool:
	return CoreManager.get_system(system_id).get("stick_dpad", true)


## Положение стика игрока port: stick 0 — левый, 1 — правый.
## Vector2 от (-1, -1) до (1, 1): x — влево/вправо, y — вверх/вниз
## (вниз — плюс, как в Godot и в libretro).
func get_analog(port: int, stick: int, system_id := "") -> Vector2:
	var value := Vector2.ZERO
	var pads_list := Input.get_connected_joypads()
	if port < pads_list.size():
		var device: int = pads_list[port]
		if stick == 0:
			value = Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
		else:
			value = Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
		value = apply_deadzone(value)

	# Клавиатура: если стрелки не крестовина (Nintendo 64), они — левый стик.
	if port == 0 and stick == 0 and value == Vector2.ZERO and not stick_moves_dpad(system_id):
		value = Vector2(
				float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT)),
				float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP)))
		value = value.limit_length(1.0)  # по диагонали — тоже не дальше края
	return value


## Мёртвая зона «по кругу»: маленькие наклоны — ноль, а остальной ход
## растягиваем, чтобы от края мёртвой зоны значение росло плавно с нуля
## (иначе стик «прыгал» бы сразу с 0 на 0,12).
func apply_deadzone(value: Vector2) -> Vector2:
	var length := value.length()
	if length < ANALOG_DEADZONE:
		return Vector2.ZERO
	var scaled := minf(1.0, (length - ANALOG_DEADZONE) / (1.0 - ANALOG_DEADZONE))
	return value / length * scaled


# =====================================================================
# Раскладка по приставкам
# =====================================================================
#
# У каждой приставки свои кнопки: у NES — B и A, у Mega Drive — A, B, C,
# у PlayStation — ✕ ○ □ △. Какие они и какой кнопке RetroPad каждая
# соответствует, записано в data/pads.json.
#
# Раскладка — это словарь «кнопка приставки → кнопка вашего геймпада»:
#   {"b": "a", "a": "b", "select": "back", "start": "start"}
# читается так: «B приставки — это A на геймпаде Xbox» и т.д.
#
# В настройках (раздел [pads]) хранится только то, что человек поменял.
# Если раскладка совпадает с обычной — запись удаляется.

const PADS_PATH := "res://data/pads.json"

## Кнопки вашего геймпада, которые можно назначать. Порядок — как
## они перебираются стрелками ◀ ▶. "" — «не назначена».
## Правый стик (R3) не назначается: это кнопка меню паузы.
const PHYSICAL := ["a", "b", "x", "y", "lb", "rb", "lt", "rt", "back", "start", "l3", ""]

## Кнопка геймпада → кнопка Godot. Курков (lt, rt) здесь нет: это оси.
const PHYSICAL_JOY := {
	"a": JOY_BUTTON_A,
	"b": JOY_BUTTON_B,
	"x": JOY_BUTTON_X,
	"y": JOY_BUTTON_Y,
	"lb": JOY_BUTTON_LEFT_SHOULDER,
	"rb": JOY_BUTTON_RIGHT_SHOULDER,
	"back": JOY_BUTTON_BACK,
	"start": JOY_BUTTON_START,
	"l3": JOY_BUTTON_LEFT_STICK,
}

## Имя кнопки RetroPad (как в pads.json) → её номер.
const PAD_BY_NAME := {
	"b": PAD_B, "y": PAD_Y, "select": PAD_SELECT, "start": PAD_START,
	"a": PAD_A, "x": PAD_X, "l": PAD_L, "r": PAD_R,
	"l2": PAD_L2, "r2": PAD_R2, "l3": PAD_L3, "r3": PAD_R3,
}

## Как подписаны кнопки на геймпадах Xbox и PlayStation.
const GLYPHS := {
	"xbox": {"a": "A", "b": "B", "x": "X", "y": "Y", "lb": "LB", "rb": "RB",
		"lt": "LT", "rt": "RT", "back": "Back", "start": "Start", "l3": "LS", "": "—"},
	"playstation": {"a": "✕", "b": "○", "x": "□", "y": "△", "lb": "L1", "rb": "R1",
		"lt": "L2", "rt": "R2", "back": "Share", "start": "Options", "l3": "L3", "": "—"},
}

## Цвета подписей: у Xbox цветные буквы, у PlayStation — значки.
const GLYPH_COLORS := {
	"xbox": {"a": Color("3fa34d"), "b": Color("d6453d"), "x": Color("2f6fd6"), "y": Color("d4a52a")},
	"playstation": {"a": Color("7aa7ff"), "b": Color("ff6b6b"), "x": Color("f78fd0"), "y": Color("5ed39a")},
}

## Кнопки самого Shellbit, которые тоже назначаются для каждой приставки:
## перемотка назад и ускорение. Их нет в pads.json — они общие для всех.
## В раскладке они хранятся рядом с кнопками приставки ("rewind": "lt").
const HOTKEYS := [
	{"id": "rewind", "label": "◀◀", "name": "Перемотка назад", "color": "#1f7f75"},
	{"id": "fast_forward", "label": "▶▶", "name": "Ускорение", "color": "#1f7f75"},
]
## На клавиатуре — как в RetroArch: Backspace и пробел.
const HOTKEY_KEYS := {"rewind": KEY_BACKSPACE, "fast_forward": KEY_SPACE}

## Если курок занят игрой (L2 и R2 у PlayStation, Z у Nintendo 64),
## перемотка и ускорение работают через сочетание: зажать Back, потом курок.
## Back — «модификатор», как Shift на клавиатуре: сам по себе он Select,
## а вместе с курком — команда для Shellbit.
const COMBO_MODIFIER := "back"
const COMBO_TRIGGERS := {"rewind": "lt", "fast_forward": "rt"}

## Описания геймпадов приставок из pads.json: {"snes": {...}, ...}
var pads: Dictionary = {}

# Готовые таблицы для get_retropad_mask(): {"snes": [["a", 0], ["b", 8], ...]}
# и кнопки перемотки/ускорения: {"snes:rewind": "lt"}.
# Собирать их из словарей 60 раз в секунду незачем — храним готовые.
var _tables: Dictionary = {}


func _load_pads() -> void:
	var text := FileAccess.get_file_as_string(PADS_PATH)
	var data: Variant = JSON.parse_string(text)
	if data is Dictionary:
		pads = data
		pads.erase("_help")  # это подсказка для человека, а не приставка
	else:
		push_error("Не удалось прочитать " + PADS_PATH)


## Подпись кнопки геймпада: "a" → "A" (Xbox) или "✕" (PlayStation).
## На клавиатуре показываем подписи Xbox.
func glyph(physical: String) -> String:
	var table: Dictionary = GLYPHS.get(style, GLYPHS["xbox"])
	return table.get(physical, "?")


func glyph_color(physical: String) -> Color:
	var table: Dictionary = GLYPH_COLORS.get(style, GLYPH_COLORS["xbox"])
	return table.get(physical, UiTheme.TEXT)


## Зажата ли кнопка Shellbit ("rewind" или "fast_forward") в игре system_id:
## на клавиатуре или на первом геймпаде.
func is_hotkey_pressed(system_id: String, hotkey: String) -> bool:
	if Input.is_physical_key_pressed(HOTKEY_KEYS[hotkey]):
		return true
	var pads_list := Input.get_connected_joypads()
	if pads_list.is_empty() or not pads.has(system_id):
		return false
	# Кнопку запоминаем в _tables, чтобы не собирать раскладку каждый кадр.
	var key := system_id + ":" + hotkey
	if not _tables.has(key):
		_tables[key] = get_mapping(system_id).get(hotkey, "")
	var device: int = pads_list[0]
	if is_physical_pressed(device, _tables[key]):
		return true
	# Back + курок — если курок занят игрой.
	var trigger := combo_trigger(system_id, hotkey)
	return trigger != "" and is_physical_pressed(device, COMBO_MODIFIER) \
			and is_physical_pressed(device, trigger)


## Курок для сочетания «Back + курок» ("lt" или "rt") — или "", если
## сочетание не нужно: курок свободен, и перемотка висит на нём напрямую.
## Решает раскладка: занят курок, если на нём стоит кнопка приставки.
func combo_trigger(system_id: String, hotkey: String) -> String:
	var key := system_id + ":combo:" + hotkey
	if not _tables.has(key):
		var trigger: String = COMBO_TRIGGERS[hotkey]
		var mapping := get_mapping(system_id)
		var busy := false
		for button: Dictionary in pads.get(system_id, {}).get("buttons", []):
			if mapping.get(button["id"], "") == trigger:
				busy = true
		_tables[key] = trigger if busy else ""
	return _tables[key]


## Подпись сочетания для экрана: "Back + LT" (или "Share + L2" на геймпаде PlayStation).
func combo_text(system_id: String, hotkey: String) -> String:
	var trigger := combo_trigger(system_id, hotkey)
	if trigger == "":
		return ""
	return "%s + %s" % [glyph(COMBO_MODIFIER), glyph(trigger)]


## Зажато ли сейчас сочетание Back + занятый игрой курок.
func is_combo_held(device: int, system_id: String) -> bool:
	if not is_physical_pressed(device, COMBO_MODIFIER):
		return false
	for hotkey: String in COMBO_TRIGGERS:
		var trigger := combo_trigger(system_id, hotkey)
		if trigger != "" and is_physical_pressed(device, trigger):
			return true
	return false


## Нажата ли кнопка геймпада ("a", "lt"...) на устройстве device.
func is_physical_pressed(device: int, physical: String) -> bool:
	match physical:
		"":
			return false
		"lt":
			return Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT) > STICK_DEADZONE
		"rt":
			return Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > STICK_DEADZONE
		_:
			return Input.is_joy_button_pressed(device, PHYSICAL_JOY[physical])


## Какая кнопка геймпада нажата в этом событии ("a", "lt"...).
## Пустая строка — событие не про назначаемую кнопку.
func physical_from_event(event: InputEvent) -> String:
	if event is InputEventJoypadButton and event.pressed:
		for physical: String in PHYSICAL_JOY:
			if PHYSICAL_JOY[physical] == event.button_index:
				return physical
	elif event is InputEventJoypadMotion and event.axis_value > 0.6:
		if event.axis == JOY_AXIS_TRIGGER_LEFT:
			return "lt"
		if event.axis == JOY_AXIS_TRIGGER_RIGHT:
			return "rt"
	return ""


## Готовая раскладка: preset "default" — по положению кнопок,
## "by_label" — по надписям (A на A, B на B), где это возможно.
func preset_mapping(system_id: String, preset := "default") -> Dictionary:
	var mapping := {}
	for button: Dictionary in pads.get(system_id, {}).get("buttons", []):
		mapping[button["id"]] = button.get(preset, button["default"])
	# Перемотка и ускорение — на курках LT и RT, если они свободны.
	# У PlayStation и Nintendo 64 курки заняты (L2/R2, Z) — там по умолчанию
	# только клавиатура, а кнопку геймпада человек выберет сам.
	var used := mapping.values()
	mapping["rewind"] = "lt" if not used.has("lt") else ""
	mapping["fast_forward"] = "rt" if not used.has("rt") else ""
	return mapping


## Есть ли у приставки раскладка «по надписям».
func has_label_preset(system_id: String) -> bool:
	for button: Dictionary in pads.get(system_id, {}).get("buttons", []):
		if button.has("by_label"):
			return true
	return false


## Текущая раскладка приставки: обычная + то, что человек поменял.
func get_mapping(system_id: String) -> Dictionary:
	var mapping := preset_mapping(system_id)
	var saved: Dictionary = Settings.get_value("pads", system_id, {})
	for button_id in saved:
		if mapping.has(button_id):  # кнопки, которой больше нет в pads.json, пропускаем
			mapping[button_id] = saved[button_id]
	return mapping


## Сохранить раскладку. Обычную раскладку не храним — удаляем запись.
func set_mapping(system_id: String, mapping: Dictionary) -> void:
	if mapping == preset_mapping(system_id):
		Settings.set_value("pads", system_id, null)  # null удаляет ключ из файла
	else:
		Settings.set_value("pads", system_id, mapping)


## Назначить кнопке приставки button_id кнопку геймпада physical.
## Если эта кнопка геймпада уже занята другой кнопкой приставки,
## они меняются местами — так две кнопки никогда не «слипнутся».
func assign(system_id: String, button_id: String, physical: String) -> void:
	var mapping := get_mapping(system_id)
	var old_physical: String = mapping[button_id]
	if physical != "":
		for other_id in mapping:
			if other_id != button_id and mapping[other_id] == physical:
				mapping[other_id] = old_physical
	mapping[button_id] = physical
	set_mapping(system_id, mapping)


## Какая раскладка сейчас: "default", "by_label" или "custom" (своя).
func current_preset(system_id: String) -> String:
	var mapping := get_mapping(system_id)
	if mapping == preset_mapping(system_id):
		return "default"
	if has_label_preset(system_id) and mapping == preset_mapping(system_id, "by_label"):
		return "by_label"
	return "custom"


# Таблица [кнопка геймпада, бит RetroPad] для одной приставки.
func _table(system_id: String) -> Array:
	if not _tables.has(system_id):
		var mapping := get_mapping(system_id)
		var table := []
		for button: Dictionary in pads[system_id]["buttons"]:
			var physical: String = mapping[button["id"]]
			if physical != "":
				table.append([physical, PAD_BY_NAME[button["pad"]]])
		_tables[system_id] = table
	return _tables[system_id]
