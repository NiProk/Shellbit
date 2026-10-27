extends TestCase
## Игры переложили в другие папки — избранное, время и сохранения переезжают за ними.

const FOLDER := "user://test_moves"


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(FOLDER)
	Settings.set_value("library", "folders", PackedStringArray([_abs(FOLDER)]))


func after_each() -> void:
	Settings.set_value("library", "folders", PackedStringArray())
	Library.scan()
	_remove(_abs(FOLDER))


func test_moved_game_keeps_data() -> void:
	about("Переложил игру в папку жанра — избранное, время, версия и слоты на месте")
	var old_path := _make("NES/Battletoads/Battletoads (U) [!].nes")
	Library.scan()
	var group := _group("Battletoads")
	Library.toggle_favorite(group)
	Library.add_playtime(group["variants"][0], 600)
	Settings.set_value("versions", group["key"], old_path)
	# Слот сохранения — как его записал бы SaveStates.save_slot.
	var old_states := _abs(SaveStates.ROOT.path_join(old_path.md5_text()))
	DirAccess.make_dir_recursive_absolute(old_states)
	FileAccess.open(old_states.path_join("1.state"), FileAccess.WRITE).store_string("STATE")

	var new_path := _move(old_path, "NES/Beat 'em Up/Battletoads/Battletoads (U) [!].nes")
	Library.scan()

	group = _group("Battletoads")
	check_eq(group["variants"][0]["path"], new_path, "в библиотеке новый путь")
	check(group["favorite"], "осталась в избранном")
	check_eq(group["play_seconds"], 600, "время в игре на месте")
	check_eq(group["genre"], "beat_em_up", "и жанр уже новый")
	check_eq(Settings.get_value("versions", group["key"], ""), new_path, "выбранная версия — новый путь")
	check(SaveStates.exists({"path": new_path}, "1"), "слот 1 переехал")
	check(not DirAccess.dir_exists_absolute(old_states), "старая папка сохранений убрана")
	Settings.set_value("versions", group["key"], null)
	_remove(_abs(SaveStates.ROOT.path_join(new_path.md5_text())))


func test_renamed_while_moving() -> void:
	about("Файл переложили и чуть переименовали — тоже узнаём, и карта памяти переезжает")
	var old_path := _make("PS1/Atlantis(FullRus)Лисы.chd")
	Library.scan()
	_group_by_path(old_path)["play_seconds"] = 300
	Library._save()
	var saves := _abs(CoreManager.SAVES_DIR)
	DirAccess.make_dir_recursive_absolute(saves)
	FileAccess.open(saves.path_join("Atlantis(FullRus)Лисы.srm"), FileAccess.WRITE).store_string("CARD")

	var new_path := _move(old_path, "PS1/Action/Atlantis (FullRus) Лисы.chd")
	Library.scan()
	check_eq(_group_by_path(new_path).get("play_seconds"), 300, "время на месте")
	check(FileAccess.file_exists(saves.path_join("Atlantis (FullRus) Лисы.srm")), "карта памяти под новым именем")
	DirAccess.remove_absolute(saves.path_join("Atlantis (FullRus) Лисы.srm"))


func _group_by_path(path: String) -> Dictionary:
	for game: Dictionary in Library.games:
		if game["path"] == path:
			return game
	check(false, "нет файла " + path)
	return {}


func test_same_names_are_not_guessed() -> void:
	about("Две игры с одним именем переехали — какую куда, не угадать, их не трогаем")
	var a := _make("Collection A/Batman (U).nes")
	var b := _make("Collection B/Batman (U).nes")
	Library.scan()
	for game: Dictionary in Library.games:
		game["play_seconds"] = 100
	_move(a, "Platformer/A/Batman (U).nes")
	_move(b, "Platformer/B/Batman (U).nes")
	Library.scan()
	for game: Dictionary in Library.games:
		check_eq(game["play_seconds"], 0, "время не приписано наугад")


func test_disc_memory_card_moves() -> void:
	about("Многодисковая игра: карта памяти (по имени .m3u) переименовывается")
	var old_path := _abs(FOLDER.path_join("PS1/FF7 (USA) (Disc 1).cue"))
	var new_path := _abs(FOLDER.path_join("PS1/RPG/FF7/FF7 (USA) (Disc 1).cue"))
	var saves := _abs(CoreManager.SAVES_DIR)
	DirAccess.make_dir_recursive_absolute(saves)
	var old_card := saves.path_join(Discs.set_id(old_path) + ".srm")
	FileAccess.open(old_card, FileAccess.WRITE).store_string("CARD")
	Discs.move_saves(old_path, new_path)
	var new_card := saves.path_join(Discs.set_id(new_path) + ".srm")
	check(FileAccess.file_exists(new_card), "карта памяти под новым именем")
	check(not FileAccess.file_exists(old_card), "старой нет")
	DirAccess.remove_absolute(new_card)


func _make(relative: String) -> String:
	var path := _abs(FOLDER.path_join(relative))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.open(path, FileAccess.WRITE).store_string("x")
	return path


func _move(path: String, relative: String) -> String:
	var target := _abs(FOLDER.path_join(relative))
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	DirAccess.rename_absolute(path, target)
	return target


func _group(title: String) -> Dictionary:
	for group: Dictionary in Library.groups:
		if group["title"] == title:
			return group
	check(false, "нет игры «%s»" % title)
	return {"variants": [{}], "key": "", "favorite": false, "play_seconds": 0, "genre": ""}


func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path)


func _remove(path: String) -> void:
	for sub in DirAccess.get_directories_at(path):
		_remove(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
