class_name Discs
## Discs — многодисковые игры (PlayStation).
##
## Большие игры PS1 занимали несколько дисков: Final Fantasy VII — три,
## Metal Gear Solid — два. Ядро умеет менять диски, но только если знает
## их все. Для этого есть .m3u — простой текстовый список файлов дисков:
##   D:/Games/PS1/Final Fantasy VII (USA) (Disc 1).cue
##   D:/Games/PS1/Final Fantasy VII (USA) (Disc 2).cue
##   D:/Games/PS1/Final Fantasy VII (USA) (Disc 3).cue
##
## Если .m3u у человека нет, а рядом лежат файлы «(Disc 1)», «(Disc 2)»…,
## Shellbit составляет такой список сам — в своей папке, не трогая папку с играми.

const PLAYLIST_DIR := "user://cache/m3u"

## «(Disc 2)», «(Disc 2 of 3)», «(Disk 2)», «(CD2)» — номер диска в имени файла.
## (?i) — без разницы, большие буквы или маленькие.
static var _disc_regex := RegEx.create_from_string("(?i)\\s*\\((?:disc|disk|cd)\\s*(\\d+)(?:\\s*of\\s*\\d+)?\\)")


## Код набора дисков: md5 от «папка/имя без пометки диска».
## Из него — имя .m3u, а значит, и имя карты памяти, которую ядро
## заведёт для этой игры (ядро называет её по имени .m3u).
## "" — в имени файла нет пометки диска.
static func set_id(path: String) -> String:
	var found := _disc_regex.search(path.get_file())
	if found == null:
		return ""
	var set_name := path.get_file().replace(found.get_string(), "")
	return path.get_base_dir().path_join(set_name).md5_text()


## Игру переложили из old_path в new_path. Код набора поменялся (в нём
## есть папка), и ядро не нашло бы старую карту памяти — переименовываем её:
## user://saves/<старый код>.srm → <новый код>.srm (и другие файлы ядра).
static func move_saves(old_path: String, new_path: String) -> void:
	var old_id := set_id(old_path)
	var new_id := set_id(new_path)
	if old_id == "" or old_id == new_id:
		return
	# У каждого игрока своя папка saves (autoload/Profiles.gd) — у всех и переименуем.
	for id: String in Profiles.ids():
		SaveStates._rename_core_saves(ProjectSettings.globalize_path(Profiles.saves_dir(id)), old_id, new_id)


## Если path — один из дисков набора, составить список всех дисков.
## Возвращает {} (это не набор дисков) или:
##   {"path": "<путь к .m3u>", "index": 1, "disc_path": "<путь к этому диску>"}
## index — какой по счёту (с нуля) диск выбрал человек: с него и начинаем.
static func playlist_for(path: String, system_id: String) -> Dictionary:
	var extension := path.get_extension().to_lower()
	# Только у приставок, которые понимают .m3u (это PlayStation).
	var extensions: Array = CoreManager.get_system(system_id).get("extensions", [])
	if extension == "m3u" or not extensions.has("m3u"):
		return {}
	var found := _disc_regex.search(path.get_file())
	if found == null:
		return {}

	# Имя набора — имя файла без пометки диска:
	# «Final Fantasy VII (USA) (Disc 2).cue» → «Final Fantasy VII (USA).cue».
	var set_name := path.get_file().replace(found.get_string(), "")
	var folder := path.get_base_dir()
	var discs := {}  # номер диска → путь к файлу
	for file in DirAccess.get_files_at(folder):
		if file.get_extension().to_lower() != extension:
			continue  # у дисков одного набора одинаковое расширение (.cue, .chd)
		var other := _disc_regex.search(file)
		if other != null and file.replace(other.get_string(), "") == set_name:
			discs[other.get_string(1).to_int()] = folder.path_join(file)
	if discs.size() < 2:
		return {}  # рядом нет других дисков — менять не на что

	var numbers := discs.keys()
	numbers.sort()
	var lines := PackedStringArray()
	for number: int in numbers:
		lines.append(discs[number])

	# Имя .m3u — по набору, чтобы у одной игры был один список.
	DirAccess.make_dir_recursive_absolute(PLAYLIST_DIR)
	var playlist := ProjectSettings.globalize_path(PLAYLIST_DIR.path_join(set_id(path) + ".m3u"))
	var out := FileAccess.open(playlist, FileAccess.WRITE)
	if out == null:
		return {}
	out.store_string("\n".join(lines) + "\n")
	out.close()

	return {
		"path": playlist,
		"index": numbers.find(found.get_string(1).to_int()),
		"disc_path": path,
	}


