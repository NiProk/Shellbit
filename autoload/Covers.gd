extends Node
## Covers — обложки игр из бесплатного архива libretro-thumbnails.
##
## Как это работает:
## 1. В data/covers/<приставка>.txt лежит указатель: «ключ игры → имя обложки».
##    Ключ строится той же функцией RomInfo, что объединяет версии игры,
##    поэтому "Battletoads (U) [!].nes" находит "Battletoads (USA).png".
## 2. Экран просит обложку: Covers.get_cover(group).
##    Если она уже скачана — сразу получает текстуру.
##    Если нет — получает null, а обложка ставится в очередь на скачивание.
## 3. Когда обложка скачается, сервис посылает сигнал cover_ready,
##    и карточка, которая её ждала, обновляется сама.
##
## Скачанные обложки хранятся в user://covers/<приставка>/, поэтому
## интернет нужен только в первый раз.
##
## СВОИ обложки важнее скачанных. Порядок поиска:
##   1) выбранная в программе (user://covers/custom/<приставка>/...);
##   2) картинка рядом с файлом игры с тем же именем:
##      "Donald Duck.gb" → "Donald Duck.png" / ".jpg" / ".jpeg" / ".webp";
##   3) скачанная из архива libretro.

## Сигнал: обложка игры с ключом group_key появилась или поменялась.
## texture == null — обложку убрали.
signal cover_ready(group_key: String, texture: Texture2D)

const CACHE_DIR := "user://covers"
const CUSTOM_DIR := "user://covers/custom"
const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp"]
const MAX_PARALLEL := 4   # сколько файлов качаем одновременно
const MAX_HEIGHT := 360   # большие картинки уменьшаем — экономим память

# Откуда качать — по порядку, пока какой-нибудь адрес не сработает.
# %s — сначала папка приставки, потом имя файла.
#   1) официальный сервер libretro по https (защищённое соединение);
#   2) он же по обычному http — так обложки качает сам RetroArch;
#   3) тот же архив на GitHub (там папки названы через «_»).
var sources := [
	"https://thumbnails.libretro.com/%s/Named_Boxarts/%s.png",
	"http://thumbnails.libretro.com/%s/Named_Boxarts/%s.png",
	"https://raw.githubusercontent.com/libretro-thumbnails/%s/master/Named_Boxarts/%s.png",
]

# Понятные названия ошибок HTTPRequest для сообщений в Output.
const RESULT_NAMES := {
	HTTPRequest.RESULT_CANT_CONNECT: "не удалось подключиться",
	HTTPRequest.RESULT_CANT_RESOLVE: "адрес сервера не найден (DNS)",
	HTTPRequest.RESULT_CONNECTION_ERROR: "соединение оборвалось",
	HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR: "ошибка защищённого соединения (TLS)",
	HTTPRequest.RESULT_NO_RESPONSE: "сервер не ответил",
	HTTPRequest.RESULT_TIMEOUT: "время ожидания вышло",
	HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED: "слишком много перенаправлений",
}

var _indexes := {}    # id приставки → {ключ игры: имя обложки}
var _textures := {}   # ключ группы → Texture2D (уже загруженные в память)
## Сколько обложек держать в памяти. Обложка — около 0,4 МБ видеопамяти;
## на 2000 игр это было бы 700 МБ. Храним последние MAX_TEXTURES:
## на экране видно ~30, остальные — запас, чтобы при прокрутке назад
## не читать их с диска заново. Самые давние выбрасываем.
const MAX_TEXTURES := 300
var _order: Array[String] = []  # ключи в порядке использования: давние — в начале
var _missing := {}    # ключи, для которых обложки нет (в этот запуск не ищем)
var _pending := {}    # ключи, которые сейчас в очереди или качаются
var _queue: Array[Dictionary] = []
var _active := 0      # сколько скачиваний идёт прямо сейчас


