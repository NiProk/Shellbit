class_name CheatsPanel
extends Control
## «Читы» — окно поверх меню паузы (открывается кнопкой «Читы»).
##
##   Читы · Contra
##   [ Добавить свой код…                       ]
##   [ Скачать базу читов                 37 МБ ]   ← пока базы нет
##   Contra (USA)
##   [ Infinite Lives                     (o  ) ]   ← A — включить/выключить
##   [ Totally Invincible P1              (  o) ]
##   Contra (USA) (Game Genie)
##   …
##
## Само окно ядро не трогает: оно сообщает Player'у сигналом changed,
## а тот заново передаёт ядру все включённые коды (Player._apply_cheats).
## Что включено — запоминает autoload Cheats.

## Включили или выключили чит, добавили или удалили свой код.
signal changed
signal closed

const ButtonHintsScene := preload("res://scenes/components/ButtonHints.tscn")
## Сколько секунд ждать второго нажатия X, чтобы удалить свой код.
const DELETE_CONFIRM_TIME := 3.0

var _game: Dictionary = {}
var _title: Label
var _note: Label
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _info: Label
var _hints: Control
var _download_row: SettingRow

# Окно ввода своего кода: поле и экранная клавиатура.
var _editor: Control
var _editor_title: Label
var _field: LineEdit
var _keyboard: ScreenKeyboard
var _new_code := ""  # код, набранный на первом шаге (второй шаг — название)

var _delete_armed := ""      # код, для которого уже нажали X один раз
var _delete_armed_at := 0.0


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
	panel.offset_left = 120
	panel.offset_right = -120
	panel.offset_top = 36
	panel.offset_bottom = -76

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_title)

	_note = Label.new()
	_note.theme_type_variation = &"DimLabel"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_note)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Прокручиваем сами (UiTheme.scroll_into_view) — с запасом под свечение рамки.
	_scroll.follow_focus = false
	column.add_child(_scroll)

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	_scroll.add_child(pad)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	pad.add_child(_rows)

	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size.y = 56  # две строки: список над ним не «прыгает»
	_info.max_lines_visible = 2
	_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_info.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	column.add_child(_info)

	_hints = ButtonHintsScene.instantiate()
	add_child(_hints)

	_build_editor()

	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	Cheats.download_progress.connect(_on_download_progress)
	Cheats.download_finished.connect(_on_download_finished)


## Показать читы игры. module_ok = false — модуль shellbit_core старый,
## без читов (его нужно пересобрать: native\build.bat).
func open(game: Dictionary, module_ok := true) -> void:
	_game = game
	_title.text = tr("Читы") + " · " + String(game.get("title", ""))
	if module_ok:
		_note.text = tr("Включённый чит работает сразу. Если игра повела себя странно — выключите его или загрузите сохранение.")
	else:
		var script := "native\\build.bat" if OS.get_name() == "Windows" else "native/build.sh"
		_note.text = tr("Модуль Shellbit устарел и не умеет читы. Закройте программу и запустите %s — коды можно выбрать уже сейчас, заработают после пересборки.") % script
	_rebuild()
	visible = true
	_focus_first.call_deferred()


func close() -> void:
	_close_editor()
	visible = false
	closed.emit()


# =====================================================================
# Список
# =====================================================================

