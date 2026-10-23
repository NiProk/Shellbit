extends Control
## Экран настроек: слева разделы, посередине строки настроек,
## справа предпросмотр и описание выбранной строки.
##
## Открывается так: SceneRouter.go_to("settings")
## Можно сразу открыть нужный раздел: SceneRouter.go_to("settings", {"page": "video"})
##
## Управление:
##   в разделах:  ▲▼ — раздел, A или ▶ — перейти к настройкам, B — выйти;
##   в настройках: ▲▼ — строка, ◀▶ — изменить, A — выбрать, B — к разделам.

const CRT_SHADER := preload("res://scenes/player/crt.gdshader")
const LCD_SHADER := preload("res://scenes/player/lcd.gdshader")

## Разделы. id — для кода, title — для экрана, about — описание раздела.
## title и about пишем по-русски, а переводим (tr) там, где показываем:
## в const вызывать функции нельзя.
const PAGES := [
	{"id": "folders", "title": "Папки с играми",
		"about": "Где Shellbit ищет игры. Файлы на диске он не меняет."},
	{"id": "controls", "title": "Управление",
		"about": "Геймпады, клавиатура и кнопки меню."},
	{"id": "play", "title": "Игра",
		"about": "Ускорение и перемотка назад во время игры."},
	{"id": "video", "title": "Видео",
		"about": "Как выглядит картинка во время игры."},
	{"id": "audio", "title": "Звук",
		"about": "Громкость приложения и игр."},
	{"id": "language", "title": "Язык",
		"about": "Язык интерфейса Shellbit."},
	{"id": "cores", "title": "Ядра и BIOS",
		"about": "Ядро — это эмулятор одной приставки. Здесь видно, каких ядер не хватает."},
	{"id": "about", "title": "О программе",
		"about": "Версия и полезные папки."},
]

var _page := ""  # id открытого раздела
var _dropdown: DropdownList  # выпадающий список языков (создаётся при первом открытии)
var _core_rows := {}  # файл ядра → строки, где показываем, как оно качается


func _ready() -> void:
	_build_categories()
	%FolderDialog.dir_selected.connect(_on_folder_selected)
	# Если геймпад подключили, пока открыт раздел «Управление», — обновим список.
	# Подключаем обычную функцию, а не лямбду: когда экран закроется,
	# Godot сам отключит её от сигнала.
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	# Скачивание ядер: проценты в строках и сообщение, когда готово.
	CoreDownloader.progress.connect(_on_core_progress)
	CoreDownloader.finished.connect(_on_core_finished)

	%Preview.texture = _preview_texture()

	var start: String = SceneRouter.params.get("page", "video")
	_show_page(start)
	_category_button(start).grab_focus.call_deferred()
	# После смены языка экран открывается заново — сразу на строке языка.
	if SceneRouter.params.get("rows", false):
		_enter_rows.call_deferred(SceneRouter.params.get("row", 0))


# =====================================================================
# Разделы (левая колонка)
# =====================================================================

func _build_categories() -> void:
	for page: Dictionary in PAGES:
		var button := Button.new()
		button.text = tr(page["title"])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 56
		button.set_meta("page", page["id"])  # meta — свои пометки на узле
		%Categories.add_child(button)

		# Перешли на раздел (стрелкой или мышью) — сразу показываем его строки.
		button.focus_entered.connect(_on_category_focused.bind(page["id"]))
		button.mouse_entered.connect(button.grab_focus)
		button.pressed.connect(_enter_rows)
		button.gui_input.connect(_on_category_input.bind(button))

	# Соседи по фокусу: вверх/вниз — только по разделам, влево — никуда.
	# Без этого Godot сам ищет ближайшую кнопку и может «прыгнуть» не туда.
	var buttons := %Categories.get_children()
	for i in buttons.size():
		var button: Button = buttons[i]
		button.focus_neighbor_top = button.get_path_to(buttons[maxi(i - 1, 0)])
		button.focus_neighbor_bottom = button.get_path_to(buttons[mini(i + 1, buttons.size() - 1)])
		button.focus_neighbor_left = button.get_path_to(button)


