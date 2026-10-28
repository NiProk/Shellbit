class_name SaveStates
extends RefCounted
## SaveStates — файлы сохранений (снимков состояния) на диске.
##
## Снимок состояния (save state) — это копия ВСЕЙ памяти приставки в один
## момент. Загрузил снимок — и игра оказалась ровно в том мгновении,
## даже если сама игра сохраняться не умела.
##
## Для каждого файла игры есть своя папка, а в ней слоты:
##   user://states/<код игры>/auto.state  — автосохранение при выходе
##   user://states/<код игры>/auto.png    — кадр в этот момент (миниатюра)
##   user://states/<код игры>/1.state, 1.png, 2.state ...  — ручные слоты
##
## <код игры> — md5 от пути к файлу: короткая строка из букв и цифр,
## одинаковая для одного пути. Так нам не страшны пробелы, скобки
## и русские буквы в имени игры.
##
## У каждого игрока (autoload/Profiles.gd) своя папка states: у первого —
## user://states, у остальных — user://profiles/<id>/states.
##
## Как и RomInfo, это класс со static-функциями: SaveStates.save_slot(...).

const AUTO := "auto"
const MANUAL_SLOTS := ["1", "2", "3"]
const THUMB_WIDTH := 256  # ширина миниатюры в пикселях


## Папка слотов игры у текущего игрока (root — у другого игрока).
static func _dir(game: Dictionary, root := "") -> String:
	if root == "":
		root = Profiles.states_dir()
	return root.path_join(game["path"].md5_text())


## Игру переложили в другую папку: перенести её сохранения.
## Папка сохранений названа по md5 пути — у нового пути она другая.
## Если на новом месте уже успели сохраниться — те слоты не трогаем,
## переносим только недостающие. Переносим у ВСЕХ игроков.
static func move_game(old_path: String, new_path: String) -> void:
	for id: String in Profiles.ids():
		_move_game_in(Profiles.states_dir(id), old_path, new_path)


static func _move_game_in(root: String, old_path: String, new_path: String) -> void:
	var old_dir := ProjectSettings.globalize_path(_dir({"path": old_path}, root))
	var new_dir := ProjectSettings.globalize_path(_dir({"path": new_path}, root))
	if not DirAccess.dir_exists_absolute(old_dir):
		return  # сохранений не было
	DirAccess.make_dir_recursive_absolute(new_dir)
	for file in DirAccess.get_files_at(old_dir):
		if not FileAccess.file_exists(new_dir.path_join(file)):
			DirAccess.rename_absolute(old_dir.path_join(file), new_dir.path_join(file))
	DirAccess.remove_absolute(old_dir)  # удалится, только если опустела

	# В discs.json записаны полные пути дисков — они тоже переехали
	# (диски набора лежат в одной папке с игрой).
	var game := {"path": new_path}
	var all := _read_discs(game, root)
	var old_folder := old_path.get_base_dir()
	var new_folder := new_path.get_base_dir()
	for slot: String in all:
		var disc: Variant = all[slot]
		if disc is Dictionary and String(disc.get("path", "")).get_base_dir() == old_folder:
			disc["path"] = new_folder.path_join(String(disc["path"]).get_file())
	if not all.is_empty():
		var out := FileAccess.open(_discs_path(game, root), FileAccess.WRITE)
		if out != null:
			out.store_string(JSON.stringify(all, "\t"))


## Сохранения самой игры (батарейка картриджа, карта памяти PS1) пишет ядро
## в user://saves и называет по имени файла игры: «Contra (USA).srm».
## Если при переезде файл переименовали — переименовываем и их,
## иначе ядро их не найдёт.
static func move_core_saves(old_path: String, new_path: String) -> void:
	var old_name := old_path.get_file().get_basename()
	var new_name := new_path.get_file().get_basename()
	if old_name == new_name:
		return
	for id: String in Profiles.ids():  # у каждого игрока своя папка saves
		_rename_core_saves(ProjectSettings.globalize_path(Profiles.saves_dir(id)), old_name, new_name)


## Переименовать в папке saves файлы «old_name.*» в «new_name.*».
## Если такой новый файл уже есть — старый не трогаем (не затираем).
static func _rename_core_saves(saves: String, old_name: String, new_name: String) -> void:
	for file in DirAccess.get_files_at(saves):
		if file.begins_with(old_name + "."):
			var target := saves.path_join(new_name + file.substr(old_name.length()))
			if not FileAccess.file_exists(target):
				DirAccess.rename_absolute(saves.path_join(file), target)


static func _state_path(game: Dictionary, slot: String) -> String:
	return _dir(game).path_join(slot + ".state")


static func _thumb_path(game: Dictionary, slot: String) -> String:
	return _dir(game).path_join(slot + ".png")


