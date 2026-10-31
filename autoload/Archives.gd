extends Node
## Archives — игры в архивах .zip и .7z.
##
## Многие хранят игры в архивах: «Contra (USA).zip» с файлом «Contra (USA).nes»
## внутри. Ядра libretro сами архивы обычно не открывают (кроме аркадного
## FBNeo — ему архив и нужен). Поэтому:
##   • при поиске игр Shellbit заглядывает в архив и по файлу внутри понимает,
##     какая это приставка (detect_system);
##   • перед запуском распаковывает архив во временную папку (prepare),
##     а ядру отдаёт уже распакованный файл.
##
## .zip Godot читает сам (класс ZIPReader). Для .7z нужен 7-Zip:
##   • Windows — консольный 7zr.exe с официального сайта 7-zip.org
##     (600 КБ, бесплатный). Shellbit скачивает его сам при первой встрече с .7z;
##   • Linux — программа 7z / 7zz / 7za из системы (пакет p7zip или 7zip).
##
## Распакованные игры лежат в user://cache/roms. Если их больше CACHE_LIMIT_MB,
## самые давние удаляются: архив-то остался, распакуем снова.

## 7-Zip скачался (или не скачался — ok = false).
signal tool_ready(ok: bool)

const ARCHIVE_EXTENSIONS := ["zip", "7z"]
const CACHE_DIR := "user://cache/roms"
const CACHE_LIMIT_MB := 4096
const TOOLS_DIR := "user://tools"
const SEVEN_ZIP_URL := "https://www.7-zip.org/a/7zr.exe"

var _tool := ""            # путь к 7-Zip ("" — ещё не искали или нет)
var _tool_searched := false
var _downloading := false
var _download_tried := false  # качаем 7-Zip не больше одного раза за запуск


## Это архив с игрой?
func is_archive(path: String) -> bool:
	return path.get_extension().to_lower() in ARCHIVE_EXTENSIONS


## Нужно ли распаковывать игру перед запуском. Аркадам — нет:
## FBNeo сам читает архив, внутри которого — микросхемы автомата.
func needs_extraction(game: Dictionary) -> bool:
	return is_archive(game.get("path", "")) and game.get("system", "") != "arcade"


# =====================================================================
# Какая приставка в архиве
# =====================================================================

## Приставка по файлам внутри архива:
##   "nes" — внутри файл .nes;
##   "arcade" — ничего знакомого (так выглядят архивы аркадных автоматов);
##   ""  — пока не знаем: .7z, а 7-Zip ещё нет (Library спросит позже).
func detect_system(path: String) -> String:
	var files := list_files(path)
	if files.is_empty() and path.get_extension().to_lower() == "7z" and not has_builtin_7z() and seven_zip() == "":
		return ""
	return system_for_files(files)


## Приставка по списку файлов архива (отдельно — чтобы проверять в тестах).
func system_for_files(files: PackedStringArray) -> String:
	for file in files:
		var system_id := CoreManager.system_for_extension(file.get_extension())
		if system_id != "" and system_id != "arcade":
			return system_id
	return "arcade"


## Список файлов в архиве (пустой — если открыть не удалось).
func list_files(path: String) -> PackedStringArray:
	if path.get_extension().to_lower() == "zip":
		var zip := ZIPReader.new()
		if zip.open(path) != OK:
			return PackedStringArray()
		var files := zip.get_files()
		zip.close()
		return files

	if has_builtin_7z():
		return ClassDB.instantiate("SevenZip").list(path)
	var tool := seven_zip()
	if tool == "":
		return PackedStringArray()
	# 7z l -ba -slt — список файлов «по строчке на свойство»:
	#   Path = Contra (USA).nes
	#   Size = 262160 ...
	var output := []
	if OS.execute(tool, ["l", "-ba", "-slt", path], output) != 0:
		return PackedStringArray()
	var files := PackedStringArray()
	for line in "\n".join(output).split("\n"):
		if line.begins_with("Path = "):
			files.append(line.trim_prefix("Path = ").strip_edges())
	return files


# =====================================================================
# Распаковка перед запуском
# =====================================================================

