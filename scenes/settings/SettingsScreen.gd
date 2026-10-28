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
	{"id": "look", "title": "Оформление",
		"about": "Как выглядят меню Shellbit."},
	{"id": "players", "title": "Игроки",
		"about": "У каждого игрока своё избранное, время в игре и сохранения."},
	{"id": "family", "title": "Семья",
		"about": "Детский режим: ребёнок может только играть."},
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
	_fit_to_screen()
	_build_categories()
	%FolderDialog.dir_selected.connect(_on_folder_selected)
	# Если геймпад подключили, пока открыт раздел «Управление», — обновим список.
	# Подключаем обычную функцию, а не лямбду: когда экран закроется,
	# Godot сам отключит её от сигнала.
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	# Скачивание ядер: проценты в строках и сообщение, когда готово.
	CoreDownloader.progress.connect(_on_core_progress)
	CoreDownloader.finished.connect(_on_core_finished)

	_add_category_fades()
	%Preview.texture = _preview_texture()
	# Узор фона — и здесь: выбираешь вариант и сразу видишь его на экране.
	var backdrop := Backdrop.new()
	add_child(backdrop)
	move_child(backdrop, $Background.get_index() + 1)

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


# Разделов больше, чем помещается по высоте, — список прокручивается.
# Чтобы было видно, что ниже (или выше) есть ещё, край списка плавно
# растворяется в фоне, а не обрезается «ножом» посреди слова.
func _add_category_fades() -> void:
	var scroll: ScrollContainer = $Margin/VBox/Body/CategoriesScroll
	var fades: Array[TextureRect] = []
	for top in [true, false]:
		var gradient := Gradient.new()
		# Сверху вниз: у верхней «шторки» — от фона к прозрачному, у нижней — наоборот.
		gradient.colors = PackedColorArray([UiTheme.BG, Color(UiTheme.BG, 0.0)] if top else [Color(UiTheme.BG, 0.0), UiTheme.BG])
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill_from = Vector2(0, 0)
		texture.fill_to = Vector2(0, 1)  # градиент по вертикали
		var fade := TextureRect.new()
		fade.texture = texture
		fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Не внутрь ScrollContainer (он решил бы, что это ещё один раздел),
		# а поверх экрана — и двигаем вслед за списком.
		add_child(fade)
		fades.append(fade)
	var bar := scroll.get_v_scroll_bar()
	var update := func() -> void:
		var height := 40.0
		fades[0].position = scroll.global_position
		fades[0].size = Vector2(scroll.size.x, height)
		fades[1].position = scroll.global_position + Vector2(0, scroll.size.y - height)
		fades[1].size = Vector2(scroll.size.x, height)
		# Шторка видна, только если в ту сторону ещё есть что прокручивать.
		fades[0].visible = bar.value > 1.0
		fades[1].visible = bar.value + bar.page < bar.max_value - 1.0
	bar.value_changed.connect(func(_value: float) -> void: update.call())
	bar.changed.connect(update)
	scroll.resized.connect(update)
	update.call_deferred()


func _on_category_input(event: InputEvent, button: Button) -> void:
	# ▶ на разделе — перейти к его настройкам.
	if event.is_action_pressed("ui_right"):
		_enter_rows()
		button.accept_event()


func _on_category_focused(id: String) -> void:
	_scroll_to(_category_button(id))
	_show_page(id)
	%Description.text = tr(_page_info(id)["about"])
	%Hints.set_hints([["accept", tr("Выбрать")], ["cancel", tr("Назад")]])


# Прокрутить список так, чтобы выделенная кнопка была видна ЦЕЛИКОМ —
# вместе со свечением рамки. У ScrollContainer есть своё follow_focus,
# но оно двигает список ровно до края кнопки, и свечение (≈23 пикселя
# вокруг) обрезалось краем списка. Поэтому follow_focus выключено
# в сцене, а прокручиваем сами — с запасом GLOW_ROOM.
const GLOW_ROOM := 28.0


