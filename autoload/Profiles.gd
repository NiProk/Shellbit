extends Node
## Profiles — игроки. На одном Shellbit могут играть несколько человек
## (например, муж и жена на телевизоре), и у каждого своё:
##   • избранное;
##   • «Продолжить играть» и время в игре;
##   • сохранения: и снимки состояния (слоты), и сохранения самой игры
##     (батарейка картриджа, карта памяти). Прогресс жены в «Марио»
##     не затрёт прогресс мужа.
## Общие для всех: папки с играми, обложки, настройки, ядра.
##
## Где что хранится (в settings.cfg):
##   [profiles]
##   ids=["p1", "p2"]        # игроки по порядку
##   current="p2"            # кто играет сейчас
##   [profile_p1]
##   name="Никита"
##   color="#4fd1c5"
##
## Первый игрок (MAIN, "p1") — особенный: его сохранения лежат там же,
## где лежали до появления игроков (user://states, user://saves). Так после
## обновления Shellbit старые сохранения просто остаются у первого игрока —
## ничего никуда переносить не надо. Поэтому первого игрока нельзя удалить,
## только переименовать.
##
## Сохранения остальных — в своих папках: user://profiles/<id>/states и /saves.
## Избранное и время в игре — в library.json (см. Library.gd, поле "stats").

## Игрок сменился (или его переименовали) — экраны и библиотека обновляются.
signal changed

const MAIN := "p1"
const MAX_PROFILES := 6
## Цвета игроков на выбор. Цвет — это кружок с буквой (аватар) и рамка на
## экране «Кто играет?». Так игроков легко различить издалека, с дивана.
const COLORS := [
	["#4fd1c5", "Бирюзовый"],
	["#f6a04d", "Оранжевый"],
	["#f06292", "Розовый"],
	["#9f7aea", "Фиолетовый"],
	["#4c9aff", "Синий"],
	["#7bc950", "Зелёный"],
	["#f5c542", "Жёлтый"],
	["#ef5350", "Красный"],
]

## Картинки-аватары, встроенные в программу: все .png из папки data/avatars.
## Хотите свою — просто положите туда квадратный PNG (лучше с прозрачным
## фоном), откройте проект в Godot — и картинка появится в списке.
## Удалили файл — пропадёт из списка.
const AVATAR_DIR := "res://data/avatars"
## Русские названия для картинок, которые были в Shellbit с самого начала.
## У новых картинок названием будет имя файла: «Aaron.png» → «Aaron».
const AVATAR_NAMES := {
	"fox": "Лиса", "cat": "Кот", "owl": "Сова", "frog": "Лягушка",
	"panda": "Панда", "bear": "Медвежонок", "bunny": "Зайчик", "penguin": "Пингвин",
	"octopus": "Осьминог", "turtle": "Черепаха", "axolotl": "Аксолотль", "mushroom": "Грибок",
	"ghost": "Привидение", "robot": "Робот", "dragon": "Дракончик", "slime": "Слизень",
}
## Своя картинка игрока хранится здесь (копия, уменьшенная до этого размера).
const CUSTOM_SIZE := 256

# Спрашивали ли уже «Кто играет?» при этом запуске программы.
var _asked := false
# Загруженные картинки аватаров: путь → текстура. Чтобы не читать файл
# с диска заново на каждом экране.
var _textures := {}


## Все игроки по порядку (их id).
func ids() -> Array:
	# duplicate() — копия: список меняют (add, remove), а копию из настроек
	# менять нельзя — изменения должны попадать туда только через set_value.
	var list: Array = Settings.get_value("profiles", "ids", [MAIN]).duplicate()
	return list if not list.is_empty() else [MAIN]


func count() -> int:
	return ids().size()


## Кто играет сейчас.
func current() -> String:
	var id: String = Settings.get_value("profiles", "current", MAIN)
	return id if id in ids() else MAIN


## Имя игрока. У первого игрока, которого ещё не переименовали, — «Игрок».
func name_of(id: String) -> String:
	var text: String = Settings.get_value(_section(id), "name", "")
	return text if text != "" else tr("Игрок")


func color_of(id: String) -> Color:
	return Color(Settings.get_value(_section(id), "color", COLORS[0][0]))


## Все встроенные аватары: [[путь, название], ...], по алфавиту файлов.
##
## Почему ResourceLoader.list_directory, а не обычный DirAccess: в готовой
## программе (.exe) картинок «как файлов» нет — Godot упаковал их в .pck,
## а на месте каждой лежит служебная пометка. list_directory это знает
## и возвращает настоящие имена («fox.png»), и в редакторе, и в .exe.
func avatar_list() -> Array:
	var result: Array = []
	var files := Array(ResourceLoader.list_directory(AVATAR_DIR))
	files.sort()
	for file: String in files:
		if file.get_extension().to_lower() != "png":
			continue
		var base := file.get_basename()
		var title: String = tr(AVATAR_NAMES[base]) if AVATAR_NAMES.has(base) else base.replace("_", " ")
		result.append([AVATAR_DIR.path_join(file), title])
	return result


