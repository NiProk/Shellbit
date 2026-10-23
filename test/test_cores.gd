extends TestCase
## Скачивание ядер: адреса, распаковка архива, кнопки в интерфейсе.
## В интернет тесты не ходят: архив с «ядром» собираем сами.

const WORK := "user://test_cores"


func after_each() -> void:
	# Убираем «ядро» NES, которое кладут тесты, и папку с архивами.
	var nes_core := CoreManager.core_path(CoreManager.get_system("nes"))
	if FileAccess.file_exists(nes_core):
		DirAccess.remove_absolute(nes_core)
	var dir := ProjectSettings.globalize_path(WORK)
	if DirAccess.dir_exists_absolute(dir):
		for file in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file))
		DirAccess.remove_absolute(dir)


func test_url() -> void:
	about("Адрес ядра на сервере libretro")
	check_eq(CoreDownloader.url_for("fceumm_libretro.dll"),
			"https://buildbot.libretro.com/nightly/%s/latest/fceumm_libretro.dll.zip" % CoreDownloader.platform_dir())
	check(CoreDownloader.platform_dir() in ["windows/x86_64", "linux/x86_64"], "папка для Windows или Linux")


func test_extract() -> void:
	about("Ядро достаётся из архива, временных файлов не остаётся")
	var zip_path := _make_zip("fceumm_libretro.dll", "ЯДРО")
	var dest := _path("fceumm_libretro.dll")
	check_eq(CoreDownloader.extract_core(zip_path, "fceumm_libretro.dll", dest), "")
	check_eq(FileAccess.get_file_as_string(dest), "ЯДРО")
	check(not FileAccess.file_exists(dest + ".tmp"), "временный .tmp удалён")
	# Ядро уже было — новое заменяет старое.
	check_eq(CoreDownloader.extract_core(_make_zip("fceumm_libretro.dll", "НОВОЕ"), "fceumm_libretro.dll", dest), "")
	check_eq(FileAccess.get_file_as_string(dest), "НОВОЕ")


func test_extract_errors() -> void:
	about("Плохой архив — понятная ошибка, а не сломанное ядро")
	var dest := _path("snes9x_libretro.dll")
	var wrong := CoreDownloader.extract_core(_make_zip("other.dll", "x"), "snes9x_libretro.dll", dest)
	check(wrong.contains("snes9x_libretro.dll"), "нет файла в архиве: «%s»" % wrong)
	var broken_path := _path("broken.zip")
	FileAccess.open(broken_path, FileAccess.WRITE).store_string("это не zip")
	check(CoreDownloader.extract_core(broken_path, "snes9x_libretro.dll", dest) != "", "повреждённый архив")
	check(not FileAccess.file_exists(dest), "сломанное ядро не появилось")


func test_missing_systems() -> void:
	about("Список приставок без ядра обновляется, когда ядро появилось")
	var before := CoreDownloader.missing_systems().size()
	check_eq(before, CoreManager.systems.size(), "в песочнице ядер нет ни одного")
	var nes_core := CoreManager.core_path(CoreManager.get_system("nes"))
	FileAccess.open(nes_core, FileAccess.WRITE).store_string("ядро")
	check_eq(CoreDownloader.missing_systems().size(), before - 1, "у NES ядро есть")


func test_cores_page() -> void:
	about("В «Ядрах и BIOS» есть «Скачать недостающие» и «Скачать» у приставок")
	SceneRouter.params = {"page": "cores"}
	var screen: Control = load("res://scenes/settings/SettingsScreen.tscn").instantiate()
	add_child(screen)
	await frames(3)
	var rows: Array = screen.get_node("%Rows").get_children()
	check_eq(rows[0].title, "Скачать недостающие ядра")
	var download_rows := rows.filter(func(row: SettingRow) -> bool: return row.info_text == "Скачать")
	check_eq(download_rows.size(), CoreManager.systems.size(), "у каждой приставки — «Скачать»")
	# Проценты из CoreDownloader появляются в строке.
	screen._on_core_progress("fceumm_libretro." + ("dll" if OS.get_name() == "Windows" else "so"), 45)
	check(rows.any(func(row: SettingRow) -> bool: return row.info_text == "45 %"), "в строке NES — 45 %")
	screen.queue_free()


func test_player_download_button() -> void:
	about("На экране игры «Скачать ядро» появляется, только если нет ядра")
	SceneRouter.params = {"game": {"system": "nes", "path": "x.nes", "title": "X"}}
	var player: Control = load("res://scenes/player/Player.tscn").instantiate()
	add_child(player)
	await frames(2)
	player._missing_core = true
	player._show_error("нет ядра")
	check(player.get_node("%DownloadButton").visible, "кнопка видна")
	check(player.get_node("%DownloadButton").has_focus(), "и выбрана — нажать A")
	player._missing_core = false
	player._show_error("другая ошибка")
	check(not player.get_node("%DownloadButton").visible, "при другой ошибке кнопки нет")
	player.queue_free()


# --- Помощники ----------------------------------------------------------------

func _path(file: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK))
	return ProjectSettings.globalize_path(WORK.path_join(file))


# Собрать zip с одним файлом — как на сервере libretro.
# ZIPPacker — встроенный в Godot класс для создания zip-архивов.
func _make_zip(file_name: String, content: String) -> String:
	var zip_path := _path(file_name + ".zip")
	var zip := ZIPPacker.new()
	zip.open(zip_path)
	zip.start_file(file_name)
	zip.write_file(content.to_utf8_buffer())
	zip.close_file()
	zip.close()
	return zip_path
