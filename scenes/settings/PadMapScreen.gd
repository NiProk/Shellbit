extends Control
## Экран «Кнопки приставок»: своя раскладка кнопок для каждой приставки.
##
## Слева — кнопки приставки и какая кнопка вашего геймпада их нажимает.
## Справа — два рисунка: геймпад приставки и ваш геймпад. Выбранная
## кнопка подсвечена на обоих, поэтому сразу видно, где она.
##
## Открывается так: SceneRouter.go_to("pad_map", {"system": "snes"})
##
## Управление:
##   ▲▼     — кнопка приставки
##   ◀ ▶    — перебрать кнопки геймпада
##   A      — «Нажмите кнопку…»: следующая нажатая кнопка геймпада
##            станет этой кнопкой приставки
##   LB RB  — другая приставка
##   B      — назад

## Сколько ждать нажатия, прежде чем отменить назначение.
const LISTEN_SECONDS := 5.0

var _system_id := ""
var _systems: Array[String] = []   # приставки, у которых есть описание геймпада
var _rows: Array[Button] = []      # строки с кнопками приставки (без нижних строк-действий)

# Ожидание нажатия: какую кнопку приставки назначаем ("" — не ждём).
var _listening := ""
var _listen_started := 0
var _listen_timer: Timer
var _building := false   # сейчас пересобираем строки


func _ready() -> void:
	# Берём приставки в том же порядке, что и в systems.json.
	for system: Dictionary in CoreManager.systems:
		if InputMapper.pads.has(system["id"]):
			_systems.append(system["id"])

	_listen_timer = Timer.new()
	_listen_timer.one_shot = true
	_listen_timer.wait_time = LISTEN_SECONDS
	_listen_timer.timeout.connect(_stop_listening)
	add_child(_listen_timer)

	# Сменился геймпад (Xbox ↔ PlayStation) — подписи кнопок другие.
	InputMapper.style_changed.connect(_on_style_changed)

	var start: String = SceneRouter.params.get("system", "")
	if not _systems.has(start):
		# Не сказали, какую, — первую приставку, в которую есть игры.
		var with_games := Library.systems_with_games()
		start = with_games[0] if not with_games.is_empty() and _systems.has(with_games[0]) else _systems[0]
	_show_system(start)


# =====================================================================
# Приставка
# =====================================================================

func _show_system(system_id: String, focus_index := 0) -> void:
	_stop_listening()
	_system_id = system_id
	var system := CoreManager.get_system(system_id)
	%Strip.color = Color(system.get("color", "#888888"))
	%SystemName.text = tr(system.get("name", system_id))
	%ConsoleCaption.text = tr("Геймпад %s") % system.get("short", system_id)
	_update_modern_caption()
	_build_rows()
	var all_rows := %Rows.get_children()
	all_rows[clampi(focus_index, 0, all_rows.size() - 1)].grab_focus.call_deferred()


func _next_system(step: int) -> void:
	# Остаёмся на той же по счёту строке — удобно сравнивать приставки.
	var focused := get_viewport().gui_get_focus_owner()
	var index: int = focused.get_index() if focused and focused.get_parent() == %Rows else 0
	var position := wrapi(_systems.find(_system_id) + step, 0, _systems.size())
	_show_system(_systems[position], index)


func _update_modern_caption() -> void:
	var names := {"xbox": "Xbox", "playstation": "PlayStation", "keyboard": "Xbox"}
	%ModernCaption.text = tr("Ваш геймпад (%s)") % names.get(InputMapper.style, "Xbox")


func _on_style_changed(_style: String) -> void:
	_update_modern_caption()
	_refresh()


# =====================================================================
# Строки
# =====================================================================

func _build_rows() -> void:
	# Старые строки убираем. Если одна из них была в фокусе, Godot сообщит
	# focus_exited прямо во время удаления, и _refresh() увидит строки прошлой
	# приставки. _building говорит ему: «подожди, пока соберём новые».
	_building = true
	for child in %Rows.get_children():
		%Rows.remove_child(child)
		child.queue_free()
	_rows.clear()

	for button: Dictionary in InputMapper.pads[_system_id]["buttons"]:
		var row := _new_row()
		row.set_meta("button", button)  # meta — своя пометка на узле
		row.pressed.connect(_start_listening.bind(button["id"]))
		_rows.append(row)

	# Готовые раскладки — только если у приставки есть кнопки с надписями,
	# как у Xbox (A, B, X, Y). У Mega Drive или PlayStation такого нет.
	if InputMapper.has_label_preset(_system_id):
		var preset := _new_row()
		preset.set_meta("action", "preset")
		preset.pressed.connect(_change_preset.bind(1))
	var reset := _new_row()
	reset.set_meta("action", "reset")
	reset.pressed.connect(_reset)

	# Соседи по фокусу: вверх/вниз — по строкам, влево/вправо — никуда
	# (стрелками ◀ ▶ строка меняет значение сама, см. _on_row_input).
	var all_rows := %Rows.get_children()
	for i in all_rows.size():
		var row: Button = all_rows[i]
		row.focus_neighbor_top = row.get_path_to(all_rows[maxi(i - 1, 0)])
		row.focus_neighbor_bottom = row.get_path_to(all_rows[mini(i + 1, all_rows.size() - 1)])
		row.focus_neighbor_left = row.get_path_to(row)
		row.focus_neighbor_right = row.get_path_to(row)
	_building = false
	_refresh()


