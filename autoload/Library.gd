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
##     "play_seconds": 0,             # сколько секунд наиграно
##     "stats": {                     # то же самое — у каждого игрока своё
##       "p1": {"favorite": true, "last_played": 1730000000, "play_seconds": 5400},
##       "p2": {...}
##     },
##     "archive_checked": true,       # только у .zip/.7z: приставку узнали по файлу внутри
##     "genre": "platformer"          # по папке, см. scripts/Genres.gd ("" — не узнали)
##   }
##
## 2. ИГРА (группа) — все версии одной игры вместе. Именно группы видит
##    пользователь на экране: одна карточка «Battletoads» вместо семи.
##   {
##     "key": "nes_battletoads",
##     "title": "Battletoads",
##     "system": "nes",
##     "variants": [ ...файлы, лучший первым... ],
##     "genre": "platformer",                     # первый узнанный жанр среди файлов
##     "favorite", "last_played", "play_seconds"  # собраны со всех файлов
##   }
##
## Игроки (autoload/Profiles.gd). У каждого своё избранное и время в игре —
## они лежат в "stats" по id игрока. А поля "favorite", "last_played",
## "play_seconds" — это значения ТЕКУЩЕГО игрока: их копирует туда
## _apply_profile(). Так весь остальной код (экраны, сортировка) просто
## читает game["favorite"] и даже не знает, что игроков несколько.

## Сигнал: поиск игр закончен. Экраны подписываются на него и обновляются.
signal scan_finished

const SAVE_PATH := "user://library.json"

## «Приставка» для экрана избранного. Это не настоящая приставка,
## а подборка избранных игр со всех приставок. Экран библиотеки
## открывается с ней так же, как с обычной: {"system": Library.FAVORITES}.
const FAVORITES := "favorites"
const FAVORITES_COLOR := "#f5c542"  # золотой — цвет звезды
const MAX_DEPTH := 6  # насколько глубоко заходить во вложенные папки
## Поля, которые у каждого игрока свои.
const STAT_FIELDS := ["favorite", "last_played", "play_seconds"]

var games: Array[Dictionary] = []   # все файлы
# При поиске нашлись .7z, а 7-Zip ещё нет — скачаем его и поищем снова.
var _waiting_for_7zip := false
var groups: Array[Dictionary] = []  # все игры (группы файлов)
var _by_key := {}  # ключ игры → группа: найти игру по ключу сразу, не перебирая все
## Разобранные имена файлов: путь → результат RomInfo.parse().
## Разбор — это несколько регулярных выражений на файл; на 5000 игр
## это ~0,1 с, а группы пересобираются при каждом запуске и выходе из игры.
## Имя файла не меняется — разбираем его один раз.
var _parsed := {}
## Жанры файлов: путь → id жанра. Тоже считаем один раз на файл.
var _genres := {}


func _ready() -> void:
	_load()
	_apply_profile()
	_rebuild_groups()
	# Сменился игрок — у игр теперь его избранное и время.
	Profiles.changed.connect(func() -> void:
		_apply_profile()
		_rebuild_groups())
	# Описания версий («США · проверенная») зависят от языка —
	# при смене языка собираем группы заново.
	Lang.language_changed.connect(func() -> void:
		_parsed.clear()  # описания версий — на старом языке, разберём заново
		_rebuild_groups())
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
	_waiting_for_7zip = false
	_genres.clear()  # папки могли переложить — жанры узнаем заново
	for folder in Settings.get_rom_folders():
		_scan_dir(folder, found, old, 0)

	var moved := _carry_over_moved(old, found)
	games = found
	_rebuild_groups()
	_save()
	scan_finished.emit()
	if moved > 0:
		print("Library: переложенных игр — %d, их данные перенесены" % moved)
		# call_deferred — scan бывает при запуске, когда SceneRouter ещё не готов.
		_announce_moved.call_deferred(moved)
	if _waiting_for_7zip:
		# call_deferred — после того как все синглтоны готовы (scan вызывается
		# и при запуске программы, когда SceneRouter ещё не создан).
		_fetch_7zip_and_rescan.call_deferred()


