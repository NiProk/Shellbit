extends Control
## Экран библиотеки одной приставки: сетка игр + панель с информацией.
##
## Какую приставку показать, экран узнаёт из SceneRouter.params:
##   SceneRouter.go_to("library", {"system": "snes"})
## Избранное со всех приставок открывается так же:
##   SceneRouter.go_to("library", {"system": Library.FAVORITES})
## Можно сразу открыть с фильтром по жанру:
##   SceneRouter.go_to("library", {"system": "nes", "genre": "platformer"})
##
## Каждая карточка — это ИГРА (группа версий), а не отдельный файл.

const MAX_VERSION_LINES := 8  # сколько версий показывать в панели

## Способы сортировки: [значение для настроек, надпись на кнопке].
## Кнопка переключает их по кругу, выбор запоминается в Settings.
const SORTS := [
	["title", "По названию"],
	["system", "По приставке"],
	["recent", "Недавние"],
]

var system_id := ""
var _groups: Array = []  # игры этого экрана (в порядке сортировки)
## Какой жанр показываем: "" — все, Genres.NONE — игры без жанра,
## иначе id жанра ("platformer"). См. scripts/Genres.gd.
var _genre := ""
var _genre_list := DropdownList.new()  # выпадающий список жанров
var _genre_just_chosen := false  # выбрали жанр (а не закрыли список кнопкой B)
var _focus_before_genres: Control  # где был фокус, когда открыли список жанров

# Меню «Обложка» (компонент scenes/components/CoverPicker.gd).
var _cover_picker := CoverPicker.new()
# Экранная клавиатура для поиска с геймпада (scenes/components/ScreenKeyboard.gd).
var _keyboard := ScreenKeyboard.new()


func _ready() -> void:
	system_id = SceneRouter.params.get("system", "")
	var groups: Array
	if _is_favorites():
		# Избранное: игры со всех приставок, золотая полоска.
		groups = Library.favorite_groups()
		%Strip.color = Color(Library.FAVORITES_COLOR)
		%SystemName.text = "★ " + tr("Избранное")
	else:
		var system := CoreManager.get_system(system_id)
		groups = Library.groups_for_system(system_id)
		%Strip.color = Color(system.get("color", "#888888"))
		%SystemName.text = tr(system.get("name", "Неизвестная приставка"))
	_groups = groups
	_fit_to_screen()

	# Сетка «виртуальная»: карточек в ней ровно столько, сколько видно
	# на экране (см. scenes/components/VirtualGrid.gd). Так экран
	# с тысячами игр открывается мгновенно.
	%Grid.card_pressed.connect(_on_game_pressed)
	%Grid.card_focused.connect(_show_info)
	_setup_search_and_sort()
	_setup_genres()
	# Вернулись со страницы игры — восстанавливаем поиск, как был.
	# text = … не вызывает text_changed, фильтр применит _build_grid().
	%Search.text = SceneRouter.params.get("search", "")
	_build_grid()

	# Подсказки внизу. «Жанр» — только если у игр этого экрана есть жанры.
	# Строка длинная, поэтому подписи короткие: «Приставка», а не «Другая приставка».
	var hints := [["page", "Приставка"]]
	if %GenreButton.visible:
		hints.append(["genre", "Жанр"])
	hints.append_array([
		["accept", "Открыть"],
		["details", "Версия"],
		["favorite", "Избранное"],
	])
	if not Family.is_on():
		hints.append(["menu", "Обложка"])  # в детском режиме обложки не меняем
	hints.append_array([
		["search", "Поиск"],
		["cancel", "Назад"],
	])
	%Hints.set_hints(hints)
	add_child(_cover_picker)
	add_child(_keyboard)
	add_child(_genre_list)
	# Фон по выбранной игре. Ушёл к поиску или жанрам — фон остаётся.
	var backdrop := Backdrop.new()
	backdrop.follow_focus = true
	backdrop.clear_off_games = false
	add_child(backdrop)
	move_child(backdrop, $Background.get_index() + 1)
	# Свечение цвета приставки — сразу, ещё до выбора игры.
	backdrop.show_glow(Backdrop.system_color(system_id))
	# Клавиатуру закрыли — переходим к найденным играм.
	_keyboard.closed.connect(_leave_search)
	_restore_focus()


