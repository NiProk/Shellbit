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
# Русское название — это и ключ для перевода: на экран оно идёт через Lang.t().
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
##   label   — описание версии на языке интерфейса ("США · проверенная")
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

	# Текст ПОСЛЕ последней скобки — обычно авторы перевода или озвучки:
	# "Silent Hill (FullRus), Metallist озвучка Team Raccoon".
	# В название он не идёт, но показываем его в описании версии.
	var tail := _tail_after_tags(base)
	if tail != "":
		parts.append(tail)

	# .m3u — список всех дисков многодисковой игры (PS1). Его и запускаем:
	# ядро само сменит диск, когда игра попросит.
	if file_name.get_extension().to_lower() == "m3u":
		parts.append(Lang.t("все диски"))
		score += 15

	if parts.is_empty():
		parts.append(Lang.t("без пометок"))

	return {
		"title": title,
		"group": _group_key(title),
		"label": " · ".join(parts),
		"score": score,
	}


## Сделать подписи версий одной игры разными.
##
## Подпись версии собирается из меток в скобках: «(USA)» → «США». Но бывает,
## что у двух файлов метки одинаковые, а сами файлы разные:
##   Crash (USA).cue  и  Crash (USA).chd        — разный формат;
##   Rayman (USA) (En,Fr).bin и Rayman (USA) (De).bin — незнакомые метки;
##   PS1/Rus/Silent Hill.cue  и  PS1/Silent Hill.cue — разные папки.
## Тогда в списке версий видно «США» и «США» — непонятно, что выбирать.
##
## Эта функция находит такие повторы и дописывает к подписи то, чем файлы
## отличаются (по порядку, что первое сработает):
##   1) расширения разные → формат:           «США · CHD»;
##   2) имена разные → имя без названия:       «США · (USA) (En,Fr)»;
##   3) имя файла целиком (вместе с форматом);
##   4) иначе (имена одинаковые) → папка:      «США · папка Rus».
## Подходит только способ, при котором у ВСЕХ повторов вышло разное.
## variants — массив словарей с ключами "path", "title", "version";
## меняется "version" прямо в них. Уникальные подписи не трогаем.
static func tell_apart(variants: Array) -> void:
	var same := {}  # подпись → версии с этой подписью
	for variant: Dictionary in variants:
		var label: String = variant["version"]
		if not same.has(label):
			same[label] = []
		same[label].append(variant)

	for label: String in same:
		var twins: Array = same[label]
		if twins.size() < 2:
			continue
		# Три способа описать отличие — берём первый, где у всех «близнецов»
		# получилось разное. Callable — это функция, которую можно положить
		# в переменную или массив и вызвать потом: way.call(variant).
		var ways: Array[Callable] = [
			func(v: Dictionary) -> String: return String(v["path"]).get_extension().to_upper(),
			func(v: Dictionary) -> String: return _name_rest(String(v["path"]).get_file().get_basename(), v["title"]),
			func(v: Dictionary) -> String: return String(v["path"]).get_file(),
			func(v: Dictionary) -> String: return Lang.t("папка %s") % String(v["path"]).get_base_dir().get_file(),
			func(v: Dictionary) -> String: return Lang.t("папка %s") % String(v["path"]).get_base_dir().get_file() + " · " + String(v["path"]).get_file(),
		]
		var chosen: Callable = ways[-1]  # если ничто не помогло — хотя бы папка
		for way in ways:
			var seen := {}
			for variant: Dictionary in twins:
				seen[way.call(variant)] = true
			if seen.size() == twins.size():
				chosen = way
				break
		for variant: Dictionary in twins:
			variant["version"] = label + " · " + String(chosen.call(variant))


# Имя файла без названия игры в начале — чтобы не повторять «Crash Bandicoot»
# в каждой строке: «Crash Bandicoot (USA) (En,Fr)» → «(USA) (En,Fr)».
# Незнакомые метки вроде (En,Fr) в подпись не попадают — а здесь их видно.
static func _name_rest(base: String, title: String) -> String:
	var rest := base.replace("_", " ")
	if rest.to_lower().begins_with(title.to_lower()):
		rest = rest.substr(title.length()).strip_edges().trim_prefix(",").strip_edges()
	return rest if rest != "" else base