# =====================================================================
# PlayStation или PlayStation 2?
# =====================================================================
# Образы дисков обеих приставок выглядят одинаково: .iso, .cue+.bin, .chd.
# Отличить можно по файлу SYSTEM.CNF в корне диска — он есть на каждом
# диске PlayStation и говорит приставке, какую программу запускать:
#   PS1:  BOOT = cdrom:\SLUS_007.66;1
#   PS2:  BOOT2 = cdrom0:\SLUS_203.12;1
# Чтобы его прочитать, разбираем файловую систему диска (ISO 9660 —
# стандарт CD и DVD): сектор 16 — «оглавление» диска, в нём — где лежит
# корневая папка, в корневой папке — где лежит SYSTEM.CNF.

const PS2_MIN_DVD_SIZE := 1024 * 1024 * 1024  # больше 1 ГБ — точно не CD, а DVD


## "ps2", "psx" или "" (не поняли). path — .iso, .img, .cue или .chd.
static func console_of(path: String) -> String:
	var extension := path.get_extension().to_lower()
	var image := path
	if extension == "cue":
		image = _first_track(path)
		if image == "":
			return ""
	if extension == "chd":
		# .chd сжат — внутрь не заглянуть. Но DVD (PS2) больше любого CD (PS1):
		# даже сжатый образ DVD обычно весит больше гигабайта.
		return "ps2" if _size(path) > PS2_MIN_DVD_SIZE else ""
	var file := FileAccess.open(image, FileAccess.READ)
	if file == null:
		return ""
	var text := _read_system_cnf(file)
	if text.contains("BOOT2"):
		return "ps2"
	if text.contains("BOOT"):
		return "psx"
	return "ps2" if file.get_length() > PS2_MIN_DVD_SIZE else ""


static func _size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_length() if file != null else 0


# Первая дорожка из .cue: строка FILE "Game (Track 1).bin" BINARY.
static func _first_track(cue_path: String) -> String:
	var text := FileAccess.get_file_as_string(cue_path)
	for line in text.split("\n", false):
		line = line.strip_edges()
		if line.to_upper().begins_with("FILE"):
			var first := line.find("\"")
			var last := line.rfind("\"")
			if first >= 0 and last > first:
				return cue_path.get_base_dir().path_join(line.substr(first + 1, last - first - 1))
	return ""


# Сектор диска бывает двух видов:
#   2048 байт — «чистые» данные (обычный .iso);
#   2352 байта — «сырой» сектор, как он записан на CD (.bin):
#     в начале 16 байт служебной разметки, у дисков PlayStation (режим
#     «Mode 2») — ещё 8, и только потом 2048 байт данных.
# Вид узнаём по метке «CD001» в 16-м секторе — там, где она должна быть.
static func _layout(file: FileAccess) -> Vector2i:  # x — размер сектора, y — где в нём данные
	for layout in [Vector2i(2048, 0), Vector2i(2352, 24), Vector2i(2352, 16)]:
		file.seek(16 * layout.x + layout.y + 1)
		if file.get_buffer(5).get_string_from_ascii() == "CD001":
			return layout
	return Vector2i.ZERO


static func _read_sector(file: FileAccess, layout: Vector2i, lba: int) -> PackedByteArray:
	file.seek(lba * layout.x + layout.y)
	return file.get_buffer(2048)


# Текст SYSTEM.CNF (первые 2 КБ — его хватает) или "".
static func _read_system_cnf(file: FileAccess) -> String:
	var layout := _layout(file)
	if layout == Vector2i.ZERO:
		return ""
	var volume := _read_sector(file, layout, 16)
	if volume.size() < 2048:
		return ""
	# Запись о корневой папке — с 156-го байта «оглавления»:
	# со 2-го байта записи — номер первого сектора папки, с 10-го — её размер.
	var root_lba := volume.decode_u32(156 + 2)
	var root_size := volume.decode_u32(156 + 10)
	for i in mini(ceili(root_size / 2048.0), 16):  # больше 16 секторов в корне не бывает
		var sector := _read_sector(file, layout, root_lba + i)
		var at := 0
		while at + 34 < sector.size():
			var length := sector[at]  # длина записи; 0 — дальше в этом секторе пусто
			if length == 0:
				break
			var name_length := sector[at + 32]
			var name := sector.slice(at + 33, at + 33 + name_length).get_string_from_ascii()
			if name.to_upper().begins_with("SYSTEM.CNF"):
				var data := _read_sector(file, layout, sector.decode_u32(at + 2))
				return data.get_string_from_ascii()
			at += length
	return ""
