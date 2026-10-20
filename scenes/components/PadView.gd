class_name PadView
extends Control
## Рисунок геймпада — без картинок, одним кодом (функции draw_*).
##
## Умеет рисовать два вида:
##   • геймпад приставки (modern = false) — по описанию из data/pads.json;
##   • ваш геймпад Xbox или PlayStation (modern = true). На его кнопках
##     написано, какая кнопка приставки на них стоит, — так видно,
##     где «B от SNES» на вашем геймпаде. Там же видны кнопки
##     перемотки ◀◀ и ускорения ▶▶.
##
## Использование:
##   pad_view.show_pad("snes", InputMapper.get_mapping("snes"), "b")
## Третий параметр — кнопка приставки, которую подсветить (или "").
##
## Рисуем на «холсте» 600 × 260 (как в pads.json), а потом пересчитываем
## под настоящий размер узла: _p() — точка, _s() — размер.

const W := 600.0
const H := 260.0

## Ваш геймпад: кнопка → [форма, место]. У Xbox и PlayStation
## крестовина и левый стик стоят по-разному.
const XBOX_LAYOUT := {
	"lt": ["trigger", Vector2(150, 16)], "rt": ["trigger", Vector2(450, 16)],
	"lb": ["shoulder", Vector2(150, 46)], "rb": ["shoulder", Vector2(450, 46)],
	"l3": ["stick", Vector2(158, 112)],
	"back": ["pill", Vector2(258, 112)], "start": ["pill", Vector2(342, 112)],
	"y": ["round", Vector2(450, 72)], "x": ["round", Vector2(403, 116)],
	"b": ["round", Vector2(497, 116)], "a": ["round", Vector2(450, 160)],
}
const PS_LAYOUT := {
	"lt": ["trigger", Vector2(150, 16)], "rt": ["trigger", Vector2(450, 16)],
	"lb": ["shoulder", Vector2(150, 46)], "rb": ["shoulder", Vector2(450, 46)],
	"l3": ["stick", Vector2(238, 186)],
	"back": ["pill", Vector2(222, 108)], "start": ["pill", Vector2(370, 108)],
	"y": ["round", Vector2(470, 72)], "x": ["round", Vector2(423, 116)],
	"b": ["round", Vector2(517, 116)], "a": ["round", Vector2(470, 160)],
}
const MODERN_BODY := Color("2b3140")
const EMPTY_BUTTON := Color("1b202b")

## true — рисовать ваш геймпад, false — геймпад приставки.
## @export — свойство видно в Инспекторе: его можно включить прямо в сцене.
@export var modern := false

var _system_id := ""
var _mapping: Dictionary = {}   # кнопка приставки → кнопка геймпада
var _highlight := ""            # какую кнопку приставки подсветить

# Пересчёт холста 600×260 в размер узла (считается в начале _draw).
var _k := 1.0
var _origin := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Сменился тип геймпада (Xbox ↔ PlayStation) — перерисовать подписи.
	InputMapper.style_changed.connect(func(_style: String) -> void: queue_redraw())


## Показать геймпад приставки system_id с раскладкой mapping.
func show_pad(system_id: String, mapping: Dictionary, highlight := "") -> void:
	_system_id = system_id
	_mapping = mapping
	_highlight = highlight
	queue_redraw()  # «перерисуй меня в следующем кадре» — вызовет _draw()


func _draw() -> void:
	var info: Dictionary = InputMapper.pads.get(_system_id, {})
	if info.is_empty():
		return
	# Холст вписываем в узел целиком, сохраняя пропорции, и ставим по центру.
	_k = minf(size.x / W, size.y / H)
	_origin = (size - Vector2(W, H) * _k) / 2.0

	if modern:
		_draw_modern(info)
	else:
		_draw_console(info)


# =====================================================================
# Геймпад приставки
# =====================================================================

func _draw_console(info: Dictionary) -> void:
	var body := Color(info["body_color"])
	# Цвет, на котором лежат кнопки: у NES и PC Engine — тёмная вставка.
	var face := Color(info.get("face_color", info["body_color"]))
	var buttons: Array = info["buttons"]

	# Курки (L2, R2) рисуем ДО корпуса: корпус закроет их нижнюю часть,
	# и они будут «выглядывать» сверху, как настоящие. Остальное — поверх.
	for button: Dictionary in buttons:
		if _is_top(button):
			_draw_button(button, _vec(button["pos"]), face)

	_draw_body(info["body"], body, info)

	if info.has("screen"):
		var r: Array = info["screen"]
		var screen := Rect2(r[0], r[1], r[2], r[3])
		_rrect(screen.grow(10), 10, body.darkened(0.45))
		_rrect(screen, 4, Color(info.get("screen_color", "#26323f")))
	if info.has("dpad"):
		_dpad(_vec(info["dpad"]), face)
	if info.has("stick"):
		_arcade_stick(_vec(info["stick"]), info["body"] == "panel")
	for decor: Dictionary in info.get("decor", []):
		_draw_decor(decor, body)

	for button: Dictionary in buttons:
		if not _is_top(button):
			_draw_button(button, _vec(button["pos"]), face)


