extends TestCase
## Игры в архивах .zip и .7z: какая приставка внутри и распаковка перед запуском.
## Тесты с .7z работают, только если 7-Zip уже есть (в песочнице Windows его
## обычно нет — тогда они отмечают себя «пропущен»).

const FIXTURE_ROMS := "res://test/fixtures/roms"
const WORK := "user://test_archives"


func after_each() -> void:
	Archives._remove_dir(ProjectSettings.globalize_path(WORK))
	Archives._remove_dir(ProjectSettings.globalize_path(Archives.CACHE_DIR))


func test_system_by_files_inside() -> void:
	about("Приставка — по файлу внутри архива; незнакомые файлы — аркада")
	check_eq(Archives.system_for_files(PackedStringArray(["Contra (USA).nes"])), "nes")
	check_eq(Archives.system_for_files(PackedStringArray(["Game (Disc 1).bin", "Game (Disc 1).cue"])), "psx")
	check_eq(Archives.system_for_files(PackedStringArray(["pacman.6e", "pacman.6f"])), "arcade")
	check_eq(Archives.system_for_files(PackedStringArray(["readme.txt", "Tetris.GB"])), "gb", "регистр букв не важен")


func test_detect_zip() -> void:
	about("В .zip Shellbit заглядывает сам")
	check_eq(Archives.detect_system(_fixture("Duck Hunt (World).zip")), "nes")
	check_eq(Archives.detect_system(_fixture("pacman.zip")), "arcade")


func test_detect_7z() -> void:
	if Archives.seven_zip() == "":
		about("Приставка внутри .7z (пропущен: 7-Zip нет)")
		return
	about("В .7z Shellbit заглядывает через 7-Zip")
	check_eq(Archives.detect_system(_fixture("Sonic the Hedgehog (Europe).7z")), "md")


func test_extraction_rules() -> void:
	about("Распаковывать нужно консольные архивы, но не аркадные")
	check(Archives.needs_extraction({"path": "D:/Games/Contra.zip", "system": "nes"}), "NES в zip — да")
	check(Archives.needs_extraction({"path": "D:/Games/Sonic.7z", "system": "md"}), "Mega Drive в 7z — да")
	check(not Archives.needs_extraction({"path": "D:/Games/pacman.zip", "system": "arcade"}), "аркада — нет, FBNeo читает архив сам")
	check(not Archives.needs_extraction({"path": "D:/Games/Contra.nes", "system": "nes"}), "обычный файл — нет")


func test_prepare_zip() -> void:
	about("Перед запуском zip распаковывается, повторно — берётся готовое")
	var game := {"path": _fixture("Duck Hunt (World).zip"), "system": "nes"}
	var result: Dictionary = await Archives.prepare(game)
	check_eq(result["error"], "")
	check_eq(result["path"].get_file(), "Duck Hunt (World).nes")
	check_eq(FileAccess.get_file_as_string(result["path"]), "TEST")
	# Второй раз — из кеша: тот же файл, архив не трогаем.
	var again: Dictionary = await Archives.prepare(game)
	check_eq(again["path"], result["path"])


func test_prepare_picks_main_file() -> void:
	about("Из архива с несколькими файлами запускается главный: .m3u, потом .cue")
	var with_cue := _make_zip("Game.zip", ["Game (Track 1).bin", "Game.cue"])
	check_eq((await Archives.prepare({"path": with_cue, "system": "psx"}))["path"].get_file(), "Game.cue")
	var with_m3u := _make_zip("Big.zip", ["Big (Disc 1).cue", "Big (Disc 2).cue", "Big.m3u"])
	check_eq((await Archives.prepare({"path": with_m3u, "system": "psx"}))["path"].get_file(), "Big.m3u")


func test_zip_cannot_escape_folder() -> void:
	about("Файл «../…» из архива не попадает за пределы папки")
	var evil := _make_zip("evil.zip", ["../../escaped.txt", "Evil.nes"])
	var result: Dictionary = await Archives.prepare({"path": evil, "system": "nes"})
	check_eq(result["path"].get_file(), "Evil.nes")
	check(not FileAccess.file_exists(ProjectSettings.globalize_path("user://escaped.txt")), "escaped.txt не появился")
	check(not FileAccess.file_exists(ProjectSettings.globalize_path("user://cache/escaped.txt")), "и здесь тоже")


func test_prepare_wrong_archive() -> void:
	about("В архиве нет файла приставки — понятная ошибка")
	var junk := _make_zip("junk.zip", ["readme.txt"])
	var result: Dictionary = await Archives.prepare({"path": junk, "system": "nes"})
	check_eq(result["path"], "")
	check(result["error"] != "", "есть текст ошибки")


func test_prepare_7z() -> void:
	if Archives.seven_zip() == "":
		about("Распаковка .7z (пропущен: 7-Zip нет)")
		return
	about("Перед запуском .7z распаковывается через 7-Zip")
	var result: Dictionary = await Archives.prepare({"path": _fixture("Sonic the Hedgehog (Europe).7z"), "system": "md"})
	check_eq(result["error"], "")
	check_eq(result["path"].get_file(), "Sonic the Hedgehog (Europe).md")


# --- Помощники ----------------------------------------------------------------

func _fixture(file: String) -> String:
	return ProjectSettings.globalize_path(FIXTURE_ROMS.path_join(file))


# Собрать zip из файлов с содержимым «TEST».
func _make_zip(file_name: String, inside: Array) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK))
	var path := ProjectSettings.globalize_path(WORK.path_join(file_name))
	var zip := ZIPPacker.new()
	zip.open(path)
	for name: String in inside:
		zip.start_file(name)
		zip.write_file("TEST".to_utf8_buffer())
		zip.close_file()
	zip.close()
	return path
