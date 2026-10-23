extends Node
## Settings — хранит настройки приложения.
##
## Это синглтон (Autoload): Godot создаёт его один раз при запуске,
## и из любого скрипта к нему можно обратиться по имени: Settings.get_value(...)
##
## Настройки лежат в файле user://settings.cfg.
## user:// — это личная папка приложения. В Windows это %APPDATA%\Shellbit,
## в Linux — ~/.local/share/Shellbit. Своё имя папки включено в project.godot:
## application/config/use_custom_user_dir и custom_user_dir_name.
## Без этого Godot кладёт данные в общую папку Godot\app_userdata\Shellbit.

## Сигнал: какую-то настройку поменяли. Экраны могут подписаться
## и сразу применить новое значение.
signal changed(section: String, key: String)

const PATH := "user://settings.cfg"

## Где данные лежали раньше, до своей папки (в Windows — с большой буквы,
## в Linux — с маленькой). Отсюда они один раз переезжают на новое место.
const OLD_DIRS := ["Godot/app_userdata/Shellbit", "godot/app_userdata/Shellbit"]
## Эти папки Godot создаёт сам (журналы, кеш шейдеров) — их не переносим.
const SKIP_DIRS := ["logs", "shader_cache", "vulkan", "objectdb_snapshots"]

## Откуда перенесли данные при этом запуске ("" — ничего не переносили).
## Главный экран покажет об этом сообщение.
var moved_from := ""

## Сколько памяти (в мегабайтах) можно отдать под «ленту» перемотки.
## Если игра тяжёлая (PlayStation), снимки делаются реже, чтобы уложиться.
const REWIND_BUDGET_MB := 256

## Значения по умолчанию — пока человек ничего не менял.
## get_value() берёт их отсюда, если в файле настройки ещё нет.
const DEFAULTS := {
	"general": {
		"language": "auto",  # auto (как в Windows) / ru / en / zh / ja
	},
	"video": {
		"window_mode": "fullscreen",  # fullscreen (во весь экран) / windowed (в окне)
		"filter": "none",   # none / smooth / crt / lcd
		"scale": "fit",     # fit (во весь экран) / integer (целые пиксели)
		"aspect": "core",   # core (как у приставки) / square / stretch
		"sides": "black",   # black (чёрные поля) / blur (размытый кадр)
		"vsync": true,
	},
	"play": {
		"ff_speed": 3,          # ускорение: во сколько раз быстрее (2, 3, 4, 8)
		"ff_mode": "hold",      # hold — пока держишь кнопку, toggle — нажал и отпустил
		"rewind_seconds": 20,   # длина «ленты» перемотки, 0 — перемотка выключена
		"rumble": true,         # вибрация геймпада, если игра её использует
	},
	"audio": {
		"volume": 100,      # громкость в процентах: 0..100
		"ui_sounds": true,  # щелчки при переходах и «бульк» при запуске игры
	},
}

# ConfigFile — встроенный класс Godot для файлов вида:
#   [library]
#   folders=PackedStringArray("D:/Games/NES")
var _cfg := ConfigFile.new()


func _ready() -> void:
	# Settings — первый синглтон в списке, поэтому переезд данных
	# случится раньше, чем библиотека и обложки начнут их читать.
	_move_old_data()
	# Если файла ещё нет (первый запуск), load() вернёт ошибку,
	# а настройки просто останутся пустыми. Это нормально.
	_cfg.load(PATH)
	# Сразу применяем то, что действует на всё приложение.
	apply_vsync()
	apply_window_mode()
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


# --- Переезд данных в свою папку --------------------------------------------

## Если на новом месте настроек ещё нет, а в старой папке Godot есть —
## копируем туда всё: настройки, библиотеку, сохранения, обложки, ядра.
## Копируем, а не переносим: если что-то пойдёт не так, старая папка цела.
func _move_old_data() -> void:
	if FileAccess.file_exists(PATH):
		return  # данные уже на новом месте
	var here := ProjectSettings.globalize_path("user://").simplify_path()
	for old_name: String in OLD_DIRS:
		# OS.get_data_dir() — общая папка программ: %APPDATA% в Windows,
		# ~/.local/share в Linux.
		var old := OS.get_data_dir().path_join(old_name).simplify_path()
		if old.to_lower() == here.to_lower():
			return  # своя папка выключена — переезжать некуда
		if FileAccess.file_exists(old.path_join("settings.cfg")):
			var count := _copy_dir(old, here)
			moved_from = old
			print("Данные Shellbit перенесены: %s → %s (файлов: %d)" % [old, here, count])
			# Записка в старой папке — чтобы было понятно, что её можно удалить.
			var note := FileAccess.open(old.path_join("ДАННЫЕ ПЕРЕЕХАЛИ.txt"), FileAccess.WRITE)
			if note:
				note.store_string("Данные Shellbit скопированы в папку:\n%s\n\nЭту папку можно удалить.\n" % here)
			return


## Скопировать папку со всем содержимым. Возвращает, сколько файлов скопировано.
## Функция вызывает сама себя для каждой вложенной папки — это называется рекурсия.
func _copy_dir(from: String, to: String) -> int:
	var dir := DirAccess.open(from)
	if dir == null:
		return 0
	DirAccess.make_dir_recursive_absolute(to)
	var count := 0
	for file_name in dir.get_files():
		var target := to.path_join(file_name)
		# Файл, который уже есть на новом месте, не трогаем.
		if not FileAccess.file_exists(target) \
				and DirAccess.copy_absolute(from.path_join(file_name), target) == OK:
			count += 1
	for dir_name in dir.get_directories():
		if not SKIP_DIRS.has(dir_name):
			count += _copy_dir(from.path_join(dir_name), to.path_join(dir_name))
	return count


# --- Применение настроек ----------------------------------------------------

## Полный экран или окно. Shellbit и так стартует во весь экран
## (window/size/mode = 3 в project.godot — без «мигания» окна при запуске),
## а здесь применяем выбор человека из Настроек → Видео.
func apply_window_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return  # без окна (автотесты) переключать нечего
	var full_modes := [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	if get_value("video", "window_mode") == "fullscreen":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	var was_full := DisplayServer.window_get_mode() in full_modes
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if was_full:
		# Из полного экрана — в окно 1280×720 посередине монитора.
		var screen := DisplayServer.window_get_current_screen()
		var size := Vector2i(1280, 720)
		DisplayServer.window_set_size(size)
		DisplayServer.window_set_position(DisplayServer.screen_get_position(screen)
				+ (DisplayServer.screen_get_size(screen) - size) / 2)


## Переключить: полный экран ↔ окно (F11 или Alt+Enter).
func toggle_window_mode() -> void:
	var mode := "windowed" if get_value("video", "window_mode") == "fullscreen" else "fullscreen"
	set_value("video", "window_mode", mode)
	apply_window_mode()


# _input получает нажатия раньше кнопок интерфейса — поэтому F11 работает
# на любом экране, даже в игре.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen") and not event.is_echo():
		toggle_window_mode()
		# Enter из Alt+Enter не должен заодно нажать кнопку на экране.
		get_viewport().set_input_as_handled()


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
