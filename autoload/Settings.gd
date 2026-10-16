extends Node
## Settings — хранит настройки приложения.
##
## Это синглтон (Autoload): Godot создаёт его один раз при запуске,
## и из любого скрипта к нему можно обратиться по имени: Settings.get_value(...)
##
## Настройки лежат в файле user://settings.cfg.
## user:// — это личная папка приложения. В Windows это
## %APPDATA%\Godot\app_userdata\Shellbit

const PATH := "user://settings.cfg"

# ConfigFile — встроенный класс Godot для файлов вида:
#   [library]
#   folders=PackedStringArray("D:/Games/NES")
var _cfg := ConfigFile.new()


func _ready() -> void:
	# Если файла ещё нет (первый запуск), load() вернёт ошибку,
	# а настройки просто останутся пустыми. Это нормально.
	_cfg.load(PATH)


## Прочитать значение. Если его нет — вернуть default.
func get_value(section: String, key: String, default: Variant = null) -> Variant:
	return _cfg.get_value(section, key, default)


## Записать значение и сразу сохранить файл на диск.
func set_value(section: String, key: String, value: Variant) -> void:
	_cfg.set_value(section, key, value)
	_cfg.save(PATH)


## Список папок, в которых лежат игры.
func get_rom_folders() -> PackedStringArray:
	return get_value("library", "folders", PackedStringArray())


func add_rom_folder(path: String) -> void:
	var folders := get_rom_folders()
	if not folders.has(path):
		folders.append(path)
		set_value("library", "folders", folders)