func _on_category_input(event: InputEvent, button: Button) -> void:
	# ▶ на разделе — перейти к его настройкам.
	if event.is_action_pressed("ui_right"):
		_enter_rows()
		button.accept_event()


func _on_category_focused(id: String) -> void:
	_show_page(id)
	%Description.text = tr(_page_info(id)["about"])
	%Hints.set_hints([["accept", tr("Выбрать")], ["cancel", tr("Назад")]])


func _category_button(id: String) -> Button:
	for button: Button in %Categories.get_children():
		if button.get_meta("page") == id:
			return button
	return %Categories.get_child(0)


func _page_info(id: String) -> Dictionary:
	for page: Dictionary in PAGES:
		if page["id"] == id:
			return page
	return PAGES[0]


## Открытый раздел подсвечен: фон карточки и бирюзовая полоска слева.
func _style_categories() -> void:
	for button: Button in %Categories.get_children():
		var selected: bool = button.get_meta("page") == _page
		for state in ["normal", "hover", "pressed"]:
			var box := StyleBoxFlat.new()
			box.set_corner_radius_all(12)
			box.content_margin_left = 24
			box.content_margin_right = 16
			if selected:
				box.bg_color = UiTheme.CARD_HOVER if state == "hover" else UiTheme.CARD
				box.border_width_left = 4
				box.border_color = UiTheme.ACCENT
			else:
				# Прозрачный фон; при наведении мышью — едва заметный.
				box.bg_color = Color(UiTheme.CARD, 0.5) if state == "hover" else Color(0, 0, 0, 0)
			button.add_theme_stylebox_override(state, box)
		var text_color := UiTheme.TEXT if selected else UiTheme.TEXT_DIM
		button.add_theme_color_override("font_color", text_color)
		button.add_theme_color_override("font_hover_color", UiTheme.TEXT)
		button.add_theme_color_override("font_focus_color", UiTheme.TEXT)


# =====================================================================
# Строки настроек (средняя колонка)
# =====================================================================

func _show_page(id: String) -> void:
	if id == _page:
		return
	_page = id
	_style_categories()

	# Убираем строки прошлого раздела.
	for child in %Rows.get_children():
		%Rows.remove_child(child)
		child.queue_free()

	match id:
		"folders": _build_folders()
		"controls": _build_controls()
		"play": _build_play()
		"video": _build_video()
		"audio": _build_audio()
		"language": _build_language()
		"cores": _build_cores()
		"about": _build_about()

	_link_rows()
	# Предпросмотр нужен только в разделе «Видео».
	%PreviewBox.visible = id == "video"
	# В «О программе» вместо предпросмотра — радостный Пип.
	%AboutPip.visible = id == "about"
	_update_preview()


## Пересобрать текущий раздел (например, после добавления папки).
func _rebuild_page() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	var was_in_rows := focused is SettingRow
	var index := focused.get_index() if was_in_rows else 0  # остаться на той же строке
	var id := _page
	_page = ""  # иначе _show_page решит, что раздел уже открыт
	_show_page(id)
	if was_in_rows:
		_enter_rows.call_deferred(index)


## Перейти из разделов к строкам (index — на какую строку встать).
func _enter_rows(index := 0) -> void:
	if %Rows.get_child_count() > 0:
		%Rows.get_child(mini(index, %Rows.get_child_count() - 1)).grab_focus()


# Соседи по фокусу для строк: вверх/вниз — по строкам, влево — к разделу.
func _link_rows() -> void:
	var rows := %Rows.get_children()
	var category := _category_button(_page)
	for i in rows.size():
		var row: SettingRow = rows[i]
		row.focus_neighbor_top = row.get_path_to(rows[maxi(i - 1, 0)])
		row.focus_neighbor_bottom = row.get_path_to(rows[mini(i + 1, rows.size() - 1)])
		row.focus_neighbor_left = row.get_path_to(category)
		row.focus_neighbor_right = row.get_path_to(row)


func _on_row_focused(row: SettingRow) -> void:
	%Description.text = row.current_description()
	match row.kind:
		SettingRow.Kind.CHOICE, SettingRow.Kind.TOGGLE:
			%Hints.set_hints([["change", tr("Изменить")], ["accept", tr("Выбрать")], ["cancel", tr("Назад")]])
		SettingRow.Kind.ACTION:
			%Hints.set_hints([["accept", tr("Выбрать")], ["cancel", tr("Назад")]])
		_:
			%Hints.set_hints([["cancel", tr("Назад")]])


