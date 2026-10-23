extends Node
## CoreDownloader — скачивает ядра libretro одной кнопкой.
##
## Ядра берём с официального сервера libretro (buildbot.libretro.com) —
## оттуда же их скачивает RetroArch. Каждое ядро лежит там в zip-архиве:
##   https://buildbot.libretro.com/nightly/windows/x86_64/latest/fceumm_libretro.dll.zip
## Внутри архива — один файл fceumm_libretro.dll. Его мы и кладём в папку ядер.
##
## Как пользоваться:
##   CoreDownloader.download(CoreManager.get_system("nes"))
##   CoreDownloader.progress.connect(…)   # сколько процентов скачано
##   CoreDownloader.finished.connect(…)   # готово или ошибка
##
## BIOS не скачиваем: это программы самих приставок, и раздавать их нельзя.

## Скачано percent процентов ядра core_file ("fceumm_libretro.dll").
## percent = -1 — ядро ждёт своей очереди.
signal progress(core_file: String, percent: int)
## Скачивание закончилось. ok = false — тогда message объясняет, что не так.
signal finished(core_file: String, ok: bool, message: String)

const SERVER := "https://buildbot.libretro.com/nightly/%s/latest/%s.zip"
## Сколько ядер качать одновременно. Больше — не быстрее, а серверу тяжелее.
const MAX_PARALLEL := 2

var _queue: Array[Dictionary] = []   # ждут очереди: {"file", "dest"}
var _active: Dictionary = {}         # качаются сейчас: файл ядра → HTTPRequest


func _ready() -> void:
	set_process(false)  # _process нужен, только пока что-то качается


## Папка на сервере для нашей системы ("" — для неё ядер нет).
func platform_dir() -> String:
	match OS.get_name():
		"Windows":
			return "windows/x86_64"
		"Linux":
			return "linux/x86_64"
	return ""


## Адрес архива с ядром: "fceumm_libretro.dll" → https://…/fceumm_libretro.dll.zip
func url_for(core_file: String) -> String:
	return SERVER % [platform_dir(), core_file]


## Ядро сейчас качается или ждёт очереди?
func is_busy(core_file: String) -> bool:
	return _active.has(core_file) or _queue.any(func(job: Dictionary) -> bool: return job["file"] == core_file)


## Приставки, для которых нет ядра.
func missing_systems() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for system in CoreManager.systems:
		if not FileAccess.file_exists(CoreManager.core_path(system)):
			result.append(system)
	return result


## Скачать ядра для всех приставок, где их нет. Возвращает, сколько ядер
## поставлено в очередь (у Game Boy и Game Boy Color ядро общее — одно).
func download_missing() -> int:
	var count := 0
	for system in missing_systems():
		if download(system):
			count += 1
	return count


## Скачать ядро для приставки. Возвращает false, если оно уже качается.
func download(system: Dictionary) -> bool:
	var dest := CoreManager.core_path(system)
	var file := dest.get_file()
	if file == "" or is_busy(file):
		return false
	if platform_dir() == "":
		finished.emit(file, false, tr("Скачивание ядер работает только в Windows и Linux."))
		return false
	_queue.append({"file": file, "dest": dest})
	progress.emit(file, -1)  # «в очереди»
	_pump()
	return true


# Запустить столько скачиваний, сколько разрешено одновременно.
func _pump() -> void:
	while _active.size() < MAX_PARALLEL and not _queue.is_empty():
		_start(_queue.pop_front())
	set_process(not _active.is_empty())


func _start(job: Dictionary) -> void:
	var file: String = job["file"]
	# HTTPRequest — узел Godot, который скачивает файл по ссылке.
	# download_file — писать сразу на диск, а не держать архив в памяти.
	var http := HTTPRequest.new()
	http.use_threads = true  # качать в отдельном потоке — интерфейс не тормозит
	http.timeout = 180.0
	var zip_path := ProjectSettings.globalize_path(CoreManager.CORES_DIR.path_join(file + ".zip.part"))
	http.download_file = zip_path
	add_child(http)
	http.request_completed.connect(_on_downloaded.bind(file, zip_path, job["dest"], http))
	_active[file] = http
	var error := http.request(url_for(file))
	if error != OK:
		_on_downloaded(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray(),
				file, zip_path, job["dest"], http)


# Пока что-то качается — раз в кадр сообщаем проценты.
func _process(_delta: float) -> void:
	for file: String in _active.keys():  # keys() — копия: словарь может меняться
		var http: HTTPRequest = _active[file]
		var total := http.get_body_size()  # -1, пока сервер не сказал размер
		if total > 0:
			progress.emit(file, int(100.0 * http.get_downloaded_bytes() / total))


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray,
		file: String, zip_path: String, dest: String, http: HTTPRequest) -> void:
	_active.erase(file)
	http.queue_free()

	var error := ""
	if result != HTTPRequest.RESULT_SUCCESS:
		error = tr("Нет связи с сервером libretro (ошибка %d).") % result
	elif code != 200:
		error = tr("Сервер ответил %d — такого ядра там нет.") % code
	else:
		error = extract_core(zip_path, file, dest)
	DirAccess.remove_absolute(zip_path)  # архив больше не нужен

	if error == "":
		print("Ядро скачано: ", dest)
	else:
		print("Ядро %s не скачалось: %s" % [file, error])
	finished.emit(file, error == "", error)
	_pump()


## Достать файл ядра из скачанного архива и положить в dest.
## Возвращает "" если всё хорошо, иначе — текст ошибки.
func extract_core(zip_path: String, core_file: String, dest: String) -> String:
	# ZIPReader — встроенный в Godot класс для чтения zip-архивов.
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return tr("Скачанный архив повреждён.")
	if not zip.get_files().has(core_file):
		zip.close()
		return tr("В архиве нет файла %s.") % core_file
	var data := zip.read_file(core_file)
	zip.close()

	# Сначала пишем во временный файл и только потом переименовываем.
	# Если запись оборвётся, в папке ядер не останется «половинки» .dll.
	var temp := dest + ".tmp"
	var out := FileAccess.open(temp, FileAccess.WRITE)
	if out == null:
		return tr("Не удалось записать файл %s.") % dest
	out.store_buffer(data)
	out.close()
	if FileAccess.file_exists(dest):
		DirAccess.remove_absolute(dest)
	if DirAccess.rename_absolute(temp, dest) != OK:
		return tr("Не удалось записать файл %s.") % dest
	return ""
