extends Node
## Library — список всех игр пользователя.
##
## Ищет файлы игр в папках из настроек, запоминает их в user://library.json
## и отвечает на вопросы: «какие игры у SNES?», «во что играли недавно?».
##
## Здесь два уровня:
##
## 1. ФАЙЛ (вариант) — одна запись на один файл на диске:
##   {
##     "path": "D:/Games/NES/Battletoads (U) [!].nes",
##     "system": "nes",
##     "title": "Battletoads",        # из RomInfo
##     "version": "США · проверенная", # из RomInfo
##     "score": 130,                  # из RomInfo: чем больше, тем лучше версия
##     "favorite": false,
##     "last_played": 0,              # Unix-время последнего запуска (0 = ни разу)
##     "play_seconds": 0              # сколько секунд наиграно
##   }
##
## 2. ИГРА (группа) — все версии одной игры вместе. Именно группы видит
##    пользователь на экране: одна карточка «Battletoads» вместо семи.
##   {
##     "key": "nes_battletoads",
##     "title": "Battletoads",
##     "system": "nes",
##     "variants": [ ...файлы, лучший первым... ],
##     "favorite", "last_played", "play_seconds"  # собраны со всех файлов
##   }

## Сигнал: поиск игр закончен. Экраны подписываются на него и обновляются.
signal scan_finished

const SAVE_PATH := "user://library.json"
const MAX_DEPTH := 6  # насколько глубоко заходить во вложенные папки

var games: Array[Dictionary] = []   # все файлы
var groups: Array[Dictionary] = []  # все игры (группы файлов)


func _ready() -> void:
	_load()
	_rebuild_groups()
	# Если папки уже выбраны — проверяем, не появились ли новые игры.
	if not Settings.get_rom_folders().is_empty():
		scan()


## Заново пройти по всем папкам и собрать список игр.
func scan() -> void:
	# Запоминаем старые записи, чтобы не потерять «избранное» и время в игре.
	var old := {}
	for game in games:
		old[game["path"]] = game

	var found: Array[Dictionary] = []
	for folder in Settings.get_rom_folders():
		_scan_dir(folder, found, old, 0)

	games = found
	_rebuild_groups()
	_save()
	scan_finished.emit()


# Рекурсивная функция: смотрит файлы в папке, а для каждой
# вложенной папки вызывает саму себя.
func _scan_dir(path: String, found: Array[Dictionary], old: Dictionary, depth: int) -> void:
	if depth > MAX_DEPTH:
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return

	for sub in dir.get_directories():
		_scan_dir(path.path_join(sub), found, old, depth + 1)

	for file in dir.get_files():
		var system_id := CoreManager.system_for_extension(file.get_extension())
		if system_id == "":
			continue  # это не игра (или приставка, которую мы не знаем)
		var full_path := path.path_join(file)
		if old.has(full_path):
			found.append(old[full_path])
		else:
			found.append({
				"path": full_path,
				"system": system_id,
				"favorite": false,
				"last_played": 0,
				"play_seconds": 0,
			})


# Собрать файлы в группы. Вызывается после любого изменения.
func _rebuild_groups() -> void:
	var by_key := {}  # ключ группы → группа

	for game in games:
		# Каждый раз заново разбираем имя: если правила в RomInfo
		# улучшатся, старые записи тоже получат правильные названия.
		var info := RomInfo.parse(game["path"].get_file())
		game["title"] = info["title"]
		game["version"] = info["label"]
		game["score"] = info["score"]

		var key: String = game["system"] + "_" + info["group"]
		if not by_key.has(key):
			by_key[key] = {
				"key": key,
				"title": info["title"],
				"system": game["system"],
				"variants": [],
			}
		by_key[key]["variants"].append(game)

	groups.clear()
	for group: Dictionary in by_key.values():
		var variants: Array = group["variants"]
		# Лучшая версия — первая. При равной оценке — по имени файла.
		variants.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["score"] != b["score"]:
				return a["score"] > b["score"]
			return a["path"] < b["path"])
		# Название берём у лучшей версии (у «плохих» оно бывает кривым).
		group["title"] = variants[0]["title"]
		group["favorite"] = variants.any(func(v: Dictionary) -> bool: return v["favorite"])
		group["last_played"] = variants.map(func(v: Dictionary) -> int: return int(v["last_played"])).max()
		group["play_seconds"] = variants.reduce(func(sum: int, v: Dictionary) -> int: return sum + int(v["play_seconds"]), 0)
		groups.append(group)


