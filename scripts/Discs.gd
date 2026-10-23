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
	var playlist := ProjectSettings.globalize_path(
			PLAYLIST_DIR.path_join(folder.path_join(set_name).md5_text() + ".m3u"))
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
