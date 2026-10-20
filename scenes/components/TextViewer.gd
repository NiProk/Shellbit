class_name TextViewer
extends Control
## Окно для длинного текста — например, полного описания игры.
##
## Листается крестовиной, стиком, стрелками или колёсиком мыши.
## Закрывается кнопкой B (Esc) или A (Enter).
##
## Использование:
##   var viewer := TextViewer.new()
##   add_child(viewer)
##   viewer.open("Название", "Длинный текст…")
##   viewer.closed.connect(…)   # например, вернуть фокус на кнопку

## Окно закрыли.
signal closed

const ButtonHintsScene := preload("res://scenes/components/ButtonHints.tscn")
const SCROLL_STEP := 60  # на сколько пикселей листать за одно нажатие

var _title: Label
var _text: Label
var _scroll: ScrollContainer


func _ready() -> void:
	visible = false
	# Окно растянуто на весь экран и ловит мышь — клики не проходят
	# к кнопкам страницы, которые остались под ним.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Затемнение всего экрана.
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BG, 0.9)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Панель по центру: 840×520, чуть выше середины (внизу — подсказки).
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = UiTheme.PANEL
	box.set_corner_radius_all(16)
	box.set_content_margin_all(32)
	panel.add_theme_stylebox_override("panel", box)
	add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -420
	panel.offset_right = 420
	panel.offset_top = -280
	panel.offset_bottom = 240

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)

	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_title)

	# ScrollContainer показывает часть содержимого и умеет его прокручивать.
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.focus_mode = Control.FOCUS_ALL  # чтобы получать нажатия стрелок
	column.add_child(_scroll)

	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = 760
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("font_size", 19)
	_text.add_theme_color_override("font_color", Color(0.784, 0.812, 0.863))
	# Описание — это текст из файла игры, его не нужно переводить через tr().
	_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_scroll.add_child(_text)

	# Фокус не должен «убегать» на кнопки страницы под окном.
	for side in ["focus_neighbor_left", "focus_neighbor_top", "focus_neighbor_right", "focus_neighbor_bottom"]:
		_scroll.set(side, _scroll.get_path_to(_scroll))
	_scroll.gui_input.connect(_on_scroll_input)

	var hints := ButtonHintsScene.instantiate()
	add_child(hints)
	hints.set_hints([["scroll", "Прокрутить"], ["cancel", "Закрыть"]])


func open(title: String, text: String) -> void:
	_title.text = title
	_text.text = text
	_scroll.scroll_vertical = 0  # всегда с начала
	visible = true
	_scroll.grab_focus()


func close() -> void:
	visible = false
	closed.emit()


# Стрелки вверх/вниз листают текст. true — работает и при удержании кнопки.
func _on_scroll_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down", true):
		_scroll.scroll_vertical += SCROLL_STEP
		_scroll.accept_event()
	elif event.is_action_pressed("ui_up", true):
		_scroll.scroll_vertical -= SCROLL_STEP
		_scroll.accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		close()
	# Пока окно открыто, остальные кнопки страницы (избранное, версия…)
	# не должны срабатывать — забираем все нажатия себе.
	if event.is_pressed():
		get_viewport().set_input_as_handled()