# Курок, который прячется за корпусом?
func _is_top(button: Dictionary) -> bool:
	return button["shape"] == "trigger"


# Одна кнопка приставки: форма, цвет, надпись и подсветка.
func _draw_button(button: Dictionary, pos: Vector2, body: Color) -> void:
	var color := Color(button["color"])
	var text_color := Color(button.get("text_color", "#ffffff"))
	var label: String = button["label"]
	var lit: bool = button["id"] == _highlight
	match button["shape"]:
		"round":
			var radius := 22.0
			if lit:
				_glow_circle(pos, radius)
			_circle(pos, radius, color)
			_circle(pos, radius - 3, color.lightened(0.08))  # лёгкий объём
			if label.length() <= 2:
				_text(pos, label, 20, text_color)
			else:
				# Длинную надпись («Start», «Fire») пишем под кнопкой, как на корпусе.
				_text(pos + Vector2(0, 36), label, 13, _ink(body))
		"pill":
			var rect := Rect2(pos - Vector2(23, 7), Vector2(46, 14))
			if lit:
				_glow_rect(rect, 7)
			_rrect(rect, 7, color)
			_text(pos + Vector2(0, 22), label, 13, _ink(body))
		"shoulder":
			var rect := Rect2(pos - Vector2(55, 14), Vector2(110, 28))
			if lit:
				_glow_rect(rect, 10)
			_rrect(rect, 10, color)
			_text(pos + Vector2(0, -2), label, 15, text_color)
		"trigger":
			var rect := Rect2(pos - Vector2(40, 12), Vector2(80, 24))
			if lit:
				_glow_rect(rect, 8)
			_rrect(rect, 8, color)
			_text(pos + Vector2(0, -2), label, 13, text_color)
		"stick":
			if lit:
				_glow_circle(pos, 28)
			_circle(pos, 28, color)
			_circle(pos, 20, color.lightened(0.12))
			_text(pos, label, 14, text_color)


# Украшения без назначения (стик N64, жёлтые C-кнопки).
func _draw_decor(decor: Dictionary, body: Color) -> void:
	var pos := _vec(decor["pos"])
	match decor["kind"]:
		"stick":
			_circle(pos, 24, body.darkened(0.35))
			_circle(pos, 15, body.lightened(0.15))
		"small":
			var color := Color(decor.get("color", "#888888"))
			_circle(pos, 12, color)
			_text(pos, decor["label"], 11, Color("3a2e00"))


# Корпус. Формы составлены из прямоугольников и кругов.
func _draw_body(shape: String, color: Color, info: Dictionary) -> void:
	match shape:
		"rect":  # NES, Master System, PC Engine
			_rrect(Rect2(40, 50, 520, 190), 24, color)
			if info.has("face_color"):
				_rrect(Rect2(72, 82, 456, 126), 12, Color(info["face_color"]))
		"dogbone":  # SNES: прямоугольник с кругами по краям
			_circle(Vector2(140, 140), 95, color)
			_circle(Vector2(460, 140), 95, color)
			_rrect(Rect2(140, 55, 320, 170), 30, color)
		"crescent":  # Mega Drive: правая половина больше
			_circle(Vector2(150, 145), 90, color)
			_circle(Vector2(468, 135), 105, color)
			_rrect(Rect2(150, 62, 318, 160), 40, color)
		"trident":  # Nintendo 64: три ручки
			_rrect(Rect2(75, 100, 100, 150), 45, color)
			_rrect(Rect2(250, 110, 100, 140), 45, color)
			_rrect(Rect2(425, 100, 100, 150), 45, color)
			_rrect(Rect2(50, 42, 500, 110), 50, color)
		"grips":  # PlayStation и современные геймпады: «рожки» снизу
			_circle(Vector2(128, 200), 50, color)
			_circle(Vector2(472, 200), 50, color)
			_circle(Vector2(150, 125), 88, color)
			_circle(Vector2(450, 125), 88, color)
			_rrect(Rect2(150, 48, 300, 150), 30, color)
		"handheld_v":  # Game Boy: вертикальный, скруглённый правый нижний угол
			var box := StyleBoxFlat.new()
			box.bg_color = color
			box.set_corner_radius_all(int(_s(14)))
			box.corner_radius_bottom_right = int(_s(60))
			draw_style_box(box, Rect2(_p(Vector2(198, 4)), Vector2(_s(204), _s(252))))
		"handheld_h":  # Game Boy Advance, Game Gear
			_rrect(Rect2(40, 46, 520, 186), 80, color)
		"joystick":  # Atari: квадратное основание со стиком
			_rrect(Rect2(175, 52, 250, 196), 22, color)
		"panel":  # аркадная панель
			_rrect(Rect2(30, 40, 540, 206), 26, color)