## Картинка игрока: путь к файлу или "" — нет картинки, рисуем букву.
##   "res://data/avatars/fox.png"    — встроенная
##   "user://profiles/p2/avatar.png" — своя (выбрали файл на диске)
func avatar_of(id: String) -> String:
	return Settings.get_value(_section(id), "avatar", "")


## Текстура картинки игрока (null — картинки нет или файл пропал).
func avatar_texture(id: String) -> Texture2D:
	var path := avatar_of(id)
	if path == "":
		return null
	if not _textures.has(path):
		var texture: Texture2D = null
		if path.begins_with("res://"):
			# Встроенная — Godot уже подготовил её при импорте. Картинку могли
			# удалить из data/avatars — тогда без ошибки показываем букву.
			if ResourceLoader.exists(path):
				texture = load(path)
		elif FileAccess.file_exists(path):
			texture = ImageTexture.create_from_image(Image.load_from_file(path))
		_textures[path] = texture
	return _textures[path]


## Поставить игроку свою картинку из файла на диске. Возвращает false,
## если файл не картинка. Картинку копируем к себе, обрезав до квадрата
## (по центру) и уменьшив до 256×256: потом исходный файл можно хоть удалить.
func set_custom_avatar(id: String, file_path: String) -> bool:
	var image := Covers.load_any_image(file_path)  # PNG, JPG или WebP
	if image == null:
		return false
	var side := mini(image.get_width(), image.get_height())
	image = image.get_region(Rect2i((image.get_width() - side) / 2, (image.get_height() - side) / 2, side, side))
	image.resize(CUSTOM_SIZE, CUSTOM_SIZE, Image.INTERPOLATE_LANCZOS)
	var folder := "user://profiles".path_join(id)
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("avatar.png")
	image.save_png(path)
	_textures.erase(path)  # старую картинку из кэша — вон, иначе покажем её
	Settings.set_value(_section(id), "avatar", path)
	changed.emit()
	return true


## Раздел настроек игрока: в нём имя и цвет. Строки «Цвет» на странице
## настроек меняют его напрямую (SettingRow пишет в section/key).
func section_of(id: String) -> String:
	return _section(id)


func switch_to(id: String) -> void:
	if id == current() or not id in ids():
		return
	Settings.set_value("profiles", "current", id)
	changed.emit()


## Новый игрок. Возвращает его id ("" — игроков уже слишком много).
func add() -> String:
	var list := ids()
	if list.size() >= MAX_PROFILES:
		return ""
	# Номер — больше всех прежних, даже удалённых: id никогда не повторяется,
	# поэтому новый игрок не получит случайно чужие сохранения.
	var number: int = Settings.get_value("profiles", "next", 2)
	var id := "p%d" % number
	Settings.set_value("profiles", "next", number + 1)
	list.append(id)
	Settings.set_value("profiles", "ids", list)
	Settings.set_value(_section(id), "name", tr("Игрок %d") % list.size())
	# Цвет — первый, которого ещё нет ни у кого.
	var used := list.map(func(other: String) -> String: return color_of(other).to_html(false))
	var color: String = COLORS[0][0]
	for option: Array in COLORS:
		if not Color(option[0]).to_html(false) in used:
			color = option[0]
			break
	Settings.set_value(_section(id), "color", color)
	return id


func rename(id: String, text: String) -> void:
	text = text.strip_edges()
	if text == "":
		return
	Settings.set_value(_section(id), "name", text)
	changed.emit()


## Удалить игрока со всеми его сохранениями. Первого удалить нельзя.
func remove(id: String) -> void:
	if id == MAIN or not id in ids():
		return
	var list := ids()
	list.erase(id)
	Settings.set_value("profiles", "ids", list)
	Settings.set_value(_section(id), "name", null)  # null — стереть ключ
	Settings.set_value(_section(id), "color", null)
	Settings.set_value(_section(id), "avatar", null)
	_delete_folder(ProjectSettings.globalize_path("user://profiles".path_join(id)))
	Library.forget_profile(id)
	if Settings.get_value("profiles", "current", MAIN) == id:
		Settings.set_value("profiles", "current", MAIN)
	changed.emit()


## Папка снимков состояния (слотов) игрока.
func states_dir(id := "") -> String:
	if id == "":
		id = current()
	return "user://states" if id == MAIN else "user://profiles".path_join(id).path_join("states")


## Папка, куда ядро пишет сохранения самой игры (.srm, карты памяти).
func saves_dir(id := "") -> String:
	if id == "":
		id = current()
	return "user://saves" if id == MAIN else "user://profiles".path_join(id).path_join("saves")


## Показать ли «Кто играет?» сейчас, при запуске. true — только один раз
## за запуск, только если игроков больше одного и это не выключено в настройках.
func should_ask() -> bool:
	if _asked:
		return false
	_asked = true
	return count() > 1 and Settings.get_value("profiles", "ask_on_start", true)


func _section(id: String) -> String:
	return "profile_" + id


# Удалить папку со всем содержимым. В Godot нет «удалить папку целиком» —
# поэтому рекурсия: сначала вложенные папки и файлы, потом сама папка.
func _delete_folder(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		_delete_folder(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
