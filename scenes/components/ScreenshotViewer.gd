class_name ScreenshotViewer
extends Control
## Просмотр скриншота во весь экран — открывается из галереи на странице игры.
##
##   ◀ ▶ (крестовина, стик, стрелки, колёсико) — предыдущий / следующий снимок
##   X — удалить снимок (нажать дважды, чтобы не стереть случайно)
##   B / A — закрыть
##
## Использование:
##   viewer.open(paths, 2)       # список файлов и какой показать первым
##   viewer.closed.connect(…)    # index — на каком снимке закрыли
##   viewer.deleted.connect(…)   # удалили файл — галерее пора обновиться

signal closed(index: int)
signal deleted(path: String)

const ButtonHintsScene := preload("res://scenes/components/ButtonHints.tscn")
const DELETE_CONFIRM_TIME := 3.0

var _paths: PackedStringArray = []
var _index := 0
var _picture: TextureRect
var _caption: Label
var _hints: Control
var _delete_armed_at := -100.0


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 10  # выше выделенных кнопок страницы

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.94)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Картинка — по центру, с отступами; пропорции сохраняются (KEEP_ASPECT_CENTERED).
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Скриншот — пиксельная картинка приставки: без сглаживания, чёткими квадратами.
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_picture)
	_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picture.offset_left = 40
	_picture.offset_right = -40
	_picture.offset_top = 56
	_picture.offset_bottom = -72

	# Подпись сверху: «3 / 12 · 30.10.2026  21:15».
	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 20)
	_caption.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_caption)
	_caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_caption.offset_top = 16

	_hints = ButtonHintsScene.instantiate()
	add_child(_hints)


func open(paths: PackedStringArray, index: int) -> void:
	_paths = paths
	_index = clampi(index, 0, paths.size() - 1)
	var hints := [["change", "Листать"]]
	if not Family.is_on():
		hints.append(["details", "Удалить"])  # в детском режиме ничего не удаляем
	hints.append(["cancel", "Закрыть"])
	_hints.set_hints(hints)
	visible = true
	_show()


func close() -> void:
	visible = false
	_picture.texture = null  # большая картинка больше не нужна — освобождаем память
	closed.emit(_index)


func _show() -> void:
	if _paths.is_empty():
		close()
		return
	var path := _paths[_index]
	var image := Image.load_from_file(path)
	_picture.texture = ImageTexture.create_from_image(image) if image != null else null
	_caption.text = "%d / %d  ·  %s" % [_index + 1, _paths.size(), Screenshots.date_text(path)]
	_delete_armed_at = -100.0


func _step(direction: int) -> void:
	if _paths.size() < 2:
		return
	_index = wrapi(_index + direction, 0, _paths.size())  # по кругу
	UiSounds.play_click()
	_show()


func _delete() -> void:
	if Family.is_on():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _delete_armed_at > DELETE_CONFIRM_TIME:
		_delete_armed_at = now
		Haptics.confirm()
		SceneRouter.toast(tr("Нажмите ещё раз, чтобы удалить снимок"))
		return
	var path := _paths[_index]
	if DirAccess.remove_absolute(path) != OK:
		SceneRouter.toast(tr("Не удалось удалить файл"))
		return
	_paths.remove_at(_index)
	_index = mini(_index, _paths.size() - 1)
	deleted.emit(path)
	SceneRouter.toast(tr("Снимок удалён"))
	_show()


# В _input — раньше страницы игры: её кнопки не должны срабатывать под окном.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_left", true):
		_step(-1)
	elif event.is_action_pressed("ui_right", true):
		_step(1)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_step(-1)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_step(1)
	elif event.is_action_pressed("details"):
		_delete()
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		close()
	elif not (event is InputEventMouseMotion):
		pass  # остальные кнопки просто «глотаем»
	get_viewport().set_input_as_handled()
