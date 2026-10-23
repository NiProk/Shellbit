extends TestCase
## Все экраны открываются без ошибок — на всех языках.
## Ошибки в коде экранов (обращение к null, опечатка в имени узла)
## ловит запускалка: тест падает, если во время него была ошибка.

const FIXTURE_ROMS := "res://test/fixtures/roms"


func before_each() -> void:
	Settings.set_value("library", "folders", PackedStringArray([ProjectSettings.globalize_path(FIXTURE_ROMS)]))
	Library.scan()


func after_each() -> void:
	Settings.set_value("library", "folders", PackedStringArray())
	Library.scan()
	Lang.apply(Settings.get_value("general", "language"))
	await _open("home")


func test_main_screens() -> void:
	about("Главный экран, библиотека, страница игры и экран игры открываются")
	check_eq(await _open("home"), "Home")
	check_eq(await _open("library", {"system": "nes"}), "Library")
	check_eq(await _open("library", {"system": Library.FAVORITES}), "Library", "библиотека «Избранное»")
	check_eq(await _open("details", {"key": Library.groups[0]["key"]}), "GameDetails")
	# Ядер в тестах нет — экран игры должен спокойно показать ошибку.
	check_eq(await _open("player", {"game": Library.chosen_variant(Library.groups[0])}), "Player")
	check(get_tree().current_scene.get_node("%Error").visible, "на экране игры — сообщение об ошибке")


func test_settings_pages() -> void:
	about("Все разделы настроек открываются")
	for page in ["folders", "controls", "play", "video", "audio", "language", "cores", "about"]:
		check_eq(await _open("settings", {"page": page, "rows": true}), "SettingsScreen", "раздел " + page)
		check(get_tree().current_scene.get_node("%Rows").get_child_count() > 0, "в разделе %s есть строки" % page)


func test_button_screens() -> void:
	about("«Кнопки приставок» открываются для каждой приставки")
	for system: Dictionary in CoreManager.systems:
		check_eq(await _open("pad_map", {"system": system["id"]}), "PadMapScreen", system["id"])


func test_every_language() -> void:
	about("Главный экран и настройки открываются на всех 9 языках")
	for code: String in Lang.SUPPORTED:
		Lang.apply(code)
		check_eq(await _open("home"), "Home", "язык " + code)
		check_eq(await _open("settings", {"page": "language", "rows": true}), "SettingsScreen", "язык " + code)


func test_language_dropdown() -> void:
	about("Выпадающий список языков открывается и закрывается")
	await _open("settings", {"page": "language", "rows": true})
	var screen := get_tree().current_scene
	screen._open_language_list(screen.get_node("%Rows").get_child(0))
	await frames(2)
	check(screen._dropdown.visible, "список открылся")
	check_eq(screen._dropdown._list.get_child_count(), Lang.CHOICES.size(), "в списке все языки")
	screen._dropdown.close()
	check(not screen._dropdown.visible, "список закрылся")


# Открыть экран через SceneRouter и вернуть имя его сцены ("Home", "Library"…).
func _open(screen: String, params := {}) -> String:
	# Переход идёт с плавной «шторкой» (SceneRouter._busy), и пока она
	# не закончилась, новый переход SceneRouter не начнёт. Ждём её.
	while SceneRouter._busy:
		await frames(1)
	SceneRouter.go_to(screen, params)
	await frames(1)
	while SceneRouter._busy:
		await frames(1)
	await frames(3)  # экрану — пару кадров, чтобы собраться
	var current := get_tree().current_scene
	# Имя узла не годится: корень Library.tscn называется так же, как синглтон
	# Library, и Godot переименовывает его. Поэтому берём имя файла сцены.
	return current.scene_file_path.get_file().get_basename() if current else ""


func test_library_remembers_game() -> void:
	about("Открыл игру, вернулся «Назад» — фокус на той же игре, а не на первой")
	await _open("home")
	await _open("library", {"system": "nes"})
	var cards: Array = get_tree().current_scene.get_node("%Grid").get_children()
	var last: GameCard = cards[-1]
	var key: String = last.game["key"]  # сама карточка исчезнет вместе с экраном
	last.grab_focus()
	last.pressed.emit()  # открыть страницу игры
	await _wait_router()
	check_eq(get_tree().current_scene.scene_file_path.get_file(), "GameDetails.tscn")
	SceneRouter.back()
	await _wait_router()
	await frames(2)
	var focused := get_viewport().gui_get_focus_owner()
	check(focused is GameCard and focused.game["key"] == key, "фокус на последней открытой игре")


func test_home_quit_button() -> void:
	about("На главном экране есть «Выход» — в два нажатия")
	await _open("home")
	var quit: Button = get_tree().current_scene.find_child("QuitButton", true, false)
	check(quit != null, "кнопка есть")
	if quit == null:
		return
	quit.set_meta("armed", false)
	quit.grab_focus()
	quit.pressed.emit()  # первое нажатие только спрашивает (второе закрыло бы тесты)
	check(quit.get_meta("armed", false), "после первого нажатия — «Нажмите ещё раз»")
	quit.release_focus()
	check(not quit.get_meta("armed", false), "ушли с кнопки — вопрос снят")


func _wait_router() -> void:
	await frames(2)
	while SceneRouter._busy:
		await frames(1)
