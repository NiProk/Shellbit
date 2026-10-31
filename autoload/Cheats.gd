extends Node
## Cheats — читы: коды Game Genie, Action Replay, GameShark и другие.
##
## Как работали читы на настоящих приставках: Game Genie вставляли между
## картриджем и приставкой, и он подменял пару байт в игре — например,
## «сколько жизней отнять при смерти» с 1 на 0. Код вроде «SXIOPO» — это
## зашифрованные «адрес и новое значение». В эмуляторе всё то же самое,
## только подменяет ядро: мы передаём ему текст кода (RetroCore.cheat_set),
## а разбирает и применяет его оно само.
##
## Откуда берутся коды:
##   • база читов libretro — архив cheats.zip (~37 МБ) с тысячами готовых
##     кодов для NES, SNES, Mega Drive, PlayStation и других. Скачивается
##     один раз по кнопке в окне «Читы». Внутри — по папке на приставку
##     (имена папок те же, что у обложек: поле "thumbnails" в systems.json)
##     и по файлу .cht на игру:
##         Nintendo - Nintendo Entertainment System/Contra (USA).cht
##   • свои коды — можно набрать вручную (например, из журнала).
##
## Что запоминаем — в user://cheats/<приставка>/<имя файла игры>.json:
##   {"on": ["SXIOPO", "00AE:41"],            ← какие коды включены
##    "custom": [{"name": "…", "code": "…"}]} ← свои коды
## Сами коды из базы не копируем: обновится база — новые коды появятся сами.
## Читы общие для всех игроков (как и обложки).

signal download_progress(percent: int)
signal download_finished(ok: bool, message: String)

const DATABASE_URL := "https://buildbot.libretro.com/assets/frontend/cheats.zip"
const DIR := "user://cheats"
const DATABASE := "user://cheats/cheats.zip"
## Подпись группы своих кодов (в entries() поле "source").
const CUSTOM := ""

var _http: HTTPRequest
## Список файлов базы по папкам: "Nintendo - …" → ["Contra (USA).cht", …].
## Читаем из архива один раз — при первом вопросе.
var _index := {}


func _ready() -> void:
	set_process(false)  # _process нужен только пока качается база


# =====================================================================
# База читов
# =====================================================================

func has_database() -> bool:
	return FileAccess.file_exists(DATABASE)


func is_downloading() -> bool:
	return _http != null


## Скачать базу. Конец — сигнал download_finished(ok, сообщение).
func download_database() -> void:
	if _http != null:
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	_http = HTTPRequest.new()
	_http.use_threads = true  # качаем в отдельном потоке — игра не замирает
	_http.timeout = 600.0
	# .part — «недокачанный»: если связь оборвётся, неполный архив
	# не примем за настоящую базу.
	_http.download_file = ProjectSettings.globalize_path(DATABASE + ".part")
	add_child(_http)
	_http.request_completed.connect(_on_downloaded)
	set_process(true)
	if _http.request(DATABASE_URL) != OK:
		_on_downloaded.call_deferred(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())


func _process(_delta: float) -> void:
	if _http != null and _http.get_body_size() > 0:
		download_progress.emit(int(100.0 * _http.get_downloaded_bytes() / _http.get_body_size()))


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	set_process(false)
	_http.queue_free()
	_http = null
	var part := ProjectSettings.globalize_path(DATABASE + ".part")
	var message := ""
	if result != HTTPRequest.RESULT_SUCCESS:
		message = tr("Нет связи с сервером libretro (ошибка %d).") % result
	elif code != 200:
		message = tr("Сервер ответил %d — база читов не скачалась.") % code
	else:
		# Проверяем, что это настоящий zip, а не, например, страница с ошибкой.
		var zip := ZIPReader.new()
		if zip.open(part) != OK:
			message = tr("Скачанный файл повреждён. Попробуйте ещё раз.")
		zip.close()
	if message != "":
		DirAccess.remove_absolute(part)
		download_finished.emit(false, message)
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DATABASE))
	DirAccess.rename_absolute(part, ProjectSettings.globalize_path(DATABASE))
	_index.clear()  # база новая — список файлов перечитаем
	download_finished.emit(true, "")