# Строка: [значок кнопки приставки] ........ ‹ кнопка геймпада ›
func _new_row() -> Button:
	var row := Button.new()
	row.custom_minimum_size.y = 54
	# Свой текст у строки не нужен — всё внутри. А «Button.text» по умолчанию
	# пустой, так что переводить нечего.
	%Rows.add_child(row)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	row.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 10)
	margin.add_child(line)

	var chip := Label.new()            # значок кнопки приставки
	chip.name = "Chip"
	chip.custom_minimum_size = Vector2(36, 32)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_theme_font_size_override("font_size", 17)
	line.add_child(chip)

	var title := Label.new()           # название (для строк-действий)
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(title)

	var value := Label.new()           # кнопка геймпада: ‹ A ›
	value.name = "Value"
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	value.add_theme_font_size_override("font_size", 19)
	line.add_child(value)

	# Мышь и геймпад работают одинаково: навели мышью — строка в фокусе.
	row.mouse_entered.connect(row.grab_focus)
	row.focus_entered.connect(_on_row_focused.bind(row))
	row.focus_exited.connect(_refresh)
	row.gui_input.connect(_on_row_input.bind(row))
	return row


## Обновить надписи всех строк и рисунки.
func _refresh() -> void:
	if _building:
		return
	var mapping := InputMapper.get_mapping(_system_id)
	var focused := get_viewport().gui_get_focus_owner()

	for row: Button in %Rows.get_children():
		if row.is_queued_for_deletion():
			continue
		var chip: Label = row.find_child("Chip", true, false)
		var title: Label = row.find_child("Title", true, false)
		var value: Label = row.find_child("Value", true, false)
		var arrows := row == focused and _listening == ""

		if row.has_meta("button"):
			var button: Dictionary = row.get_meta("button")
			var physical: String = mapping[button["id"]]
			chip.visible = true
			chip.text = button["label"]
			chip.add_theme_color_override("font_color", Color(button.get("text_color", "#ffffff")))
			chip.add_theme_stylebox_override("normal", UiTheme.badge_box(Color(button["color"])))
			title.text = ""
			if _listening == button["id"]:
				value.text = tr("Нажмите кнопку…")
				value.add_theme_color_override("font_color", UiTheme.ACCENT)
			else:
				var glyph := InputMapper.glyph(physical)
				value.text = ("‹  %s  ›" % glyph) if arrows else glyph
				var color := InputMapper.glyph_color(physical) if physical != "" else UiTheme.TEXT_DIM
				value.add_theme_color_override("font_color", color)
		else:
			chip.visible = false
			value.add_theme_color_override("font_color", UiTheme.TEXT if arrows else UiTheme.TEXT_DIM)
			if row.get_meta("action") == "preset":
				title.text = tr("Раскладка кнопок")
				var names := {"default": "По положению", "by_label": "По надписям", "custom": "Своя"}
				var text := tr(names[InputMapper.current_preset(_system_id)])
				value.text = ("‹  %s  ›" % text) if arrows else text
			else:
				title.text = tr("Вернуть обычную раскладку")
				value.text = ""

	# Подсветка на рисунках — у выбранной строки.
	var highlight := ""
	if focused is Button and focused.has_meta("button"):
		highlight = focused.get_meta("button")["id"]
	if _listening != "":
		highlight = _listening
	%ConsolePad.show_pad(_system_id, mapping, highlight)
	%ModernPad.show_pad(_system_id, mapping, highlight)


func _on_row_focused(row: Button) -> void:
	_refresh()
	%Note.text = _note_for(row)
	if row.has_meta("button"):
		%Hints.set_hints([["accept", "Назначить"], ["change", "Изменить"], ["page", "Другая приставка"], ["cancel", "Назад"]])
	elif row.get_meta("action") == "preset":
		%Hints.set_hints([["change", "Изменить"], ["page", "Другая приставка"], ["cancel", "Назад"]])
	else:
		%Hints.set_hints([["accept", "Выбрать"], ["page", "Другая приставка"], ["cancel", "Назад"]])


