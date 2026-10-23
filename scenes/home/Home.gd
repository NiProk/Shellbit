extends Control
## Главный экран: «Продолжить играть» + плитки приставок.

# preload загружает сцену один раз, при запуске игры.
# Потом из неё можно сколько угодно раз «печатать» копии через instantiate().
const GameCardScene := preload("res://scenes/components/GameCard.tscn")
const ConsoleTileScene := preload("res://scenes/components/ConsoleTile.tscn")


func _ready() -> void:
	%AddFolderButton.pressed.connect(_on_add_folder_pressed)
	_add_settings_button()
	_add_quit_button()
	%FolderDialog.dir_selected.connect(_on_folder_selected)
	Library.scan_finished.connect(_refresh)

	# Часы в углу обновляем раз в секунду.
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(_update_clock)
	add_child(timer)
	timer.start()
	_update_clock()

	%Hints.set_hints([["accept", "Открыть"], ["details", "Обновить список"], ["menu", "Настройки"]])
	_refresh()

	# Данные только что переехали в свою папку — скажем об этом один раз.
	if Settings.moved_from != "":
		SceneRouter.toast(tr("Данные Shellbit перенесены в новую папку: %s") % ProjectSettings.globalize_path("user://"))
		Settings.moved_from = ""


## Перерисовать всё: карточки недавних игр и плитки приставок.
func _refresh() -> void:
	_clear(%RecentRow)
	_clear(%SystemsRow)

	# --- Недавние игры ---
	var recent := Library.get_recent(10)
	for i in recent.size():
		var card: GameCard = GameCardScene.instantiate()
		%RecentRow.add_child(card)
		card.setup(recent[i], GameCard.Style.WIDE_BIG if i == 0 else GameCard.Style.WIDE)
		card.pressed.connect(_on_game_pressed.bind(recent[i]))
	%RecentTitle.visible = not recent.is_empty()
	%RecentScroll.visible = not recent.is_empty()

	# --- Плитка «★ Избранное» — первой в ряду приставок ---
	var favorites := Library.favorite_groups()
	if not favorites.is_empty():
		var fav_tile: ConsoleTile = ConsoleTileScene.instantiate()
		%SystemsRow.add_child(fav_tile)
		# Плитка ждёт описание приставки — даём ей «приставку-подборку».
		fav_tile.setup({
			"id": Library.FAVORITES,
			"short": "★ " + tr("Избранное"),
			"name": "Избранное",
			"color": Library.FAVORITES_COLOR,
		}, favorites.size())
		fav_tile.pressed.connect(_on_system_pressed.bind(Library.FAVORITES))

	# --- Приставки, у которых есть игры ---
	var system_ids := Library.systems_with_games()
	for system_id in system_ids:
		var tile: ConsoleTile = ConsoleTileScene.instantiate()
		%SystemsRow.add_child(tile)
		tile.setup(CoreManager.get_system(system_id), Library.groups_for_system(system_id).size())
		tile.pressed.connect(_on_system_pressed.bind(system_id))
	%SystemsTitle.visible = not system_ids.is_empty()
	%SystemsScroll.visible = not system_ids.is_empty()

	%EmptyState.visible = Library.groups.is_empty()

	# Ставим фокус на первый элемент. call_deferred — «сделать в конце кадра»,
	# когда новые карточки уже точно встанут на свои места.
	_focus_first.call_deferred()


func _focus_first() -> void:
	# Вернулись из библиотеки или из игры — фокус туда же, где был.
	var remembered: String = SceneRouter.params.get("focus", "")
	for row: Control in [%RecentRow, %SystemsRow]:
		for item: Control in row.get_children():
			if remembered != "" and _focus_id(item) == remembered:
				item.grab_focus()
				return
	for row: Control in [%RecentRow, %SystemsRow]:
		if row.is_visible_in_tree() and row.get_child_count() > 0:
			row.get_child(0).grab_focus()
			return
	%AddFolderButton.grab_focus()


## Что за элемент: "game:nes_contra" для карточки игры, "system:nes" для плитки.
func _focus_id(item: Control) -> String:
	if item is GameCard:
		return "game:" + item.game["key"]
	if item is ConsoleTile:
		return "system:" + item.system_id
	return ""


func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _update_clock() -> void:
	var t := Time.get_time_dict_from_system()
	%Clock.text = "%02d:%02d" % [t["hour"], t["minute"]]


# _unhandled_input получает нажатия, которые не забрали кнопки.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		SceneRouter.go_to("settings")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("details"):
		Library.scan()
		SceneRouter.toast(tr("Список игр обновлён: %s") % Library.count_text(Library.groups.size()))
		get_viewport().set_input_as_handled()
	# Если фокус потерялся (например, кликнули мышью в пустоту),
	# любое нажатие стрелки возвращает его на первый элемент.
	elif get_viewport().gui_get_focus_owner() == null and _is_direction(event):
		_focus_first()
		get_viewport().set_input_as_handled()


func _is_direction(event: InputEvent) -> bool:
	for action in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		if event.is_action_pressed(action):
			return true
	return false


# Кнопка «Настройки» в шапке, рядом с «+ Папка с играми».
# Создаём её из кода: так не нужно менять сцену Home.tscn.
func _add_settings_button() -> void:
	var button := Button.new()
	button.text = tr("Настройки")
	# add_sibling — поставить новую кнопку сразу после «+ Папка с играми»,
	# в тот же ряд. Внешний вид она возьмёт из общей темы UiTheme.
	%AddFolderButton.add_sibling(button)
	button.pressed.connect(SceneRouter.go_to.bind("settings"))
	button.mouse_entered.connect(button.grab_focus)


# Кнопка «Выход» — последней в шапке. Выход — в два нажатия:
# с геймпада легко нажать A лишний раз, а закрытая программа — это обидно.
func _add_quit_button() -> void:
	var button := Button.new()
	button.name = "QuitButton"
	button.text = tr("Выход")
	# В шапку, сразу перед часами: «+ Папка с играми», «Настройки», «Выход», 12:34.
	var header := %Clock.get_parent()
	header.add_child(button)
	header.move_child(button, %Clock.get_index())
	button.mouse_entered.connect(button.grab_focus)
	button.pressed.connect(func() -> void:
		if button.get_meta("armed", false):
			get_tree().quit()  # настройки и библиотека уже сохранены на диск
		else:
			button.set_meta("armed", true)
			button.text = tr("Точно выйти? Нажмите ещё раз"))
	# Ушли с кнопки — отменяем «Точно выйти?».
	button.focus_exited.connect(func() -> void:
		button.set_meta("armed", false)
		button.text = tr("Выход"))


# --- Обработчики нажатий -------------------------------------------------

func _on_add_folder_pressed() -> void:
	%FolderDialog.popup_centered_ratio(0.7)


func _on_folder_selected(path: String) -> void:
	Settings.add_rom_folder(path)
	Library.scan()  # после поиска сработает сигнал scan_finished → _refresh()
	SceneRouter.toast(tr("Найдено: %s") % Library.count_text(Library.groups.size()))


func _on_system_pressed(system_id: String) -> void:
	SceneRouter.params["focus"] = "system:" + system_id  # вернёмся — фокус на эту плитку
	SceneRouter.go_to("library", {"system": system_id})


# Карточка — это игра (группа версий). Запускаем выбранную версию.
func _on_game_pressed(group: Dictionary) -> void:
	SceneRouter.params["focus"] = "game:" + group["key"]
	SceneRouter.go_to("player", {"game": Library.chosen_variant(group)})