## Распаковать игру. Это может занять время (диск PS1 — сотни мегабайт),
## поэтому работа идёт в отдельном потоке, а функцию нужно ждать через await:
##   var result := await Archives.prepare(game)
## Возвращает {"path": распакованный файл для ядра, "error": ""}
## или {"path": "", "error": "что не так"}.
func prepare(game: Dictionary) -> Dictionary:
	var archive: String = game["path"]
	if archive.get_extension().to_lower() == "7z" and not has_builtin_7z() and seven_zip() == "":
		if not await ensure_seven_zip():
			return {"path": "", "error": _no_tool_message()}

	var folder := _cache_folder(archive)
	var main := _main_file(folder, game["system"])
	if main == "":
		# Распаковываем в отдельном потоке — интерфейс в это время не замирает.
		var thread := Thread.new()
		thread.start(_extract.bind(archive, folder))
		while thread.is_alive():
			await get_tree().process_frame
		var error: String = thread.wait_to_finish()
		if error != "":
			return {"path": "", "error": error}
		main = _main_file(folder, game["system"])
		if main == "":
			return {"path": "", "error": tr("В архиве нет файла игры для этой приставки.")}
	_touch(folder)
	_trim_cache(folder)
	return {"path": main, "error": ""}


# Папка для распакованной игры: своя для каждого архива. В имени — md5 пути
# и время изменения архива: заменили архив — распакуем заново.
func _cache_folder(archive: String) -> String:
	var stamp := str(FileAccess.get_modified_time(archive))
	var name := (archive + stamp).md5_text().substr(0, 16)
	return ProjectSettings.globalize_path(CACHE_DIR.path_join(name))


# Главный файл игры среди распакованных: .m3u (все диски) или первый файл
# с расширением приставки в порядке из systems.json (у PS1 — .cue раньше .bin).
func _main_file(folder: String, system_id: String) -> String:
	if not DirAccess.dir_exists_absolute(folder):
		return ""
	var files := _all_files(folder)
	var extensions: Array = CoreManager.get_system(system_id).get("extensions", [])
	for wanted: String in ["m3u"] + extensions:
		for file in files:
			if file.get_extension().to_lower() == wanted:
				return file
	return ""


# Работает в отдельном потоке: только файлы, никаких узлов и сигналов.
func _extract(archive: String, folder: String) -> String:
	var temp := folder + ".part"  # недораспакованное не должно выглядеть готовым
	_remove_dir(temp)
	DirAccess.make_dir_recursive_absolute(temp)
	var error := ""
	if archive.get_extension().to_lower() == "zip":
		error = _extract_zip(archive, temp)
	elif has_builtin_7z():
		error = ClassDB.instantiate("SevenZip").extract(archive, temp)
	else:
		# x — распаковать с папками, -y — на всё отвечать «да», -o — куда.
		var output := []
		if OS.execute(seven_zip(), ["x", "-y", "-o" + temp, archive], output) != 0:
			error = tr("7-Zip не смог распаковать архив:\n%s") % "\n".join(output).strip_edges().right(300)
	if error != "":
		_remove_dir(temp)
		return error
	_remove_dir(folder)
	DirAccess.rename_absolute(temp, folder)
	return ""


func _extract_zip(archive: String, folder: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(archive) != OK:
		return tr("Архив повреждён: %s") % archive.get_file()
	for name in zip.get_files():
		if name.ends_with("/"):
			continue  # это папка, а не файл
		# «../» в имени — попытка записать файл за пределы папки. Пропускаем.
		if name.contains(".."):
			continue
		var target := folder.path_join(name)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var out := FileAccess.open(target, FileAccess.WRITE)
		if out == null:
			zip.close()
			return tr("Не удалось записать файл %s.") % target
		out.store_buffer(zip.read_file(name))
		out.close()
	zip.close()
	return ""


# Отметить, что игру запускали сейчас (по этому времени чистим кеш).
func _touch(folder: String) -> void:
	var mark := FileAccess.open(folder.path_join(".used"), FileAccess.WRITE)
	if mark:
		mark.store_string(str(Time.get_unix_time_from_system()))


# Кеш больше лимита — удаляем давно не запускавшиеся игры (кроме текущей).
func _trim_cache(keep: String) -> void:
	var root := ProjectSettings.globalize_path(CACHE_DIR)
	var entries := []
	var total := 0
	for name in DirAccess.get_directories_at(root):
		var folder := root.path_join(name)
		var size := _folder_size(folder)
		total += size
		entries.append({"folder": folder, "size": size, "used": FileAccess.get_modified_time(folder.path_join(".used"))})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["used"] < b["used"])
	for entry: Dictionary in entries:
		if total <= CACHE_LIMIT_MB * 1024 * 1024:
			break
		if entry["folder"] != keep:
			_remove_dir(entry["folder"])
			total -= entry["size"]