func _rebuild(focus_code := "") -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()

	var add := _action("Добавить свой код…", "", "Набрать код из журнала или с сайта: Game Genie, Action Replay, GameShark…")
	add.pressed.connect(_start_editor)

	_download_row = null
	if not Cheats.has_database():
		_download_row = _action("Скачать базу читов", tr("≈ 37 МБ"),
				"Тысячи готовых кодов от libretro: NES, SNES, Mega Drive, PlayStation и другие приставки. Скачивается один раз.")
		_download_row.pressed.connect(_download)
		if Cheats.is_downloading():
			_download_row.info_text = tr("Скачивается…")

	var entries := Cheats.entries(_game)
	var source := "—"  # такой группы не бывает: первый заголовок появится всегда
	var focus_row: Control = null
	for entry: Dictionary in entries:
		if entry["source"] != source:
			source = entry["source"]
			var header := Label.new()
			header.text = tr("Свои коды") if source == Cheats.CUSTOM else source
			header.theme_type_variation = &"CardTitleLabel"
			header.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			header.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # имя файла базы — не переводим
			_rows.add_child(header)
		var row := CheatRow.new()
		row.entry = entry
		_rows.add_child(row)
		row.pressed.connect(_toggle.bind(row))
		if entry["code"] == focus_code:
			focus_row = row

	if entries.is_empty() and Cheats.has_database():
		var empty := Label.new()
		empty.theme_type_variation = &"DimLabel"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.text = tr("В базе нет читов для этой игры. Можно добавить свой код.")
		_rows.add_child(empty)

	if focus_row != null:
		focus_row.grab_focus.call_deferred()


func _action(title: String, info: String, description: String) -> SettingRow:
	var row := SettingRow.new()
	row.kind = SettingRow.Kind.ACTION
	row.title = title
	row.info_text = info
	row.description = description
	_rows.add_child(row)
	return row


func _toggle(row: CheatRow) -> void:
	var on := not bool(row.entry["on"])
	row.entry["on"] = on
	row.refresh()
	Cheats.set_enabled(_game, row.entry["code"], on)
	UiSounds.play_click()
	changed.emit()


func _focus_first() -> void:
	for child in _rows.get_children():
		if child is Button:
			child.grab_focus()
			break
	await get_tree().process_frame
	_scroll.scroll_vertical = 0


func _on_focus_changed(item: Control) -> void:
	if not visible or not _rows.is_ancestor_of(item):
		return
	UiTheme.scroll_into_view(_scroll, item)
	_update_info(item)


# Внизу — подробности о выделенной строке, а в подсказках — что можно сделать.
func _update_info(item: Control) -> void:
	var hints := [["accept", "Выбрать"], ["cancel", "Назад"]]
	if item is CheatRow:
		var entry: Dictionary = item.entry
		_info.text = tr("Код: %s") % entry["code"]
		hints = [["accept", "Вкл / выкл"], ["cancel", "Назад"]]
		if entry["custom"]:
			hints.insert(1, ["details", "Удалить"])
	elif item is SettingRow:
		_info.text = tr(item.description)
	_hints.set_hints(hints)


# =====================================================================
# База читов
# =====================================================================

func _download() -> void:
	if Cheats.is_downloading():
		return
	_download_row.info_text = tr("Скачивается…")
	_download_row.refresh()
	Cheats.download_database()


func _on_download_progress(percent: int) -> void:
	if _download_row != null and is_instance_valid(_download_row):
		_download_row.info_text = tr("Скачивается… %d %%") % percent
		_download_row.refresh()


func _on_download_finished(ok: bool, message: String) -> void:
	if not ok:
		SceneRouter.toast(message)
		if _download_row != null and is_instance_valid(_download_row):
			_download_row.info_text = tr("≈ 37 МБ")
			_download_row.refresh()
		return
	SceneRouter.toast(tr("База читов скачана"))
	if visible:
		_rebuild()
		_focus_first.call_deferred()


# =====================================================================
# Свой код: шаг 1 — код, шаг 2 — название
# =====================================================================

func _build_editor() -> void:
	_editor = Control.new()
	_editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_editor.mouse_filter = Control.MOUSE_FILTER_STOP
	_editor.z_index = 9  # над окном; клавиатура внутри — ещё выше
	_editor.visible = false
	add_child(_editor)
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BG, 0.97)  # почти непрозрачно: текст окна под полем не просвечивает
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_editor.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_editor.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.offset_top = 48
	_editor_title = Label.new()
	_editor_title.theme_type_variation = &"HeaderLabel"
	_editor_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_editor_title)
	_field = LineEdit.new()
	_field.custom_minimum_size = Vector2(520, 52)
	_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_field.add_theme_font_size_override("font_size", 24)
	_field.focus_mode = Control.FOCUS_NONE  # печатает экранная клавиатура
	column.add_child(_field)

	_keyboard = ScreenKeyboard.new()
	_editor.add_child(_keyboard)
	_keyboard.closed.connect(_on_keyboard_closed)