func _scroll_to(item: Control) -> void:
	# Ищем, в каком ScrollContainer лежит кнопка (разделы или строки).
	var scroll := item.get_parent()
	while scroll != null and not scroll is ScrollContainer:
		scroll = scroll.get_parent()
	if scroll == null:
		return
	await get_tree().process_frame  # новая страница могла ещё не разложиться
	if not is_instance_valid(item) or not item.is_inside_tree():
		return
	# Где кнопка относительно видимого окошка списка: 0 — у верхнего края.
	var top: float = item.global_position.y - scroll.global_position.y
	var bottom: float = top + item.size.y
	if top - GLOW_ROOM < 0.0:
		scroll.scroll_vertical += int(top - GLOW_ROOM)
	elif bottom + GLOW_ROOM > scroll.size.y:
		scroll.scroll_vertical += int(bottom + GLOW_ROOM - scroll.size.y)


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
	if id != "players":
		_editing_player = ""  # ушли из раздела «Игроки» — потом снова откроется список
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
		"look": _build_look()
		"players": _build_players()
		"family": _build_family()
		"audio": _build_audio()
		"language": _build_language()
		"cores": _build_cores()
		"about": _build_about()

	_link_rows()
	# Предпросмотр нужен только в разделе «Видео».
	%PreviewBox.visible = id == "video"
	# В «О программе» вместо предпросмотра — радостный Пип.
	%AboutPip.visible = id == "about"
	_show_player_preview()
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
	_scroll_to(row)
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


func _build_look() -> void:
	var scale := _choice("Размер интерфейса", "look", "ui_scale", [
		[100, tr("Обычный"), tr("Для монитора, перед которым сидишь близко.")],
		[115, tr("Крупнее"), tr("Всё немного крупнее: удобно на ноутбуке или небольшом телевизоре.")],
		[130, tr("Для телевизора"),
			tr("Всё крупно, чтобы читалось с дивана. На экране помещается меньше: в библиотеке меньше колонок, а панель сведений об игре прячется.")],
	])
	scale.value_changed.connect(func(_value: Variant) -> void:
		Settings.apply_ui_scale()
		# Экран настроек уже собран под старый размер — открываем его заново,
		# на той же строке (row 0 — «Размер интерфейса»).
		SceneRouter.replace("settings", {"page": "look", "rows": true, "row": 0}))
	_choice("Узор фона", "look", "pattern", [
		["none", tr("Без узора"), tr("Чистый тёмный фон.")],
		["grid", tr("Пиксельная сетка"),
			tr("Мелкие точки через ровные промежутки, как экран старого монитора вблизи.")],
		["stars", tr("Пиксельные звёзды"),
			tr("Звёздное небо из 8-битной игры: звёзды мерцают и медленно плывут вверх.")],
		["dither", tr("Дизеринг"),
			tr("Шахматные клеточки, которыми в играх NES и Game Boy рисовали полутени.")],
		["scanlines", tr("Строки кинескопа"),
			tr("Тонкие тёмные линии и затемнённые края, как на старом телевизоре.")],
	])
	_choice("Переход между экранами", "look", "transition", [
		["fade", tr("Затемнение"), tr("Экран плавно гаснет, и следующий так же плавно проявляется.")],
		["mosaic", tr("Мозаика"),
			tr("Экран укрупняется до больших квадратов и собирается обратно, как в играх SNES.")],
		["dissolve", tr("Рассыпание"),
			tr("Экран распадается на квадраты, которые гаснут в случайном порядке.")],
	])


# --- Игроки (autoload/Profiles.gd) -------------------------------------------
# Раздел в два уровня: сначала список игроков, а A на игроке открывает
# его настройки (имя, цвет, удалить). Какой игрок открыт — _editing_player
# ("" — показываем список).

var _editing_player := ""
var _player_preview: ProfileAvatar  # большой кружок игрока справа (создаётся при первом показе)
var _name_editor: Control  # окно ввода имени (создаётся при первом открытии)