# =====================================================================
# Ваш геймпад (Xbox / PlayStation)
# =====================================================================

func _draw_modern(info: Dictionary) -> void:
	var layout: Dictionary = PS_LAYOUT if InputMapper.style == "playstation" else XBOX_LAYOUT

	# Обратный словарь: кнопка геймпада → описание кнопки приставки.
	# Кнопки перемотки и ускорения (◀◀ ▶▶) тоже показываем на вашем геймпаде.
	var on_physical := {}
	for button: Dictionary in info["buttons"] + InputMapper.HOTKEYS:
		var physical: String = _mapping.get(button["id"], "")
		if physical != "":
			on_physical[physical] = button
	var lit_physical: String = _mapping.get(_highlight, "") if _highlight != "" else ""

	# Курки торчат из-за корпуса, а бамперы LB/RB лежат на его верхнем краю.
	for physical: String in ["lt", "rt"]:
		_draw_physical(physical, layout[physical], on_physical, lit_physical)
	_draw_body("grips", MODERN_BODY, {})
	for physical: String in ["lb", "rb"]:
		_draw_physical(physical, layout[physical], on_physical, lit_physical)

	if InputMapper.style == "playstation":
		_dpad(Vector2(150, 118), MODERN_BODY)
		_rrect(Rect2(262, 52, 76, 48), 10, MODERN_BODY.lightened(0.08))  # тачпад
		_menu_stick(Vector2(362, 186))
	else:
		_dpad(Vector2(232, 180), MODERN_BODY)
		_menu_stick(Vector2(368, 180))
		_circle(Vector2(300, 68), 14, MODERN_BODY.lightened(0.15))  # кнопка Xbox

	for physical: String in layout:
		if not (physical in ["lt", "rt", "lb", "rb"]):
			_draw_physical(physical, layout[physical], on_physical, lit_physical)


# Кнопка вашего геймпада. Если на ней стоит кнопка приставки — она
# окрашена в цвет кнопки приставки и подписана её надписью, а рядом
# мелко написано, что это за кнопка на самом геймпаде (A, LB, ✕…).
func _draw_physical(physical: String, place: Array, on_physical: Dictionary, lit_physical: String) -> void:
	var shape: String = place[0]
	var pos: Vector2 = place[1]
	var mapped: bool = on_physical.has(physical)
	var button: Dictionary = on_physical.get(physical, {})
	var color := Color(button["color"]) if mapped else EMPTY_BUTTON
	var text: String = button["label"] if mapped else InputMapper.glyph(physical)
	var text_color := Color(button.get("text_color", "#ffffff")) if mapped else UiTheme.TEXT_DIM
	var lit := physical == lit_physical
	var glyph := InputMapper.glyph(physical)
	var glyph_color := InputMapper.glyph_color(physical)

	match shape:
		"round":
			if lit:
				_glow_circle(pos, 22)
			_circle(pos, 22, color)
			_text(pos, text, 20 if text.length() <= 2 else 11, text_color)
			if mapped:
				_tag(pos + Vector2(0, 33), glyph, glyph_color)
		"pill":
			var rect := Rect2(pos - Vector2(32, 13), Vector2(64, 26))
			if lit:
				_glow_rect(rect, 13)
			_rrect(rect, 13, color)
			_text(pos, text, 12, text_color)
			if mapped:
				_tag(pos + Vector2(0, 26), glyph, UiTheme.TEXT_DIM)
		"stick":
			if lit:
				_glow_circle(pos, 30)
			_circle(pos, 30, Color("161a22"))
			_circle(pos, 23, color if mapped else Color("3a4152"))
			_text(pos, text, 14 if text.length() <= 3 else 11, text_color)
			if mapped:
				_tag(pos + Vector2(0, 42), glyph, UiTheme.TEXT_DIM)
		"shoulder", "trigger":
			var half := Vector2(55, 14) if shape == "shoulder" else Vector2(40, 12)
			var rect := Rect2(pos - half, half * 2)
			if lit:
				_glow_rect(rect, 10)
			_rrect(rect, 10, color)
			_text(pos + Vector2(0, -2), text, 14 if text.length() <= 3 else 11, text_color)
			if mapped:
				# Подпись — снаружи: у левых кнопок слева, у правых справа.
				var side := -1.0 if pos.x < W / 2 else 1.0
				_tag(pos + Vector2(side * (half.x + 22), -2), glyph, UiTheme.TEXT_DIM)