# --- Помощники: создать строку нужного вида -------------------------------
# Свойства задаём до add_child() — строка собирает себя в _ready().

func _add(row: SettingRow) -> SettingRow:
	%Rows.add_child(row)
	row.focus_entered.connect(_on_row_focused.bind(row))
	return row


func _choice(title: String, section: String, key: String, options: Array,
		description := "", wrap := true) -> SettingRow:
	var row := SettingRow.new()
	row.kind = SettingRow.Kind.CHOICE
	row.title = title
	row.section = section
	row.key = key
	row.options = options
	row.description = description
	row.wrap = wrap
	_add(row)
	# Поменяли значение — обновить описание справа (у вариантов оно своё).
	row.value_changed.connect(func(_value: Variant) -> void:
		%Description.text = row.current_description())
	return row


func _toggle(title: String, section: String, key: String, description: String) -> SettingRow:
	var row := SettingRow.new()
	row.kind = SettingRow.Kind.TOGGLE
	row.title = title
	row.section = section
	row.key = key
	row.description = description
	return _add(row)


func _action(title: String, value: String, description: String, callback: Callable) -> SettingRow:
	var row := SettingRow.new()
	row.kind = SettingRow.Kind.ACTION
	row.title = title
	row.info_text = value
	row.description = description
	_add(row)
	if callback.is_valid():  # пустой Callable() — обработчик подключат отдельно
		row.pressed.connect(callback)
	return row


func _info(title: String, value: String, description: String, warn := false) -> SettingRow:
	var row := SettingRow.new()
	row.kind = SettingRow.Kind.INFO
	row.title = title
	row.info_text = value
	row.description = description
	row.warn = warn
	return _add(row)


# =====================================================================
# Содержимое разделов
# =====================================================================

func _build_folders() -> void:
	_action("+ Добавить папку…", "", "Выберите папку с играми. Shellbit найдёт игры и во вложенных папках.",
			func() -> void: %FolderDialog.popup_centered_ratio(0.7))
	_action("Обновить список игр", Library.count_text(Library.groups.size()),
			tr("Заново просмотреть все папки — если вы добавили или удалили игры."),
			_rescan)

	var folders := Settings.get_rom_folders()
	if folders.is_empty():
		_info("Папок пока нет", "", tr("Добавьте папку, в которой лежат ваши игры."))
	for path in folders:
		var row := _action(path.get_file() if path.get_file() != "" else path, tr("Убрать"),
				path + "\n\n" + tr("A — убрать папку из списка. Сами игры на диске останутся."),
				Callable())
		row.pressed.connect(_on_folder_row_pressed.bind(row, path))
		# Ушли со строки — отменяем «Нажмите ещё раз».
		row.focus_exited.connect(func() -> void:
			row.set_meta("armed", false)
			row.info_text = tr("Убрать")
			row.warn = false
			row.refresh())


# Убираем папку в два нажатия, чтобы не убрать случайно.
func _on_folder_row_pressed(row: SettingRow, path: String) -> void:
	if not row.get_meta("armed", false):
		row.set_meta("armed", true)
		row.info_text = tr("Нажмите ещё раз")
		row.warn = true
		row.refresh()
		return
	Settings.remove_rom_folder(path)
	Library.scan()
	SceneRouter.toast(tr("Папка убрана · %s") % Library.count_text(Library.groups.size()))
	_rebuild_page()


func _on_folder_selected(path: String) -> void:
	Settings.add_rom_folder(path)
	Library.scan()
	SceneRouter.toast(tr("Найдено: %s") % Library.count_text(Library.groups.size()))
	_rebuild_page()


func _rescan() -> void:
	Library.scan()
	SceneRouter.toast(tr("Список игр обновлён: %s") % Library.count_text(Library.groups.size()))
	_rebuild_page()


