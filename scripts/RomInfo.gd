class_name RomInfo
extends RefCounted
## RomInfo — разбирает имя файла игры и понимает, что это за версия.
##
## В именах ROM-файлов прячется много сведений. Есть две системы меток:
##
##   GoodTools (старая):  "Battletoads (U) [!].nes"
##       (U) — регион США, [!] — проверенная копия, [b1] — повреждённая...
##   No-Intro (новая):    "Battletoads (USA) (Rev 1).nes"
##       только аккуратные круглые скобки, плохих копий в наборах нет.
##
## Все функции здесь static — их вызывают прямо через имя класса,
## без создания объекта:   var info := RomInfo.parse("Battletoads (U) [!].nes")
##
## class_name вверху делает класс видимым во всём проекте (как Button или Label),
## поэтому его не нужно добавлять в Autoload.

# Регионы: метка в скобках → название по-русски.
const REGIONS := {
	"U": "США", "USA": "США",
	"E": "Европа", "EUROPE": "Европа",
	"J": "Япония", "JAPAN": "Япония",
	"W": "Весь мир", "WORLD": "Весь мир",
	"UE": "США и Европа", "JU": "США и Япония", "JUE": "Весь мир",
	"R": "Россия", "RUSSIA": "Россия",
	"K": "Корея", "KOREA": "Корея",
	"F": "Франция", "FRANCE": "Франция",
	"G": "Германия", "GERMANY": "Германия",
	"S": "Испания", "SPAIN": "Испания",
	"I": "Италия", "ITALY": "Италия",
	"A": "Австралия", "AUSTRALIA": "Австралия",
	"B": "Бразилия", "BRAZIL": "Бразилия",
	"CH": "Китай", "CHINA": "Китай",
}

# Насколько регион хорош для игры. Американские версии идут на 60 кадрах
# в секунду, как задумано авторами; европейские (PAL) — на 50, медленнее.
const REGION_SCORE := {
	"США": 30, "Весь мир": 30, "США и Европа": 28, "США и Япония": 26,
	"Европа": 20, "Япония": 10,
}

# Пометки, которые означают «не финальная версия».
const UNFINISHED := ["PROTOTYPE", "PROTO", "BETA", "SAMPLE", "DEMO"]

# Находит все кусочки в скобках: (U), [!], (Rev 1), [b1]...
static var _tags_regex := RegEx.create_from_string("\\(([^)]*)\\)|\\[([^\\]]*)\\]")
# "Rev 1", "Rev A", "V1.1"
static var _revision_regex := RegEx.create_from_string("^(REV\\s*\\w+|V\\d+(\\.\\d+)*)$")
# Всё, что не буква и не цифра (для ключа группы).
static var _not_letters_regex := RegEx.create_from_string("[^\\p{L}\\p{N}]+")


## Разобрать имя файла. Возвращает словарь:
##   title   — красивое название ("The Bugs Bunny Crazy Castle")
##   group   — ключ для объединения версий ("bugsbunnycrazycastle")
##   label   — описание версии по-русски ("США · проверенная")
##   score   — оценка: чем больше, тем лучше версия
static func parse(file_name: String) -> Dictionary:
	var base := file_name.get_basename().replace("_", " ")
	var title := _clean_title(base)
	var parts: Array[String] = []  # кусочки описания версии
	var score := 0

	for m in _tags_regex.search_all(base):
		var round_tag := m.get_string(1)   # то, что было в ( )
		var square_tag := m.get_string(2)  # то, что было в [ ]
		if square_tag != "":
			score += _read_square_tag(square_tag, parts)
		else:
			score += _read_round_tag(round_tag, parts)

	if parts.is_empty():
		parts.append("без пометок")

	return {
		"title": title,
		"group": _group_key(title),
		"label": " · ".join(parts),
		"score": score,
	}


# Метки GoodTools в квадратных скобках.
static func _read_square_tag(tag: String, parts: Array[String]) -> int:
	if tag == "!":
		parts.append("проверенная")
		return 100
	if tag.begins_with("T+") or tag.begins_with("T-"):
		# [T+Rus] — перевод. Язык — буквы после + или -, до версии перевода.
		var lang := tag.substr(2).rstrip("0123456789._ ")
		parts.append("перевод " + lang)
		return -20
	if tag.is_empty():
		return 0

	# Остальные метки — буква и номер: b1, o2, h1C, a1...
	match tag[0]:
		"b":
			parts.append("повреждённая")
			return -300
		"o":
			parts.append("с лишними данными")
			return -40
		"a":
			parts.append("альтернативная")
			return -10
		"h":
			parts.append("хак")
			return -80
		"t":
			parts.append("с трейнером")
			return -60
		"p":
			parts.append("пиратская")
			return -70
		"f":
			parts.append("исправленная")
			return -5
	return 0


# Метки в круглых скобках: регион, ревизия, прототип или номер копии.
static func _read_round_tag(tag: String, parts: Array[String]) -> int:
	var upper := tag.strip_edges().to_upper()

	# "(1)", "(2)" — Windows дописывает такое к копиям файла.
	if upper.is_valid_int():
		parts.append("копия файла")
		return -5

	if upper in UNFINISHED:
		parts.append("прототип" if upper.begins_with("PROTO") else "бета/демо")
		return -50

	if _revision_regex.search(upper):
		parts.append("ревизия " + tag.strip_edges().trim_prefix("Rev ").trim_prefix("rev "))
		return 2  # поздние ревизии обычно с исправлениями

	# "(USA, Europe)" — бывает несколько регионов через запятую.
	var best := -1
	var names: Array[String] = []
	for piece in upper.split(",", false):
		var region: String = REGIONS.get(piece.strip_edges(), "")
		if region != "":
			names.append(region)
			best = maxi(best, REGION_SCORE.get(region, 5))
	if names.is_empty():
		return 0  # незнакомая метка — просто пропускаем
	parts.append(" и ".join(names) if names.size() <= 2 else "Весь мир")
	return best


# "Bugs_Bunny_Crazy_Castle, The (U) [b1]" → "The Bugs Bunny Crazy Castle"
static func _clean_title(base: String) -> String:
	var title := _tags_regex.sub(base, "", true).strip_edges()
	# В архивах артикль часто переносят в конец для сортировки: "Castle, The".
	for article in ["The", "A", "An"]:
		var suffix: String = ", " + article
		if title.ends_with(suffix):
			title = article + " " + title.trim_suffix(suffix)
	# Двойные пробелы, оставшиеся после удаления меток.
	while title.contains("  "):
		title = title.replace("  ", " ")
	return title


# Ключ группы: только буквы и цифры в нижнем регистре.
# "The Bugs Bunny: Crazy Castle" и "Bugs Bunny Crazy Castle" дадут один ключ.
static func _group_key(title: String) -> String:
	var key := title.to_lower()
	if key.begins_with("the "):
		key = key.substr(4)
	# \p{L} — любая буква любого алфавита (латиница, кириллица, японский...),
	# \p{N} — любая цифра. Убираем всё, что НЕ буква и НЕ цифра.
	return _not_letters_regex.sub(key, "", true)