# --- Вопросы к библиотеке -------------------------------------------------

## Игры (группы) одной приставки, по алфавиту.
func groups_for_system(system_id: String) -> Array:
	var result := groups.filter(func(g: Dictionary) -> bool: return g["system"] == system_id)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["title"].naturalnocasecmp_to(b["title"]) < 0)
	return result


## Игры, в которые играли, — самые свежие первыми.
func get_recent(limit: int) -> Array:
	var result := groups.filter(func(g: Dictionary) -> bool: return g["last_played"] > 0)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["last_played"] > b["last_played"])
	return result.slice(0, limit)


## id приставок, у которых есть хотя бы одна игра (в порядке systems.json).
func systems_with_games() -> Array[String]:
	var result: Array[String] = []
	for system in CoreManager.systems:
		if games.any(func(g: Dictionary) -> bool: return g["system"] == system["id"]):
			result.append(system["id"])
	return result


## Какую версию запускать: выбранную вручную или лучшую.
func chosen_variant(group: Dictionary) -> Dictionary:
	var path: String = Settings.get_value("versions", group["key"], "")
	for variant: Dictionary in group["variants"]:
		if variant["path"] == path:
			return variant
	return group["variants"][0]


## Выбрать следующую версию (по кругу). Возвращает выбранную.
func choose_next_variant(group: Dictionary) -> Dictionary:
	var variants: Array = group["variants"]
	var index := variants.find(chosen_variant(group))
	var next: Dictionary = variants[(index + 1) % variants.size()]
	Settings.set_value("versions", group["key"], next["path"])
	return next


# --- Изменения -------------------------------------------------------------
# mark_played и add_playtime получают ФАЙЛ (его запускает Player),
# а toggle_favorite — ИГРУ (её выбирают в библиотеке).

func mark_played(game: Dictionary) -> void:
	game["last_played"] = int(Time.get_unix_time_from_system())
	_rebuild_groups()
	_save()


func add_playtime(game: Dictionary, seconds: int) -> void:
	game["play_seconds"] = int(game["play_seconds"]) + seconds
	_rebuild_groups()
	_save()


func toggle_favorite(group: Dictionary) -> void:
	group["favorite"] = not group["favorite"]
	for variant: Dictionary in group["variants"]:
		variant["favorite"] = group["favorite"]
	_save()


# --- Тексты для интерфейса -------------------------------------------------

## 1 игра, 2 игры, 5 игр — русские окончания.
func count_text(n: int) -> String:
	return "%d %s" % [n, plural(n, "игра", "игры", "игр")]


## Выбрать форму слова для числа: plural(3, "версия", "версии", "версий").
func plural(n: int, one: String, few: String, many: String) -> String:
	if n % 10 == 1 and n % 100 != 11:
		return one
	if n % 10 in [2, 3, 4] and not (n % 100 in [12, 13, 14]):
		return few
	return many


func playtime_text(seconds: int) -> String:
	if seconds < 60:
		return "меньше минуты"
	var hours := seconds / 3600
	var minutes := (seconds % 3600) / 60
	if hours == 0:
		return "%d мин" % minutes
	return "%d ч %d мин" % [hours, minutes]


func last_played_text(unix_time: int) -> String:
	if unix_time <= 0:
		return "ещё не запускалась"
	var days := int(Time.get_unix_time_from_system() - unix_time) / 86400
	if days == 0:
		return "сегодня"
	if days == 1:
		return "вчера"
	return "%d дн. назад" % days


# --- Сохранение на диск ----------------------------------------------------

func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(games, "\t"))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if data is Array:
		games.assign(data)
