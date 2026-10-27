class_name Genres
extends RefCounted
## Genres — жанр игры по названию папки, в которой она лежит.
##
## Игры разложены так:
##   D:/Game_archive/NES(Famicom)/Platformer/Mega Man 2/Mega Man 2 (USA).nes
##                    приставка    ЖАНР     папка игры   файл
##
## Мы идём по папкам пути сверху вниз и ищем первую, чьё имя похоже на жанр
## из списка LIST. «Сверху вниз» важно: игра «Pinball» в папке Sports
## лежит в Sports/Pinball/ — жанр у неё «Спорт», а не «Пинбол».
##
## Папки, которые не жанры (_Unsorted, _Saves without game, «NES(Famicom)»,
## папки игр), просто не совпадают ни с одним названием — у таких игр жанра нет.
##
## Использование:
##   Genres.from_path("D:/Game_archive/NES/RPG/Zelda/Zelda.nes", ["D:/Game_archive"])  # → "rpg"
##   Genres.title("rpg")  # → «Ролевая игра» на языке интерфейса

## «Без жанра» — особое значение для фильтра: игры, жанр которых не узнали.
const NONE := "none"

## Все жанры: [id, русское название (ключ перевода), названия папок].
## Порядок — как в выпадающем списке. Названия папок можно писать как
## угодно: большие и маленькие буквы, пробелы, «&», «'» и запятые
## не важны («Beat 'em Up» = «beat em up» = «BeatEmUp»).
## Чтобы Shellbit понял новую папку — допиши её имя в нужную строку.
const LIST := [
	["action", "Экшен", ["Action", "Action Adventure", "Экшен", "Экшн"]],
	["platformer", "Платформер", ["Platformer", "Platform", "Platformers", "Платформер", "Платформеры"]],
	["adventure", "Приключения", ["Adventure", "Приключения"]],
	["rpg", "Ролевая игра", ["RPG", "Role-playing", "Role-Playing (RPG)", "JRPG", "Ролевые", "Ролевая игра", "РПГ"]],
	["beat_em_up", "Beat 'em up", ["Beat 'em Up", "Beat'em Up", "Brawler"]],
	["fighting", "Файтинг", ["Fighting", "Fighter", "Файтинг", "Файтинги"]],
	["shooter", "Шутер", ["Shooter", "Shoot 'em Up", "Shmup", "Run and Gun", "Шутер", "Шутеры", "Стрелялки"]],
	["lightgun", "Тир", ["Lightgun Shooter", "Lightgun", "Light Gun", "Gun", "Тир"]],
	["horror", "Хоррор", ["Survival Horror", "Horror", "Хоррор", "Ужасы"]],
	["racing", "Гонки", ["Racing", "Driving", "Гонки"]],
	["sports", "Спорт", ["Sports", "Sport", "Спорт"]],
	["puzzle", "Головоломка", ["Puzzle", "Puzzles", "Головоломки", "Головоломка", "Пазлы"]],
	["strategy", "Стратегия", ["Strategy", "Стратегии", "Стратегия"]],
	["simulation", "Симулятор", ["Simulation", "Simulator", "Симуляторы", "Симулятор"]],
	["pinball", "Пинбол", ["Pinball", "Пинбол"]],
	["board", "Настольные и карточные", ["Board & Card", "Board, Card & Mahjong", "Board", "Card", "Cards", "Mahjong", "Настольные", "Карточные"]],
	["educational", "Обучение и викторины", ["Educational & Quiz", "Educational", "Quiz", "Обучающие", "Викторины"]],
	["music", "Музыкальная", ["Music", "Rhythm", "Музыкальные"]],
	["misc", "Разное", ["Misc", "Miscellaneous", "Other", "Разное", "Другое"]],
	["utilities", "Программы", ["Utilities", "Utilities & Hardware", "Utility", "Программы", "Утилиты"]],
	["adult", "Для взрослых", ["Adult", "18+", "Для взрослых"]],
]

# Нормализованное имя папки → id жанра. Собирается один раз, при первом вызове.
# static var — одна копия на всю программу.
static var _by_folder := {}
# «Всё, что не буква и не цифра» — см. simplify().
static var _not_letters: RegEx


## Жанр файла по его пути. roots — папки с играми из настроек: их собственные
## имена не считаются (если папка с играми называется «D:/Action», это ещё
## не значит, что все игры в ней — экшены). "" — жанр не узнали.
static func from_path(path: String, roots: PackedStringArray = PackedStringArray()) -> String:
	# В Windows путь может прийти и с «\», и с «/» — приводим к одному виду.
	var relative := path.replace("\\", "/")
	for root in roots:
		var prefix := root.replace("\\", "/").trim_suffix("/") + "/"
		# В Windows «D:/Games» и «d:/games» — одна и та же папка.
		if relative.to_lower().begins_with(prefix.to_lower()):
			relative = relative.substr(prefix.length())
			break
	var parts := relative.split("/", false)
	# Последняя часть — имя самого файла, его не смотрим.
	for i in parts.size() - 1:
		var id := for_folder(parts[i])
		if id != "":
			return id
	return ""


## Жанр по имени одной папки: «Beat 'em Up» → "beat_em_up". "" — это не жанр.
static func for_folder(folder_name: String) -> String:
	if _by_folder.is_empty():
		for genre: Array in LIST:
			for alias: String in genre[2]:
				_by_folder[simplify(alias)] = genre[0]
	return _by_folder.get(simplify(folder_name), "")


## Название жанра на языке интерфейса. Для NONE — «Без жанра».
static func title(id: String) -> String:
	if id == NONE:
		return Lang.t("Без жанра")
	for genre: Array in LIST:
		if genre[0] == id:
			return Lang.t(genre[1])
	return id


## Место жанра в списке — чтобы показывать жанры всегда в одном порядке.
static func order(id: String) -> int:
	for i in LIST.size():
		if LIST[i][0] == id:
			return i
	return LIST.size()  # NONE и незнакомые — в самом конце


## Оставить только буквы и цифры, маленькими: «Board, Card & Mahjong» → «boardcardmahjong».
## Так не важно, как именно написали пробелы, апострофы и «&».
## (Library тоже этим пользуется — узнавать переименованные файлы игр.)
static func simplify(text: String) -> String:
	if _not_letters == null:
		# Регулярное выражение: \p{L} — буква любого алфавита (и латиница,
		# и кириллица), \p{N} — цифра. [^…] — «всё, КРОМЕ этого».
		_not_letters = RegEx.create_from_string("[^\\p{L}\\p{N}]")
	return _not_letters.sub(text.to_lower(), "", true)  # true — заменить все, а не первое
