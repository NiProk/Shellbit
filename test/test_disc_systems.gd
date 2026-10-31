extends TestCase
## Образы дисков: PS1 или другая приставка — по названиям папок.


func test_folder_hints() -> void:
	about("«PC Engine NEC/…chd» — PC Engine, «SonyPlayStation1/…chd» — PS1, Saturn — пропускаем")
	check_eq(Library._disc_system("D:/Game_archive/PC Engine NEC/Virgin Dream (Japan).chd", "psx"), "pce")
	check_eq(Library._disc_system("D:/Game_archive/SonyPlayStation1/RPG/Alundra/Alundra.iso", "psx"), "psx")
	check_eq(Library._disc_system("D:/Games/Sega Saturn/Nights.cue", "psx"), "", "Saturn — не поддерживаем")
	check_eq(Library._disc_system("D:/Games/PS1/Wild Arms/Wild Arms.cue", "psx"), "psx", "«Wild» — не «wii»")
	check_eq(CoreManager.system_for_extension("img"), "psx", ".img — образ PS1")
	check_eq(CoreManager.system_for_extension("iso"), "psx", ".iso — тоже")


func test_missing_setting_is_quiet() -> void:
	about("Нет ключа в настройках — null, без ошибки в журнале")
	check(Settings.get_value("profile_p99", "avatar") == null)


func test_pce_cd_needs_bios() -> void:
	about("Диск PC Engine CD без syscard3.pce — понятная ошибка, а не «ядро не смогло открыть»")
	var player: Control = load("res://scenes/player/Player.tscn").instantiate()
	player._content_path = "D:/Games/PC Engine/Magical Dinosaur Tour (USA).chd"
	var system := CoreManager.get_system("pce")
	check_eq(player._missing_disc_bios(system), "syscard3.pce", "диску нужен syscard3.pce")
	player._content_path = "D:/Games/PC Engine/Bomberman.pce"
	check_eq(player._missing_disc_bios(system), "", "картриджу — нет")
	player.free()


func test_native_paths() -> void:
	about("Ядрам — пути с родным разделителем системы (в Windows «\\»: FBNeo иначе не находит архивы)")
	var expected := "D:\\Arcade\\mslug.zip" if OS.get_name() == "Windows" else "D:/Arcade/mslug.zip"
	check_eq(load("res://scenes/player/Player.gd")._native("D:/Arcade/mslug.zip"), expected)


func test_bin_files() -> void:
	about(".bin: Mega Drive — по «SEGA» в заголовке, маленький — Atari 2600, дорожка диска — пропускаем")
	var folder := "user://test_bin"
	DirAccess.make_dir_recursive_absolute(folder.path_join("cd"))
	var rom := PackedByteArray()
	rom.resize(0x200)
	rom.encode_u32(0x100, 0x41474553)  # «SEGA» в обратном порядке байт = little-endian
	FileAccess.open(folder.path_join("Garfield (USA).bin"), FileAccess.WRITE).store_buffer(rom)
	var small := PackedByteArray()
	small.resize(4096)
	FileAccess.open(folder.path_join("Pitfall (USA).bin"), FileAccess.WRITE).store_buffer(small)
	FileAccess.open(folder.path_join("cd/Game.cue"), FileAccess.WRITE).store_string('FILE "Game.bin" BINARY')
	FileAccess.open(folder.path_join("cd/Game.bin"), FileAccess.WRITE).store_buffer(rom)
	check_eq(Library._bin_system(ProjectSettings.globalize_path(folder.path_join("Garfield (USA).bin"))), "md", "SEGA в заголовке — Mega Drive")
	check_eq(Library._bin_system(ProjectSettings.globalize_path(folder.path_join("Pitfall (USA).bin"))), "atari2600", "4 КБ — Atari 2600")
	Settings.set_value("library", "folders", PackedStringArray([ProjectSettings.globalize_path(folder)]))
	Library.scan()
	var systems := Library.games.map(func(g: Dictionary) -> String: return g["system"] + ":" + String(g["path"]).get_file())
	systems.sort()
	check_eq(systems, ["atari2600:Pitfall (USA).bin", "md:Garfield (USA).bin", "psx:Game.cue"], "дорожка Game.bin рядом с .cue — не отдельная игра")
	Settings.set_value("library", "folders", PackedStringArray())
	Library.scan()
