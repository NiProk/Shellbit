class_name ArcadeNames
extends RefCounted
## ArcadeNames — настоящие названия аркадных игр.
##
## Аркадная игра — это архив с коротким «машинным» именем: sf2.zip,
## mslug.zip, dino.zip. Переименовывать его нельзя: по имени эмулятор
## понимает, что за игра. Поэтому красивое название берём из таблицы
## data/meta/arcade_names.txt — её Shellbit получил из официального списка
## игр эмулятора FinalBurn Neo (по строке на игру):
##   имя <TAB> название <TAB> версия <TAB> родитель <TAB> b, если это BIOS <TAB> нужный BIOS
##   sf2      Street Fighter II: The World Warrior   World 910522
##   sf2ceua  Street Fighter II': Champion Edition   USA 920313   sf2ce
##   neogeo   Neo Geo                                                b
##   mslug    Metal Slug - Super Vehicle-001                              neogeo
##
## «Родитель» и «клон»: у многих игр есть несколько версий — для разных
## стран или исправленные. Главная версия — родитель, остальные — клоны.
## Shellbit собирает их в одну карточку, как версии игр для приставок.
##
## BIOS (neogeo.zip, pgm.zip…) — не игры, а «прошивка» автомата, которая
## нужна другим играм. Их в библиотеке не показываем, но с диска не трогаем.
## Какой BIOS нужен игре — последний столбец: всем играм Neo Geo (Metal Slug,
## King of Fighters…) нужен neogeo.zip, играм PGM — pgm.zip и т.д.
## Без него FBNeo показывает вместо игры экран «romset is missing files».

const PATH := "res://data/meta/arcade_names.txt"

# Таблица, прочитанная с диска: имя архива → [название, версия, родитель, BIOS?, нужный BIOS].
# static var — одна на всю программу; читаем при первом вопросе.
static var _rows := {}


## Есть ли игра в таблице (по пути к архиву).
static func knows(path: String) -> bool:
	return _table().has(_short(path))


## Какой BIOS (имя архива без .zip) нужен игре: "neogeo" — или "", если никакой.
static func bios_of(path: String) -> String:
	var row: Array = _table().get(_short(path), [])
	return row[4] if not row.is_empty() else ""


## Название BIOS для человека: "neogeo" → "Neo Geo".
static func bios_title(bios: String) -> String:
	var row: Array = _table().get(bios, [])
	return row[0] if not row.is_empty() else bios


## Это BIOS, а не игра? Такие архивы в библиотеку не попадают.
static func is_bios(path: String) -> bool:
	var row: Array = _table().get(_short(path), [])
	return not row.is_empty() and row[3]


## Сведения об игре в том же виде, что у RomInfo.parse():
## {"title", "group", "label", "score"}. group — имя родителя: так все
## версии игры (sf2, sf2ua, sf2j…) окажутся в одной карточке.
static func parse(path: String) -> Dictionary:
	var short := _short(path)
	var row: Array = _table()[short]
	var parent: String = row[2] if row[2] != "" else short
	return {
		"title": row[0],
		"group": parent,
		"label": row[1] if row[1] != "" else Lang.t("без пометок"),
		# Родитель — «лучшая» версия: её запускаем по умолчанию.
		"score": 100 if row[2] == "" else 50,
	}


# "D:/Games/Arcade/sf2.zip" → "sf2" (имена в таблице — маленькими буквами).
static func _short(path: String) -> String:
	return path.get_file().get_basename().to_lower()


static func _table() -> Dictionary:
	if _rows.is_empty():
		var text := FileAccess.get_file_as_string(PATH)
		for line in text.split("\n", false):
			if line.begins_with("#"):
				continue  # строки с # — пояснения в начале файла
			var f := line.split("\t")
			if f.size() >= 5:
				_rows[f[0]] = [f[1], f[2], f[3], f[4] == "b", f[5] if f.size() > 5 else ""]
	return _rows
