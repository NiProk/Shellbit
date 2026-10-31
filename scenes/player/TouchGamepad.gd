class_name TouchGamepad
extends Control
## Экранный геймпад: крестовина и кнопки поверх игры — играть пальцами.
##
##   ┌──────────────────────────────────────────────┐
##   │ ❚❚  [L]                              [R]     │
##   │                 картинка игры                │
##   │   ╋                                   Ⓧ      │
##   │  ╋ ╋                                Ⓨ   Ⓐ    │
##   │   ╋        [Select] [Start]           Ⓑ      │
##   └──────────────────────────────────────────────┘
##
## Какие кнопки у приставки, какого они цвета и как расположены, берём
## из того же описания, что рисует геймпады в настройках управления:
## data/pads.json (InputMapper.pads). Круглые кнопки ставим справа так же,
## как на настоящем геймпаде (у SNES — ромбом, у Mega Drive — тремя
## в ряд), верхние (L, R) — в верхние углы, Select/Start — внизу посередине.
##
## Несколько пальцев сразу: у каждого касания свой номер (index), и мы
## помним, что каким пальцем зажато. Палец можно вести: по крестовине —
## меняется направление, с кнопки на кнопку — нажимается соседняя,
## а между двумя кнопками — нажимаются обе (как B+A на NES).
##
## Player каждый кадр спрашивает mask() — какие кнопки RetroPad зажаты —
## и stick() — куда наклонён экранный стик (у Nintendo 64).
##
## Когда показывать — Настройки → Управление → «Экранный геймпад»:
## «Авто» — на телефоне, пока не подключён настоящий геймпад.

const ALPHA := 0.45          # прозрачность кнопок: игру под ними видно
const ALPHA_PRESSED := 0.8
const SLOP := 1.25           # кнопку можно нажать чуть мимо: палец толще, чем кажется
const DPAD_DEAD := 0.22      # в середине крестовины — «ничего не нажато»

## Кнопки и крестовина. У каждого элемента:
##   kind   — "button", "dpad" или "stick";
##   center — середина, radius — радиус (у кнопок-«таблеток» — size);
##   bits   — кнопки RetroPad, которые он нажимает (битовая маска).
var _controls: Array[Dictionary] = []
var _touches := {}         # номер касания → индекс элемента в _controls
var _touch_pos := {}       # номер касания → где сейчас палец
var _system := ""
var _gun := false          # игра с пистолетом: целятся пальцем по экрану, кнопок почти нет


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # касания ловим сами, в _input
	resized.connect(_layout)
	visibility_changed.connect(_release_all)


## Настроить под приставку. gun = true — игра со световым пистолетом:
## стреляют касанием экрана, поэтому оставляем только Select и Start.
func configure(system_id: String, gun := false) -> void:
	_system = system_id
	_gun = gun
	_layout()


## Нужен ли экранный геймпад сейчас (по настройке и устройству).
static func wanted() -> bool:
	match String(Settings.get_value("controls", "touch_pad")):
		"off":
			return false
		"always":
			return Platform.touch_first()
	# «Авто»: на телефоне, пока не подключён настоящий геймпад.
	return Platform.touch_first() and Input.get_connected_joypads().is_empty()


## Какие кнопки RetroPad сейчас зажаты пальцами.
func mask() -> int:
	if not visible:
		return 0
	var result := 0
	for index: int in _touches:
		var control: Dictionary = _controls[_touches[index]]
		match control["kind"]:
			"dpad":
				result |= _dpad_bits(control, _touch_pos[index])
			"button":
				result |= _buttons_at(_touch_pos[index])
	return result


## Куда наклонён экранный стик: от (-1, -1) до (1, 1). Нет стика — ноль.
## kind "stick" — основной (слева), "cstick" — C-кнопки Nintendo 64
## (у ядра это правый стик).
func stick(kind := "stick") -> Vector2:
	if not visible:
		return Vector2.ZERO
	for index: int in _touches:
		var control: Dictionary = _controls[_touches[index]]
		if control["kind"] == kind:
			return _stick_value(control, _touch_pos[index])
	return Vector2.ZERO


func _stick_value(control: Dictionary, pos: Vector2) -> Vector2:
	return ((pos - control["center"]) / control["radius"]).limit_length(1.0)


