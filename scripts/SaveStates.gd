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
## Как и RomInfo, это класс со static-функциями: SaveStates.save_slot(...).

const ROOT := "user://states"
const AUTO := "auto"
const MANUAL_SLOTS := ["1", "2", "3"]
const THUMB_WIDTH := 256  # ширина миниатюры в пикселях


static func _dir(game: Dictionary) -> String:
	return ROOT.path_join(game["path"].md5_text())


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
	return core.load_state(data)


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
		return "пусто"
	var unix := FileAccess.get_modified_time(_state_path(game, slot))
	# Время файла — в UTC. Добавляем смещение часового пояса компьютера.
	var bias_minutes: int = Time.get_time_zone_from_system()["bias"]
	var local := Time.get_datetime_dict_from_unix_time(unix + bias_minutes * 60)
	var today := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()) + bias_minutes * 60)
	var clock := "%02d:%02d" % [local["hour"], local["minute"]]

	var days_ago := (_day_number(today) - _day_number(local))
	if days_ago == 0:
		return "сегодня, " + clock
	if days_ago == 1:
		return "вчера, " + clock
	return "%02d.%02d, %s" % [local["day"], local["month"], clock]


# Номер дня от 1970 года — чтобы сравнивать даты вычитанием.
static func _day_number(date: Dictionary) -> int:
	return int(Time.get_unix_time_from_datetime_dict({
		"year": date["year"], "month": date["month"], "day": date["day"],
	})) / 86400
