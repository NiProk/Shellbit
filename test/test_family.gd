extends TestCase
## Детский режим: что прячется и как из него выйти.

const FOLDER := "user://test_family"


func before_each() -> void:
	for file in ["NES/Platformer/Mario/Mario (USA).nes", "NES/Adult/Grown Up Game/Grown Up Game (USA).nes"]:
		var path := FOLDER.path_join(file)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		FileAccess.open(path, FileAccess.WRITE).store_string("x")
	Settings.set_value("library", "folders", PackedStringArray([ProjectSettings.globalize_path(FOLDER)]))
	Library.scan()


func after_each() -> void:
	Family.disable()
	Settings.set_value("library", "folders", PackedStringArray())
	Library.scan()
	_remove(ProjectSettings.globalize_path(FOLDER))
	if SceneRouter._pin_dialog:
		SceneRouter._pin_dialog.close()
	await _open("home")


func test_pin_check() -> void:
	about("PIN-код: верный подходит, неверный — нет, хранится не открытым текстом")
	Family.enable("2580")
	check(Family.is_on(), "режим включён")
	check(Family.check_pin("2580"), "верный PIN подходит")
	check(not Family.check_pin("1234"), "неверный — нет")
	check(not str(Settings.get_value("family", "pin_hash", "")).contains("2580"), "в настройках не сам PIN, а отпечаток")


func test_adult_games_hidden() -> void:
	about("Игры «Для взрослых» в детском режиме не видны")
	check_eq(Library.groups_for_system("nes").size(), 2, "без режима — обе игры")
	Family.enable("1111")
	var titles := Library.groups_for_system("nes").map(func(g: Dictionary) -> String: return g["title"])
	check_eq(titles, ["Mario"], "в детском режиме — только Mario")


func test_home_buttons() -> void:
	about("Главный экран: в детском режиме нет «+ Папка», «Выход», а «Настройки» — «Родителям»")
	Family.enable("1111")
	await _open("home")
	var home := get_tree().current_scene
	check(not home.get_node("%AddFolderButton").visible, "«+ Папка с играми» спрятана")
	check(not home.find_child("QuitButton", true, false).visible, "«Выход» спрятан")
	check_eq(home._settings_button.text, tr("Родителям"))


func test_settings_need_pin() -> void:
	about("Настройки открываются только по PIN-коду, и он выключает режим")
	Family.enable("2580")
	await _open("home")
	SceneRouter.go_to("settings")
	await frames(2)
	check_eq(get_tree().current_scene.scene_file_path, SceneRouter.SCENES["home"], "без PIN остаёмся на главном")
	check(SceneRouter._pin_dialog.visible, "появилось окно PIN-кода")
	SceneRouter._pin_dialog.entered.emit("0000")
	check(Family.is_on(), "неверный PIN — режим остался")
	check(SceneRouter._pin_dialog.visible, "окно не закрылось")
	SceneRouter._pin_dialog.entered.emit("2580")
	check(not Family.is_on(), "верный PIN — режим выключен")
	await _wait_router()
	check_eq(get_tree().current_scene.scene_file_path, SceneRouter.SCENES["settings"], "открылись настройки")


func _open(screen: String, params := {}) -> void:
	while SceneRouter._busy:
		await frames(1)
	SceneRouter.go_to(screen, params)
	await _wait_router()


func _wait_router() -> void:
	await frames(2)
	while SceneRouter._busy:
		await frames(1)
	await frames(2)


func _remove(path: String) -> void:
	for sub in DirAccess.get_directories_at(path):
		_remove(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