## Зажата ли пальцем кнопка Shellbit: "rewind" (◀◀ перемотка назад)
## или "fast_forward" (▶▶ ускорение).
func hotkey_held(id: String) -> bool:
	if not visible:
		return false
	for index: int in _touches:
		var control: Dictionary = _controls[_touches[index]]
		if control["kind"] == "hotkey" and control["id"] == id and _hits(control, _touch_pos[index]):
			return true
	return false


## Есть ли у этой раскладки стик (Nintendo 64).
func has_stick() -> bool:
	return _controls.any(func(c: Dictionary) -> bool: return c["kind"] == "stick")


# =====================================================================
# Раскладка
# =====================================================================

func _layout() -> void:
	_controls.clear()
	_release_all()
	var pad: Dictionary = InputMapper.pads.get(_system, InputMapper.pads.get("snes", {}))
	if pad.is_empty() or size.y <= 0.0:
		return
	var u := size.y / 720.0  # всё меряем в долях высоты экрана: на любом телефоне одинаково
	var margin := 30.0 * u

	var rounds: Array = []
	var shoulders: Array = []
	var pills: Array = []
	for button: Dictionary in pad.get("buttons", []):
		# Select и Start (а также Mode, Coin, Run…) — всегда внизу посередине,
		# даже если на настоящем геймпаде они круглые (Start у Nintendo 64).
		if String(button.get("pad", "")) in ["select", "start"]:
			pills.append(button)
			continue
		match String(button.get("shape", "round")):
			"round":
				rounds.append(button)
			"shoulder", "trigger":
				shoulders.append(button)
			"pill":
				pills.append(button)
			# "stick" — нажатие стика (L3/R3): на экране не нужно

	# --- Слева: крестовина, а у Nintendo 64 — стик ---
	if not _gun:
		var dpad_radius := 124.0 * u
		var dpad_center := Vector2(margin + dpad_radius, size.y - margin - dpad_radius)
		var kind := "dpad" if InputMapper.stick_moves_dpad(_system) else "stick"
		_controls.append({"kind": kind, "center": dpad_center, "radius": dpad_radius, "bits": 0})

	# --- Справа: круглые кнопки — так же, как на настоящем геймпаде ---
	if not _gun and not rounds.is_empty():
		var radius := (54.0 if rounds.size() <= 2 else 45.0) * u
		# Точки из pads.json (рисунок 600 × 260) растягиваем так, чтобы
		# соседние кнопки не налезали друг на друга.
		var min_gap := INF
		for i in rounds.size():
			for j in range(i + 1, rounds.size()):
				min_gap = minf(min_gap, _pos(rounds[i]).distance_to(_pos(rounds[j])))
		var scale := 1.5 * u
		if min_gap < INF:
			scale = maxf(scale, radius * 2.15 / min_gap)
		var box := Rect2(_pos(rounds[0]), Vector2.ZERO)
		for button: Dictionary in rounds:
			box = box.expand(_pos(button))
		var cluster := box.size * scale
		var origin := Vector2(size.x - margin - radius - cluster.x, size.y - margin - radius - cluster.y)
		for button: Dictionary in rounds:
			_controls.append(_button(button, origin + (_pos(button) - box.position) * scale, radius))

	# --- C-кнопки Nintendo 64 — маленький стик над A и B ---
	# (в ядре они — правый стик: вверх = C↑, влево = C← и т.д.)
	if not _gun and _system == "n64":
		var c_radius := 68.0 * u
		_controls.append({"kind": "cstick", "center": Vector2(size.x - margin - c_radius - 10.0 * u, size.y - 360.0 * u),
				"radius": c_radius, "bits": 0, "label": "C"})

	# --- ◀◀ и ▶▶ — перемотка назад и ускорение, вверху посередине ---
	# Держишь — работает (как курки на геймпаде). В играх с пистолетом тоже есть.
	var hotkey_size := Vector2(100, 52) * u
	for i in 2:
		var id: String = ["rewind", "fast_forward"][i]
		var center := Vector2(size.x / 2.0 + (i - 0.5) * (hotkey_size.x + 16.0 * u), 20.0 * u + hotkey_size.y / 2.0)
		_controls.append({"kind": "hotkey", "id": id, "center": center, "radius": 0.0, "size": hotkey_size,
				"bits": 0, "label": "◀◀" if id == "rewind" else "▶▶",
				"color": Color("2a3344"), "text_color": Color.WHITE})

	# --- Верхние кнопки (L, R, L2…) — в верхние углы, под кнопкой паузы ---
	if not _gun:
		var left_y := 104.0 * u
		var right_y := 104.0 * u
		var shoulder_size := Vector2(140, 62) * u
		for button: Dictionary in shoulders:
			var on_left := _pos(button).x < 300.0
			var x := margin if on_left else size.x - margin - shoulder_size.x
			var y := left_y if on_left else right_y
			var control := _button(button, Vector2(x, y) + shoulder_size / 2.0, 0.0)
			control["size"] = shoulder_size
			_controls.append(control)
			if on_left:
				left_y += shoulder_size.y + 14.0 * u
			else:
				right_y += shoulder_size.y + 14.0 * u

	# --- Select, Start, «Монета»… — внизу посередине ---
	var pill_size := Vector2(128, 52) * u
	var gap := 22.0 * u
	var row_width := pills.size() * pill_size.x + maxf(0, pills.size() - 1) * gap
	var x0 := (size.x - row_width) / 2.0
	for i in pills.size():
		var center := Vector2(x0 + i * (pill_size.x + gap) + pill_size.x / 2.0, size.y - 28.0 * u - pill_size.y / 2.0)
		var control := _button(pills[i], center, 0.0)
		control["size"] = pill_size
		_controls.append(control)
	queue_redraw()