# Правый стик — кнопка меню паузы, назначать её нельзя.
func _menu_stick(pos: Vector2) -> void:
	_circle(pos, 30, Color("161a22"))
	_circle(pos, 23, Color("3a4152"))
	_text(pos, "≡", 18, UiTheme.TEXT_DIM)
	_text(pos + Vector2(0, 42), tr("меню"), 12, UiTheme.TEXT_DIM)


# =====================================================================
# Простые фигуры (в координатах холста 600 × 260)
# =====================================================================

func _p(v: Vector2) -> Vector2:
	return _origin + v * _k


func _s(value: float) -> float:
	return value * _k


func _vec(pair: Array) -> Vector2:
	return Vector2(pair[0], pair[1])


func _circle(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(_p(center), _s(radius), color, true, -1.0, true)


func _rrect(rect: Rect2, radius: float, color: Color) -> void:
	# StyleBoxFlat — тот же «прямоугольник со скруглёнными углами»,
	# что и у кнопок интерфейса. Рисовать им проще, чем считать дуги.
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(int(_s(radius)))
	box.anti_aliasing = true
	draw_style_box(box, Rect2(_p(rect.position), rect.size * _k))


# Крестовина: два перекрещённых прямоугольника.
func _dpad(center: Vector2, body: Color) -> void:
	var color := Color("1d1d22") if body.get_luminance() > 0.35 else body.lightened(0.18)
	_rrect(Rect2(center - Vector2(36, 12), Vector2(72, 24)), 5, color)
	_rrect(Rect2(center - Vector2(12, 36), Vector2(24, 72)), 5, color)


# Стик Atari (вид сверху) или шар аркадного джойстика.
func _arcade_stick(center: Vector2, ball: bool) -> void:
	_circle(center, 42, Color("101013"))
	if ball:
		_circle(center, 26, Color("d6303a"))
		_circle(center + Vector2(-7, -7), 8, Color("ff7a7a"))
	else:
		_circle(center, 22, Color("3a3a40"))
		_circle(center, 12, Color("2a2a2e"))


# Подсветка выбранной кнопки: бирюзовое кольцо со свечением.
func _glow_circle(center: Vector2, radius: float) -> void:
	_circle(center, radius + 12, Color(UiTheme.ACCENT, 0.18))
	_circle(center, radius + 6, UiTheme.ACCENT)


func _glow_rect(rect: Rect2, radius: float) -> void:
	_rrect(rect.grow(10), radius + 10, Color(UiTheme.ACCENT, 0.18))
	_rrect(rect.grow(5), radius + 5, UiTheme.ACCENT)


# Маленькая подпись-ярлычок: на тёмной плашке, чтобы читалась на любом фоне.
func _tag(center: Vector2, text: String, color: Color) -> void:
	var font := get_theme_default_font()
	var font_size := int(_s(13))
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x / _k
	_rrect(Rect2(center - Vector2(width / 2 + 7, 10), Vector2(width + 14, 20)), 10, Color("0b0f17", 0.85))
	_text(center, text, 13, color)


# Надпись по центру точки center.
func _text(center: Vector2, text: String, font_size: float, color: Color) -> void:
	var font := get_theme_default_font()
	var px := int(_s(font_size))
	if px < 6 or text == "":
		return
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
	# draw_string ставит текст по базовой линии (низ букв без «хвостиков»),
	# поэтому сдвигаем на половину высоты букв, чтобы попасть в центр.
	var baseline := _p(center) + Vector2(-text_size.x / 2, (font.get_ascent(px) - font.get_descent(px)) / 2)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)


# Цвет надписей на корпусе: на светлом корпусе — тёмные, на тёмном — светлые.
func _ink(body: Color) -> Color:
	return Color("2c2c33") if body.get_luminance() > 0.45 else Color("c9ccd6")