# =====================================================================
# Читы игры
# =====================================================================

## Все читы игры, для окна «Читы»: сначала свои, потом из базы.
## Каждый — {"name", "code", "source", "on", "custom"}:
##   source — откуда код: "Contra (USA) (Game Genie)" (файл базы) или CUSTOM.
func entries(game: Dictionary) -> Array:
	var saved := _load(game)
	var on: Array = saved["on"]
	var result: Array = []
	var seen := {}  # одинаковый код бывает в нескольких файлах — показываем один раз
	for cheat: Dictionary in saved["custom"]:
		result.append({"name": cheat["name"], "code": cheat["code"], "source": CUSTOM,
				"on": cheat["code"] in on, "custom": true})
		seen[cheat["code"]] = true
	for file: String in find_files(game):
		for cheat: Dictionary in parse_cht(_read(file)):
			if seen.has(cheat["code"]):
				continue
			seen[cheat["code"]] = true
			result.append({"name": cheat["name"], "code": cheat["code"],
					"source": file.get_file().get_basename(), "on": cheat["code"] in on, "custom": false})
	return result


## Коды, которые надо включить при запуске игры. Базу не открываем —
## включённые коды записаны в файле игры.
func enabled_codes(game: Dictionary) -> PackedStringArray:
	return PackedStringArray(_load(game)["on"])


func set_enabled(game: Dictionary, code: String, enabled: bool) -> void:
	var saved := _load(game)
	var on: Array = saved["on"]
	on.erase(code)
	if enabled:
		on.append(code)
	_save(game, saved)


## Добавить свой код. Возвращает false, если код пустой или такой уже есть.
## Свой код сразу включаем: раз его набрали — значит, хотят попробовать.
func add_custom(game: Dictionary, name: String, code: String) -> bool:
	code = normalize_code(code)
	if code == "":
		return false
	var saved := _load(game)
	for cheat: Dictionary in saved["custom"]:
		if cheat["code"] == code:
			return false
	name = name.strip_edges()
	saved["custom"].append({"name": name if name != "" else code, "code": code})
	if not code in saved["on"]:
		saved["on"].append(code)
	_save(game, saved)
	return true


func remove_custom(game: Dictionary, code: String) -> void:
	var saved := _load(game)
	saved["custom"] = saved["custom"].filter(func(cheat: Dictionary) -> bool: return cheat["code"] != code)
	saved["on"].erase(code)
	_save(game, saved)


## Код, как его набрали, → как его ждёт ядро: заглавные буквы, без пробелов
## по краям. Несколько кодов в одном (через «+» или пробел в начале/конце)
## ядра понимают сами.
static func normalize_code(code: String) -> String:
	return code.strip_edges().to_upper()


# --- Где лежат свои настройки читов игры ---

func _saved_path(game: Dictionary) -> String:
	var file := String(game.get("path", "")).get_file().get_basename()
	# Имя файла игры может содержать что угодно — берём безопасный вариант.
	return DIR.path_join(String(game.get("system", "other"))).path_join(file.validate_filename() + ".json")


func _load(game: Dictionary) -> Dictionary:
	var path := _saved_path(game)
	var data: Variant = null
	if FileAccess.file_exists(path):
		data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		data = {}  # файла ещё нет (или испорчен) — читов нет
	return {"on": Array(data.get("on", [])), "custom": Array(data.get("custom", []))}


func _save(game: Dictionary, saved: Dictionary) -> void:
	var path := _saved_path(game)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(saved, "\t"))


# =====================================================================
# Поиск игры в базе
# =====================================================================

