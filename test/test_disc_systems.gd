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


# --- PlayStation 2 ---------------------------------------------------------

# Крошечный «образ диска» ISO 9660 с одним файлом SYSTEM.CNF.
# raw = true — «сырые» сектора по 2352 байта, как в .bin (данные с 24-го байта).
func _disc_image(system_cnf: String, raw := false) -> PackedByteArray:
	var sectors: Array[PackedByteArray] = []
	for i in 21:
		var data := PackedByteArray()
		data.resize(2048)
		sectors.append(data)
	var volume := sectors[16]  # «оглавление» диска
	volume[0] = 1
	volume.encode_u32(1, 0x30304443)  # «CD00» (байты задом наперёд)
	volume[5] = 0x31                  # «1»
	volume[156] = 34                  # запись о корневой папке
	volume.encode_u32(156 + 2, 18)    # корень — в секторе 18
	volume.encode_u32(156 + 10, 2048)
	var root := sectors[18]
	var name := "SYSTEM.CNF;1".to_ascii_buffer()
	root[0] = 34 + name.size()
	root.encode_u32(2, 20)            # сам файл — в секторе 20
	root.encode_u32(10, system_cnf.length())
	root[32] = name.size()
	for i in name.size():
		root[33 + i] = name[i]
	var text := system_cnf.to_ascii_buffer()
	for i in text.size():
		sectors[20][i] = text[i]
	var image := PackedByteArray()
	for data in sectors:
		if raw:
			var header := PackedByteArray()
			header.resize(24)
			image.append_array(header)
		image.append_array(data)
		if raw:
			var tail := PackedByteArray()
			tail.resize(2352 - 24 - 2048)
			image.append_array(tail)
	return image


func test_ps2_detection() -> void:
	about("PS1 или PS2: по SYSTEM.CNF внутри диска (.iso и .cue+.bin), по папке, .cso — PS2")
	var folder := ProjectSettings.globalize_path("user://test_ps2")
	DirAccess.make_dir_recursive_absolute(folder)
	var ps2_iso := folder.path_join("Okami (USA).iso")
	FileAccess.open(ps2_iso, FileAccess.WRITE).store_buffer(_disc_image("BOOT2 = cdrom0:\\SLUS_215.15;1\nVER = 1.00\n"))
	var ps1_iso := folder.path_join("Spyro (USA).iso")
	FileAccess.open(ps1_iso, FileAccess.WRITE).store_buffer(_disc_image("BOOT = cdrom:\\SCUS_942.28;1\n"))
	FileAccess.open(folder.path_join("Ico (USA).bin"), FileAccess.WRITE).store_buffer(_disc_image("BOOT2 = cdrom0:\\SCUS_971.13;1\n", true))
	var cue := folder.path_join("Ico (USA).cue")
	FileAccess.open(cue, FileAccess.WRITE).store_string('FILE "Ico (USA).bin" BINARY\n  TRACK 01 MODE2/2352\n')
	check_eq(Discs.console_of(ps2_iso), "ps2", "BOOT2 — PlayStation 2")
	check_eq(Discs.console_of(ps1_iso), "psx", "BOOT — PlayStation")
	check_eq(Discs.console_of(cue), "ps2", ".cue → «сырой» .bin с BOOT2")
	check_eq(Library._disc_system("D:/Games/PS2/Okami.chd", "psx"), "ps2", "папка «PS2»")
	check_eq(Library._disc_system("D:/Games/Sony PlayStation 2/Okami.chd", "psx"), "ps2", "папка «Sony PlayStation 2»")
	check_eq(CoreManager.system_for_extension("cso"), "ps2", ".cso — сжатый образ PS2")
	check_eq(CoreManager.system_for_extension("iso"), "psx", ".iso без подсказок — по-прежнему PS1")

	Settings.set_value("library", "folders", PackedStringArray([folder]))
	Library.scan()
	var systems := Library.games.map(func(g: Dictionary) -> String: return g["system"] + ":" + String(g["path"]).get_file())
	systems.sort()
	check_eq(systems, ["ps2:Ico (USA).cue", "ps2:Okami (USA).iso", "psx:Spyro (USA).iso"], "библиотека разложила по приставкам")
	Settings.set_value("library", "folders", PackedStringArray())
	Library.scan()


func test_ps2_bios_and_rewind() -> void:
	about("PS2: BIOS — любой .bin в system/pcsx2/bios; перемотки нет")
	var ps2 := CoreManager.get_system("ps2")
	check(not ps2.is_empty(), "PS2 есть в списке приставок на компьютере")
	check_eq(ps2.get("rewind", true), false, "перемотка выключена")
	var bios_dir := CoreManager.SYSTEM_DIR.path_join("pcsx2/bios")
	var bios := bios_dir.path_join("test-bios.bin")
	DirAccess.remove_absolute(bios)
	var had_bios := CoreManager.has_bios_dir_files(ps2)
	if not had_bios:
		check(not CoreManager.has_bios_dir_files(ps2), "пустая папка — BIOS нет")
	DirAccess.make_dir_recursive_absolute(bios_dir)
	FileAccess.open(bios, FileAccess.WRITE).store_string("x")
	check(CoreManager.has_bios_dir_files(ps2), "файл появился — BIOS есть")
	DirAccess.remove_absolute(bios)
	check(CoreManager.has_bios_dir_files({"id": "nes"}), "приставкам без bios_dir папка не нужна")
	check(InputMapper.pads.has("ps2"), "есть рисунок и кнопки геймпада PS2")