# =====================================================================
# Поиск и сортировка
# =====================================================================

func _setup_search_and_sort() -> void:
	%Search.placeholder_text = tr("Поиск…")
	_style_search()
	# text_changed срабатывает на КАЖДУЮ напечатанную или стёртую букву.
	%Search.text_changed.connect(func(_text: String) -> void: _apply_filter())
	# Enter в поле поиска — перейти к найденным карточкам.
	%Search.text_submitted.connect(func(_text: String) -> void: _focus_first_card())
	%Search.focus_entered.connect(_on_search_focused)
	%Search.gui_input.connect(_on_search_input)

	%SortButton.pressed.connect(_next_sort)
	%SortButton.mouse_entered.connect(%SortButton.grab_focus)
	_update_sort_button()


## Отсортировать игры и показать их — в порядке текущей сортировки.
func _build_grid() -> void:
	_sort_groups()
	_apply_filter()


## Показать только игры, в названии которых есть текст из поиска.
func _apply_filter() -> void:
	var query: String = %Search.text.strip_edges()
	# Игра остаётся, только если подходит И под поиск, И под жанр.
	# findn — поиск БЕЗ учёта регистра: «toad» найдёт «Battletoads».
	# Возвращает место, где нашёлся текст, или −1, если не нашёлся.
	var found := _groups.filter(func(group: Dictionary) -> bool:
		return (query == "" or group["title"].findn(query) != -1) and _genre_matches(group))
	%Grid.set_items(found)
	var shown := found.size()

	# Панель сведений справа — о первой найденной игре,
	# чтобы там не осталась игра, которую поиск уже спрятал.
	if not found.is_empty():
		_show_info(found[0])

	var total := _groups.size()
	if query == "" and _genre == "":
		%Count.text = Library.count_text(total)
	else:
		%Count.text = tr("%d из %s") % [shown, Library.count_text(total)]
	%NoResults.visible = shown == 0 and total > 0


## Отсортировать _groups выбранным способом.
func _sort_groups() -> void:
	var by_title := func(a: Dictionary, b: Dictionary) -> bool:
		return a["title"].naturalnocasecmp_to(b["title"]) < 0

	match _current_sort():
		"system":
			# Порядок приставок — как в data/systems.json; внутри приставки — по названию.
			var order := {}
			for i in CoreManager.systems.size():
				order[CoreManager.systems[i]["id"]] = i
			_groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				if a["system"] != b["system"]:
					return order.get(a["system"], 999) < order.get(b["system"], 999)
				return by_title.call(a, b))
		"recent":
			# Сначала недавние. Игры, в которые ещё не играли (0), — в конце, по названию.
			_groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				if a["last_played"] != b["last_played"]:
					return a["last_played"] > b["last_played"]
				return by_title.call(a, b))
		_:
			_groups.sort_custom(by_title)


func _current_sort() -> String:
	return Settings.get_value("library", "sort", "title")


# Кнопка: следующий способ сортировки по кругу.
func _next_sort() -> void:
	var ids := SORTS.map(func(s: Array) -> String: return s[0])
	var index := ids.find(_current_sort())
	Settings.set_value("library", "sort", ids[(index + 1) % ids.size()])
	_update_sort_button()
	_build_grid()


func _update_sort_button() -> void:
	for sort: Array in SORTS:
		if sort[0] == _current_sort():
			# Коротко, чтобы шапка помещалась: «↕ По названию».
			# Полное «Сортировка: …» — во всплывающей подсказке для мыши.
			%SortButton.text = "↕ " + tr(sort[1])
			%SortButton.tooltip_text = tr("Сортировка: %s") % tr(sort[1])


# =====================================================================
# Жанры
# =====================================================================
#
# Жанр игры Library узнаёт по папке (Platformer, RPG…) — см. scripts/Genres.gd.
# Здесь — кнопка «Все жанры ▾» в шапке и выпадающий список: в нём только
# те жанры, что есть у игр этого экрана, и сколько в каждом игр.