func _build_players() -> void:
	if _editing_player != "":
		_build_player(_editing_player)
		return
	for id: String in Profiles.ids():
		var playing := id == Profiles.current()
		_action(Profiles.name_of(id), tr("Сейчас играет") if playing else "",
				tr("Имя и цвет игрока. Здесь же игрока можно удалить."),
				_open_player.bind(id))
	if Profiles.count() < Profiles.MAX_PROFILES:
		_action("+ Добавить игрока", "",
				tr("Новый игрок начинает с чистого листа: своё избранное, своё «Продолжить играть» и свои сохранения. Игры и настройки — общие."),
				_add_player)
	_toggle("Спрашивать «Кто играет?»", "profiles", "ask_on_start",
			tr("При запуске Shellbit показать экран выбора игрока. Работает, если игроков больше одного. Сменить игрока можно и кнопкой с именем на главном экране."))


func _build_player(id: String) -> void:
	_action("Имя", Profiles.name_of(id), tr("Как зовут игрока. Первая буква имени будет на его кружке."),
			_ask_player_name.bind(id))
	var colors := Profiles.COLORS.map(func(option: Array) -> Array:
		return [option[0], tr(option[1]), tr("Цвет кружка игрока и рамки на экране «Кто играет?».")])
	var color := _choice("Цвет", Profiles.section_of(id), "color", colors)
	# Цвет поменялся — кружки игрока на всех экранах перерисуются.
	color.value_changed.connect(func(_value: Variant) -> void: Profiles.changed.emit())

	# Картинка: ◀ ▶ листают встроенные (data/avatars), первая — «Буква имени».
	var about_avatar := tr("Картинка в кружке игрока. Листайте ◀ ▶ — справа сразу видно, как получится.")
	var avatars: Array = [["", tr("Буква имени"), about_avatar]]
	for avatar: Array in Profiles.AVATARS:
		avatars.append([Profiles.AVATAR_DIR.path_join(avatar[0] + ".png"), tr(avatar[1]), about_avatar])
	if Profiles.avatar_of(id).begins_with("user://"):
		avatars.append([Profiles.avatar_of(id), tr("Своя картинка"), about_avatar])
	var avatar_row := _choice("Аватар", Profiles.section_of(id), "avatar", avatars)
	avatar_row.value_changed.connect(func(_value: Variant) -> void: Profiles.changed.emit())
	_action("Своя картинка…", "", tr("Выбрать картинку на компьютере: фото или рисунок (PNG, JPG, WebP). Shellbit сохранит себе её копию, обрезанную до квадрата."),
			_pick_avatar_file.bind(id))
	if id != Profiles.MAIN:
		var remove := _action("Удалить игрока", "",
				tr("Удалятся избранное, время в игре и все сохранения этого игрока. Игры на диске не тронутся."),
				Callable())
		# Удаление — в два нажатия, как «Выход»: сохранения не вернуть.
		remove.pressed.connect(func() -> void:
			if remove.get_meta("armed", false):
				var player_name := Profiles.name_of(id)
				Profiles.remove(id)
				_close_player()
				SceneRouter.toast(tr("Игрок удалён: %s") % player_name)
			else:
				remove.set_meta("armed", true)
				remove.info_text = tr("Точно? Нажмите ещё раз")
				remove.refresh())
		remove.focus_exited.connect(func() -> void:
			remove.set_meta("armed", false)
			remove.info_text = ""
			remove.refresh())
	else:
		_info("Первый игрок", "", tr("Первого игрока нельзя удалить: у него хранятся сохранения, сделанные до появления игроков. Переименовать — можно."))
	_action("← Все игроки", "", tr("Вернуться к списку игроков."), _close_player)


# Своя картинка: окно выбора файла Windows (use_native_dialog — настоящее
# окно системы, а не нарисованное Godot). Создаём его один раз.
var _avatar_dialog: FileDialog


