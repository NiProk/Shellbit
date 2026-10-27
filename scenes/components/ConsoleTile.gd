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

var system_id := ""
var color := Color.GRAY  ## цвет приставки — для полоски и свечения фона (Backdrop)
var _focus_tween: Tween

@onready var _art: TextureRect = %Art
@onready var _strip: ColorRect = %Strip
@onready var _name: Label = %SystemName
@onready var _count: Label = %Count


func _ready() -> void:
	mouse_entered.connect(grab_focus)
	focus_entered.connect(_on_focus_changed.bind(true))
	focus_exited.connect(_on_focus_changed.bind(false))
	resized.connect(_on_resized)
	_on_resized()


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
	z_index = 1 if focused else 0