func _setup_genres() -> void:
	_genre = SceneRouter.params.get("genre", "")
	# Жанр пришёл с другой приставки, а здесь таких игр нет — показываем все.
	if not _genre_counts().has(_genre):
		_genre = ""
	%GenreButton.pressed.connect(_open_genres)
	%GenreButton.mouse_entered.connect(%GenreButton.grab_focus)
	_genre_list.chosen.connect(_choose_genre)
	_genre_list.closed.connect(_on_genres_closed)
	_update_genre_button()


## Сколько игр в каждом жанре на этом экране: {"": все, "rpg": 12, "none": 3…}.
func _genre_counts() -> Dictionary:
	var counts := {"": _groups.size()}
	for group: Dictionary in _groups:
		var genre: String = group.get("genre", "")
		var id := genre if genre != "" else Genres.NONE
		counts[id] = counts.get(id, 0) + 1
	return counts


func _genre_matches(group: Dictionary) -> bool:
	if _genre == "":
		return true
	if _genre == Genres.NONE:
		return group.get("genre", "") == ""
	return group.get("genre", "") == _genre


func _open_genres() -> void:
	var counts := _genre_counts()
	var ids := counts.keys()
	ids.erase("")
	# Порядок — как в Genres.LIST, «Без жанра» — в конце.
	ids.sort_custom(func(a: String, b: String) -> bool: return Genres.order(a) < Genres.order(b))
	# Пары [значение, надпись] для DropdownList. Надписи уже переведены.
	var items := [["", "%s  · %d" % [tr("Все жанры"), counts[""]]]]
	for id: String in ids:
		items.append([id, "%s  · %d" % [Genres.title(id), counts[id]]])
	_genre_just_chosen = false
	# Список могли открыть кнопкой View/G прямо с карточки — запоминаем,
	# куда вернуть фокус, если закроют без выбора.
	_focus_before_genres = get_viewport().gui_get_focus_owner()
	_genre_list.open(items, _genre, %GenreButton)


func _choose_genre(id: String) -> void:
	_genre = id
	_genre_just_chosen = true
	_update_genre_button()
	_apply_filter()


# Список закрылся. Выбрали жанр — сразу к играм. Закрыли кнопкой B —
# туда, где были до этого (на карточку или на кнопку жанра).
func _on_genres_closed() -> void:
	if _genre_just_chosen and _focus_first_card():
		return
	if is_instance_valid(_focus_before_genres) and _focus_before_genres.is_visible_in_tree() \
			and not _genre_list.is_ancestor_of(_focus_before_genres):
		_focus_before_genres.grab_focus()
	else:
		%GenreButton.grab_focus()


func _update_genre_button() -> void:
	# Если ни одна игра этого экрана не лежит в папке жанра — кнопка не нужна.
	var counts := _genre_counts()
	%GenreButton.visible = counts.size() > 2 or (counts.size() == 2 and not counts.has(Genres.NONE))
	var text := tr("Все жанры") if _genre == "" else Genres.title(_genre)
	%GenreButton.text = text + "  ▾"
	%GenreButton.tooltip_text = tr("Жанр: %s") % text


## Стрелка вправо в поле поиска. Обычно она двигает курсор по тексту,
## но если курсор уже в самом конце — уходим к кнопкам сортировки и жанра.
## Иначе с клавиатуры до них было бы не добраться.
func _on_search_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_right") and %Search.caret_column >= %Search.text.length():
		%Search.accept_event()  # «нажатие обработано» — поле курсор не двигает
		%SortButton.grab_focus()


## Пришли в поле поиска.
func _on_search_focused() -> void:
	if InputMapper.style == "keyboard":
		# С клавиатурой печатаем прямо в поле. В Godot 4.4+ поле в фокусе
		# ещё не «редактируется», пока его не включить, — включаем сразу.
		%Search.edit()
	else:
		# С геймпада печатать нечем — открываем экранную клавиатуру.
		# call_deferred — «сделать в конце кадра». Сразу нельзя: мы внутри
		# обработчика focus_entered, и если прямо отсюда отдать фокус клавише,
		# Godot закончит начатое и вернёт фокус полю — оно снова откроет
		# клавиатуру, и так без конца (программа зависнет).
		_keyboard.open.call_deferred(%Search)