func _pos(button: Dictionary) -> Vector2:
	var p: Array = button.get("pos", [0, 0])
	return Vector2(p[0], p[1])


func _button(button: Dictionary, center: Vector2, radius: float) -> Dictionary:
	var bit: int = InputMapper.PAD_BY_NAME.get(String(button.get("pad", "")), -1)
	return {
		"kind": "button",
		"center": center,
		"radius": radius,
		"bits": (1 << bit) if bit >= 0 else 0,
		"label": tr(String(button.get("label", ""))),
		"color": Color(String(button.get("color", "#55555e"))),
		"text_color": Color(String(button.get("text_color", "#ffffff"))),
	}


# =====================================================================
# Касания
# =====================================================================

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var pos: Vector2 = make_input_local(event).position
		if event.pressed:
			var hit := _control_at(pos)
			if hit >= 0:
				_touches[event.index] = hit
				_touch_pos[event.index] = pos
				_feedback()
				queue_redraw()
		elif _touches.has(event.index):
			_touches.erase(event.index)
			_touch_pos.erase(event.index)
			queue_redraw()
	elif event is InputEventScreenDrag and _touches.has(event.index):
		var before := mask()
		_touch_pos[event.index] = make_input_local(event).position
		if mask() & ~before:
			_feedback()  # палец съехал на новую кнопку — коротко «тык»
		queue_redraw()


# Какой элемент под пальцем (-1 — никакой). Крестовину и стик ловим
# с запасом: большой палец часто ставят мимо середины.
func _control_at(pos: Vector2) -> int:
	for i in _controls.size():
		var control: Dictionary = _controls[i]
		if control["kind"] in ["dpad", "stick", "cstick"] and pos.distance_to(control["center"]) <= control["radius"] * 1.4:
			return i
	for i in _controls.size():
		if _controls[i]["kind"] in ["button", "hotkey"] and _hits(_controls[i], pos):
			return i
	return -1


func _hits(control: Dictionary, pos: Vector2) -> bool:
	if control.has("size"):
		return Rect2(control["center"] - control["size"] / 2.0, control["size"]).grow(10.0).has_point(pos)
	return pos.distance_to(control["center"]) <= control["radius"] * SLOP


# Все кнопки под пальцем: между двумя кнопками нажимаются обе.
func _buttons_at(pos: Vector2) -> int:
	var bits := 0
	for control: Dictionary in _controls:
		if control["kind"] == "button" and _hits(control, pos):
			bits |= control["bits"]
	return bits


