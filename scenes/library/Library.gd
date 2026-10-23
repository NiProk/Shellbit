extends Control
## Экран библиотеки одной приставки: сетка игр + панель с информацией.
##
## Какую приставку показать, экран узнаёт из SceneRouter.params:
##   SceneRouter.go_to("library", {"system": "snes"})
## Избранное со всех приставок открывается так же:
##   SceneRouter.go_to("library", {"system": Library.FAVORITES})
##
## Каждая карточка — это ИГРА (группа версий), а не отдельный файл.

const GameCardScene := preload("res://scenes/components/GameCard.tscn")
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

	_setup_search_and_sort()
	# Вернулись со страницы игры — восстанавливаем поиск, как был.
	# text = … не вызывает text_changed, фильтр применит _build_grid().
	%Search.text = SceneRouter.params.get("search", "")
	_build_grid()

	%Hints.set_hints([
		["page", "Другая приставка"],
		["accept", "Открыть"],
		["details", "Версия"],
		["favorite", "Избранное"],
		["menu", "Обложка"],
		["search", "Поиск"],
		["cancel", "Назад"],
	])
	add_child(_cover_picker)
	add_child(_keyboard)
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

	%SortButton.pressed.connect(_next_sort)
	%SortButton.mouse_entered.connect(%SortButton.grab_focus)
	_update_sort_button()


## Создать карточки заново — в порядке текущей сортировки.
func _build_grid() -> void:
	for child in %Grid.get_children():
		%Grid.remove_child(child)
		child.queue_free()

	_sort_groups()
	for group: Dictionary in _groups:
		var card: GameCard = GameCardScene.instantiate()
		%Grid.add_child(card)
		card.setup(group, GameCard.Style.COVER)
		card.pressed.connect(_on_game_pressed.bind(group))
		# Когда карточка получает фокус — показываем её данные справа.
		card.focus_entered.connect(_show_info.bind(group))
	_apply_filter()


## Спрятать карточки, в названии которых нет текста из поиска.
## GridContainer сам «сдвигает» видимые карточки — пустых дыр не будет.
func _apply_filter() -> void:
	var query: String = %Search.text.strip_edges()
	var shown := 0
	var first_shown: GameCard = null
	for card: GameCard in %Grid.get_children():
		# findn — поиск БЕЗ учёта регистра: «toad» найдёт «Battletoads».
		# Возвращает место, где нашёлся текст, или −1, если не нашёлся.
		var match_title: bool = query == "" or card.game["title"].findn(query) != -1
		card.visible = match_title
		if match_title:
			shown += 1
			if first_shown == null:
				first_shown = card

	# Панель сведений справа — о первой найденной игре,
	# чтобы там не осталась игра, которую поиск уже спрятал.
	if first_shown:
		_show_info(first_shown.game)

	var total := _groups.size()
	if query == "":
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
	for card: GameCard in %Grid.get_children():
		if card.visible and card.game["key"] == key:
			card.grab_focus()
			# follow_focus прокрутил бы «впритык» — карточка оказалась бы у
			# самого края. Ставим её посередине экрана: так видно и соседей.
			await get_tree().process_frame
			var content: Control = %Scroll.get_child(0)  # то, что прокручивается
			var top := card.global_position.y - content.global_position.y
			%Scroll.scroll_vertical = int(top - (%Scroll.size.y - card.size.y) / 2.0)
			return
	_focus_first_card()


## Поставить фокус на первую видимую карточку. false — если видимых нет.
func _focus_first_card() -> bool:
	for card: Control in %Grid.get_children():
		if card.visible:
			card.grab_focus()
			return true
	return false


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
	elif event.is_action_pressed("menu") and focused is GameCard:
		_cover_picker.open(focused.game, focused)
	elif event.is_action_pressed("page_left"):
		_switch_system(-1)
	elif event.is_action_pressed("page_right"):
		_switch_system(1)
	elif focused == null and event.is_action_pressed("ui_down"):
		_focus_first_card()
	else:
		return  # нажатие нам не нужно — пусть идёт дальше
	get_viewport().set_input_as_handled()


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
	SceneRouter.replace("library", {"system": next_id})


# Карточка — это игра (группа версий). Открываем её страницу.
# Передаём не саму группу, а её ключ: пока мы играем, библиотека
# пересобирает группы, и старый словарь устарел бы.
func _on_game_pressed(group: Dictionary) -> void:
	# Запоминаем, где были: SceneRouter вернёт эти параметры по «Назад».
	SceneRouter.params["focus_key"] = group["key"]
	SceneRouter.params["search"] = %Search.text
	SceneRouter.go_to("details", {"key": group["key"]})
