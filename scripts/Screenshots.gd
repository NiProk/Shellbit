class_name Screenshots
extends RefCounted
## Screenshots — скриншоты игр: как назвать файл и как найти снимки игры.
##
## Все скриншоты лежат в одной папке («Изображения\Shellbit», см.
## Settings.screenshots_dir()), а к какой игре относится снимок, видно
## по имени файла: «название игры» + пробел + дата и время:
##   Contra 2026-10-30 21-15-02.png
##   Contra Force 2026-10-30 21-40-11.png
## Поэтому для галереи на странице игры достаточно прочитать имена файлов.
## Чтобы «Contra» не забрала снимки «Contra Force», после названия
## должна идти именно дата — это проверяет регулярное выражение STAMP.

## Дата и время в конце имени: «2026-10-30 21-15-02.png».
## Регулярное выражение — «шаблон» строки: \d — цифра, {4} — четыре раза,
## ^ — начало, $ — конец.
const STAMP := "^\\d{4}-\\d{2}-\\d{2} \\d{2}-\\d{2}-\\d{2}\\.png$"


## Название игры без знаков, запрещённых в именах файлов Windows: \ / : * ? " < > |
static func clean_title(title: String) -> String:
	for bad in ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]:
		title = title.replace(bad, "")
	return title.strip_edges()


## Имя файла для нового снимка: «Contra 2026-10-30 21-15-02.png».
## Двоеточия во времени меняем на «-»: в именах файлов их тоже нельзя.
static func file_name(title: String) -> String:
	var stamp := Time.get_datetime_string_from_system().replace("T", " ").replace(":", "-")
	return "%s %s.png" % [clean_title(title), stamp]


## Снимки игры (полные пути), новые — первыми.
## titles — названия, под которыми игра могла сохраняться (у разных
## версий одной игры названия обычно одинаковые, но бывают и разные).
static func list_for(titles: Array, folder := "") -> PackedStringArray:
	if folder == "":
		folder = Settings.screenshots_dir()
	var stamp := RegEx.create_from_string(STAMP)
	var prefixes := []
	for title: String in titles:
		var clean := clean_title(title)
		if clean != "" and not (clean + " ") in prefixes:
			prefixes.append(clean + " ")
	var found: Array = []
	for file in DirAccess.get_files_at(folder):  # папки нет — пустой список
		for prefix: String in prefixes:
			if file.begins_with(prefix) and stamp.search(file.trim_prefix(prefix)) != null:
				found.append(file)
				break
	# Дата в имени записана «год-месяц-день часы-минуты-секунды», поэтому
	# сортировка по алфавиту хвоста — это сортировка по времени.
	found.sort_custom(func(a: String, b: String) -> bool: return a.right(23) > b.right(23))
	return PackedStringArray(found.map(func(file: String) -> String: return folder.path_join(file)))


## «Contra 2026-10-30 21-15-02.png» → «30.10.2026  21:15».
static func date_text(path: String) -> String:
	var tail := path.get_file().right(23)  # «2026-10-30 21-15-02.png»
	return "%s.%s.%s  %s:%s" % [tail.substr(8, 2), tail.substr(5, 2), tail.substr(0, 4),
			tail.substr(11, 2), tail.substr(14, 2)]