# Крестовина: куда от середины отведён палец — 8 направлений.
func _dpad_bits(control: Dictionary, pos: Vector2) -> int:
	var offset: Vector2 = pos - control["center"]
	if offset.length() < control["radius"] * DPAD_DEAD:
		return 0
	# Угол делим на 8 секторов по 45°: вправо, вправо-вниз, вниз…
	var sector := wrapi(roundi(offset.angle() / (PI / 4.0)), 0, 8)
	const SECTORS := [
		[InputMapper.PAD_RIGHT], [InputMapper.PAD_RIGHT, InputMapper.PAD_DOWN],
		[InputMapper.PAD_DOWN], [InputMapper.PAD_DOWN, InputMapper.PAD_LEFT],
		[InputMapper.PAD_LEFT], [InputMapper.PAD_LEFT, InputMapper.PAD_UP],
		[InputMapper.PAD_UP], [InputMapper.PAD_UP, InputMapper.PAD_RIGHT],
	]
	var bits := 0
	for pad_bit: int in SECTORS[sector]:
		bits |= 1 << pad_bit
	return bits


func _release_all() -> void:
	_touches.clear()
	_touch_pos.clear()
	queue_redraw()


# Короткая вибрация телефона на нажатие — как будто кнопка настоящая.
func _feedback() -> void:
	if Haptics.enabled():
		Input.vibrate_handheld(12)


# =====================================================================
# Рисование
# =====================================================================

func _draw() -> void:
	var pressed := mask()
	for control: Dictionary in _controls:
		match control["kind"]:
			"dpad":
				_draw_dpad(control, pressed)
			"stick", "cstick":
				_draw_stick(control)
			"button", "hotkey":
				var down: bool = (pressed & int(control["bits"])) != 0
				if control["kind"] == "hotkey":
					down = hotkey_held(control["id"])
				if control.has("size"):
					_draw_pill(control, down)
				else:
					_draw_round(control, down)


# Круглая кнопка «как настоящая»: мягкая тень, цветной корпус, светлый блик
# сверху (будто свет падает сверху), тонкий ободок. Нажатая — чуть меньше,
# ярче и без тени: кажется, что она утонула.
func _draw_round(control: Dictionary, down: bool) -> void:
	var center: Vector2 = control["center"]
	var r: float = control["radius"] * (0.93 if down else 1.0)
	var color: Color = control["color"]
	if not down:
		draw_circle(center + Vector2(0, r * 0.08), r * 1.02, Color(0, 0, 0, 0.28))  # тень
	var body := color.lightened(0.15) if down else color
	body.a = ALPHA_PRESSED if down else ALPHA + 0.1
	draw_circle(center, r, body)
	# Блик: светлый круг поменьше, сдвинутый вверх, — получается «выпуклость».
	draw_circle(center - Vector2(0, r * 0.18), r * 0.72, Color(1, 1, 1, 0.10 if down else 0.14))
	draw_arc(center, r, 0, TAU, 64, Color(1, 1, 1, 0.45 if down else 0.3), 2.5, true)
	_draw_label(control, center, int(r * 0.78), down)


# Кнопка-«таблетка» (Select, Start, L, R, ◀◀ ▶▶): то же, но вытянутая.
func _draw_pill(control: Dictionary, down: bool) -> void:
	var rect := Rect2(control["center"] - control["size"] / 2.0, control["size"])
	if down:
		rect = rect.grow(-2.0)
	var radius := int(rect.size.y / 2.0)
	if not down:
		var shadow := StyleBoxFlat.new()
		shadow.bg_color = Color(0, 0, 0, 0.25)
		shadow.set_corner_radius_all(radius)
		draw_style_box(shadow, Rect2(rect.position + Vector2(0, 3), rect.size))
	var color: Color = control["color"]
	var box := StyleBoxFlat.new()
	box.bg_color = Color(color.lightened(0.15) if down else color, ALPHA_PRESSED if down else ALPHA + 0.1)
	box.set_corner_radius_all(radius)
	box.border_color = Color(1, 1, 1, 0.45 if down else 0.28)
	box.set_border_width_all(2)
	box.anti_aliasing = true
	draw_style_box(box, rect)
	_draw_label(control, rect.get_center(), int(rect.size.y * 0.42), down)


func _draw_label(control: Dictionary, center: Vector2, font_size: int, down: bool) -> void:
	var font := get_theme_default_font()
	var text: String = control["label"]
	var color: Color = control["text_color"]
	color.a = 1.0 if down else 0.85
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := Vector2(center.x - text_size.x / 2.0,
			center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0)
	# Тёмная «подложка» под буквой — надпись читается на любом цвете кнопки.
	draw_string(font, baseline + Vector2(0, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.35))
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