## Уйти из поиска к результатам. Если ничего не нашлось — на кнопку сортировки,
## а не обратно в поле (иначе клавиатура тут же открылась бы снова).
func _leave_search() -> void:
	if not _focus_first_card():
		%SortButton.grab_focus()


## Фокус — на игру, которую открывали перед уходом со страницы
## (SceneRouter.params["focus_key"]), иначе на первую.
##
## Зачем: долистал до 30-й игры, открыл её, вернулся — и список снова
## с начала. Поэтому, уходя на страницу игры, мы запоминаем её ключ
## в параметрах ЭТОГО экрана (см. _on_game_pressed), а SceneRouter
## по «Назад» возвращает их нам.
func _restore_focus() -> void:
	# Ждём кадр: карточки должны встать по местам, иначе ScrollContainer
	# не поймёт, куда прокручивать.
	await get_tree().process_frame
	var key: String = SceneRouter.params.get("focus_key", "")
	var items: Array = %Grid.items
	for i in items.size():
		if items[i]["key"] == key:
			# Посередине экрана — так видно и соседние игры.
			%Grid.select(i, true)
			return
	_focus_first_card()


## Поставить фокус на первую игру. false — если игр нет (поиск ничего не нашёл).
func _focus_first_card() -> bool:
	if %Grid.items.is_empty():
		return false
	%Grid.select(0)
	return true


# Поле поиска в цветах приложения (у LineEdit своего стиля в теме нет).
func _style_search() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = UiTheme.CARD
	box.set_corner_radius_all(12)
	box.content_margin_left = 16
	box.content_margin_right = 12
	%Search.add_theme_stylebox_override("normal", box)
	var focus: StyleBoxFlat = UiTheme.theme.get_stylebox("focus", "Button").duplicate()
	focus.set_corner_radius_all(16)
	%Search.add_theme_stylebox_override("focus", focus)
	%Search.add_theme_color_override("font_color", UiTheme.TEXT)
	%Search.add_theme_color_override("font_placeholder_color", UiTheme.TEXT_DIM)
	%Search.add_theme_font_size_override("font_size", 18)


func _show_info(group: Dictionary) -> void:
	var chosen := Library.chosen_variant(group)
	%InfoTitle.text = group["title"]
	var info_lines: Array[String] = []
	# В избранном игры с разных приставок — подписываем, с какой.
	if _is_favorites():
		info_lines.append(tr(CoreManager.get_system(group["system"]).get("name", "")))
	if group.get("genre", "") != "":
		info_lines.append(tr("Жанр: %s") % Genres.title(group.get("genre", "")))
	# Ни разу не играли — время не показываем («меньше минуты» сбивало бы с толку).
	# Так же сделано и на странице игры.
	if int(group["play_seconds"]) > 0:
		info_lines.append(tr("Время в игре: %s") % Library.playtime_text(int(group["play_seconds"])))
	info_lines.append(tr("Последний запуск: %s") % Library.last_played_text(int(group["last_played"])))
	%InfoText.text = "\n".join(info_lines)

	# Список версий. RichTextLabel понимает BBCode — разметку в [квадратных]
	# скобках: [color=#ffffff]текст[/color] красит часть строки.
	var variants: Array = group["variants"]
	%VersionsTitle.text = Lang.n("%d версия|%d версии|%d версий", variants.size())
	var lines: Array[String] = []
	for i in mini(variants.size(), MAX_VERSION_LINES):
		var variant: Dictionary = variants[i]
		var line: String = variant["version"]
		if variant == chosen:
			line = "[color=#5eead4]▶ " + line + "[/color]"
		else:
			line = "   " + line
		lines.append(line)
	if variants.size() > MAX_VERSION_LINES:
		lines.append("   " + tr("…и ещё %d") % (variants.size() - MAX_VERSION_LINES))
	%Versions.text = "\n".join(lines)
	# Если версия одна — переключать нечего, список не нужен.
	%Versions.visible = variants.size() > 1