# Подсказка под рисунками.
func _note_for(row: Button) -> String:
	var lines := PackedStringArray()
	if row.has_meta("button"):
		var button: Dictionary = row.get_meta("button")
		var physical: String = InputMapper.get_mapping(_system_id)[button["id"]]
		if physical == "":
			lines.append(tr("Кнопка «%s» не назначена.") % button["label"])
		else:
			lines.append(tr("Кнопка «%s» — это %s на вашем геймпаде.") % [button["label"], InputMapper.glyph(physical)])
		lines.append(tr("«Назначить» — и нажмите нужную кнопку на геймпаде. ◀ ▶ — выбрать из списка. Если кнопка уже занята, они поменяются местами."))
	elif row.get_meta("action") == "preset":
		lines.append(tr("По положению — кнопки стоят там же, где на геймпаде приставки. По надписям — A на A, B на B."))
	else:
		lines.append(tr("Раскладка по положению кнопок — как была с самого начала."))
	var note: String = InputMapper.pads[_system_id].get("note", "")
	if note != "":
		lines.append(tr(note))
	elif InputMapper.style == "keyboard":
		lines.append(tr("Клавиатура: стрелки, Z X A S Q W, Enter — Start, Shift — Select."))
	return "\n".join(lines)


# _gui_input строки: ◀ ▶ меняют значение, а не переводят фокус.
func _on_row_input(event: InputEvent, row: Button) -> void:
	if _listening != "":
		return
	var step := 0
	if event.is_action_pressed("ui_left", true):
		step = -1
	elif event.is_action_pressed("ui_right", true):
		step = 1
	if step == 0:
		return
	row.accept_event()
	if row.has_meta("button"):
		var button_id: String = row.get_meta("button")["id"]
		var current: String = InputMapper.get_mapping(_system_id)[button_id]
		var index := wrapi(InputMapper.PHYSICAL.find(current) + step, 0, InputMapper.PHYSICAL.size())
		InputMapper.assign(_system_id, button_id, InputMapper.PHYSICAL[index])
		_after_change(row)
	elif row.get_meta("action") == "preset":
		_change_preset(step)


func _after_change(row: Button) -> void:
	UiSounds.play_click()
	_refresh()
	%Note.text = _note_for(row)


# Переключить «По положению» ↔ «По надписям».
func _change_preset(_step: int) -> void:
	var preset := "by_label" if InputMapper.current_preset(_system_id) == "default" else "default"
	InputMapper.set_mapping(_system_id, InputMapper.preset_mapping(_system_id, preset))
	_after_change(get_viewport().gui_get_focus_owner())


func _reset() -> void:
	InputMapper.set_mapping(_system_id, InputMapper.preset_mapping(_system_id))
	SceneRouter.toast(tr("Обычная раскладка для %s") % CoreManager.get_system(_system_id).get("short", ""))
	_after_change(get_viewport().gui_get_focus_owner())


# =====================================================================
# «Нажмите кнопку…»
# =====================================================================

func _start_listening(button_id: String) -> void:
	_listening = button_id
	_listen_started = Time.get_ticks_msec()
	_listen_timer.start()
	%Hints.set_hints([])
	%Note.text = tr("Нажмите на геймпаде кнопку для «%s». Через 5 секунд или по Esc — отмена.") \
			% _label_of(button_id)
	_refresh()


# Надпись кнопки приставки по её id: "b" → "B", "cross" → "✕".
func _label_of(button_id: String) -> String:
	for button: Dictionary in InputMapper.pads[_system_id]["buttons"]:
		if button["id"] == button_id:
			return button["label"]
	return button_id


func _stop_listening() -> void:
	if _listening == "":
		return
	_listening = ""
	_listen_timer.stop()
	var focused := get_viewport().gui_get_focus_owner()
	if focused is Button:
		_on_row_focused(focused)


# _input получает нажатия раньше всех: пока ждём кнопку, забираем
# ВСЕ нажатия себе — иначе B вернул бы на прошлый экран, а LB сменил бы
# приставку, хотя человек как раз хотел назначить эту кнопку.
func _input(event: InputEvent) -> void:
	if _listening == "" or not event.is_pressed():
		return
	get_viewport().set_input_as_handled()
	# Нажатие A, которым начали ждать, ещё может «долететь» — пропускаем.
	if Time.get_ticks_msec() - _listen_started < 200:
		return
	var physical := InputMapper.physical_from_event(event)
	if physical != "":
		var button_id := _listening
		_listening = ""
		_listen_timer.stop()
		InputMapper.assign(_system_id, button_id, physical)
		_after_change(get_viewport().gui_get_focus_owner())
		_on_row_focused(get_viewport().gui_get_focus_owner())
	elif event is InputEventKey or event is InputEventMouseButton:
		_stop_listening()  # клавиатуру и мышь не назначаем — это отмена


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneRouter.back()
	elif event.is_action_pressed("page_left"):
		_next_system(-1)
	elif event.is_action_pressed("page_right"):
		_next_system(1)
	else:
		return
	get_viewport().set_input_as_handled()
