class_name GameInfo
extends RefCounted
## GameInfo — сведения об игре: год, жанр, число игроков, разработчик.
##
## Данные взяты из открытой базы libretro-database (файлы .rdb) и заранее
## собраны в data/meta/<приставка>.txt — по строке на игру:
##   ключ <TAB> год <TAB> жанр <TAB> игроков <TAB> разработчик <TAB> издатель
## Ключ — тот же, что у RomInfo и обложек ("battletoads").
##
## Описания игры в базе нет. Его можно написать самому: положи рядом
## с игрой текстовый файл с тем же именем — "Battletoads (U) [!].txt".
## В одном файле можно держать описания на разных языках — формат
## описан у функции parse_description() и в README.
##
## Использование:  var info := GameInfo.lookup(group)
##                 info["year"], info["genre"], info["players"] ...

# Справочники, уже прочитанные с диска: id приставки → {ключ: [поля]}.
# static var — одна копия на всю программу, общая для всех вызовов.
static var _indexes := {}

# Жанры из базы — по-английски. Сопоставляем их с русскими названиями,
# а русское название — ключ в таблице переводов (Lang.t переведёт на язык интерфейса).
const GENRES := {
	"Action": "Экшен", "Sports": "Спорт", "Platform": "Платформер",
	"Role-playing (RPG)": "Ролевая игра", "Adventure": "Приключения",
	"Racing": "Гонки", "Strategy": "Стратегия", "Puzzle": "Головоломка",
	"Simulation": "Симулятор", "Fighting": "Файтинг", "Shooter": "Шутер",
	"Board": "Настольная игра", "Gambling": "Азартная игра",
	"Shoot'em Up": "Скролл-шутер", "Beat'em Up": "Beat 'em up",
	"Compilation": "Сборник", "Hunting and Fishing": "Охота и рыбалка",
	"Quiz": "Викторина", "Card": "Карточная игра", "Educational": "Обучающая",
	"Mahjong": "Маджонг", "Pinball": "Пинбол", "Music": "Музыкальная",
	"Basketball": "Баскетбол", "Dancing": "Танцевальная", "Football": "Футбол",
	"Wrestling": "Рестлинг", "Gun": "Тир", "Lightgun Shooter": "Тир",
	"Boxing": "Бокс", "Tennis": "Теннис", "Mini Games": "Мини-игры",
	"Various": "Разное", "Music / Dancing": "Музыка и танцы",
	"Sports with Animals": "Спорт с животными", "Casual Game": "Казуальная",
}


## Сведения об игре (группе). Пустые строки — если в базе ничего нет.
static func lookup(group: Dictionary) -> Dictionary:
	var system_id: String = group["system"]
	if not _indexes.has(system_id):
		_indexes[system_id] = _load(system_id)
	var key: String = group["key"].trim_prefix(system_id + "_")
	var f: Array = _indexes[system_id].get(key, ["", "", "", "", ""])

	var genre: String = f[1]
	var about := _description(group)
	return {
		"year": f[0],
		"genre": Lang.t(GENRES.get(genre, genre)),
		"players": _players_text(f[2]),
		"developer": f[3],
		"publisher": f[4],
		"title": about["title"],        # название на языке интерфейса ("" — нет)
		"description": about["text"],
	}


## Строка «1991 · Beat 'em up · 1–2 игрока · Rareware» — без пустых кусков.
static func summary(info: Dictionary) -> String:
	var parts: Array[String] = []
	for field in ["year", "genre", "players", "developer"]:
		if info[field] != "":
			parts.append(info[field])
	return " · ".join(parts)


static func _load(system_id: String) -> Dictionary:
	var index := {}
	var text := FileAccess.get_file_as_string("res://data/meta/%s.txt" % system_id)
	for line in text.split("\n", false):
		var f := line.split("\t")
		if f.size() == 6:
			index[f[0]] = [f[1], f[2], f[3], f[4], f[5]]
	return index


# "2" → "1–2 игрока", "1" → "1 игрок", "5" → "1–5 игроков"
static func _players_text(users: String) -> String:
	var n := users.to_int()
	if n <= 0:
		return ""
	if n == 1:
		return Lang.t("1 игрок")
	return Lang.n("1–%d игрок|1–%d игрока|1–%d игроков", n)


# Описание из текстового файла рядом с игрой (с тем же именем, .txt).
static func _description(group: Dictionary) -> Dictionary:
	for variant: Dictionary in group["variants"]:
		var path: String = variant["path"].get_basename() + ".txt"
		if FileAccess.file_exists(path):
			return parse_description(FileAccess.get_file_as_string(path))
	return {"title": "", "text": ""}


## Разобрать файл описания и взять текст на языке интерфейса.
##
## Формат файла (кодировка UTF-8):
##
##     [ru]
##     title: Боевые жабы
##     Три жабы-космонавта летят спасать подругу…
##
##     [en]
##     Three space toads set out to rescue…
##
##     [ja]
##     title: バトルトード
##     …
##
## * [ru], [en], [zh], [ja], [de], [fr], [es], [pt], [ko] — с этой строки начинается текст на этом языке.
## * title: — необязательная первая строка: название игры на этом языке.
##   (Можно писать и «название:».)
## * Всё остальное — описание. Пустые строки и абзацы сохраняются.
## * Файл без меток [..] — старый формат: весь текст — описание
##   для любого языка. Такие файлы продолжают работать.
##
## Какой язык показать: язык интерфейса → английский → русский →
## текст без метки → любой, какой есть.
## Название (title:) берётся только на языке интерфейса или английское —
## иначе показывается название из имени файла.
## Возвращает {"title": "...", "text": "..."}.
static func parse_description(content: String) -> Dictionary:
	# Разделы: код языка → {"title": "...", "lines": [строки текста]}.
	# "*" — текст до первой метки (старый формат без языков).
	var sections := {}
	var current := "*"

	for line in content.replace("\r", "").split("\n"):
		var stripped := line.strip_edges()

		# Строка-метка языка: [ru], [EN]…
		if stripped.begins_with("[") and stripped.ends_with("]"):
			var code := stripped.substr(1, stripped.length() - 2).strip_edges().to_lower()
			if Lang.SUPPORTED.has(code):
				current = code
				continue

		if not sections.has(current):
			sections[current] = {"title": "", "lines": []}
		var section: Dictionary = sections[current]
		var lines: Array = section["lines"]

		# Пустые строки в начале раздела пропускаем.
		if lines.is_empty() and stripped == "":
			continue
		# «title:» — только в самом начале раздела.
		if lines.is_empty() and section["title"] == "":
			for prefix in ["title:", "название:"]:
				if stripped.to_lower().begins_with(prefix):
					section["title"] = stripped.substr(prefix.length()).strip_edges()
					break
			if section["title"] != "":
				continue
		lines.append(line)

	var result := {"title": "", "text": ""}

	# Название — только на языке интерфейса или английское.
	# Иначе останется название из имени файла (обычно оно латиницей,
	# и это лучше, чем показать англичанину русское название).
	for code in [Lang.language, "en"]:
		if sections.has(code) and result["title"] == "":
			result["title"] = sections[code]["title"]

	# Описание — первое непустое по порядку языков.
	var order: Array = [Lang.language, "en", "ru", "*"] + sections.keys()
	for code: String in order:
		if sections.has(code) and result["text"] == "":
			result["text"] = "\n".join(sections[code]["lines"]).strip_edges()
	return result
