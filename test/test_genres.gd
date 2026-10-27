extends TestCase
## Жанры по папкам и фильтр по жанру в библиотеке.

const FOLDER := "user://test_genres"
## Файлы для теста: папки — как у настоящей коллекции.
const FILES := [
	"NES(Famicom)/Platformer/Mega Man 2/Mega Man 2 (USA).nes",
	"NES(Famicom)/Platformer/Kirby's Adventure/Kirby's Adventure (USA).nes",
	"NES(Famicom)/Beat 'em Up/Double Dragon/Double Dragon (USA).nes",
	"NES(Famicom)/Sports/Pinball/Pinball (Japan).nes",
	"NES(Famicom)/_Unsorted/Unknown Game (China).nes",
	"SuperNES/Platformer/Super Mario World/Super Mario World (USA).sfc",
	"SuperNES/RPG/Chrono Trigger/Chrono Trigger (USA).sfc",
]


func before_each() -> void:
	for file: String in FILES:
		var path := FOLDER.path_join(file)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		FileAccess.open(path, FileAccess.WRITE).store_string("x")
	Settings.set_value("library", "folders", PackedStringArray([ProjectSettings.globalize_path(FOLDER)]))
	Library.scan()


func after_each() -> void:
	Settings.set_value("library", "folders", PackedStringArray())
	Library.scan()
	_remove(ProjectSettings.globalize_path(FOLDER))
	while SceneRouter._busy:
		await frames(1)
	SceneRouter.go_to("home")
	await frames(3)


func test_genre_from_folder() -> void:
	about("Жанр узнаётся по папке, как бы её ни назвали")
	var roots := PackedStringArray(["D:/Game_archive"])
	check_eq(Genres.from_path("D:/Game_archive/NES(Famicom)/Platformer/Mega Man/Mega Man (U).nes", roots), "platformer")
	check_eq(Genres.from_path("D:/Game_archive/NES(Famicom)/Beat 'em Up/Double Dragon/DD.nes", roots), "beat_em_up", "апостроф и пробелы")
	check_eq(Genres.from_path("D:/Game_archive/SuperNES/Board, Card & Mahjong/x.sfc", roots), "board", "запятые и &")
	check_eq(Genres.from_path("D:\\Game_archive\\SonyPlayStation1\\Survival Horror\\Silent Hill\\SH.cue", roots), "horror", "путь с обратными чертами")
	check_eq(Genres.from_path("D:/Game_archive/NES(Famicom)/Sports/Pinball/Pinball.nes", roots), "sports", "игра «Pinball» в папке Sports — спорт")
	check_eq(Genres.from_path("D:/Game_archive/NES(Famicom)/_Unsorted/x.nes", roots), "", "_Unsorted — не жанр")
	check_eq(Genres.from_path("D:/Игры/Денди/Платформеры/x.nes", PackedStringArray(["D:/Игры"])), "platformer", "русские папки")
	check_eq(Genres.from_path("D:/Action/NES/x.nes", PackedStringArray(["D:/Action"])), "", "сама папка с играми — не жанр")
	check_eq(Genres.from_path("D:/Game_archive/NES/Puzzle.nes", roots), "", "имя файла — не папка")


func test_library_knows_genres() -> void:
	about("Library записывает жанр в каждую игру")
	var mega := _group("Mega Man 2")
	check_eq(mega.get("genre"), "platformer")
	check_eq(_group("Unknown Game").get("genre"), "", "игра из _Unsorted — без жанра")
	check_eq(_group("Chrono Trigger").get("genre"), "rpg")


