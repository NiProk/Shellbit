extends TestCase
## Читы: разбор файлов .cht, поиск игры в базе, свои коды, передача ядру.

const GAME := {"system": "nes", "path": "/roms/Contra (USA).nes", "title": "Contra"}

const CHT := """cheats = 4

cheat0_desc = "Infinite Lives"
cheat0_code = "sxiopo"
cheat0_enable = false

cheat1_desc = "Rumble only"
cheat1_code = ""
cheat1_enable = false

cheat2_desc = "Pick your own value"
cheat2_code = "D005E400+????"
cheat2_enable = false

cheat3_desc = "Invincible"
cheat3_code = "00AE:41"
cheat3_enable = false
"""


func before_each() -> void:
	_clean()


func after_each() -> void:
	_clean()


func test_parse_cht() -> void:
	about("Файл .cht: берём название и код, пропускаем читы без кода и с «????»")
	var cheats := Cheats.parse_cht(CHT)
	check_eq(cheats.size(), 2)
	check_eq(cheats[0], {"name": "Infinite Lives", "code": "SXIOPO"}, "код — заглавными")
	check_eq(cheats[1]["code"], "00AE:41")


func test_title_key() -> void:
	about("Ключ названия: без скобок, регистра, знаков и «The»")
	check_eq(Cheats.title_key("Contra (USA) (Game Genie)"), "contra")
	check_eq(Cheats.title_key("Legend of Zelda, The (USA)"), Cheats.title_key("The Legend of Zelda"))
	check_eq(Cheats.title_key("Mario & Luigi"), "marioandluigi")
	check_eq(Cheats.title_key("Контра"), "контра", "русские буквы не теряются")


func test_find_files_ranking() -> void:
	about("Поиск в базе: сначала точное имя, потом та же страна, потом остальные")
	_make_database({
		"Nintendo - Nintendo Entertainment System/Contra (Japan).cht": CHT,
		"Nintendo - Nintendo Entertainment System/Contra (USA) (Game Genie).cht": CHT,
		"Nintendo - Nintendo Entertainment System/Contra (USA).cht": CHT,
		"Nintendo - Nintendo Entertainment System/Contra Force (USA).cht": CHT,
		"Nintendo - Super Nintendo Entertainment System/Contra (USA).cht": CHT,
	})
	var files := Cheats.find_files(GAME)
	check_eq(Array(files).map(func(f: String) -> String: return f.get_file()),
			["Contra (USA).cht", "Contra (USA) (Game Genie).cht", "Contra (Japan).cht"],
			"Contra Force и SNES — не наши")


func test_entries_and_custom_codes() -> void:
	about("Свои коды: добавить (сразу включён), включить код из базы, удалить")
	_make_database({"Nintendo - Nintendo Entertainment System/Contra (USA).cht": CHT})
	var entries := Cheats.entries(GAME)
	check_eq(entries.size(), 2, "из базы — два кода")
	check(entries.all(func(e: Dictionary) -> bool: return not e["on"]), "сначала всё выключено")

	check(Cheats.add_custom(GAME, "  Мой код ", " aaaaaa "), "добавился")
	check(not Cheats.add_custom(GAME, "Ещё раз", "AAAAAA"), "такой код уже есть")
	check(not Cheats.add_custom(GAME, "Пусто", "   "), "пустой код не добавляем")
	Cheats.set_enabled(GAME, "SXIOPO", true)

	entries = Cheats.entries(GAME)
	check_eq(entries[0], {"name": "Мой код", "code": "AAAAAA", "source": Cheats.CUSTOM, "on": true, "custom": true},
			"свои — первыми, сразу включены")
	check_eq(entries[1]["source"], "Contra (USA)")
	check(entries[1]["on"], "код из базы включился")
	check_eq(Cheats.enabled_codes(GAME), PackedStringArray(["AAAAAA", "SXIOPO"]))

	Cheats.remove_custom(GAME, "AAAAAA")
	check_eq(Cheats.enabled_codes(GAME), PackedStringArray(["SXIOPO"]), "удалённый код больше не включён")
	check_eq(Cheats.entries(GAME).size(), 2)


func test_player_passes_codes_to_core() -> void:
	about("Экран игры передаёт ядру все включённые коды по порядку")
	Cheats.add_custom(GAME, "", "AAAAAA")
	Cheats.add_custom(GAME, "", "00AE:41")
	SceneRouter.params = {"game": GAME}
	var player: Control = load("res://scenes/player/Player.tscn").instantiate()
	add_child(player)
	await frames(2)
	player.get_node("%Error").visible = false
	var core: Node = load("res://test/MockCore.gd").new()
	player.add_child(core)
	player.core = core
	player.game = GAME
	core.cheats = {7: [true, "OLD"]}  # «старый» чит должен исчезнуть

	player._apply_cheats()
	check_eq(core.cheats, {0: [true, "AAAAAA"], 1: [true, "00AE:41"]})

	Cheats.set_enabled(GAME, "AAAAAA", false)
	player._on_cheats_changed()
	check_eq(core.cheats, {0: [true, "00AE:41"]}, "выключили — пропал")

	core.cheats_supported = false
	core.cheats = {}
	player._apply_cheats()
	check_eq(core.cheats, {}, "ядро без читов — ничего не передаём")

	player.core = null
	player.queue_free()
	await frames(2)


func _make_database(files: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(Cheats.DIR)
	var zip := ZIPPacker.new()
	zip.open(ProjectSettings.globalize_path(Cheats.DATABASE))
	for path: String in files:
		zip.start_file(path)
		zip.write_file(String(files[path]).to_utf8_buffer())
		zip.close_file()
	zip.close()
	Cheats._index.clear()


func _clean() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Cheats.DATABASE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Cheats._saved_path(GAME)))
	Cheats._index.clear()
