extends Node
## Haptics — короткая вибрация геймпада в меню: «отдача» на важные действия.
##
## Как в приставках: нажал «Выход» в первый раз — геймпад коротко дрогнул
## («точно?»), ввёл неверный PIN — два толчка («нет!»), добавил в избранное —
## лёгкий «тык». Так понятно, что произошло, даже не глядя на экран.
##
## Вибрируем тем геймпадом, которым человек нажимал кнопку последним.
## Выключается: Настройки → Управление → «Вибрация в меню».
## (Вибрация в самих играх — отдельно: Настройки → Игра → «Вибрация».)
##
## Моторы у геймпада два: weak — слабый, быстрый (тонкое «жужжание»),
## strong — сильный, тяжёлый (ощутимый толчок). Сила — от 0 до 1.

var _last_pad := -1  # геймпад, которым нажимали последним (-1 — ещё ни одним)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # и на паузе (меню паузы в игре)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		_last_pad = event.device


func enabled() -> bool:
	return bool(Settings.get_value("controls", "ui_rumble"))


## Лёгкий «тык»: избранное, сохранение в слот.
func tap() -> void:
	_pulse(0.35, 0.0, 0.05)


## Толчок-предупреждение: «Точно выйти? Нажмите ещё раз», «Точно удалить?».
func confirm() -> void:
	_pulse(0.5, 0.35, 0.12)


## Ошибка — два толчка подряд: неверный PIN, коды не совпали.
func error() -> void:
	_pulse(0.6, 0.5, 0.08)
	await get_tree().create_timer(0.14).timeout
	_pulse(0.6, 0.5, 0.08)


## Геймпад только что подключили — пусть сам «отзовётся» коротким толчком:
## так видно, какой из геймпадов в руках подключился.
func hello(device: int) -> void:
	if enabled():
		Input.start_joy_vibration(device, 0.4, 0.25, 0.15)


func _pulse(weak: float, strong: float, seconds: float) -> void:
	if not enabled():
		return
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return  # играют с клавиатуры — вибрировать нечем
	var device := _last_pad if _last_pad in pads else pads[0]
	Input.start_joy_vibration(device, weak, strong, seconds)
