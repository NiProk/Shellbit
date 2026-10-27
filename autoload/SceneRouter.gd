extends Node
## SceneRouter — переходы между экранами и кнопка «Назад».
##
## Вместо того чтобы каждый экран сам вызывал change_scene_to_file(),
## все переходы идут через этот синглтон:
##   SceneRouter.go_to("library", {"system": "snes"})  — открыть экран
##   SceneRouter.back()                                 — вернуться назад
##
## Он помнит историю (стопку экранов), поэтому «Назад» всегда работает.

const SCENES := {
	"home": "res://scenes/home/Home.tscn",
	"library": "res://scenes/library/Library.tscn",
	"details": "res://scenes/details/GameDetails.tscn",
	"player": "res://scenes/player/Player.tscn",
	"settings": "res://scenes/settings/SettingsScreen.tscn",
	"pad_map": "res://scenes/settings/PadMapScreen.tscn",
}

## Параметры текущего экрана. Экран читает их в своём _ready():
##   var system_id = SceneRouter.params.get("system", "")
var params: Dictionary = {}

var _current := "home"
var _history: Array[Dictionary] = []
var _busy := false

var _layer: CanvasLayer
var _fade: ColorRect

## Переходы между экранами (раздел настроек «Оформление»).
## "fade" — обычное затемнение (без шейдера), остальные — шейдеры.
const TRANSITIONS := {
	"mosaic": preload("res://scenes/components/transitions/mosaic.gdshader"),
	"dissolve": preload("res://scenes/components/transitions/dissolve.gdshader"),
}
# Шейдерные переходы чуть длиннее затемнения: глазу нужно время,
# чтобы увидеть, как экран рассыпается.
const FADE_OUT := 0.12
const FADE_IN := 0.18
const PIXEL_OUT := 0.22
const PIXEL_IN := 0.28


func _ready() -> void:
	# CanvasLayer рисуется поверх всех экранов. На нём живут
	# чёрная «шторка» для плавных переходов и всплывающие сообщения.
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_fade)


## Открыть экран и запомнить текущий в истории.
func go_to(screen: String, new_params: Dictionary = {}) -> void:
	if _busy:
		return
	_history.append({"screen": _current, "params": params})
	_open(screen, new_params)


## Заменить текущий экран, не добавляя его в историю
## (например, переключение приставок кнопками LB/RB).
func replace(screen: String, new_params: Dictionary = {}) -> void:
	if not _busy:
		_open(screen, new_params)


## Вернуться на предыдущий экран.
func back() -> void:
	if _busy or _history.is_empty():
		return
	var previous: Dictionary = _history.pop_back()
	_open(previous["screen"], previous["params"])


func _open(screen: String, new_params: Dictionary) -> void:
	_busy = true
	if screen == "player":
		UiSounds.play_launch()  # «бульк» — игра запускается
	_current = screen
	params = new_params

	var shader: Shader = TRANSITIONS.get(Settings.get_value("look", "transition"))
	if shader == null:
		# Затемнить → сменить сцену → проявить.
		var tween := create_tween()
		tween.tween_property(_fade, "color:a", 1.0, FADE_OUT)
		await tween.finished
		get_tree().change_scene_to_file(SCENES[screen])
		tween = create_tween()
		tween.tween_property(_fade, "color:a", 0.0, FADE_IN)
		await tween.finished
	else:
		await _pixel_transition(shader, screen)
	_busy = false


# Пиксельный переход: тот же «затемнить → сменить → проявить», но шторку
# рисует шейдер (scenes/components/transitions). Он берёт уже нарисованный
# экран и рассыпает его на квадраты; progress: 0 — экран как есть, 1 — рассыпан.
func _pixel_transition(shader: Shader, screen: String) -> void:
	var material := ShaderMaterial.new()
	material.shader = shader
	_fade.material = material
	_fade.color = Color.BLACK  # непрозрачная шторка — дальше цвет решает шейдер
	var set_progress := func(value: float) -> void:
		material.set_shader_parameter("progress", value)
	set_progress.call(0.0)

	var tween := create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_method(set_progress, 0.0, 1.0, PIXEL_OUT)
	await tween.finished
	get_tree().change_scene_to_file(SCENES[screen])
	# Ждём кадр: новый экран должен нарисоваться, иначе шейдер
	# «проявит» ещё старую картинку.
	await get_tree().process_frame
	tween = create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_method(set_progress, 1.0, 0.0, PIXEL_IN)
	await tween.finished

	# Переход закончен: убрать шейдер и вернуть прозрачную шторку.
	# Иначе шейдер каждый кадр копировал бы весь экран — зря.
	_fade.material = null
	_fade.color = Color(0, 0, 0, 0)


## Короткое всплывающее сообщение сверху экрана.
func toast(text: String) -> void:
	var label := Label.new()
	label.text = text
	var box := UiTheme.badge_box(UiTheme.CARD_HOVER)
	box.set_content_margin_all(12)
	box.content_margin_left = 24
	box.content_margin_right = 24
	label.add_theme_stylebox_override("normal", box)
	_layer.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 24)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.modulate.a = 0.0

	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.15)
	tween.tween_interval(2.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.3)
	tween.tween_callback(label.queue_free)