func _start_editor() -> void:
	_new_code = ""
	_editor_title.text = tr("Код чита")
	_field.text = ""
	_field.max_length = 80
	_keyboard.code_mode = true
	_keyboard.done_text = "Дальше"
	_editor.visible = true
	_keyboard.open(_field)


func _on_keyboard_closed() -> void:
	if _new_code == "":
		# Закрыли первый шаг. Пусто — передумали; иначе — к названию.
		var code := Cheats.normalize_code(_field.text)
		if code == "":
			_close_editor()
			return
		_new_code = code
		_editor_title.text = tr("Название чита (можно пропустить)")
		_field.text = ""
		_field.max_length = 40
		_keyboard.code_mode = false
		_keyboard.done_text = "Сохранить"
		_keyboard.open.call_deferred(_field)  # в следующем кадре: клавиатура ещё закрывается
		return
	var code := _new_code
	if Cheats.add_custom(_game, _field.text, code):
		changed.emit()
	else:
		SceneRouter.toast(tr("Такой код уже есть"))
	_close_editor()
	_rebuild(code)


func _close_editor() -> void:
	_new_code = ""
	_editor.visible = false
	if _keyboard.visible:
		_keyboard.visible = false
	if visible and get_viewport().gui_get_focus_owner() == null:
		_focus_first.call_deferred()


# =====================================================================
# Кнопки
# =====================================================================

# Ловим в _input — раньше меню паузы, которое на B вернулось бы в игру.
func _input(event: InputEvent) -> void:
	if not visible or _editor.visible:
		return  # пока вводят код, кнопками командует клавиатура
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("game_menu"):
		close()
	elif event.is_action_pressed("details"):
		var focused := get_viewport().gui_get_focus_owner()
		if focused is CheatRow and focused.entry["custom"]:
			_delete(focused.entry["code"])
		else:
			return
	else:
		return
	get_viewport().set_input_as_handled()


# Удалить свой код — по второму нажатию X, чтобы не стереть случайно.
func _delete(code: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _delete_armed != code or now - _delete_armed_at > DELETE_CONFIRM_TIME:
		_delete_armed = code
		_delete_armed_at = now
		Haptics.confirm()
		SceneRouter.toast(tr("Нажмите ещё раз, чтобы удалить код"))
		return
	_delete_armed = ""
	Cheats.remove_custom(_game, code)
	changed.emit()
	_rebuild()
	_focus_first.call_deferred()


# =====================================================================
# Строка чита: название слева, переключатель справа
# =====================================================================

class CheatRow extends Button:
	## {"name", "code", "source", "on", "custom"} — из Cheats.entries().
	var entry: Dictionary = {}
	var _switch: SettingRow.SwitchIcon

	func _ready() -> void:
		custom_minimum_size.y = 56
		focus_mode = Control.FOCUS_ALL
		for state in ["normal", "hover", "pressed"]:
			var box := StyleBoxFlat.new()
			box.bg_color = UiTheme.CARD if state == "normal" else UiTheme.CARD_HOVER
			box.set_corner_radius_all(14)
			add_theme_stylebox_override(state, box)
		mouse_entered.connect(grab_focus)

		var margin := MarginContainer.new()
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_theme_constant_override("margin_left", 22)
		margin.add_theme_constant_override("margin_right", 22)
		add_child(margin)
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 12)
		margin.add_child(row)

		var label := Label.new()
		label.text = entry["name"]  # названия из базы — по-английски, как есть
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.add_theme_font_size_override("font_size", 18)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(label)

		_switch = SettingRow.SwitchIcon.new()
		_switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(_switch)
		refresh()

	func refresh() -> void:
		if _switch != null:
			_switch.on = bool(entry["on"])
			_switch.queue_redraw()