func _pick_avatar_file(id: String) -> void:
	if _avatar_dialog == null:
		_avatar_dialog = FileDialog.new()
		_avatar_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_avatar_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_avatar_dialog.use_native_dialog = true
		_avatar_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; " + tr("Картинки")])
		add_child(_avatar_dialog)
	# Подключение — на один раз: в следующий раз игрок может быть другой.
	for connection in _avatar_dialog.file_selected.get_connections():
		_avatar_dialog.file_selected.disconnect(connection["callable"])
	_avatar_dialog.file_selected.connect(func(path: String) -> void:
		if not Profiles.set_custom_avatar(id, path):
			SceneRouter.toast(tr("Не получилось открыть картинку"))
		_rebuild_page()  # в списке «Аватар» появится «Своя картинка»
		_enter_rows.call_deferred(2))  # строка «Аватар»
	_avatar_dialog.popup_centered_ratio(0.7)


# В настройках игрока справа — его кружок крупно: листаешь цвет и картинку
# и сразу видишь результат.
func _show_player_preview() -> void:
	var show := _page == "players" and _editing_player != ""
	if _player_preview == null:
		if not show:
			return
		_player_preview = ProfileAvatar.new()
		_player_preview.custom_minimum_size = Vector2(160, 160)
		_player_preview.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		%PreviewBox.add_sibling(_player_preview)
	_player_preview.visible = show
	if show:
		_player_preview.profile_id = _editing_player


func _open_player(id: String) -> void:
	_editing_player = id
	_rebuild_page()
	_enter_rows.call_deferred(0)


func _close_player() -> void:
	var id := _editing_player
	_editing_player = ""
	_rebuild_page()
	# Фокус — на того игрока, из которого вышли (если он ещё есть).
	_enter_rows.call_deferred(maxi(Profiles.ids().find(id), 0))


func _add_player() -> void:
	var id := Profiles.add()
	if id == "":
		return
	_editing_player = id
	_rebuild_page()
	_ask_player_name(id)  # сразу спросить имя


# Окно ввода имени: поле с именем и экранная клавиатура под ним
# (scenes/components/ScreenKeyboard.gd — та же, что в поиске).
func _ask_player_name(id: String) -> void:
	if _name_editor == null:
		_name_editor = _make_name_editor()
	var field: LineEdit = _name_editor.get_meta("field")
	var keyboard: ScreenKeyboard = _name_editor.get_meta("keyboard")
	field.text = Profiles.name_of(id)
	field.caret_column = field.text.length()
	# Клавиатуру закрыли — сохраняем имя. CONNECT_ONE_SHOT — «один раз»:
	# после срабатывания подключение само убирается (в следующий раз
	# здесь будет другой игрок).
	keyboard.closed.connect(func() -> void:
		Profiles.rename(id, field.text)
		_name_editor.visible = false
		_rebuild_page()
		_enter_rows.call_deferred(0), CONNECT_ONE_SHOT)
	_name_editor.visible = true
	keyboard.open(field)


func _make_name_editor() -> Control:
	var editor := Control.new()
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	editor.mouse_filter = Control.MOUSE_FILTER_STOP
	editor.z_index = 9  # клавиатура — на этаже 10, поверх
	add_child(editor)
	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BG, 0.85)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	editor.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	editor.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.offset_top = 48
	var title := Label.new()
	title.text = tr("Имя игрока")
	title.theme_type_variation = &"HeaderLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var field := LineEdit.new()
	field.custom_minimum_size = Vector2(420, 52)
	field.max_length = 20
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.add_theme_font_size_override("font_size", 24)
	# Печатает экранная клавиатура, а не само поле: фокус полю не нужен.
	field.focus_mode = Control.FOCUS_NONE
	column.add_child(field)

	var keyboard := ScreenKeyboard.new()
	keyboard.done_text = "Сохранить"
	editor.add_child(keyboard)
	editor.set_meta("field", field)
	editor.set_meta("keyboard", keyboard)
	return editor


# --- Семья: детский режим (autoload/Family.gd) -------------------------------

var _pin_dialog: PinDialog
var _new_pin := ""  # первый ввод нового PIN — ждём повтора


