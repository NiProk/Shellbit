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
}

## Параметры текущего экрана. Экран читает их в своём _ready():
##   var system_id = SceneRouter.params.get("system", "")
var params: Dictionary = {}

var _current := "home"
var _history: Array[Dictionary] = []
var _busy := false

var _layer: CanvasLayer
var _fade: ColorRect


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
	_current = screen
	params = new_params

	# Затемнить → сменить сцену → проявить.
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.12)
	await tween.finished

	get_tree().change_scene_to_file(SCENES[screen])

	tween = create_tween()
	tween.tween_property(_fade, "color:a", 0.0, 0.18)
	await tween.finished
	_busy = false


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
