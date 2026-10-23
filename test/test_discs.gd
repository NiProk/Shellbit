extends TestCase
## Многодисковые игры: список дисков (.m3u), какой диск запомнить, меню паузы.

const FOLDER := "user://test_discs"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(FOLDER)
	for name in ["Final Fantasy VII (USA) (Disc 1).cue", "Final Fantasy VII (USA) (Disc 2).cue",
			"Final Fantasy VII (USA) (Disc 3).cue", "Final Fantasy VII (Europe) (Disc 1).cue",
			"Crash Bandicoot (USA).cue"]:
		FileAccess.open(FOLDER.path_join(name), FileAccess.WRITE).store_string("x")


func after_each() -> void:
	for file in DirAccess.get_files_at(FOLDER):
		DirAccess.remove_absolute(FOLDER.path_join(file))
	DirAccess.remove_absolute(FOLDER)


func test_playlist_from_discs() -> void:
	about("Из «(Disc 1)», «(Disc 2)», «(Disc 3)» составляется .m3u")
	var disc2 := ProjectSettings.globalize_path(FOLDER.path_join("Final Fantasy VII (USA) (Disc 2).cue"))
	var playlist := Discs.playlist_for(disc2, "psx")
	check_eq(playlist.get("index"), 1, "выбран второй диск — с него и начинаем")
	check_eq(playlist.get("disc_path"), disc2)
	var lines := FileAccess.get_file_as_string(playlist.get("path", "")).strip_edges().split("\n")
	check_eq(lines.size(), 3, "в списке три диска — европейская версия сюда не попала")
	check(lines[0].ends_with("(Disc 1).cue") and lines[2].ends_with("(Disc 3).cue"), "диски по порядку")


func test_no_playlist_for_single_disc() -> void:
	about("Однодисковая игра и другие приставки — без списка")
	var crash := ProjectSettings.globalize_path(FOLDER.path_join("Crash Bandicoot (USA).cue"))
	check_eq(Discs.playlist_for(crash, "psx"), {}, "у Crash Bandicoot один диск")
	var europe := ProjectSettings.globalize_path(FOLDER.path_join("Final Fantasy VII (Europe) (Disc 1).cue"))
	check_eq(Discs.playlist_for(europe, "psx"), {}, "рядом нет других дисков этой версии")
	var disc1 := ProjectSettings.globalize_path(FOLDER.path_join("Final Fantasy VII (USA) (Disc 1).cue"))
	check_eq(Discs.playlist_for(disc1, "snes"), {}, "у SNES дисков не бывает")


func test_save_remembers_disc() -> void:
	about("Сохранение помнит диск, загрузка сначала вставляет его")
	var core: Node = load("res://test/MockCore.gd").new()
	add_child(core)
	var game := {"path": ProjectSettings.globalize_path(FOLDER.path_join("game.m3u"))}
	core.disk_count = 3
	core.disk_index = 1
	check(SaveStates.save_slot(core, game, "1"), "сохранились")
	check_eq(SaveStates.disc_of(game, "1"), {"index": 1, "path": "disc2.cue"})
	core.disk_index = 0  # потом человек вставил первый диск
	check(SaveStates.load_slot(core, game, "1"), "загрузились")
	check_eq(core.disk_index, 1, "перед загрузкой вставлен второй диск")
	SaveStates.remove(game, "1")
	DirAccess.remove_absolute(SaveStates._discs_path(game))
	DirAccess.remove_absolute(SaveStates._dir(game))
	core.queue_free()


func test_pause_menu_disc_button() -> void:
	about("«Сменить диск» в меню паузы — только у многодисковых игр")
	var menu: Control = load("res://scenes/pause/PauseMenu.tscn").instantiate()
	add_child(menu)
	await frames(1)
	menu.open({"title": "Test", "path": "x.cue"})
	check(not menu.get_node("%DiscButton").visible, "один диск — кнопки нет")
	menu.open({"title": "Test", "path": "x.m3u"}, {"count": 3, "index": 1})
	check(menu.get_node("%DiscButton").visible, "три диска — кнопка есть")
	check(menu.get_node("%DiscButton").text.contains("2"), "на кнопке — какой диск сейчас")
	menu.queue_free()
