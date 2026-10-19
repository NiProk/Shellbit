extends Node
## Settings — хранит настройки приложения.
##
## Это синглтон (Autoload): Godot создаёт его один раз при запуске,
## и из любого скрипта к нему можно обратиться по имени: Settings.get_value(...)
##
## Настройки лежат в файле user://settings.cfg.
## user:// — это личная папка приложения. В Windows это
## %APPDATA%\Godot\app_userdata\Shellbit

## Сигнал: какую-то настройку поменяли. Экраны могут подписаться
## и сразу применить новое значение.
signal changed(section: String, key: String)

const PATH := "user://settings.cfg"

## Значения по умолчанию — пока человек ничего не менял.
## get_value() берёт их отсюда, если в файле настройки ещё нет.
const DEFAULTS := {
	"general": {
		"language": "auto",  # auto (как в Windows) / ru / en / zh / ja
	},
	"video": {
		"filter": "none",   # none / smooth / crt / lcd
		"scale": "fit",     # fit (во весь экран) / integer (целые пиксели)
		"aspect": "core",   # core (как у приставки) / square / stretch
		"sides": "black",   # black (чёрные поля) / blur (размытый кадр)
		"vsync": true,
	},
	"audio": {
		"volume": 100,      # громкость в процентах: 0..100
	},
}

# ConfigFile — встроенный класс Godot для файлов вида:
#   [library]
#   folders=PackedStringArray("D:/Games/NES")
var _cfg := ConfigFile.new()


func _ready() -> void:
	# Если файла ещё нет (первый запуск), load() вернёт ошибку,
	# а настройки просто останутся пустыми. Это нормально.
	_cfg.load(PATH)
	# Сразу применяем то, что действует на всё приложение.
	apply_vsync()
	apply_volume()


## Прочитать значение. Если его нет — вернуть default,
## а если и default не передали — значение из DEFAULTS.
func get_value(section: String, key: String, default: Variant = null) -> Variant:
	if default == null and DEFAULTS.has(section):
		default = DEFAULTS[section].get(key)
	return _cfg.get_value(section, key, default)


## Записать значение и сразу сохранить файл на диск.
func set_value(section: String, key: String, value: Variant) -> void:
	_cfg.set_value(section, key, value)
	_cfg.save(PATH)
	changed.emit(section, key)


## Список папок, в которых лежат игры.
func get_rom_folders() -> PackedStringArray:
	return get_value("library", "folders", PackedStringArray())


func add_rom_folder(path: String) -> void:
	var folders := get_rom_folders()
	if not folders.has(path):
		folders.append(path)
		set_value("library", "folders", folders)


## Папка для скриншотов: «Изображения\Shellbit».
## OS.get_system_dir() знает, где у Windows лежат «Изображения»
## (обычно C:\Users\<имя>\Pictures), даже если папку перенесли.
func screenshots_dir() -> String:
	var pictures := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if pictures == "":
		# Не удалось узнать — сохраняем в папку данных программы.
		return ProjectSettings.globalize_path("user://screenshots")
	return pictures.path_join("Shellbit")


## Убрать папку из списка (сами файлы на диске не трогаем).
func remove_rom_folder(path: String) -> void:
	var folders := get_rom_folders()
	var index := folders.find(path)
	if index >= 0:
		folders.remove_at(index)
		set_value("library", "folders", folders)


# --- Применение настроек ----------------------------------------------------

## Вертикальная синхронизация: кадры выводятся в такт монитору,
## поэтому картинка не «рвётся» при движении.
func apply_vsync() -> void:
	var mode := DisplayServer.VSYNC_ENABLED if get_value("video", "vsync") else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(mode)


## Общая громкость. AudioServer — «микшерный пульт» Godot,
## шина 0 (Master) — главный регулятор, через который идёт весь звук.
func apply_volume() -> void:
	var percent := int(get_value("audio", "volume"))
	# Громкость в Godot задаётся в децибелах, а нам удобнее проценты.
	# linear_to_db переводит одно в другое: 1.0 → 0 дБ, 0.5 → −6 дБ.
	AudioServer.set_bus_volume_db(0, linear_to_db(percent / 100.0))
	AudioServer.set_bus_mute(0, percent == 0)
