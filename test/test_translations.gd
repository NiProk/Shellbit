extends TestCase
## Переводы: таблица strings.tsv и формы слов с числами.

const TABLE := "res://data/i18n/strings.tsv"
## Где искать тексты интерфейса, которые должны быть в таблице.
const CODE_DIRS := ["res://autoload", "res://scenes", "res://scripts"]


func after_each() -> void:
	Lang.apply(Settings.get_value("general", "language"))  # вернуть язык как был


func test_table_shape() -> void:
	about("В таблице переводов у каждой строки 9 языков")
	var rows := _rows()
	check_eq(rows[0], PackedStringArray(Lang.SUPPORTED), "заголовок таблицы — коды языков из Lang.SUPPORTED")
	for row in rows.slice(1):
		check_eq(row.size(), Lang.SUPPORTED.size(), "строка «%s»" % row[0])


func test_placeholders_match() -> void:
	about("В переводах те же %s, %d и переносы строк, что в русском")
	# Порядок важен: tr("%d из %s") % [3, "20 игр"] подставляет значения
	# по очереди, и перевод «%s 중 %d» получил бы текст вместо числа.
	var rows := _rows()
	for row in rows.slice(1):
		# У слов с числами формы разделены «|»: сравниваем каждую форму с первой русской.
		var expected := _placeholders(row[0].split("|")[0])
		for i in range(1, row.size()):
			if row[i] == "":
				continue
			for form in row[i].split("|"):
				check_eq(_placeholders(form), expected, "«%s» → %s: «%s»" % [row[0], rows[0][i], form])
			check_eq(row[i].count("\\n"), row[0].count("\\n"), "переносы строк: «%s» → %s" % [row[0], rows[0][i]])


func test_code_texts_are_translated() -> void:
	about("Каждый русский текст из кода и сцен есть в таблице переводов")
	var keys := {}
	for row in _rows().slice(1):
		keys[row[0].c_unescape()] = true
	# Названия языков в списке пишутся на самих языках — их не переводят.
	for choice: Array in Lang.CHOICES:
		if choice[0] != "auto":
			keys[choice[1]] = true
	for text: String in _texts_in_code():
		check(keys.has(text), "нет перевода: «%s»" % text.c_escape())


func test_plural_forms() -> void:
	about("Числа со словами: 1 игра, 2 игры, 5 игр — на всех языках")
	var forms := "%d игра|%d игры|%d игр"
	var expected := {
		"ru": ["1 игра", "3 игры", "5 игр", "21 игра", "11 игр"],
		"en": ["1 game", "3 games", "5 games", "21 games", "11 games"],
		"de": ["1 Spiel", "3 Spiele", "5 Spiele", "21 Spiele", "11 Spiele"],
		"fr": ["1 jeu", "3 jeux", "5 jeux", "21 jeux", "11 jeux"],
		"ko": ["게임 1개", "게임 3개", "게임 5개", "게임 21개", "게임 11개"],
	}
	for code: String in expected:
		Lang.apply(code)
		var got := []
		for number in [1, 3, 5, 21, 11]:
			got.append(Lang.n(forms, number))
		check_eq(got, expected[code], "язык %s" % code)
	# Во французском ноль — тоже «один».
	Lang.apply("fr")
	check_eq(Lang.n(forms, 0), "0 jeu", "0 во французском")


func test_language_switch() -> void:
	about("Смена языка переводит tr()")
	Lang.apply("de")
	check_eq(tr("Настройки"), "Einstellungen")
	Lang.apply("ja")
	check_eq(tr("Настройки"), "設定")
	Lang.apply("ru")
	check_eq(tr("Настройки"), "Настройки")


# --- Помощники ----------------------------------------------------------------

func _rows() -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var file := FileAccess.open(TABLE, FileAccess.READ)
	while not file.eof_reached():
		var row := file.get_csv_line("\t")
		if row.is_empty() or row[0].strip_edges() == "" or row[0].begins_with("#"):
			continue
		rows.append(row)
	return rows


func _placeholders(text: String) -> Array:
	var found := []
	for m in RegEx.create_from_string("%[sd]").search_all(text):
		found.append(m.get_string())
	return found


# Русские тексты, которые программа показывает человеку:
#   tr("…"), Lang.t("…"), Lang.n("…"), _choice("…"), _action("…") и т.п.,
#   пары подсказок ["accept", "…"], поля "title"/"about"/"name"/"note",
#   надписи text = "…" в сценах .tscn, названия приставок в systems.json.
func _texts_in_code() -> Dictionary:
	var patterns := [
		'\\btr\\("((?:[^"\\\\]|\\\\.)*)"\\)',
		'Lang\\.[tn]\\("((?:[^"\\\\]|\\\\.)*)"',
		'_(?:choice|action|toggle|info)\\("((?:[^"\\\\]|\\\\.)*)"',
		'\\["[a-z_]+", "((?:[^"\\\\]|\\\\.)*)"',
		'"(?:title|about|name|note)": "((?:[^"\\\\]|\\\\.)*)"',
	]
	var regexes := patterns.map(func(p: String) -> RegEx: return RegEx.create_from_string(p))
	var scene_text := RegEx.create_from_string('(?m)^text = "((?:[^"\\\\]|\\\\.)*)"')
	var texts := {}
	for path: String in _files(CODE_DIRS, ["gd"]):
		var source := FileAccess.get_file_as_string(path)
		for regex: RegEx in regexes:
			for m in regex.search_all(source):
				_add_text(texts, m.get_string(1).c_unescape())
	for path: String in _files(CODE_DIRS, ["tscn"]):
		for m in scene_text.search_all(FileAccess.get_file_as_string(path)):
			_add_text(texts, m.get_string(1).c_unescape())
	for system: Dictionary in CoreManager.systems:
		_add_text(texts, system["name"])
	for system_id in InputMapper.pads:
		_add_text(texts, InputMapper.pads[system_id].get("note", ""))
	return texts


func _add_text(texts: Dictionary, text: String) -> void:
	# Переводить нужно только русские надписи: «Shellbit», «A», «×3» — нет.
	if RegEx.create_from_string("[А-Яа-яЁё]").search(text) != null:
		texts[text] = true


func _files(dirs: Array, extensions: Array) -> Array[String]:
	var result: Array[String] = []
	for dir: String in dirs:
		for file in DirAccess.get_files_at(dir):
			if file.get_extension() in extensions:
				result.append(dir.path_join(file))
		for sub in DirAccess.get_directories_at(dir):
			result.append_array(_files([dir.path_join(sub)], extensions))
	return result