# Метки GoodTools в квадратных скобках.
static func _read_square_tag(tag: String, parts: Array[String]) -> int:
	if tag == "!":
		parts.append(Lang.t("проверенная"))
		return 100
	if tag.begins_with("T+") or tag.begins_with("T-"):
		# [T+Rus] — перевод. Язык — буквы после + или -, до версии перевода.
		var lang := tag.substr(2).rstrip("0123456789._ ")
		parts.append(Lang.t("перевод %s") % lang)
		return -20
	if tag.is_empty():
		return 0

	# Остальные метки — буква и номер: b1, o2, h1C, a1...
	match tag[0]:
		"b":
			parts.append(Lang.t("повреждённая"))
			return -300
		"o":
			parts.append(Lang.t("с лишними данными"))
			return -40
		"a":
			parts.append(Lang.t("альтернативная"))
			return -10
		"h":
			parts.append(Lang.t("хак"))
			return -80
		"t":
			parts.append(Lang.t("с трейнером"))
			return -60
		"p":
			parts.append(Lang.t("пиратская"))
			return -70
		"f":
			parts.append(Lang.t("исправленная"))
			return -5
	return 0


# Метки в круглых скобках: регион, ревизия, прототип или номер копии.
static func _read_round_tag(tag: String, parts: Array[String]) -> int:
	var upper := tag.strip_edges().to_upper()

	# "(1)", "(2)" — Windows дописывает такое к копиям файла.
	if upper.is_valid_int():
		parts.append(Lang.t("копия файла"))
		return -5

	# "(Disc 2)", "(Disc 2 of 3)" — один из дисков многодисковой игры.
	if upper.begins_with("DISC "):
		var number := upper.get_slice(" ", 1)
		parts.append(Lang.t("диск %s") % number)
		return -number.to_int()  # первый диск — выше остальных

	# Русские переводы: (Rus), (RUS), (FullRus), (Rus by Shedevr)...
	if (upper.begins_with("RUS") and upper != "RUSSIA") or upper.begins_with("FULLRUS") or upper.contains(" RUS"):
		parts.append(Lang.t("русский перевод"))
		return 0

	if upper in UNFINISHED:
		parts.append(Lang.t("прототип") if upper.begins_with("PROTO") else Lang.t("бета/демо"))
		return -50

	if _revision_regex.search(upper):
		parts.append(Lang.t("ревизия %s") % tag.strip_edges().trim_prefix("Rev ").trim_prefix("rev "))
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
	# Названия регионов переводим только сейчас, при выводе:
	# очки (REGION_SCORE) выше считались по русским названиям.
	if names.size() == 1:
		parts.append(Lang.t(names[0]))
	elif names.size() == 2:
		parts.append(Lang.t("%s и %s") % [Lang.t(names[0]), Lang.t(names[1])])
	else:
		parts.append(Lang.t("Весь мир"))
	return best


# "Bugs_Bunny_Crazy_Castle, The (U) [b1]" → "The Bugs Bunny Crazy Castle"
static func _clean_title(base: String) -> String:
	# Название — всё, что ДО первой скобки. После скобок идёт служебное:
	# регион, метки, имена переводчиков.
	var cut := base.length()
	for bracket in ["(", "["]:
		var at := base.find(bracket)
		if at > 0:
			cut = mini(cut, at)
	var title := base.substr(0, cut).strip_edges().trim_suffix(",").strip_edges()
	if title.is_empty():
		# Имя начинается со скобки, например "[BIOS] ..." — просто убираем метки.
		title = _tags_regex.sub(base, "", true).strip_edges()
	# В архивах артикль часто переносят в конец для сортировки: "Castle, The".
	for article in ["The", "A", "An"]:
		var suffix: String = ", " + article
		if title.ends_with(suffix):
			title = article + " " + title.trim_suffix(suffix)
	# Двойные пробелы, оставшиеся после удаления меток.
	while title.contains("  "):
		title = title.replace("  ", " ")
	return title


# Текст после последней закрывающей скобки: "...(FullRus)Лисы" → "Лисы".
static func _tail_after_tags(base: String) -> String:
	var last := maxi(base.rfind(")"), base.rfind("]"))
	if last < 0:
		return ""
	return base.substr(last + 1).strip_edges().trim_prefix(",").strip_edges()


# Ключ группы: только буквы и цифры в нижнем регистре.
# "The Bugs Bunny: Crazy Castle" и "Bugs Bunny Crazy Castle" дадут один ключ.
static func _group_key(title: String) -> String:
	var key := title.to_lower()
	if key.begins_with("the "):
		key = key.substr(4)
	# \p{L} — любая буква любого алфавита (латиница, кириллица, японский...),
	# \p{N} — любая цифра. Убираем всё, что НЕ буква и НЕ цифра.
	return _not_letters_regex.sub(key, "", true)
