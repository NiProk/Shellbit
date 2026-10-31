extends TestCase
## Аркадные игры: настоящие названия вместо «sf2», версии в одной карточке, BIOS скрыт.

const FOLDER := "user://test_arcade"


func test_names_table() -> void:
	about("Таблица FinalBurn Neo: название, версия, родитель, BIOS")
	var sf2 := ArcadeNames.parse("D:/Arcade/sf2.zip")
	check_eq(sf2["title"], "Street Fighter II: The World Warrior")
	check_eq(sf2["label"], "World 910522", "версия — из скобок")
	var clone := ArcadeNames.parse("D:/Arcade/sf2ua.zip")
	check_eq(clone["group"], "sf2", "клон — в карточке родителя")
	check(clone["score"] < sf2["score"], "по умолчанию запускаем родителя")
	check(ArcadeNames.is_bios("D:/Arcade/neogeo.zip"), "neogeo.zip — BIOS")
	check(not ArcadeNames.is_bios("D:/Arcade/mslug.zip"), "mslug.zip — игра")
	check(ArcadeNames.knows("D:/Arcade/MSLUG.ZIP"), "большие буквы в имени — не помеха")
	check(not ArcadeNames.knows("D:/Arcade/my_hack.zip"), "неизвестный архив — нет в таблице")


func test_library() -> void:
	about("В библиотеке: «Street Fighter II» с двумя версиями, без neogeo.zip; год и разработчик")
	DirAccess.make_dir_recursive_absolute(FOLDER)
	for name in ["sf2", "sf2ua", "neogeo"]:
		var zip := ZIPPacker.new()
		zip.open(ProjectSettings.globalize_path(FOLDER.path_join(name + ".zip")))
		zip.start_file(name + ".bin")  # внутри «микросхема» — не файл приставки
		zip.write_file("x".to_utf8_buffer())
		zip.close_file()
		zip.close()
	Settings.set_value("library", "folders", PackedStringArray([ProjectSettings.globalize_path(FOLDER)]))
	Library.scan()
	var groups := Library.groups_for_system("arcade")
	check_eq(groups.size(), 1, "одна карточка: neogeo.zip скрыт, sf2ua — версия sf2")
	if groups.size() == 1:
		check_eq(groups[0]["title"], "Street Fighter II: The World Warrior")
		check_eq(groups[0]["variants"].size(), 2, "две версии")
		var info := GameInfo.lookup(groups[0])
		check_eq([info["year"], info["developer"]], ["1991", "Capcom"])
	Settings.set_value("library", "folders", PackedStringArray())
	Library.scan()
	for file in DirAccess.get_files_at(ProjectSettings.globalize_path(FOLDER)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FOLDER.path_join(file)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FOLDER))


func test_neogeo_bios_check() -> void:
	about("Metal Slug без neogeo.zip — понятная ошибка; с neogeo.zip рядом — всё в порядке")
	check_eq(ArcadeNames.bios_of("D:/Arcade/mslug2.zip"), "neogeo")
	check_eq(ArcadeNames.bios_of("D:/Arcade/sf2.zip"), "", "Street Fighter II — без BIOS")
	check_eq(ArcadeNames.bios_title("neogeo"), "Neo Geo")
	DirAccess.make_dir_recursive_absolute(FOLDER)
	var folder := ProjectSettings.globalize_path(FOLDER)
	var player: Control = load("res://scenes/player/Player.tscn").instantiate()
	player.game = {"system": "arcade", "path": folder.path_join("mslug2.zip")}
	player._content_path = folder.path_join("mslug2.zip")
	check_eq(player._missing_arcade_bios(), "neogeo", "neogeo.zip нет — нужен")
	FileAccess.open(folder.path_join("neogeo.zip"), FileAccess.WRITE).store_string("x")
	check_eq(player._missing_arcade_bios(), "", "положили рядом — нашёлся")
	player.free()
	DirAccess.remove_absolute(folder.path_join("neogeo.zip"))
	DirAccess.remove_absolute(folder)