func _build_controls() -> void:
	var style_names := {
		"xbox": tr("Геймпад Xbox"),
		"playstation": tr("Геймпад PlayStation"),
		"keyboard": tr("Клавиатура"),
	}
	_info("Сейчас управление", style_names.get(InputMapper.style, "?"),
			tr("Shellbit сам замечает, чем вы пользуетесь, и меняет значки в подсказках внизу."))

	var pads := Input.get_connected_joypads()
	var names := PackedStringArray()
	for i in pads.size():
		names.append(tr("Игрок %d: %s") % [i + 1, Input.get_joy_name(pads[i])])
	_info("Подключённые геймпады", tr("нет") if pads.is_empty() else str(pads.size()),
			"\n".join(names) if not pads.is_empty() else tr("Подключите геймпад — он появится здесь."))

	_info("Меню паузы в игре", "R3 · Select+Start · Esc",
			tr("Нажмите правый стик, Select и Start вместе или Esc на клавиатуре."))
	_info("Скриншот", "F12 · Share",
			tr("Кнопка Share («Поделиться») есть на геймпадах Xbox Series и PlayStation 5. На других геймпадах — пункт «Скриншот» в меню паузы."))
	_info("Перемотка и ускорение", "%s · %s" % [InputMapper.glyph("lt"), InputMapper.glyph("rt")],
			_hotkeys_text())
	var pad_row := _action("Кнопки приставок", "",
			tr("Своя раскладка для каждой приставки: какая кнопка вашего геймпада — это A, B или Start приставки. С рисунками геймпадов."),
			Callable())
	pad_row.pressed.connect(_open_pad_map.bind(pad_row))


## Как включать перемотку и ускорение. Подписи кнопок — под ваш геймпад:
## у Xbox это LT, RT и Back, у PlayStation — L2, R2 и Share.
func _hotkeys_text() -> String:
	var lt := InputMapper.glyph("lt")
	var rt := InputMapper.glyph("rt")
	var back := InputMapper.glyph(InputMapper.COMBO_MODIFIER)
	return tr("На геймпаде: %s — перемотка назад, %s — ускорение. У PlayStation и Nintendo 64 курки нужны самой игре — там зажмите %s и нажмите %s или %s. На клавиатуре — Backspace и пробел.") % [lt, rt, back, lt, rt]


# Открыть экран «Кнопки приставок». Запоминаем в параметрах этого экрана
# раздел и строку — по «Назад» настройки откроются ровно на ней.
func _open_pad_map(row: SettingRow) -> void:
	SceneRouter.params["page"] = _page
	SceneRouter.params["rows"] = true
	SceneRouter.params["row"] = row.get_index()
	SceneRouter.go_to("pad_map")


func _build_play() -> void:
	_choice("Ускорение", "play", "ff_speed", [
		[2, "×2"], [3, "×3"], [4, "×4"], [8, "×8"],
	], tr("Во сколько раз быстрее идёт игра, пока включено ускорение. Удобно, чтобы проскочить долгие диалоги и прогулки. Звук при этом прерывистый."), false)
	_choice("Кнопка ускорения", "play", "ff_mode", [
		["hold", tr("Держать"), tr("Игра ускоряется, пока кнопка зажата.")],
		["toggle", tr("Нажать один раз"),
			tr("Нажали — ускорение включилось, нажали ещё раз — выключилось.")],
	])
	var rewind_description := tr("Shellbit запоминает последние секунды игры. Пока держите кнопку перемотки, игра идёт назад — можно исправить ошибку. Чем длиннее запись, тем больше памяти она занимает (не больше %d МБ).") % Settings.REWIND_BUDGET_MB
	_choice("Перемотка назад", "play", "rewind_seconds", [
		[0, tr("Выключена"), tr("Перемотка выключена — игра не тратит на неё память.")],
		[10, tr("10 секунд"), rewind_description],
		[20, tr("20 секунд"), rewind_description],
		[30, tr("30 секунд"), rewind_description],
		[60, tr("1 минута"), rewind_description],
	], "", false)
	_toggle("Вибрация", "play", "rumble",
			tr("Геймпад вибрирует, когда этого хочет игра: удары, взрывы, мотор машины. Работает у PlayStation (игры с поддержкой DualShock) и у картриджей Game Boy и Game Boy Advance со встроенным моторчиком."))
	var pad_row := _action("Кнопки перемотки и ускорения", "",
			_hotkeys_text() + " " + tr("Поменять можно в «Кнопках приставок» для каждой приставки."),
			Callable())
	pad_row.pressed.connect(_open_pad_map.bind(pad_row))


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	if _page == "controls":
		_rebuild_page()