# =====================================================================
# 7-Zip
# =====================================================================

## Есть ли встроенный распаковщик .7z (класс SevenZip в модуле shellbit_core,
## native/src/seven_zip.cpp). Он работает везде, и на Android тоже, — тогда
## отдельная программа 7-Zip не нужна. Нет (старый модуль) — как раньше,
## через 7zr.exe или 7z из системы.
func has_builtin_7z() -> bool:
	return ClassDB.class_exists("SevenZip")


## Путь к 7-Zip или "" если его нет.
func seven_zip() -> String:
	if _tool != "":
		return _tool
	var own := ProjectSettings.globalize_path(TOOLS_DIR.path_join("7zr.exe"))
	if OS.get_name() == "Windows":
		if FileAccess.file_exists(own):
			_tool = own
	elif not _tool_searched and not Platform.is_android():
		# Linux: ищем программу в системе. "command -v" печатает её путь.
		for name in ["7zz", "7z", "7za", "7zr"]:
			var output := []
			if OS.execute("sh", ["-c", "command -v " + name], output) == 0 and "".join(output).strip_edges() != "":
				_tool = "".join(output).strip_edges()
				break
	_tool_searched = true
	return _tool


## Скачать 7zr.exe, если его нет (только Windows). Ждать через await.
## Возвращает true, если 7-Zip есть.
func ensure_seven_zip() -> bool:
	if seven_zip() != "":
		return true
	if OS.get_name() != "Windows" or _download_tried:
		return false
	if not _downloading:
		_download_seven_zip()
	return await tool_ready


func _download_seven_zip() -> void:
	_downloading = true
	_download_tried = true
	SceneRouter.toast(tr("Скачиваю распаковщик 7-Zip…"))
	DirAccess.make_dir_recursive_absolute(TOOLS_DIR)
	var target := ProjectSettings.globalize_path(TOOLS_DIR.path_join("7zr.exe"))
	var http := HTTPRequest.new()
	http.use_threads = true
	http.download_file = target + ".part"
	add_child(http)
	http.request_completed.connect(_seven_zip_downloaded.bind(http, target))
	if http.request(SEVEN_ZIP_URL) != OK:
		# call_deferred — сообщить об ошибке в следующем кадре: тот, кто ждёт
		# сигнал tool_ready через await, должен успеть начать его ждать.
		_seven_zip_downloaded.call_deferred(HTTPRequest.RESULT_CANT_CONNECT, 0,
				PackedStringArray(), PackedByteArray(), http, target)


func _seven_zip_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray,
		http: HTTPRequest, target: String) -> void:
	http.queue_free()
	_downloading = false
	var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200
	if ok:
		DirAccess.rename_absolute(target + ".part", target)
		_tool = target
	else:
		DirAccess.remove_absolute(target + ".part")
		print("7-Zip не скачался: результат %d, ответ %d" % [result, code])
	tool_ready.emit(ok)


func _no_tool_message() -> String:
	if Platform.is_android():
		return tr("На Android архивы .7z пока не открываются. Распакуйте игру или запакуйте её в .zip.")
	if OS.get_name() == "Windows":
		return tr("Для архивов .7z нужен 7-Zip, но он не скачался. Проверьте интернет и попробуйте ещё раз.")
	return tr("Для архивов .7z нужен 7-Zip. Установите пакет p7zip или 7zip.")


# =====================================================================
# Помощники для папок
# =====================================================================

func _all_files(folder: String) -> PackedStringArray:
	var files := PackedStringArray()
	for file in DirAccess.get_files_at(folder):
		files.append(folder.path_join(file))
	for sub in DirAccess.get_directories_at(folder):
		files.append_array(_all_files(folder.path_join(sub)))
	return files


func _folder_size(folder: String) -> int:
	var size := 0
	for file in _all_files(folder):
		var handle := FileAccess.open(file, FileAccess.READ)
		if handle:
			size += handle.get_length()
	return size


func _remove_dir(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	for file in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
	for sub in DirAccess.get_directories_at(folder):
		_remove_dir(folder.path_join(sub))
	DirAccess.remove_absolute(folder)