# =====================================================================
# Игры переложили в другие папки
# =====================================================================
#
# Shellbit узнаёт файл по полному пути. Переложил «Battletoads» из
# NES/Battletoads/ в NES/Beat 'em Up/Battletoads/ — для программы это
# ДРУГОЙ файл: старый пропал, новый появился. Без переноса пропали бы
# избранное, время в игре, выбранная версия и сохранения в слотах.
#
# Поэтому после поиска сравниваем: какие файлы пропали и какие появились.
# Пропал «Battletoads (U) [!].nes» и появился файл с ТАКИМ ЖЕ именем
# (той же приставки) — значит, его переложили. Переносим на новый путь всё,
# что было привязано к старому.
#
# Имена сравниваем «упрощёнными» — только буквы и цифры (Genres.simplify):
# при раскладке файл могли и чуть переименовать,
# «Atlantis(FullRus)Лисы.chd» → «Atlantis (FullRus) Лисы.chd».
#
# Если файлов с одинаковым именем пропало или появилось несколько
# (например, «Batman (U).nes» с разных сборников), угадать, какой куда
# переехал, нельзя — такие не трогаем.

## Перенести данные переложенных игр. Возвращает, сколько игр нашлось.
func _carry_over_moved(old: Dictionary, found: Array[Dictionary]) -> int:
	var found_paths := {}
	for entry in found:
		found_paths[entry["path"]] = true

	# Пропавшие и появившиеся — по ключу «приставка + упрощённое имя файла».
	var lost := {}      # ключ → [старые записи]
	var appeared := {}  # ключ → [новые записи]
	for path: String in old:
		if not found_paths.has(path):
			var entry: Dictionary = old[path]
			_add_to(lost, _move_key(entry), entry)
	for entry in found:
		if not old.has(entry["path"]):
			_add_to(appeared, _move_key(entry), entry)

	var count := 0
	for key: String in lost:
		var was: Array = lost[key]
		var now: Array = appeared.get(key, [])
		if was.size() != 1 or now.size() != 1:
			continue  # не нашёлся или неясно, какой из одинаковых
		_move_entry(was[0], now[0])
		count += 1
	return count


func _move_key(entry: Dictionary) -> String:
	return entry.get("system", "") + "/" + Genres.simplify(String(entry["path"]).get_file())


func _add_to(index: Dictionary, key: String, entry: Dictionary) -> void:
	if not index.has(key):
		index[key] = []
	index[key].append(entry)


# Всё, что было у старого пути, — новому.
func _move_entry(was: Dictionary, now: Dictionary) -> void:
	var old_path: String = was["path"]
	var new_path: String = now["path"]
	for field: String in STAT_FIELDS:
		now[field] = was.get(field, now[field])
	now["stats"] = was.get("stats", {})  # и избранное с временем всех игроков
	# Выбранная версия: в настройках [versions] ключ игры → путь файла.
	var versions := Settings.get_section("versions")
	for key: String in versions:
		if versions[key] == old_path:
			Settings.set_value("versions", key, new_path)
	SaveStates.move_game(old_path, new_path)
	SaveStates.move_core_saves(old_path, new_path)
	Discs.move_saves(old_path, new_path)


func _announce_moved(count: int) -> void:
	SceneRouter.toast(tr("Игры переложены в другие папки: %d. Сохранения и время в игре перенесены.") % count)


func _fetch_7zip_and_rescan() -> void:
	if await Archives.ensure_seven_zip():
		scan()  # теперь .7z откроются


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
		var full_path := path.path_join(file)
		var archive := Archives.is_archive(full_path)
		var system_id := ""
		if archive:
			# Архив: приставку узнаём по файлу внутри («Contra.nes» → NES).
			# Если этот архив уже смотрели — берём ответ из прошлого раза.
			if old.has(full_path) and old[full_path].get("archive_checked", false):
				system_id = old[full_path]["system"]
			else:
				system_id = Archives.detect_system(full_path)
				if system_id == "":
					_waiting_for_7zip = true  # .7z, а открыть его пока нечем
					continue
		else:
			system_id = CoreManager.system_for_extension(file.get_extension())
		if system_id == "":
			continue  # это не игра (или приставка, которую мы не знаем)

		var entry: Dictionary = old.get(full_path, {
			"path": full_path,
			"favorite": false,
			"last_played": 0,
			"play_seconds": 0,
			"stats": {},
		})
		# Раньше любой .zip считался аркадой — у старых записей приставку уточняем.
		entry["system"] = system_id
		if archive:
			entry["archive_checked"] = true
		found.append(entry)