# Крестовина — «плюс» со скруглёнными концами, как у геймпадов приставок:
# тёмная подложка-круг, сам крест, ямка в середине и стрелки на концах.
# Нажатое направление подсвечивается.
func _draw_dpad(control: Dictionary, pressed: int) -> void:
	var center: Vector2 = control["center"]
	var r: float = control["radius"]
	var arm := r * 0.36   # полуширина полосы креста
	var reach := r * 0.92 # от середины до конца полосы
	draw_circle(center, r, Color(0, 0, 0, 0.22))
	draw_arc(center, r, 0, TAU, 64, Color(1, 1, 1, 0.12), 2.0, true)

	var base := Color(0.25, 0.27, 0.33, ALPHA + 0.15)
	for horizontal in [true, false]:
		var rect := Rect2(center.x - reach, center.y - arm, reach * 2.0, arm * 2.0) if horizontal \
				else Rect2(center.x - arm, center.y - reach, arm * 2.0, reach * 2.0)
		var shadow := StyleBoxFlat.new()
		shadow.bg_color = Color(0, 0, 0, 0.3)
		shadow.set_corner_radius_all(int(arm * 0.5))
		draw_style_box(shadow, Rect2(rect.position + Vector2(0, 4), rect.size))
	for horizontal in [true, false]:
		var rect := Rect2(center.x - reach, center.y - arm, reach * 2.0, arm * 2.0) if horizontal \
				else Rect2(center.x - arm, center.y - reach, arm * 2.0, reach * 2.0)
		var box := StyleBoxFlat.new()
		box.bg_color = base
		box.set_corner_radius_all(int(arm * 0.5))
		box.anti_aliasing = true
		draw_style_box(box, rect)

	# Нажатые стороны — светлее.
	var arms := {
		InputMapper.PAD_UP: Vector2.UP, InputMapper.PAD_DOWN: Vector2.DOWN,
		InputMapper.PAD_LEFT: Vector2.LEFT, InputMapper.PAD_RIGHT: Vector2.RIGHT,
	}
	for pad_bit: int in arms:
		var direction: Vector2 = arms[pad_bit]
		var down := (pressed & (1 << pad_bit)) != 0
		var mid := center + direction * (arm + (reach - arm) / 2.0)
		var half := (direction.abs() * (reach - arm) / 2.0) + (direction.orthogonal().abs() * arm)
		if down:
			var lit := StyleBoxFlat.new()
			lit.bg_color = Color(UiTheme.ACCENT, 0.55)
			lit.set_corner_radius_all(int(arm * 0.5))
			draw_style_box(lit, Rect2(mid - half, half * 2.0))
		# Стрелка-треугольник на конце.
		var p := center + direction * r * 0.68
		var side := direction.orthogonal() * arm * 0.42
		var tip := Color(1, 1, 1, 0.9 if down else 0.6)
		draw_colored_polygon(PackedVector2Array([p + direction * arm * 0.5, p - side, p + side]), tip)
	# Ямка в середине.
	draw_circle(center, arm * 0.55, Color(0, 0, 0, 0.25))


# Стик: основание с ободком и «шляпка», которая едет за пальцем.
func _draw_stick(control: Dictionary) -> void:
	var center: Vector2 = control["center"]
	var r: float = control["radius"]
	draw_circle(center, r, Color(0, 0, 0, 0.25))
	draw_circle(center, r * 0.94, Color(0.22, 0.24, 0.3, ALPHA + 0.05))
	draw_arc(center, r * 0.94, 0, TAU, 64, Color(1, 1, 1, 0.25), 2.0, true)
	var value := stick(control["kind"])
	var knob := center + value * r * 0.55
	var knob_r := r * 0.44
	draw_circle(knob + Vector2(0, knob_r * 0.12), knob_r, Color(0, 0, 0, 0.35))  # тень шляпки
	draw_circle(knob, knob_r, Color(0.78, 0.8, 0.86, 0.9) if value != Vector2.ZERO else Color(0.7, 0.72, 0.78, 0.8))
	draw_circle(knob - Vector2(0, knob_r * 0.2), knob_r * 0.7, Color(1, 1, 1, 0.18))  # блик
	if control.has("label"):  # «C» на стике C-кнопок
		var font := get_theme_default_font()
		var font_size := int(r * 0.42)
		var text_size := font.get_string_size(control["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, knob + Vector2(-text_size.x / 2.0, font_size * 0.36), control["label"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.15, 0.17, 0.2))
