extends Node
## Запускалка автотестов. Её запускает Test.bat:
##   Godot --headless --path . res://test/run_tests.tscn
##
## Находит все файлы test/test_*.gd, в каждом — все функции test_*,
## запускает по очереди и печатает итог. Код выхода: 0 — всё прошло,
## 1 — есть упавшие тесты, 2 — тесты отказались запускаться.
##
## Тест падает, если не прошла проверка check…() ИЛИ если во время теста
## в коде Shellbit случилась ошибка (например, обращение к null) —
## её ловит ErrorCounter ниже.

const TEST_DIR := "res://test/"

## Тесты меняют настройки, библиотеку и сохранения. Чтобы не испортить
## настоящие, Test.bat запускает Godot с подменённой папкой данных
## (%APPDATA% → %TEMP%\shellbit-tests). Если подмены нет — не запускаемся.
const SANDBOX_MARK := "shellbit-tests"


func _ready() -> void:
	var user_dir := ProjectSettings.globalize_path("user://")
	if not user_dir.contains(SANDBOX_MARK):
		printerr("\n[!] Тесты не запущены: папка данных — настоящая (%s).\n    Запускайте тесты через Test.bat — он подставляет временную папку.\n" % user_dir)
		get_tree().quit(2)
		return

	# Экран, который откроют тесты, заменит «текущую сцену». Чтобы при этом
	# не удалили саму запускалку, делаем текущей пустую подставку.
	var stand_in := Node.new()
	stand_in.name = "StandIn"
	get_tree().root.add_child.call_deferred(stand_in)
	await get_tree().process_frame
	get_tree().current_scene = stand_in

	# Обложки в тестах не скачиваем: Covers думает, что все «каналы» заняты.
	Covers._active = 1_000_000
	# И 7-Zip из интернета не качаем — тесты с .7z работают, только если он уже есть.
	Archives._download_tried = true

	var errors := ErrorCounter.new()
	OS.add_logger(errors)

	print("\n=== Автотесты Shellbit · папка данных: %s ===" % user_dir)
	var passed := 0
	var failed := 0
	var files := Array(DirAccess.get_files_at(TEST_DIR)).filter(
			func(f: String) -> bool: return f.begins_with("test_") and f.ends_with(".gd"))
	files.sort()

	for file: String in files:
		var script: GDScript = load(TEST_DIR + file)
		print("\n%s" % file)
		for method: Dictionary in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			# Каждый тест — на свежем экземпляре: прошлый тест ему не помешает.
			var case: TestCase = script.new()
			add_child(case)
			errors.reset()
			await case.before_each()
			await case.call(method_name)
			await case.after_each()
			for error in errors.take():
				case.failures.append("ошибка в коде: " + error)
			var title := case.description if case.description != "" else method_name
			if case.failures.is_empty():
				passed += 1
				print("  ✓ ", title)
			else:
				failed += 1
				print("  ✗ ", title, "   (", method_name, ")")
				for failure in case.failures:
					print("      – ", failure)
			case.queue_free()
			await get_tree().process_frame

	OS.remove_logger(errors)
	print("\n=== Итог: прошло %d, упало %d ===\n" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)


## «Подслушивает» ошибки Godot. Logger — класс Godot 4.5+: всё, что
## движок пишет в журнал, проходит через _log_error и _log_message.
class ErrorCounter extends Logger:
	var _errors: PackedStringArray = []
	# Журнал могут вызывать из разных потоков — Mutex не даёт им толкаться.
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String,
			rationale: String, _editor_notify: bool, error_type: int,
			_script_backtraces: Array[ScriptBacktrace]) -> void:
		# Считаем ошибки скриптов и push_error() из нашего кода (res://).
		# Предупреждения и ошибки самого движка (нет звуковой карты и т.п.) — нет.
		var ours := error_type == ERROR_TYPE_SCRIPT \
				or (error_type == ERROR_TYPE_ERROR and file.begins_with("res://"))
		if not ours:
			return
		_lock.lock()
		_errors.append("%s (%s:%d, %s)" % [rationale if rationale != "" else code, file, line, function])
		_lock.unlock()

	func reset() -> void:
		_lock.lock()
		_errors.clear()
		_lock.unlock()

	func take() -> PackedStringArray:
		_lock.lock()
		var copy := _errors.duplicate()
		_errors.clear()
		_lock.unlock()
		return copy