# Собрать файлы в группы. Вызывается после любого изменения.
func _rebuild_groups() -> void:
	var by_key := {}  # ключ группы → группа

	var roots := Settings.get_rom_folders()
	for game in games:
		# Имя разбираем при каждом запуске программы (а не храним в
		# library.json): если правила в RomInfo улучшатся, старые записи тоже
		# получат правильные названия. В пределах запуска — берём из _parsed.
		var path: String = game["path"]
		if not _parsed.has(path):
			_parsed[path] = RomInfo.parse(path.get_file())
		var info: Dictionary = _parsed[path]
		game["title"] = info["title"]
		game["version"] = info["label"]
		game["score"] = info["score"]
		if not _genres.has(path):
			_genres[path] = Genres.from_path(path, roots)
		game["genre"] = _genres[path]

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
	_by_key = by_key
	for group: Dictionary in by_key.values():
		var variants: Array = group["variants"]
		# Лучшая версия — первая. При равной оценке — по имени файла.
		variants.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["score"] != b["score"]:
				return a["score"] > b["score"]
			return a["path"] < b["path"])
		# Название берём у лучшей версии (у «плохих» оно бывает кривым).
		group["title"] = variants[0]["title"]
		# Жанр — у первой версии, чей жанр узнали. Обычно все версии игры
		# лежат в одной папке, но если одну забыли в _Unsorted — не страшно.
		group["genre"] = ""
		for variant: Dictionary in variants:
			if variant["genre"] != "":
				group["genre"] = variant["genre"]
				break
		group["favorite"] = variants.any(func(v: Dictionary) -> bool: return v["favorite"])
		group["last_played"] = variants.map(func(v: Dictionary) -> int: return int(v["last_played"])).max()
		group["play_seconds"] = variants.reduce(func(sum: int, v: Dictionary) -> int: return sum + int(v["play_seconds"]), 0)
		groups.append(group)


# --- Вопросы к библиотеке -------------------------------------------------

## Игры, которые можно показывать. В детском режиме — без жанра
## «Для взрослых» (см. autoload/Family.gd). Все списки ниже берут игры отсюда.
func visible_groups() -> Array:
	if not Family.is_on():
		return groups
	return groups.filter(Family.allows)


## Игры (группы) одной приставки, по алфавиту.
func groups_for_system(system_id: String) -> Array:
	var result := visible_groups().filter(func(g: Dictionary) -> bool: return g["system"] == system_id)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["title"].naturalnocasecmp_to(b["title"]) < 0)
	return result


## Избранные игры со всех приставок, по алфавиту.
func favorite_groups() -> Array:
	var result := visible_groups().filter(func(g: Dictionary) -> bool: return g["favorite"])
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["title"].naturalnocasecmp_to(b["title"]) < 0)
	return result


## Что листать кнопками LB/RB в библиотеке: сначала избранное
## (если в нём что-то есть), потом приставки, у которых есть игры.
func browse_ids() -> Array[String]:
	var ids: Array[String] = []
	if not favorite_groups().is_empty():
		ids.append(FAVORITES)
	ids.append_array(systems_with_games())
	return ids


## Найти игру (группу) по ключу, например "nes_battletoads". {} — если нет.
func find_group(key: String) -> Dictionary:
	# Словарь находит запись по ключу сразу — даже среди 10 000 игр.
	# Перебор groups в цикле на большой коллекции занимал около миллисекунды.
	return _by_key.get(key, {})


