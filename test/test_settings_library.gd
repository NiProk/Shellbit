extends TestCase
## Настройки, переезд данных и библиотека игр.

const FIXTURE_ROMS := "res://test/fixtures/roms"


func after_each() -> void:
	Settings.set_value("library", "folders", PackedStringArray())
	Library.scan()
	for path in ["user://test_copy_from", "user://test_copy_to"]:
		_remove_dir(ProjectSettings.globalize_path(path))


func test_defaults() -> void:
	about("Пока настройку не меняли, берётся значение по умолчанию")
	check_eq(Settings.get_value("play", "ff_speed"), 3)
	check_eq(Settings.get_value("audio", "ui_sounds"), true)
	check_eq(Settings.get_value("нет_такого", "ключа", 42), 42, "своё значение по умолчанию")


func test_set_and_erase() -> void:
	about("Настройка сохраняется, а null её удаляет")
	Settings.set_value("test", "value", 7)
	check_eq(Settings.get_value("test", "value", 0), 7)
	Settings.set_value("test", "value", null)
	check_eq(Settings.get_value("test", "value", 0), 0)


func test_copy_dir() -> void:
	about("Переезд данных копирует вложенные папки и не трогает лишнее")
	var from := ProjectSettings.globalize_path("user://test_copy_from")
	var to := ProjectSettings.globalize_path("user://test_copy_to")
	_write(from.path_join("settings.cfg"), "новые")
	_write(from.path_join("states/nes/auto.state"), "сохранение")
	_write(from.path_join("logs/godot.log"), "журнал")
	_write(to.path_join("settings.cfg"), "уже было")  # такой файл на новом месте не трогаем
	var count := Settings._copy_dir(from, to)
	check_eq(count, 1, "скопирован один файл — сохранение")
	check(FileAccess.file_exists(to.path_join("states/nes/auto.state")), "вложенная папка скопирована")
	check(not DirAccess.dir_exists_absolute(to.path_join("logs")), "журналы Godot не копируются")
	check_eq(FileAccess.get_file_as_string(to.path_join("settings.cfg")), "уже было")


func test_scan_fixture_games() -> void:
	about("Библиотека находит игры и складывает версии вместе")
	Settings.set_value("library", "folders", PackedStringArray([ProjectSettings.globalize_path(FIXTURE_ROMS)]))
	Library.scan()
	# Contra (USA) и (Japan) — одна игра; readme.txt — не игра; Mega Man 2 — во вложенной папке.
	check_eq(Library.groups.size(), 5, "игр всего")
	check_eq(Library.groups_for_system("nes").size(), 4, "игр NES")
	check_eq(Library.groups_for_system("gb").size(), 1, "игр Game Boy")
	var contra := _group("Contra")
	check_eq(contra.get("variants", []).size(), 2, "у Contra две версии")


func test_favorites() -> void:
	about("Избранное добавляется и убирается")
	Settings.set_value("library", "folders", PackedStringArray([ProjectSettings.globalize_path(FIXTURE_ROMS)]))
	Library.scan()
	var tetris := _group("Tetris")
	Library.toggle_favorite(tetris)
	check_eq(Library.favorite_groups().size(), 1)
	Library.toggle_favorite(Library.find_group(tetris["key"]))
	check_eq(Library.favorite_groups().size(), 0)


# --- Помощники ----------------------------------------------------------------

func _group(title: String) -> Dictionary:
	for group in Library.groups:
		if group["title"] == title:
			return group
	failures.append("нет игры «%s»" % title)
	return {}


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.open(path, FileAccess.WRITE).store_string(text)


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	for sub in dir.get_directories():
		_remove_dir(path.path_join(sub))
	DirAccess.remove_absolute(path)