func _build_family() -> void:
	var row := _action("Детский режим", tr("Выключен"),
			tr("Ребёнок сможет только играть. Спрячутся настройки, «+ Папка с играми», выход из программы, смена обложек, «Начать заново», настройки ядра и перезапись сохранений, а игры жанра «Для взрослых» скроются. Выйти из режима можно только по PIN-коду."),
			Callable())
	row.pressed.connect(func() -> void: _ask_new_pin(row))


# Включение: придумать PIN → повторить → совпало — режим включён.
func _ask_new_pin(row: SettingRow) -> void:
	if _pin_dialog == null:
		_pin_dialog = PinDialog.new()
		add_child(_pin_dialog)
		_pin_dialog.entered.connect(_on_pin_entered)
		_pin_dialog.cancelled.connect(func() -> void: _focus_family_row())
	_new_pin = ""
	_pin_dialog.open("Придумайте PIN-код", "4 цифры. Он понадобится, чтобы выйти из детского режима — ребёнку его не показывайте.")


func _on_pin_entered(pin: String) -> void:
	if _new_pin == "":
		_new_pin = pin
		_pin_dialog.open("Повторите PIN-код", "Чтобы не ошибиться — ещё раз те же 4 цифры.")
	elif pin != _new_pin:
		_new_pin = ""
		_pin_dialog.open("Придумайте PIN-код", "")
		_pin_dialog.show_error("Коды не совпали. Придумайте PIN-код ещё раз.")
	else:
		_pin_dialog.close()
		Family.enable(pin)
		# На главный экран «с чистого листа»: иначе «Назад» вернул бы в настройки.
		SceneRouter.reset_to("home")
		SceneRouter.toast(tr("Детский режим включён"))


func _focus_family_row() -> void:
	if %Rows.get_child_count() > 0:
		%Rows.get_child(0).grab_focus()


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
		if focused is SettingRow and _editing_player != "":
			_close_player()  # из настроек игрока — к списку игроков
		elif focused is SettingRow:
			_category_button(_page).grab_focus()  # из строк — к разделам
		else:
			SceneRouter.back()  # из разделов — выйти из настроек
	elif focused == null and (event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down")):
		_category_button(_page).grab_focus()  # фокус потерялся — вернуть
	else:
		return
	get_viewport().set_input_as_handled()


# Крупный интерфейс («Для телевизора»): в пересчёте на «виртуальные»
# пиксели экран становится уже (985 вместо 1280). Три колонки рядом —
# разделы, пункты, пояснение — уже не помещаются: названия пунктов
# обрезались бы до «Размер …». Поэтому колонку с пояснением переносим
# ПОД пункты: из трёх колонок получается две.
#
# reparent() — «пересадить» узел к другому родителю. Уникальные имена
# (%Rows, %Description) при этом продолжают работать: хозяин узлов
# (owner) остаётся тем же — корень сцены.
func _fit_to_screen() -> void:
	if not UiTheme.is_compact(self):
		return
	%Categories.custom_minimum_size.x = 200
	var body: HBoxContainer = $Margin/VBox/Body
	var rows_scroll: ScrollContainer = $Margin/VBox/Body/RowsScroll
	var side: VBoxContainer = $Margin/VBox/Body/Side
	var middle := VBoxContainer.new()  # новая колонка: пункты, а под ними пояснение
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 0)
	body.add_child(middle)
	body.move_child(middle, rows_scroll.get_index())
	rows_scroll.reparent(middle)
	rows_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Пояснение — во всю ширину колонки, с теми же отступами по бокам,
	# что у пунктов (24 — как у Pad внутри RowsScroll).
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_right", 24)
	middle.add_child(pad)
	side.reparent(pad)
	side.custom_minimum_size.x = 0
	%Description.custom_minimum_size.x = 0
	%PreviewBox.custom_minimum_size = Vector2(220, 147)
	%PreviewBox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	%AboutPip.custom_minimum_size = Vector2(0, 110)
