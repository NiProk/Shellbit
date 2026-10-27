class_name ConsoleTile
extends Button
## Плитка приставки на главном экране: картинка приставки, цветная полоска,
## название, число игр.
##
## Картинка берётся из data/systems.json (поле "image").
## Если картинки нет — плитка выглядит как раньше, просто без неё.

const FOCUS_SCALE := 1.06
const FOCUS_TIME := 0.15
# Картинка в покое чуть притушена, а на выделенной плитке — в полную яркость.
const ART_DIM := Color(0.8, 0.8, 0.8)
const ART_BRIGHT := Color(1.0, 1.0, 1.0)
# «Взяли в руки»: картинка приставки на выделенной плитке чуть поворачивается
# и приближается (это делает шейдер RoundedCorners.gdshader).
# По часовой стрелке: приставки на картинках уже нарисованы с наклоном
# вниз-вправо, и поворот в ту же сторону усиливает его — приставку будто
# наклонили к тебе. Против часовой она бы, наоборот, выпрямлялась,
# и поворот было бы почти не заметно.
const TILT := 0.16    # радиан, ≈ 9°
const ZOOM := 1.12
const RAISE := 0.05   # приподнять на 5% высоты картинки
# Пока плитка выделена, приставка чуть покачивается — как в руках.
const SWAY := 0.03    # размах покачивания, радиан (≈ ±1,7°)
const SWAY_SPEED := 2.0  # скорость (радиан в секунду: полный круг ≈ за 3 с)

var system_id := ""
var color := Color.GRAY  ## цвет приставки — для полоски и свечения фона (Backdrop)
var _focus_tween: Tween
var _lift := 0.0  # насколько плитка «приподнята»: 0 — лежит, 1 — в руках
var _sway_time := 0.0  # время для покачивания

@onready var _art: TextureRect = %Art
@onready var _strip: ColorRect = %Strip
@onready var _name: Label = %SystemName
@onready var _count: Label = %Count


func _ready() -> void:
	mouse_entered.connect(grab_focus)
	focus_entered.connect(_on_focus_changed.bind(true))
	focus_exited.connect(_on_focus_changed.bind(false))
	resized.connect(_on_resized)
	set_process(false)  # покачивание включится, когда плитку выделят
	# Материал картинки в сцене общий для всех плиток. Поворачивать
	# будем только выделенную — значит, каждой нужна своя копия.
	_art.material = _art.material.duplicate()
	_on_resized()
	# Стандартная бирюзовая рамка появляется мгновенно и одного цвета.
	# Свою — цвета приставки, с тенью — рисуем в _draw().
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func setup(system: Dictionary, game_count: int) -> void:
	system_id = system["id"]
	color = Color(system["color"])
	_strip.color = color
	_name.text = system["short"]
	_count.text = Library.count_text(game_count)
	tooltip_text = tr(system["name"])

	# Картинка приставки. ResourceLoader.exists проверяет, что файл есть,
	# чтобы опечатка в systems.json не роняла программу.
	var image_path: String = system.get("image", "")
	if image_path != "" and ResourceLoader.exists(image_path):
		_art.texture = load(image_path)
		_art.visible = true


func _on_resized() -> void:
	# Увеличиваться плитка должна от центра.
	pivot_offset = size / 2.0
	# Шейдеру нужно знать размер плитки, чтобы скруглить углы в нужных местах.
	(_art.material as ShaderMaterial).set_shader_parameter("size", size)


func _on_focus_changed(focused: bool) -> void:
	# Останавливаем прошлую анимацию, если она ещё идёт.
	if _focus_tween:
		_focus_tween.kill()
	_focus_tween = create_tween().set_parallel(true) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_focus_tween.tween_property(self, "scale",
			Vector2.ONE * (FOCUS_SCALE if focused else 1.0), FOCUS_TIME)
	# modulate — «тонировка» узла: его цвета умножаются на заданный цвет.
	# 0.8 — чуть темнее, 1.0 — как есть.
	_focus_tween.tween_property(_art, "modulate",
			ART_BRIGHT if focused else ART_DIM, FOCUS_TIME)
	# Поворот картинки, тень и рамка — чуть медленнее увеличения:
	# так движение выглядит мягче, «весомее».
	_focus_tween.tween_method(_set_lift, _lift, 1.0 if focused else 0.0, FOCUS_TIME * 2.0)
	z_index = 1 if focused else 0


func _set_lift(value: float) -> void:
	_lift = value
	# Покачивание считает _process — но только пока плитка хоть немного поднята.
	set_process(value > 0.0)
	_update_art()
	queue_redraw()  # перерисовать рамку и тень — вызовется _draw()


func _process(delta: float) -> void:
	_sway_time += delta
	_update_art()


# Передать шейдеру поворот, приближение и подъём картинки.
# sin() плавно качается от −1 до 1 — это и есть покачивание. Умножаем
# на _lift: пока плитка опускается, покачивание тоже затихает.
func _update_art() -> void:
	var material := _art.material as ShaderMaterial
	var sway := sin(_sway_time * SWAY_SPEED) * SWAY
	material.set_shader_parameter("tilt", (TILT + sway) * _lift)
	material.set_shader_parameter("zoom", lerpf(1.0, ZOOM, _lift))
	material.set_shader_parameter("raise", RAISE * _lift)


## Рамка цвета приставки и тень — под картинкой, но рамка лежит
## снаружи плитки (expand_margin), поэтому её не закрывает.
func _draw() -> void:
	UiTheme.draw_focus_lift(self, Rect2(Vector2.ZERO, size), color, _lift)