func _build_video() -> void:
	var window := _choice("Режим окна", "video", "window_mode", [
		["fullscreen", tr("Полный экран"),
			tr("Shellbit занимает весь экран, как настоящая приставка. F11 или Alt+Enter — переключить в окно.")],
		["windowed", tr("Окно"),
			tr("Shellbit открывается в обычном окне — его можно двигать и менять размер. F11 или Alt+Enter — во весь экран.")],
	])
	window.value_changed.connect(func(_value: Variant) -> void: Settings.apply_window_mode())
	var filter := _choice("Фильтр изображения", "video", "filter", [
		["none", tr("Чёткие пиксели"),
			tr("Каждый пиксель приставки — ровный квадрат. Так игры выглядят на современных экранах.")],
		["smooth", tr("Сглаживание"),
			tr("Сглаживает края пикселей. Картинка мягче, но немного размыта.")],
		["crt", tr("ЭЛТ-телевизор"),
			tr("Добавляет полосы развёртки и лёгкое скругление, как на старом телевизоре. Шейдер crt.gdshader.")],
		["lcd", tr("Сетка LCD"),
			tr("Тонкая сетка между пикселями, как на экране Game Boy. Хорошо подходит портативным приставкам. Шейдер lcd.gdshader.")],
	])
	filter.value_changed.connect(func(_value: Variant) -> void: _update_preview())

	_choice("Масштаб", "video", "scale", [
		["fit", tr("Во весь экран"),
			tr("Картинка занимает всю высоту экрана. Пиксели могут получиться чуть разного размера.")],
		["integer", tr("Целые пиксели"),
			tr("Каждый пиксель увеличен ровно в 2, 3, 4… раза — все одинаковые и ровные. Картинка может быть чуть меньше экрана.")],
	])
	_choice("Пропорции", "video", "aspect", [
		["core", tr("Как у приставки"),
			tr("Пропорции, которые сообщает эмулятор, — как картинка выглядела на телевизоре (обычно 4:3).")],
		["square", tr("Квадратные пиксели"),
			tr("Каждый пиксель квадратный. Картинка может стать чуть уже или шире, чем на телевизоре.")],
		["stretch", tr("Растянуть на экран"),
			tr("Картинка растягивается на весь экран. Без полей, но фигуры становятся шире.")],
	])
	_choice("Поля по бокам", "video", "sides", [
		["black", tr("Чёрные"), tr("Пустое место по бокам от картинки — чёрное.")],
		["blur", tr("Размытый кадр"),
			tr("По бокам — та же игра, но сильно размытая и затемнённая. Шейдер blur.gdshader.")],
	])
	var vsync := _toggle("Вертикальная синхронизация", "video", "vsync",
			tr("Кадры выводятся в такт монитору — картинка не «рвётся» при движении. Выключайте, только если игра идёт рывками."))
	vsync.value_changed.connect(func(_value: Variant) -> void: Settings.apply_vsync())


func _build_audio() -> void:
	var levels := [[0, tr("Без звука")]]
	for percent in range(10, 101, 10):
		levels.append([percent, "%d %%" % percent])  # %% — это сам знак «%»
	var volume := _choice("Громкость", "audio", "volume", levels,
			tr("Общая громкость Shellbit и игр. ◀ ▶ — тише или громче."), false)
	volume.value_changed.connect(func(_value: Variant) -> void: Settings.apply_volume())
	var ui_sounds := _toggle("Звуки интерфейса", "audio", "ui_sounds",
			tr("Тихий щелчок при переходе между играми и «бульк» при запуске игры. Свои звуки можно положить в папку data/sounds (click.wav и launch.wav)."))
	# Включили — сразу даём послушать «бульк».
	ui_sounds.value_changed.connect(func(value: Variant) -> void:
		if value:
			UiSounds.play_launch())


