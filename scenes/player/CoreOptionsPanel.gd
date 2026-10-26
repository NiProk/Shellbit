class_name CoreOptionsPanel
extends Control
## «Настройки ядра» — окно поверх меню паузы.
##
## У каждого ядра свои настройки: у PlayStation — разрешение, регион,
## тип карты памяти; у NES — палитра, обрезка краёв и т.д. Сколько их
## и какие, мы заранее не знаем — список присылает само ядро
## (RetroCore.get_option_list()). Здесь мы просто показываем его
## строками SettingRow: ◀ ▶ — поменять значение, B — назад.
##
## Значения хранятся в settings.cfg, в разделе «core_<имя ядра>»,
## например [core_pcsx_rearmed]. Только те, что человек поменял.
##
## Использование (см. Player.gd):
##   panel.option_changed.connect(...)   # поменяли значение
##   panel.open(options, "core_pcsx_rearmed", "PCSX-ReARMed")
##   panel.update_visibility(options)    # ядро спрятало/показало настройки

signal option_changed(key: String, value: String)
signal reset_requested   ## «Вернуть всё как было»
signal closed

const ButtonHintsScene := preload("res://scenes/components/ButtonHints.tscn")

## Частые надписи значений, которые ядра пишут по-английски, — переводим.
const COMMON_LABELS := {
	"enabled": "Вкл", "disabled": "Выкл", "on": "Вкл", "off": "Выкл",
	"true": "Вкл", "false": "Выкл", "auto": "Авто",
}

var _section := ""
var _title: Label
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _info: Label
var _by_key := {}  # ключ настройки → строка SettingRow


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 5

	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BG, 0.85)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = UiTheme.PANEL
	box.set_corner_radius_all(18)
	box.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", box)
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Отступы от краёв экрана; снизу — место для подсказок.
	panel.offset_left = 120
	panel.offset_right = -120
	panel.offset_top = 36
	panel.offset_bottom = -76

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	column.add_child(_title)

	var note := Label.new()
	note.theme_type_variation = &"DimLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = tr("Настройки присылает само ядро, поэтому часто они по-английски. Некоторые заработают только после «Начать заново» — обычно у них в названии есть (Restart).")
	column.add_child(note)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	column.add_child(_scroll)

	# Отступ внутри прокрутки, чтобы рамка выделения не обрезалась.
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	_scroll.add_child(pad)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	pad.add_child(_rows)

	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Высота — ровно три строки, и не больше: если бы окошко описания
	# росло и сжималось, список над ним «прыгал» бы при каждом шаге.
	_info.custom_minimum_size.y = 84
	_info.max_lines_visible = 3
	_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_info.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	column.add_child(_info)

	var hints: Control = ButtonHintsScene.instantiate()
	add_child(hints)
	hints.set_hints([["accept", "Изменить"], ["cancel", "Назад"]])


## Показать настройки ядра. options — из RetroCore.get_option_list().
func open(options: Array, section: String, core_name: String) -> void:
	_section = section
	_title.text = tr("Настройки ядра") + " · " + core_name
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_by_key.clear()

	var category := "—"  # такой категории не бывает: первый заголовок появится всегда
	for option: Dictionary in options:
		# Заголовок категории («Video», «Audio»…), если ядро их сообщает.
		if option["category_label"] != category:
			category = option["category_label"]
			if category != "":
				var header := Label.new()
				header.text = category
				header.theme_type_variation = &"CardTitleLabel"
				header.set_meta("category", option["category"])
				_rows.add_child(header)
		var row := SettingRow.new()
		row.kind = SettingRow.Kind.CHOICE
		row.title = option["label"]
		row.section = section
		row.key = option["key"]
		row.default_value = option["default"]
		row.description = option["info"]
		row.options = option["values"].map(func(pair: Array) -> Array:
			return [pair[0], COMMON_LABELS.get(String(pair[1]).to_lower(), pair[1])])
		row.visible = option["visible"]
		_rows.add_child(row)
		_by_key[option["key"]] = row
		row.value_changed.connect(func(value: Variant) -> void:
			option_changed.emit(row.key, String(value)))
		row.focus_entered.connect(func() -> void: _info.text = row.current_description())
		row.value_changed.connect(func(_value: Variant) -> void: _info.text = row.current_description())

	var reset := SettingRow.new()
	reset.kind = SettingRow.Kind.ACTION
	reset.title = "Вернуть всё как было"
	reset.description = "Все настройки этого ядра — как в самом начале."
	_rows.add_child(reset)
	reset.pressed.connect(func() -> void: reset_requested.emit())
	reset.focus_entered.connect(func() -> void: _info.text = tr(reset.description))

	_info.text = "" if not options.is_empty() else tr("У этого ядра нет настроек.")
	_update_headers()
	visible = true
	_focus_first.call_deferred()


## Ядро спрятало или показало какие-то настройки — обновить список.
func update_visibility(options: Array) -> void:
	for option: Dictionary in options:
		if _by_key.has(option["key"]):
			_by_key[option["key"]].visible = option["visible"]
	_update_headers()


## Перечитать значения (после «Вернуть всё как было»).
func refresh_values() -> void:
	for row: SettingRow in _by_key.values():
		row.refresh()


func close() -> void:
	visible = false
	closed.emit()


# Заголовок категории прячем, если все её настройки спрятаны.
func _update_headers() -> void:
	var children := _rows.get_children()
	for i in children.size():
		if not children[i] is Label:
			continue
		var any_visible := false
		for j in range(i + 1, children.size()):
			if children[j] is Label:
				break
			any_visible = any_visible or children[j].visible
		children[i].visible = any_visible


func _focus_first() -> void:
	for child in _rows.get_children():
		if child is SettingRow and child.visible:
			child.grab_focus()
			break
	# Список только что собран — с самого верха, чтобы был виден
	# заголовок первой категории. Ждём кадр: до этого у строк нет размеров.
	await get_tree().process_frame
	_scroll.scroll_vertical = 0


# B закрывает окно. Ловим в _input — раньше меню паузы, которое
# на B вернулось бы в игру.
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