func test_library_genre_filter() -> void:
	about("Кнопка жанра: только жанры этой приставки, фильтр и переход на другую приставку")
	while SceneRouter._busy:  # прошлый переход ещё идёт — новый он не начнёт
		await frames(1)
	SceneRouter.go_to("library", {"system": "nes"})
	await _wait()
	var screen := get_tree().current_scene
	var grid: VirtualGrid = screen.get_node("%Grid")
	check(screen.get_node("%GenreButton").visible, "кнопка жанра видна")
	check_eq(grid.items.size(), 5, "сначала — все игры NES")

	screen._open_genres()
	await frames(1)
	var labels: Array = screen._genre_list._list.get_children().map(func(b: Button) -> String: return b.text)
	check_eq(labels.size(), 5, "Все жанры + платформер, beat 'em up, спорт, без жанра")
	check(labels[0].ends_with("· 5"), "«Все жанры · 5»: " + labels[0])

	screen._genre_list._choose("platformer")
	await frames(1)
	check_eq(grid.items.map(func(g: Dictionary) -> String: return g["title"]), ["Kirby's Adventure", "Mega Man 2"], "остались платформеры")
	check(get_viewport().gui_get_focus_owner() is GameCard, "после выбора фокус — на первой игре")
	# Карточки переиспользуются (см. VirtualGrid) — проверяем, что на них новые игры.
	var first := grid.card_for(0)
	check(first != null and first.game["title"] == "Kirby's Adventure", "карточка №0 показывает Kirby, а не старую игру")

	# LB/RB на SNES: жанр сохраняется.
	screen._switch_system(1)
	await _wait()
	screen = get_tree().current_scene
	grid = screen.get_node("%Grid")
	check_eq(screen._genre, "platformer", "на SNES — тоже платформеры")
	check_eq(grid.items.size(), 1, "Super Mario World")

	screen._choose_genre(Genres.NONE)
	check_eq(screen._genre, Genres.NONE)
	check_eq(grid.items.size(), 0, "на SNES нет игр без жанра")


func _group(title: String) -> Dictionary:
	for group: Dictionary in Library.groups:
		if group["title"] == title:
			return group
	check(false, "нет игры «%s»" % title)
	return {}


func _wait() -> void:
	await frames(2)
	while SceneRouter._busy:
		await frames(1)
	await frames(3)


func _remove(path: String) -> void:
	for sub in DirAccess.get_directories_at(path):
		_remove(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func test_genre_hotkey_and_header_keys() -> void:
	about("Жанры открываются кнопкой View / G; из поиска стрелкой вправо — к кнопкам")
	while SceneRouter._busy:
		await frames(1)
	SceneRouter.go_to("library", {"system": "nes"})
	await _wait()
	var screen := get_tree().current_scene
	var grid: VirtualGrid = screen.get_node("%Grid")
	grid.select(2)
	await frames(1)
	var card := get_viewport().gui_get_focus_owner()
	check(card is GameCard, "фокус на карточке")

	_press_key(KEY_G)
	await frames(2)
	check(screen._genre_list.visible, "G открыл список жанров")
	_press_key(KEY_ESCAPE)
	await frames(2)
	check(not screen._genre_list.visible, "Esc закрыл список")
	check_eq(get_viewport().gui_get_focus_owner(), card, "фокус вернулся на ту же карточку")

	# Поле поиска: курсор в конце, стрелка вправо — на кнопку сортировки.
	var search: LineEdit = screen.get_node("%Search")
	search.grab_focus()
	await frames(1)
	search.text = "ab"
	search.caret_column = 1
	_press_key(KEY_RIGHT)
	await frames(1)
	check_eq(get_viewport().gui_get_focus_owner(), search, "курсор не в конце — стрелка двигает курсор")
	check_eq(search.caret_column, 2)
	_press_key(KEY_RIGHT)
	await frames(1)
	check_eq(get_viewport().gui_get_focus_owner(), screen.get_node("%SortButton"), "в конце — ушли на сортировку")
	_press_key(KEY_RIGHT)
	await frames(1)
	check_eq(get_viewport().gui_get_focus_owner(), screen.get_node("%GenreButton"), "дальше — кнопка жанра")
	search.text = ""


func _press_key(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