# Язык выбирают из выпадающего списка: языков девять, листать их
# стрелками ◀ ▶ по одному долго, а в списке все видны сразу.
func _build_language() -> void:
	var current: String = Settings.get_value("general", "language")
	var row := _action("Язык интерфейса", _language_name(current) + "  ▾",
			tr("Описания игр берутся из файлов рядом с играми — в них можно написать текст на каждом языке (см. README). «Как в системе» — язык Windows."),
			Callable())
	row.pressed.connect(_open_language_list.bind(row))


## Название языка для строки: "de" → "Deutsch", "auto" → «Как в системе».
func _language_name(code: String) -> String:
	for choice: Array in Lang.CHOICES:
		if choice[0] == code:
			return tr(choice[1])
	return code


func _open_language_list(row: SettingRow) -> void:
	# Выпадающий список создаём один раз и потом только открываем.
	if _dropdown == null:
		_dropdown = DropdownList.new()
		add_child(_dropdown)
		_dropdown.chosen.connect(_on_language_chosen)
	# Закрыли список — вернуть фокус на строку языка. Подключаем заново
	# каждый раз: строка пересоздаётся, когда раздел открывают снова.
	for connection in _dropdown.closed.get_connections():
		_dropdown.closed.disconnect(connection["callable"])
	_dropdown.closed.connect(row.grab_focus)

	var items := []
	for choice: Array in Lang.CHOICES:
		# «Как в системе» переводим, остальные названия — на своих языках.
		items.append([choice[0], tr(choice[1]) if choice[0] == "auto" else choice[1]])
	_dropdown.open(items, Settings.get_value("general", "language"), row)


func _on_language_chosen(value: Variant) -> void:
	if value == Settings.get_value("general", "language"):
		return  # выбрали тот же язык
	Settings.set_value("general", "language", value)
	_on_language_changed(value)


func _on_language_changed(value: Variant) -> void:
	Lang.apply(value)
	# Надписи, в которые код уже вписал текст, сами не переведутся.
	# Проще всего открыть экран настроек заново — уже на новом языке.
	SceneRouter.replace("settings", {"page": "language", "rows": true})


func _build_cores() -> void:
	_core_rows.clear()
	var cores_dir := ProjectSettings.globalize_path(CoreManager.CORES_DIR)
	var bios_dir := ProjectSettings.globalize_path(CoreManager.SYSTEM_DIR)

	# Сколько разных ядер не хватает (у Game Boy и Game Boy Color оно общее).
	var missing := {}
	for system in CoreDownloader.missing_systems():
		missing[CoreManager.core_path(system).get_file()] = true
	if missing.is_empty():
		_info("Все ядра на месте", "", tr("Ядра для всех приставок уже скачаны."))
	else:
		_action("Скачать недостающие ядра", str(missing.size()),
				tr("Shellbit скачает ядра для всех приставок, где их нет, с официального сервера libretro (buildbot.libretro.com). BIOS не скачиваются — их нужно положить в папку BIOS самим."),
				func() -> void: CoreDownloader.download_missing())

	_action("Открыть папку ядер", "", tr("Сюда кладут файлы ядер (%s):\n") % CoreManager.core_extension() + cores_dir,
			CoreManager.open_cores_folder)
	_action("Открыть папку BIOS", "", tr("Сюда кладут файлы BIOS:\n") + bios_dir,
			func() -> void: OS.shell_open(bios_dir))

	for system: Dictionary in CoreManager.systems:
		var core_path := CoreManager.core_path(system)
		var core_file := core_path.get_file()
		var has_core := FileAccess.file_exists(core_path)
		var text := tr("Ядро %s — %s.") % [core_file, tr("найдено") if has_core else tr("не найдено")]

		var missing_bios := PackedStringArray()
		for bios: String in system.get("bios", []):
			if not FileAccess.file_exists(CoreManager.SYSTEM_DIR.path_join(bios)):
				missing_bios.append(bios)
			text += "\nBIOS %s — %s." % [bios, tr("не найден") if missing_bios.has(bios) else tr("найден")]

		if not has_core:
			# Ядра нет — строка становится кнопкой «Скачать».
			var row := _action(system["name"], "Скачать",
					text + "\n\n" + tr("A — скачать ядро с официального сервера libretro."), Callable())
			row.pressed.connect(func() -> void: CoreDownloader.download(system))
			_core_rows.get_or_add(core_file, []).append(row)
			_show_core_state(row, core_file, -2)
			continue
		_info(system["name"], tr("Без BIOS") if not missing_bios.is_empty() else tr("Готово"), text, false)