## Обложка игры (группы) или null. Если null — обложка уже ищется,
## и позже придёт сигнал cover_ready.
##
## now = false (по умолчанию): картинку с диска читаем в фоновом потоке.
## Чтение и распаковка PNG — несколько миллисекунд, и когда при прокрутке
## библиотеки сразу появляется ряд из 4–8 карточек, интерфейс бы
## подтормаживал. now = true — прочитать сразу (страница одной игры).
func get_cover(group: Dictionary, now := false) -> Texture2D:
	var key: String = group["key"]
	if _textures.has(key):
		_touch(key)
		return _textures[key]
	if _loading.has(key):
		return null  # уже читаем с диска — придёт сигналом

	# Своя обложка — выбранная в программе или лежащая рядом с игрой.
	var own := _find_own_cover(group)
	if own != "":
		return _read(key, ProjectSettings.globalize_path(own), true, now)

	if _missing.has(key) or _pending.has(key):
		return null

	# Может, уже скачали в прошлый раз? (скачанные уже уменьшены)
	var path := _cache_path(group)
	if FileAccess.file_exists(path):
		return _read(key, ProjectSettings.globalize_path(path), false, now)
	if FileAccess.file_exists(path + ".none"):
		_missing[key] = true  # в прошлый раз сервер ответил «нет такой»
		return null

	_enqueue(group)
	return null


# --- Чтение с диска в фоновом потоке ---------------------------------------
# WorkerThreadPool — готовый «пул» потоков Godot: отдаём ему функцию,
# он выполняет её на свободном ядре процессора, не останавливая интерфейс.

var _loading := {}  # ключи обложек, которые сейчас читаются с диска
var _broken := {}   # пути картинок, которые не прочитались, — больше не пробуем


func _read(key: String, path: String, shrink: bool, now: bool) -> Texture2D:
	if _broken.has(path):
		return null  # уже пробовали — файл не читается
	if now:
		var image := _load_image(path, shrink)
		if image == null:
			_broken[path] = true
			return null
		_remember(key, ImageTexture.create_from_image(image))
		return _textures[key]
	_loading[key] = true
	WorkerThreadPool.add_task(_read_in_thread.bind(key, path, shrink))
	return null


# Работает В ДРУГОМ ПОТОКЕ. Здесь можно читать файлы и менять Image,
# но нельзя трогать узлы и посылать сигналы интерфейсу — поэтому
# результат передаём в главный поток через call_deferred.
func _read_in_thread(key: String, path: String, shrink: bool) -> void:
	var image := _load_image(path, shrink)
	_on_read.call_deferred(key, image, path)


func _load_image(path: String, shrink: bool) -> Image:
	var image := load_any_image(path)
	if image == null:
		return null
	if shrink:
		_shrink(image)
	return image


