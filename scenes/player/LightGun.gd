class_name LightGun
extends Control
## Световой пистолет: Zapper у NES (Duck Hunt, Hogan's Alley, Wild Gunman…).
##
## Как работал настоящий Zapper: в момент выстрела игра на долю секунды
## красила экран в чёрный, а утку — в белый квадрат. Пистолет смотрел
## на кинескоп: видит свет — попал, темно — мимо. На современном ЖК-экране
## так не выйдет (нет луча кинескопа), поэтому в эмуляторе иначе:
## мы просто говорим ядру, КУДА прицелились, а ядро само проверяет,
## светлый ли там пиксель.
##
## Целиться:
##   • мышью — прицел там, где курсор; левая кнопка — выстрел,
##     правая — выстрел мимо экрана (в некоторых играх так перезаряжают);
##   • геймпадом — любой стик двигает прицел, выстрел — правый курок (RT / R2)
##     или правая «плечевая» кнопка (RB / R1).
##
## Этот узел лежит поверх картинки игры (%Screen) и рисует прицел.
## Player каждый кадр спрашивает у него aim() и передаёт ядру.

## Игры с пистолетом — по названию (как его показывает Shellbit, маленькими
## буквами). Подходит и «часть названия»: так находится и сборник
## «Super Mario Bros. + Duck Hunt».
const GAMES := {
	"nes": [
		"duck hunt", "hogan's alley", "wild gunman", "gumshoe", "operation wolf",
		"baby boomer", "barker bill's trick shooting", "freedom force", "gotcha",
		"mechanized attack", "shooting range", "the adventures of bayou billy",
		"chiller", "laser invasion", "to the earth", "the lone ranger",
	],
}
## В какой порт приставки вставлен пистолет. У NES — во второй
## (первый остаётся обычному геймпаду: им выбирают режим игры).
const PORTS := {"nes": 1}

const STICK_SPEED := 1.1   # стик до упора: столько ширин экрана в секунду
const SIZE := 0.06         # размер прицела — доля высоты картинки
const COLOR := Color("ff5a5a")
## Сколько пикселей должна пройти мышь, чтобы прицел перешёл к ней.
## Без этого мышь, которую слегка задели на столе, «утаскивала» прицел,
## пока целишься стиком: он прыгал туда, где стоит курсор.
const MOUSE_TAKEOVER := 12.0
## Кнопки геймпада, которые стреляют (названия — как в InputMapper).
const FIRE_BUTTONS := ["rt", "rb"]

var port := -1             # куда вставлен пистолет (-1 — игра без пистолета)
var _aim := Vector2(0.5, 0.5)  # куда целимся: 0…1 по картинке, за краями — мимо экрана
var _shot_flash := 0.0     # прицел коротко «вспыхивает» при выстреле (1 → 0)
var _was_firing := false
var _mouse_travel := 0.0   # сколько мышь прошла с тех пор, как целились стиком


## Игра с пистолетом? Тогда — в какой порт его вставить, иначе -1.
static func port_for(game: Dictionary) -> int:
	var system: String = game.get("system", "")
	var title := String(game.get("title", "")).to_lower()
	for name: String in GAMES.get(system, []):
		if title.contains(name):
			return PORTS[system]
	return -1


## Настройки ядра для игры с пистолетом. Отдать ДО load_game.
##   zapper_mode = clightgun — «пистолет с прицелом» (координаты от нас);
##   show_crosshair = disabled — свой прицел ядро не рисует: рисуем мы,
##   крупнее и заметнее (ядро рисует крестик в пару пикселей).
static func core_options(game: Dictionary) -> Dictionary:
	if game.get("system", "") == "nes":
		return {"fceumm_zapper_mode": "clightgun", "fceumm_show_crosshair": "disabled"}
	return {}