# Что написать справа в строке ядра: «Скачать», «в очереди» или «45 %».
# percent: -2 — ничего не качается, -1 — в очереди, 0…100 — скачано процентов.
func _show_core_state(row: SettingRow, core_file: String, percent: int) -> void:
	if percent == -2 and CoreDownloader.is_busy(core_file):
		percent = -1
	match percent:
		-2:
			row.info_text = "Скачать"
		-1:
			row.info_text = "в очереди"
		_:
			row.info_text = "%d %%" % percent
	row.warn = percent == -2  # красным — пока ядра нет и оно не качается
	row.refresh()


func _on_core_progress(core_file: String, percent: int) -> void:
	for row: SettingRow in _core_rows.get(core_file, []):
		if is_instance_valid(row):
			_show_core_state(row, core_file, percent)


func _on_core_finished(core_file: String, ok: bool, message: String) -> void:
	if ok:
		SceneRouter.toast(tr("Ядро %s скачано") % core_file)
	else:
		SceneRouter.toast(tr("Не удалось скачать ядро %s: %s") % [core_file, message])
	if _page == "cores":
		_rebuild_page()  # ядро появилось — строка станет «Готово»


func _build_about() -> void:
	var version: String = ProjectSettings.get_setting("application/config/version", "")
	_info("Shellbit", version if version != "" else tr("этап 1"),
			tr("Фронтенд для ретро-эмуляторов на Godot. Маскот — рак-отшельник Пип."))
	_info("Движок", "Godot " + Engine.get_version_info()["string"], tr("Сделано на Godot Engine."))
	_info("Игр в библиотеке", Library.count_text(Library.groups.size()),
			tr("Приставок с играми: %d.") % Library.systems_with_games().size())
	var shots_dir := Settings.screenshots_dir()
	_action("Папка скриншотов", "", tr("Скриншоты игр (F12 или Share на геймпаде):\n") + shots_dir,
			func() -> void:
				DirAccess.make_dir_recursive_absolute(shots_dir)  # до первого снимка папки ещё нет
				OS.shell_open(shots_dir))
	var data_dir := ProjectSettings.globalize_path("user://")
	_action("Папка с данными", "", tr("Настройки, сохранения, обложки и ядра:\n") + data_dir,
			func() -> void: OS.shell_open(data_dir))


# =====================================================================
# Предпросмотр фильтра (правая колонка)
# =====================================================================

## Картинка для предпросмотра: кадр из последней игры,
## а если ещё не играли — картинка NES.
func _preview_texture() -> Texture2D:
	var recent := Library.get_recent(1)
	if not recent.is_empty():
		var shot := SaveStates.thumbnail(Library.chosen_variant(recent[0]), SaveStates.AUTO)
		if shot:
			return shot
	return load("res://data/consoles/NES.png")


## Наложить на предпросмотр выбранный фильтр — тот же шейдер, что в игре.
func _update_preview() -> void:
	var filter: String = Settings.get_value("video", "filter")
	%Preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if filter == "smooth" \
			else CanvasItem.TEXTURE_FILTER_NEAREST
	match filter:
		"crt":
			var material := ShaderMaterial.new()
			material.shader = CRT_SHADER
			%Preview.material = material
		"lcd":
			var material := ShaderMaterial.new()
			material.shader = LCD_SHADER
			%Preview.material = material
		_:
			%Preview.material = null


# =====================================================================
# Кнопка «Назад»
# =====================================================================

func _unhandled_input(event: InputEvent) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if event.is_action_pressed("ui_cancel"):
		if focused is SettingRow:
			_category_button(_page).grab_focus()  # из строк — к разделам
		else:
			SceneRouter.back()  # из разделов — выйти из настроек
	elif focused == null and (event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down")):
		_category_button(_page).grab_focus()  # фокус потерялся — вернуть
	else:
		return
	get_viewport().set_input_as_handled()
