extends Node
## Lang — язык интерфейса: переводы, шрифты, числа со словами.
##
## Как устроен перевод
## -------------------
## 1. В коде все тексты пишутся по-русски и оборачиваются в tr():
##        button.text = tr("Настройки")
##    tr() — встроенная функция Godot: ищет перевод для текущего языка,
##    а если не нашла — возвращает текст как есть.
## 2. Переводы лежат в таблице data/i18n/strings.tsv — по строке на текст:
##        ru <TAB> en <TAB> zh <TAB> ja <TAB> de <TAB> fr <TAB> es <TAB> pt <TAB> ko
##    Первый столбец — русский текст. Он же «ключ», по которому tr() ищет перевод.
##    Таблицу удобно править в Excel или LibreOffice Calc.
## 3. Тексты, написанные прямо в сценах (.tscn), Godot переводит сам,
##    если такой текст есть в таблице.
## 4. В static-функциях (RomInfo, GameInfo, SaveStates) tr() недоступен —
##    там пишем Lang.t("...").
##
## Числа со словами («5 игр», «5 games») — функция Lang.n(), см. ниже.

## Язык сменился. Экраны и библиотека подписываются, чтобы обновить тексты.
signal language_changed

const STRINGS_PATH := "res://data/i18n/strings.tsv"
## Коды языков — как их называет Windows (OS.get_locale_language()).
## "pt" — португальский; перевод сделан для Бразилии.
const SUPPORTED := ["ru", "en", "zh", "ja", "de", "fr", "es", "pt", "ko"]

## Варианты для экрана настроек. Названия языков — на самих языках:
## так человек найдёт свой язык, даже если случайно включил чужой.
const CHOICES := [
	["auto", "Как в системе"],
	["ru", "Русский"],
	["en", "English"],
	["zh", "中文（简体）"],
	["ja", "日本語"],
	["de", "Deutsch"],
	["fr", "Français"],
	["es", "Español"],
	["pt", "Português (Brasil)"],
	["ko", "한국어"],
]

## Текущий язык: "ru", "en", "zh", "ja", "de", "fr", "es", "pt" или "ko".
var language := "ru"


func _ready() -> void:
	_load_table()
	apply(Settings.get_value("general", "language"))


## Включить язык. choice — значение из настроек: "auto", "ru", "en"...
func apply(choice: String) -> void:
	var code := choice
	if not SUPPORTED.has(code):  # "auto" или что-то незнакомое
		# OS.get_locale_language() — язык Windows: "ru", "en", "zh", "ja"...
		code = OS.get_locale_language()
		if not SUPPORTED.has(code):
			code = "en"  # язык системы мы не знаем — берём английский
	language = code
	TranslationServer.set_locale(code)
	language_changed.emit()


## Перевести текст (для мест, где нет tr(): static-функции).
func t(text: String) -> String:
	# translate() возвращает StringName — переводим в обычную строку,
	# чтобы с ней работали % и +.
	return String(TranslationServer.translate(text))


## Число со словом в правильной форме.
##   Lang.n("%d игра|%d игры|%d игр", 5)  → "5 игр" / "5 games" / "5 个游戏"
## Формы разделены знаком |. В русском их три (1 игра, 2 игры, 5 игр),
## в английском, немецком, французском, испанском и португальском две
## (1 game, 2 games), в китайском, японском и корейском — одна.
## Ключ в таблице — русские формы, перевод — формы своего языка.
func n(forms_key: String, number: int) -> String:
	var forms := t(forms_key).split("|")
	var index := mini(_plural_index(number), forms.size() - 1)
	return forms[index] % number


# Какую форму слова взять для числа (правила своего языка).
func _plural_index(number: int) -> int:
	match language:
		"ru":
			# 1, 21, 31… → «игра»; 2–4, 22–24… → «игры»; остальные → «игр».
			if number % 10 == 1 and number % 100 != 11:
				return 0
			if number % 10 in [2, 3, 4] and not (number % 100 in [12, 13, 14]):
				return 1
			return 2
		"en", "de", "es":
			return 0 if number == 1 else 1
		"fr", "pt":
			# Во французском и бразильском португальском 0 — тоже «один»:
			# «0 jeu», «1 jeu», но «2 jeux».
			return 0 if number <= 1 else 1
		_:
			return 0  # в китайском, японском и корейском форма одна


# Прочитать таблицу переводов и отдать её Godot (TranslationServer).
func _load_table() -> void:
	var file := FileAccess.open(STRINGS_PATH, FileAccess.READ)
	if file == null:
		push_error("Нет таблицы переводов " + STRINGS_PATH)
		return

	# Первая строка — заголовок: коды языков (ru, en, zh, ja).
	# Для каждого языка создаём объект Translation — «словарь» Godot.
	var header := file.get_csv_line("\t")
	var dictionaries: Array[Translation] = []
	for code in header:
		var dictionary := Translation.new()
		dictionary.locale = code.strip_edges()
		dictionaries.append(dictionary)

	while not file.eof_reached():
		var row := file.get_csv_line("\t")
		# Пустые строки и строки-комментарии (начинаются с #) пропускаем.
		if row.is_empty() or row[0].strip_edges() == "" or row[0].begins_with("#"):
			continue
		# c_unescape превращает «\n», написанное в таблице двумя символами,
		# в настоящий перенос строки — как в коде.
		var key := row[0].c_unescape()
		for i in mini(row.size(), dictionaries.size()):
			var value := row[i].c_unescape()
			if value != "":  # пустая клетка — перевода нет, останется английский/русский
				dictionaries[i].add_message(key, value)

	for dictionary in dictionaries:
		TranslationServer.add_translation(dictionary)