## Вставить пистолет в приставку. Ядро само присылает список того, что
## можно подключить к порту, — ищем в нём «Zapper». false — не нашли.
func plug_in(core: Node, game_port: int) -> bool:
	for type: Dictionary in core.get_controller_types(game_port):
		if String(type["name"]).to_lower() == "zapper":
			core.set_controller_type(game_port, type["id"])
			port = game_port
			return true
	return false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Прицел виден, пока идёт игра; в меню паузы — прячем (и возвращаем курсор).
func set_active(active: bool) -> void:
	visible = active
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if active else Input.MOUSE_MODE_VISIBLE


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # вышли из игры — курсор обратно


# Мышь сдвинулась — прицел туда же, где курсор. Не ограничиваем 0…1:
# курсор за краем картинки — это «мимо экрана», ядро так и поймёт.
func _input(event: InputEvent) -> void:
	# Телефон: коснулся экрана — прицел сразу туда (а выстрел — это «нажатие
	# мыши», которое Godot делает из касания, см. aim()).
	if visible and event is InputEventScreenTouch and event.pressed:
		_aim = make_input_local(event).position / size
		_mouse_travel = MOUSE_TAKEOVER
		return
	if visible and event is InputEventMouseMotion:
		_mouse_travel += event.relative.length()
		if _mouse_travel >= MOUSE_TAKEOVER:
			_aim = get_local_mouse_position() / size


## Каждый кадр: где прицел и что нажато.
## Возвращает [x, y, курок, выстрел мимо экрана]. muted — перемотка
## или только что вышли из меню: тогда не стреляем.
func aim(delta: float, muted: bool) -> Array:
	# Стик: чем сильнее наклон, тем быстрее; лёгкий наклон — точная доводка
	# (поэтому скорость растёт как квадрат наклона, а не прямо).
	var stick := _stick()
	if stick != Vector2.ZERO:
		_mouse_travel = 0.0  # целимся стиком — мышь снова должна «заявить о себе»
		var aspect := size.x / maxf(size.y, 1.0)
		var step := stick * stick.length() * STICK_SPEED * delta
		_aim += Vector2(step.x, step.y * aspect)  # одинаковая скорость по X и Y на экране
		_aim = _aim.clamp(Vector2.ZERO, Vector2.ONE)

	var firing := not muted and (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or _trigger_pressed())
	var reload := not muted and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if firing and not _was_firing:
		_shot_flash = 1.0
	_was_firing = firing
	_shot_flash = maxf(0.0, _shot_flash - delta * 6.0)
	queue_redraw()
	return [_aim.x, _aim.y, firing, reload]


# Оба стика первого геймпада — какой сильнее наклонён.
func _stick() -> Vector2:
	var left := InputMapper.get_analog(0, 0)
	var right := InputMapper.get_analog(0, 1)
	return right if right.length() > left.length() else left


func _trigger_pressed() -> bool:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return false
	for button: String in FIRE_BUTTONS:
		if InputMapper.is_physical_pressed(pads[0], button):
			return true
	return false


# Прицел: кольцо и четыре чёрточки, с тёмной обводкой — чтобы был виден
# и на голубом небе Duck Hunt, и на чёрном экране вспышки выстрела.
func _draw() -> void:
	if _aim.x < 0.0 or _aim.x > 1.0 or _aim.y < 0.0 or _aim.y > 1.0:
		return  # мимо экрана — прицел не рисуем
	var center := _aim * size
	var radius := size.y * SIZE * (1.0 - 0.25 * _shot_flash)  # при выстреле кольцо сжимается
	var width := maxf(2.0, size.y * 0.006)
	var color := COLOR.lerp(Color.WHITE, _shot_flash)
	for pass_index in 2:
		# Первый проход — тёмная обводка потолще, второй — сам цветной прицел.
		var outline := pass_index == 0
		var c := Color(0, 0, 0, 0.6) if outline else color
		var w := width + 2.0 if outline else width
		draw_arc(center, radius, 0.0, TAU, 48, c, w, true)
		for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(center + direction * radius * 0.45, center + direction * radius * 1.45, c, w, true)
		draw_circle(center, w * 0.8, c)