func _unhandled_input(event: InputEvent) -> void:
	var focused := get_viewport().gui_get_focus_owner()

	# Ctrl+F — перейти в поиск (проверяем раньше остальных: в «F» ещё и избранное).
	if event is InputEventKey and event.pressed and event.keycode == KEY_F and event.ctrl_pressed:
		%Search.grab_focus()
	elif event.is_action_pressed("ui_cancel") and focused == %Search:
		# Esc в поиске: сначала стираем текст, вторым нажатием — обратно к карточкам.
		if %Search.text != "":
			%Search.clear()
			_apply_filter()  # clear() не вызывает text_changed
		else:
			_focus_first_card()
	elif event.is_action_pressed("ui_cancel"):
		SceneRouter.back()
	elif event.is_action_pressed("favorite") and focused is GameCard:
		# В избранном карточка не исчезает сразу, даже если звезду сняли:
		# иначе фокус «прыгнул» бы. Список обновится при следующем открытии.
		Library.toggle_favorite(focused.game)
		focused.refresh()
	elif event.is_action_pressed("details") and focused is GameCard:
		_next_version(focused.game)
	elif event.is_action_pressed("genre") and %GenreButton.visible and not _genre_list.visible:
		_open_genres()
	elif event.is_action_pressed("menu") and focused is GameCard and not Family.is_on():
		_cover_picker.open(focused.game, focused)
	elif event.is_action_pressed("page_left"):
		_switch_system(-1)
	elif event.is_action_pressed("page_right"):
		_switch_system(1)
	elif focused == null and _is_direction(event):
		# Фокуса нет (прокрутили колесом так, что выделенная игра ушла
		# за край) — стрелка возвращает его на выделенную игру.
		if %Grid.selected >= 0:
			%Grid.select(%Grid.selected)
		else:
			_focus_first_card()
	else:
		return  # нажатие нам не нужно — пусть идёт дальше
	get_viewport().set_input_as_handled()


func _is_direction(event: InputEvent) -> bool:
	for action in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		if event.is_action_pressed(action):
			return true
	return false


func _next_version(group: Dictionary) -> void:
	if group["variants"].size() < 2:
		SceneRouter.toast(tr("У этой игры только одна версия"))
		return
	var variant := Library.choose_next_variant(group)
	_show_info(group)
	SceneRouter.toast(tr("Версия: %s") % variant["version"])


func _is_favorites() -> bool:
	return system_id == Library.FAVORITES


# Переключиться на соседнюю приставку (по кругу).
# Избранное — тоже «приставка» в этом круге (см. Library.browse_ids).
func _switch_system(step: int) -> void:
	var ids := Library.browse_ids()
	if ids.size() < 2:
		return
	var index := ids.find(system_id)
	var next_id := ids[(index + step + ids.size()) % ids.size()]
	# Жанр берём с собой: смотрел платформеры NES — на SNES тоже платформеры.
	# Если у той приставки такого жанра нет, она покажет все игры.
	SceneRouter.replace("library", {"system": next_id, "genre": _genre})


# Карточка — это игра (группа версий). Открываем её страницу.
# Передаём не саму группу, а её ключ: пока мы играем, библиотека
# пересобирает группы, и старый словарь устарел бы.
func _on_game_pressed(group: Dictionary) -> void:
	# Запоминаем, где были: SceneRouter вернёт эти параметры по «Назад».
	SceneRouter.params["focus_key"] = group["key"]
	SceneRouter.params["search"] = %Search.text
	SceneRouter.params["genre"] = _genre
	SceneRouter.go_to("details", {"key": group["key"]})


# Крупный интерфейс («Для телевизора» в настройках): экран в пересчёте
# на «виртуальные» пиксели становится уже. Тогда панель справа с данными
# игры прячем (то же самое есть на странице игры), а поиск делаем короче —
# так сетке остаётся место хотя бы на 3 колонки.
func _fit_to_screen() -> void:
	if UiTheme.is_compact(self):
		$Margin/VBox/Body/Info.visible = false
		%Search.custom_minimum_size.x = 200