## Прочитать картинку, узнав её формат по СОДЕРЖИМОМУ, а не по расширению.
## Бывает, что JPG сохранили с расширением .png (так было с обложкой
## Mizzurna Falls) — Image.load_from_file тогда отказывается её читать.
## А у каждого формата первые байты файла свои («подпись»):
##   PNG — 89 50 4E 47 («‰PNG»), JPG — FF D8, WebP — «RIFF....WEBP».
## null — не картинка или файл испорчен.
static func load_any_image(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 12:
		return null
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0x89 and bytes[1] == 0x50:
		error = image.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8:
		error = image.load_jpg_from_buffer(bytes)
	elif bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		error = image.load_webp_from_buffer(bytes)
	if error != OK or image.is_empty():
		return null
	return image


# Снова в главном потоке: картинка прочитана.
func _on_read(key: String, image: Image, path: String) -> void:
	_loading.erase(key)
	if image == null:
		# Файл испорчен — больше не пробуем. Раньше Shellbit читал его заново
		# при каждом показе карточки, и журнал заполнялся одной и той же ошибкой.
		_broken[path] = true
		push_warning("Обложка не читается (это не PNG, JPG или WebP): " + path)
		return
	_set_texture(key, ImageTexture.create_from_image(image))


# --- Свои обложки ----------------------------------------------------------

## Поставить свою обложку из файла (png, jpg, webp). Возвращает true, если получилось.
func set_custom_cover(group: Dictionary, file_path: String) -> bool:
	var image := Image.load_from_file(file_path)
	if image == null or image.is_empty():
		return false
	_shrink(image)
	var path := _custom_path(group)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	image.save_png(path)
	_set_texture(group["key"], ImageTexture.create_from_image(image))
	return true


## Есть ли у игры обложка, выбранная в программе.
func has_custom_cover(group: Dictionary) -> bool:
	return FileAccess.file_exists(_custom_path(group))


## Убрать выбранную обложку — вернётся картинка рядом с игрой или скачанная.
func remove_custom_cover(group: Dictionary) -> void:
	DirAccess.remove_absolute(_custom_path(group))
	_textures.erase(group["key"])
	_order.erase(group["key"])
	_missing.erase(group["key"])
	# Ищем заново. Если обложку надо скачать — она придёт сигналом позже.
	cover_ready.emit(group["key"], get_cover(group, true))


# Путь к своей обложке или "" если её нет.
func _find_own_cover(group: Dictionary) -> String:
	if FileAccess.file_exists(_custom_path(group)):
		return _custom_path(group)
	# Картинка рядом с любой версией игры: "Игра (U).nes" → "Игра (U).png"
	for variant: Dictionary in group["variants"]:
		var base: String = variant["path"].get_basename()
		for ext: String in IMAGE_EXTENSIONS:
			if FileAccess.file_exists(base + "." + ext):
				return base + "." + ext
	return ""


func _set_texture(key: String, texture: Texture2D) -> void:
	_remember(key, texture)
	_missing.erase(key)
	cover_ready.emit(key, texture)


# Положить обложку в память. Если их стало слишком много — выбросить самую
# давнюю. Карточка, которая её показывает, сохранит свою копию ссылки,
# так что на экране ничего не пропадёт: из памяти обложка уйдёт, когда
# её перестанут показывать.
func _remember(key: String, texture: Texture2D) -> void:
	_textures[key] = texture
	_touch(key)
	while _order.size() > MAX_TEXTURES:
		_textures.erase(_order.pop_front())


# Отметить, что обложку только что использовали: переставить её ключ в конец.
func _touch(key: String) -> void:
	_order.erase(key)
	_order.append(key)


func _shrink(image: Image) -> void:
	if image.get_height() > MAX_HEIGHT:
		var width := int(image.get_width() * float(MAX_HEIGHT) / image.get_height())
		image.resize(width, MAX_HEIGHT, Image.INTERPOLATE_LANCZOS)


func _custom_path(group: Dictionary) -> String:
	return CUSTOM_DIR.path_join(group["system"]).path_join(group["key"].md5_text() + ".png")


# --- Поиск имени обложки ---------------------------------------------------

func _cover_name(group: Dictionary) -> String:
	var system_id: String = group["system"]
	if not _indexes.has(system_id):
		_indexes[system_id] = _load_index(system_id)
	# Ключ группы — "nes_battletoads". В указателе ключи без приставки.
	var key: String = group["key"].trim_prefix(system_id + "_")
	return _indexes[system_id].get(key, "")


# Указатель — текстовый файл, по строке на игру: ключ<TAB>имя.
func _load_index(system_id: String) -> Dictionary:
	var index := {}
	var text := FileAccess.get_file_as_string("res://data/covers/%s.txt" % system_id)
	for line in text.split("\n", false):
		var parts := line.split("\t")
		if parts.size() == 2:
			index[parts[0]] = parts[1]
	return index


# --- Очередь скачивания ----------------------------------------------------

func _enqueue(group: Dictionary) -> void:
	var name := _cover_name(group)
	var folder: String = CoreManager.get_system(group["system"]).get("thumbnails", "")
	if name == "" or folder == "":
		_missing[group["key"]] = true  # в архиве такой игры нет
		return
	_pending[group["key"]] = true
	_queue.append({
		"key": group["key"],
		"path": _cache_path(group),
		"folder": folder,
		"name": name,
		"source": 0,     # номер адреса в sources
		"all_404": true, # все серверы ответили «нет такого файла»?
		"errors": [],    # что пошло не так — для сообщения в Output
	})
	_pump()


# Запустить столько скачиваний, сколько разрешено одновременно.
func _pump() -> void:
	while _active < MAX_PARALLEL and not _queue.is_empty():
		_download(_queue.pop_front())


func _download(item: Dictionary) -> void:
	# HTTPRequest — узел Godot, который умеет скачивать по ссылке.
	# Создаём по одному на каждый файл и удаляем после.
	var http := HTTPRequest.new()
	http.timeout = 20.0
	http.use_threads = true  # качать в отдельном потоке, чтобы не тормозил интерфейс
	add_child(http)
	http.request_completed.connect(_on_downloaded.bind(item, http))

	var folder: String = item["folder"]
	var template: String = sources[item["source"]]
	if template.contains("github"):
		folder = folder.replace(" ", "_")  # на GitHub папки названы с «_»
	var url: String = template % [folder.uri_encode(), item["name"].uri_encode()]
	item["url"] = url
	_active += 1
	if http.request(url) != OK:
		_on_downloaded(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray(), item, http)


func _on_downloaded(result: int, code: int, _headers: PackedStringArray,
		body: PackedByteArray, item: Dictionary, http: HTTPRequest) -> void:
	http.queue_free()
	_active -= 1

	var image := Image.new()
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and image.load_png_from_buffer(body) == OK:
		_save_cover(item, image)
		_pump()
		return

	# Не получилось — запоминаем причину.
	if result != HTTPRequest.RESULT_SUCCESS:
		item["errors"].append("%s: %s" % [item["url"], RESULT_NAMES.get(result, "ошибка %d" % result)])
	else:
		item["errors"].append("%s: ответ %d" % [item["url"], code])
	if not (result == HTTPRequest.RESULT_SUCCESS and code == 404):
		item["all_404"] = false

	if item["source"] + 1 < sources.size():
		item["source"] += 1  # пробуем следующий адрес
		_queue.push_front(item)
	elif item["all_404"]:
		# Все серверы ответили «нет такого файла» — запомним навсегда.
		_mark_missing(item, true)
	else:
		push_warning("Обложка не скачалась: %s\n  %s" % [item["name"], "\n  ".join(item["errors"])])
		_mark_missing(item, false)  # попробуем при следующем запуске

	_pump()


func _save_cover(item: Dictionary, image: Image) -> void:
	_shrink(image)
	DirAccess.make_dir_recursive_absolute(item["path"].get_base_dir())
	image.save_png(item["path"])
	_pending.erase(item["key"])
	# Пока качали, пользователь мог поставить свою обложку — её не трогаем.
	if not _textures.has(item["key"]):
		_set_texture(item["key"], ImageTexture.create_from_image(image))


func _mark_missing(item: Dictionary, forever: bool) -> void:
	_missing[item["key"]] = true
	_pending.erase(item["key"])
	if forever:
		DirAccess.make_dir_recursive_absolute(item["path"].get_base_dir())
		FileAccess.open(item["path"] + ".none", FileAccess.WRITE)  # пустой файл-метка


# user://covers/nes/<md5 ключа>.png — md5, чтобы в имени файла
# не было скобок, двоеточий и других неудобных символов.
func _cache_path(group: Dictionary) -> String:
	return CACHE_DIR.path_join(group["system"]).path_join(group["key"].md5_text() + ".png")
