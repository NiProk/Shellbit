extends TestCase
## Экранный геймпад: какие кнопки RetroPad нажимают пальцы.

var pad: TouchGamepad


func before_each() -> void:
	pad = TouchGamepad.new()
	add_child(pad)
	pad.size = Vector2(1600, 720)  # телефон 20:9 при высоте интерфейса 720
	await frames(1)
	pad.size = Vector2(1600, 720)
	pad.visible = true


func after_each() -> void:
	pad.queue_free()
	await frames(1)


func test_nes_buttons_and_dpad() -> void:
	about("NES: крестовина слева (8 направлений), B и A справа, между ними — обе сразу")
	pad.configure("nes")
	var dpad := _control("dpad")
	var a := _button("A")
	var b := _button("B")
	check(dpad["center"].x < 400 and a["center"].x > 1200, "крестовина слева, кнопки справа")
	check(b["center"].x < a["center"].x, "B левее A, как на геймпаде NES")

	_touch(0, dpad["center"] + Vector2(80, 0))
	check_eq(pad.mask(), 1 << InputMapper.PAD_RIGHT, "палец вправо от середины — вправо")
	_drag(0, dpad["center"] + Vector2(60, -60))
	check_eq(pad.mask(), (1 << InputMapper.PAD_RIGHT) | (1 << InputMapper.PAD_UP), "повели вверх — диагональ")
	_drag(0, dpad["center"] + Vector2(5, 3))
	check_eq(pad.mask(), 0, "в самой середине — ничего")

	_touch(1, a["center"])
	check_eq(pad.mask() & ~0, 1 << InputMapper.PAD_A, "второй палец на A")
	_drag(1, (a["center"] + b["center"]) / 2.0)
	check_eq(pad.mask(), (1 << InputMapper.PAD_A) | (1 << InputMapper.PAD_B), "между B и A — обе")
	_touch(1, Vector2.ZERO, false)
	_touch(0, Vector2.ZERO, false)
	check_eq(pad.mask(), 0, "отпустили — ничего не нажато")


func test_layouts() -> void:
	about("Раскладки приставок: Select/Start внизу, L/R вверху, у N64 — стик")
	pad.configure("snes")
	check_eq(_buttons().size(), 8, "SNES: B A Y X, L R, Select Start")
	check(_button("L")["center"].y < 300 and _button("Start")["center"].y > 600)
	pad.configure("md")
	check(_button("Mode")["center"].y > 600, "Mode у Mega Drive — внизу, рядом со Start")
	pad.configure("n64")
	check(pad.has_stick(), "у Nintendo 64 вместо крестовины стик")
	var stick := _control("stick")
	_touch(0, stick["center"] + Vector2(stick["radius"] * 0.5, 0))
	_drag(0, stick["center"] + Vector2(stick["radius"] * 3, 0))
	check(pad.stick().is_equal_approx(Vector2(1, 0)), "повели палец далеко вправо — стик до упора вправо")
	pad.configure("nes", true)
	check(_control("dpad").is_empty() and _button("A").is_empty(), "игра с пистолетом — только Select и Start")
	check(not _button("Start").is_empty())


func test_hidden_pad_presses_nothing() -> void:
	about("Спрятанный геймпад (пауза, подключён настоящий) ничего не нажимает")
	pad.configure("nes")
	_touch(0, _button("A")["center"])
	pad.visible = false
	check_eq(pad.mask(), 0)


func _buttons() -> Array:
	return pad._controls.filter(func(c: Dictionary) -> bool: return c["kind"] == "button")


func _button(label: String) -> Dictionary:
	for control: Dictionary in _buttons():
		if control["label"] == label:
			return control
	return {}


func _control(kind: String) -> Dictionary:
	for control: Dictionary in pad._controls:
		if control["kind"] == kind:
			return control
	return {}


func _touch(index: int, pos: Vector2, pressed := true) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = pos
	event.pressed = pressed
	pad._input(event)


func _drag(index: int, pos: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	pad._input(event)


func test_rewind_and_fast_forward_buttons() -> void:
	about("◀◀ и ▶▶ вверху: держишь пальцем — перемотка или ускорение")
	pad.configure("nes")
	var rewind: Dictionary = pad._controls.filter(func(c: Dictionary) -> bool: return c.get("id", "") == "rewind")[0]
	check(rewind["center"].y < 100, "вверху экрана")
	_touch(3, rewind["center"])
	check(pad.hotkey_held("rewind"), "держим ◀◀")
	check(not pad.hotkey_held("fast_forward"))
	check_eq(pad.mask(), 0, "в игру ◀◀ не уходит")
	_touch(3, Vector2.ZERO, false)
	check(not pad.hotkey_held("rewind"), "отпустили")


func test_n64_c_buttons() -> void:
	about("Nintendo 64: C-кнопки — маленький стик справа (правый стик ядра)")
	pad.configure("n64")
	var c: Dictionary = pad._controls.filter(func(x: Dictionary) -> bool: return x["kind"] == "cstick")[0]
	check(c["center"].x > 1200, "справа")
	_touch(2, c["center"] + Vector2(0, -c["radius"] * 0.9))
	check(pad.stick("cstick").y < -0.8, "вверх = C↑")
	check_eq(pad.stick(), Vector2.ZERO, "основной стик не тронут")
