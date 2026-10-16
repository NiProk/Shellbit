extends Node
## InputMapper — всё, что связано с геймпадами и клавиатурой.
##
## 1. Добавляет в Input Map наши действия (favorite, details, page_left...).
##    Встроенные ui_accept, ui_cancel и стрелки уже есть в Godot,
##    но к A и B геймпада их приходится привязывать самим (см. _ready).
## 2. Следит, чем человек сейчас управляет: Xbox, PlayStation или клавиатура,
##    чтобы подсказки внизу экрана показывали правильные значки.
## 3. Переводит кнопки геймпада и клавиатуры в RetroPad для эмулятора.

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

# Кнопка реального геймпада → кнопка RetroPad.
# Раскладка «по положению»: нижняя кнопка Xbox (A) = нижняя кнопка SNES (B).
const JOY_TO_PAD := {
	JOY_BUTTON_A: PAD_B,
	JOY_BUTTON_B: PAD_A,
	JOY_BUTTON_X: PAD_Y,
	JOY_BUTTON_Y: PAD_X,
	JOY_BUTTON_BACK: PAD_SELECT,
	JOY_BUTTON_START: PAD_START,
	JOY_BUTTON_DPAD_UP: PAD_UP,
	JOY_BUTTON_DPAD_DOWN: PAD_DOWN,
	JOY_BUTTON_DPAD_LEFT: PAD_LEFT,
	JOY_BUTTON_DPAD_RIGHT: PAD_RIGHT,
	JOY_BUTTON_LEFT_SHOULDER: PAD_L,
	JOY_BUTTON_RIGHT_SHOULDER: PAD_R,
	JOY_BUTTON_LEFT_STICK: PAD_L3,
	# Правый стик (R3) не передаём в игру: это кнопка меню паузы.
	# Когда дойдём до PlayStation (там R3 нужен), сделаем это настройкой.
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


## Маска нажатых кнопок для игрока port (0 = первый игрок).
func get_retropad_mask(port: int) -> int:
	var mask := 0

	if port == 0:
		for key: Key in KEY_TO_PAD:
			if Input.is_physical_key_pressed(key):
				mask |= 1 << KEY_TO_PAD[key]

	var pads := Input.get_connected_joypads()
	if port < pads.size():
		var device: int = pads[port]
		for button: JoyButton in JOY_TO_PAD:
			if Input.is_joy_button_pressed(device, button):
				mask |= 1 << JOY_TO_PAD[button]

		# Левый стик работает как крестовина.
		var x := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
		var y := Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
		if x < -STICK_DEADZONE: mask |= 1 << PAD_LEFT
		if x > STICK_DEADZONE: mask |= 1 << PAD_RIGHT
		if y < -STICK_DEADZONE: mask |= 1 << PAD_UP
		if y > STICK_DEADZONE: mask |= 1 << PAD_DOWN

		# Курки — это оси (от 0 до 1), а не кнопки.
		if Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT) > STICK_DEADZONE: mask |= 1 << PAD_L2
		if Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > STICK_DEADZONE: mask |= 1 << PAD_R2

	return mask