## Файлы базы для этой игры, лучшие первыми:
##   1) имя совпало полностью: «Contra (USA).cht» для «Contra (USA).nes»;
##   2) та же страна: «Contra (USA) (Game Genie).cht»;
##   3) остальные версии: «Contra (Japan).cht» (коды могут не подойти!).
func find_files(game: Dictionary) -> PackedStringArray:
	var folder: String = CoreManager.get_system(game.get("system", "")).get("thumbnails", "")
	if folder == "" or not has_database():
		return PackedStringArray()
	var stem := String(game.get("path", "")).get_file().get_basename()
	var keys := [title_key(stem), title_key(String(game.get("title", "")))]
	var region := _first_tag(stem)
	var ranked: Array = []
	for name: String in _files_in(folder):
		var cht := name.get_basename()
		if not title_key(cht) in keys:
			continue
		var rank := 2
		if cht.to_lower() == stem.to_lower():
			rank = 0
		elif region != "" and _first_tag(cht) == region:
			rank = 1
		ranked.append([rank, cht.to_lower(), folder.path_join(name)])
	ranked.sort()  # массивы сравниваются по первому элементу, потом по второму
	return PackedStringArray(ranked.map(func(item: Array) -> String: return item[2]))


## «Contra (USA) (Game Genie)» → «contra». По этому ключу сравниваем
## названия: без скобок, регистра, пробелов и знаков. «Legend of Zelda,
## The» и «The Legend of Zelda» дают один ключ.
static func title_key(name: String) -> String:
	var title := name
	for mark in ["(", "["]:
		var at := title.find(mark)
		if at > 0:
			title = title.left(at)
	title = title.strip_edges().to_lower().replace("&", "and")
	if title.ends_with(", the"):
		title = title.trim_suffix(", the")
	title = title.trim_prefix("the ")
	var key := ""
	for letter in title:
		if letter.to_upper() != letter.to_lower() or letter.is_valid_int():
			key += letter  # буква (любого алфавита) или цифра
	return key


# Первая пометка в скобках: «Contra (USA) (Game Genie)» → «usa».
static func _first_tag(name: String) -> String:
	var start := name.find("(")
	var end := name.find(")", start)
	return name.substr(start + 1, end - start - 1).to_lower() if start >= 0 and end > start else ""


func _files_in(folder: String) -> Array:
	if _index.is_empty():
		var zip := ZIPReader.new()
		if zip.open(ProjectSettings.globalize_path(DATABASE)) != OK:
			return []
		for path: String in zip.get_files():
			if path.get_extension().to_lower() == "cht":
				var dir := path.get_base_dir()
				if not _index.has(dir):
					_index[dir] = []
				_index[dir].append(path.get_file())
		zip.close()
	return _index.get(folder, [])


func _read(path: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(ProjectSettings.globalize_path(DATABASE)) != OK:
		return ""
	var text := zip.read_file(path).get_string_from_utf8()
	zip.close()
	return text


## Разобрать файл .cht (формат RetroArch):
##   cheats = 2
##   cheat0_desc = "Infinite Lives"
##   cheat0_code = "SXIOPO"
##   cheat1_desc = …
## Возвращает [{"name", "code"}, …]. Пропускаем «читы» без кода — это
## особый вид RetroArch (поиск по памяти, вибрация), ядру их не передать.
static func parse_cht(text: String) -> Array:
	var fields := {}  # "cheat0_desc" → "Infinite Lives"
	for line in text.split("\n"):
		var at := line.find("=")
		if at < 0:
			continue
		var key := line.left(at).strip_edges().to_lower()
		var value := line.substr(at + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
		fields[key] = value
	var result: Array = []
	var index := 0
	while fields.has("cheat%d_desc" % index) or fields.has("cheat%d_code" % index):
		var code := normalize_code(fields.get("cheat%d_code" % index, ""))
		var name: String = fields.get("cheat%d_desc" % index, "")
		# «?» в коде — заготовка «подставьте своё число», как есть не сработает.
		if code != "" and not "?" in code:
			result.append({"name": name if name != "" else code, "code": code})
		index += 1
	return result