## Сохранить состояние ядра в слот. Возвращает true, если получилось.
static func save_slot(core: Node, game: Dictionary, slot: String) -> bool:
	var data: PackedByteArray = core.save_state()
	if data.is_empty():
		return false  # ядро не умеет сохраняться (бывает у некоторых ядер)

	DirAccess.make_dir_recursive_absolute(_dir(game))
	var file := FileAccess.open(_state_path(game, slot), FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(data)
	file.close()

	_remember_disc(core, game, slot)

	# Миниатюра: копия текущего кадра, уменьшенная до 256 пикселей в ширину.
	var frame: Image = core.get_frame()
	if frame != null:
		var thumb := frame.duplicate() as Image
		var height := int(THUMB_WIDTH * float(frame.get_height()) / frame.get_width())
		thumb.resize(THUMB_WIDTH, height, Image.INTERPOLATE_NEAREST)  # пиксели остаются чёткими
		thumb.save_png(_thumb_path(game, slot))
	return true


## Загрузить слот в ядро. Возвращает true, если получилось.
static func load_slot(core: Node, game: Dictionary, slot: String) -> bool:
	if not exists(game, slot):
		return false
	var data := FileAccess.get_file_as_bytes(_state_path(game, slot))
	# Сохранились на втором диске, а сейчас вставлен первый? Сначала меняем
	# диск — иначе игра «проснётся» на втором диске, читая данные первого.
	var disc := disc_of(game, slot)
	if not disc.is_empty() and core.has_method("get_disk_count") \
			and core.get_disk_count() > 1 and core.get_disk_index() != disc["index"]:
		core.set_disk(disc["index"])
	return core.load_state(data)


# --- Диски (многодисковые игры) -------------------------------------------
# Рядом со слотами лежит discs.json: какой диск был в приставке
# при каждом сохранении. {"auto": {"index": 1, "path": "…(Disc 2).cue"}}

static func _discs_path(game: Dictionary, root := "") -> String:
	return _dir(game, root).path_join("discs.json")


static func _read_discs(game: Dictionary, root := "") -> Dictionary:
	if not FileAccess.file_exists(_discs_path(game, root)):
		return {}
	var all: Variant = JSON.parse_string(FileAccess.get_file_as_string(_discs_path(game, root)))
	return all if all is Dictionary else {}


## Какой диск был вставлен, когда сохранялись в слот. {} — не знаем
## (игра однодисковая или сохранение старое).
static func disc_of(game: Dictionary, slot: String) -> Dictionary:
	var all := _read_discs(game)
	if all.get(slot) is Dictionary:
		var disc: Dictionary = all[slot]
		disc["index"] = int(disc.get("index", 0))  # JSON читает числа как 1.0
		return disc
	return {}


static func _remember_disc(core: Node, game: Dictionary, slot: String) -> void:
	if not core.has_method("get_disk_count") or core.get_disk_count() < 2:
		return  # один диск — запоминать нечего
	var all := _read_discs(game)
	var index: int = core.get_disk_index()
	all[slot] = {"index": index, "path": core.get_disk_path(index)}
	var file := FileAccess.open(_discs_path(game), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(all, "\t"))


static func exists(game: Dictionary, slot: String) -> bool:
	return FileAccess.file_exists(_state_path(game, slot))


## Удалить слот (например, «Начать заново» удаляет автосохранение).
static func remove(game: Dictionary, slot: String) -> void:
	DirAccess.remove_absolute(_state_path(game, slot))
	DirAccess.remove_absolute(_thumb_path(game, slot))


## Миниатюра слота как текстура для TextureRect, или null, если её нет.
static func thumbnail(game: Dictionary, slot: String) -> Texture2D:
	var path := _thumb_path(game, slot)
	if not FileAccess.file_exists(path):
		return null
	# Image.load_from_file читает PNG с диска во время работы программы
	# (обычный load() подходит только для файлов внутри проекта).
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(image) if image else null


## Когда сделано сохранение: "сегодня, 22:14", "вчера, 19:40", "12.10, 08:05".
static func time_text(game: Dictionary, slot: String) -> String:
	if not exists(game, slot):
		return Lang.t("пусто")
	var unix := FileAccess.get_modified_time(_state_path(game, slot))
	# Время файла — в UTC. Добавляем смещение часового пояса компьютера.
	var bias_minutes: int = Time.get_time_zone_from_system()["bias"]
	var local := Time.get_datetime_dict_from_unix_time(unix + bias_minutes * 60)
	var today := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()) + bias_minutes * 60)
	var clock := "%02d:%02d" % [local["hour"], local["minute"]]

	var days_ago := (_day_number(today) - _day_number(local))
	if days_ago == 0:
		return Lang.t("сегодня, %s") % clock
	if days_ago == 1:
		return Lang.t("вчера, %s") % clock
	return "%02d.%02d, %s" % [local["day"], local["month"], clock]


# Номер дня от 1970 года — чтобы сравнивать даты вычитанием.
static func _day_number(date: Dictionary) -> int:
	return int(Time.get_unix_time_from_datetime_dict({
		"year": date["year"], "month": date["month"], "day": date["day"],
	})) / 86400