## Игры, в которые играли, — самые свежие первыми.
func get_recent(limit: int) -> Array:
	var result := visible_groups().filter(func(g: Dictionary) -> bool: return g["last_played"] > 0)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["last_played"] > b["last_played"])
	return result.slice(0, limit)


## id приставок, у которых есть хотя бы одна игра (в порядке systems.json).
func systems_with_games() -> Array[String]:
	var result: Array[String] = []
	var present := {}  # приставки, у которых есть хоть одна видимая игра
	for group: Dictionary in visible_groups():
		present[group["system"]] = true
	for system in CoreManager.systems:
		if present.has(system["id"]):
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
	_store_stats(game)
	_rebuild_groups()
	_save()


func add_playtime(game: Dictionary, seconds: int) -> void:
	game["play_seconds"] = int(game["play_seconds"]) + seconds
	_store_stats(game)
	_rebuild_groups()
	_save()


func toggle_favorite(group: Dictionary) -> void:
	group["favorite"] = not group["favorite"]
	for variant: Dictionary in group["variants"]:
		variant["favorite"] = group["favorite"]
		_store_stats(variant)
	_save()


# --- Игроки ------------------------------------------------------------------

## Разложить по играм избранное и время ТЕКУЩЕГО игрока.
func _apply_profile() -> void:
	var id := Profiles.current()
	for game in games:
		var stats: Dictionary = game.get("stats", {}).get(id, {})
		game["favorite"] = bool(stats.get("favorite", false))
		# int(): JSON все числа читает как дробные (5400.0).
		game["last_played"] = int(stats.get("last_played", 0))
		game["play_seconds"] = int(stats.get("play_seconds", 0))


## Запомнить в "stats" то, что у файла сейчас, — за текущего игрока.
func _store_stats(game: Dictionary) -> void:
	# get_or_add — взять "stats", а если его нет — сначала создать пустой.
	var all: Dictionary = game.get_or_add("stats", {})
	var mine := {}
	for field: String in STAT_FIELDS:
		mine[field] = game[field]
	if mine["favorite"] or mine["last_played"] or mine["play_seconds"]:
		all[Profiles.current()] = mine
	else:
		all.erase(Profiles.current())  # пусто — не храним, файл меньше


## Игрока удалили — стереть его избранное и время.
func forget_profile(id: String) -> void:
	for game in games:
		game.get("stats", {}).erase(id)
	_save()


# --- Тексты для интерфейса -------------------------------------------------

## «1 игра, 2 игры, 5 игр» — с правильным окончанием на любом языке.
func count_text(n: int) -> String:
	return Lang.n("%d игра|%d игры|%d игр", n)


func playtime_text(seconds: int) -> String:
	if seconds < 60:
		return tr("меньше минуты")
	var hours := seconds / 3600
	var minutes := (seconds % 3600) / 60
	if hours == 0:
		return tr("%d мин") % minutes
	return tr("%d ч %d мин") % [hours, minutes]


func last_played_text(unix_time: int) -> String:
	if unix_time <= 0:
		return tr("ещё не запускалась")
	var days := int(Time.get_unix_time_from_system() - unix_time) / 86400
	if days == 0:
		return tr("сегодня")
	if days == 1:
		return tr("вчера")
	return tr("%d дн. назад") % days


# --- Сохранение на диск ----------------------------------------------------

func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		# Без отступов: на тысячах игр файл получается вдвое меньше
		# и пишется быстрее (а его пишут при каждом запуске игры).
		file.store_string(JSON.stringify(games))


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if data is Array:
		games.assign(data)
	# Файл из версии, где игроков ещё не было: избранное и время в игре
	# лежат прямо в записи — отдаём их первому игроку.
	for game in games:
		if not game.has("stats"):
			game["stats"] = {}
			if game.get("favorite", false) or game.get("last_played", 0) or game.get("play_seconds", 0):
				game["stats"][Profiles.MAIN] = {
					"favorite": game.get("favorite", false),
					"last_played": game.get("last_played", 0),
					"play_seconds": game.get("play_seconds", 0),
				}
