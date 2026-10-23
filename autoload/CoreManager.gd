extends Node
## CoreManager — знает, какие приставки поддерживаются и каким ядром их запускать.
##
## Все сведения о приставках лежат в data/systems.json.
## Чтобы добавить новую приставку, не нужно менять код —
## достаточно дописать запись в этот файл.

const SYSTEMS_PATH := "res://data/systems.json"

## Папки в user:// (в Windows: %APPDATA%\Shellbit\...)
const CORES_DIR := "user://cores"    # сюда кладём .dll ядер libretro
const SYSTEM_DIR := "user://system"  # сюда кладём BIOS
const SAVES_DIR := "user://saves"    # сюда ядра пишут сохранения

## Все приставки в том порядке, в каком они записаны в файле.
var systems: Array[Dictionary] = []

# Словарь «расширение файла → id приставки», например "sfc" → "snes".
# Нужен, чтобы быстро понять, к какой приставке относится найденный файл.
var _by_extension: Dictionary = {}


func _ready() -> void:
	# Создаём папки при первом запуске (если они уже есть — ничего не случится).
	for dir in [CORES_DIR, SYSTEM_DIR, SAVES_DIR]:
		DirAccess.make_dir_recursive_absolute(dir)

	var text := FileAccess.get_file_as_string(SYSTEMS_PATH)
	var data: Variant = JSON.parse_string(text)
	if not data is Array:
		push_error("Не удалось прочитать " + SYSTEMS_PATH)
		return

	for system: Dictionary in data:
		systems.append(system)
		for ext: String in system["extensions"]:
			_by_extension[ext] = system["id"]


## По расширению файла ("SFC", "nes"...) вернуть id приставки или "".
func system_for_extension(ext: String) -> String:
	return _by_extension.get(ext.to_lower(), "")


## Вернуть описание приставки по её id. Если не нашли — пустой словарь.
func get_system(id: String) -> Dictionary:
	for system in systems:
		if system["id"] == id:
			return system
	return {}


## Полный путь к файлу ядра для приставки, например
## "C:/Users/.../Shellbit/cores/fceumm_libretro.dll".
## globalize_path превращает "user://..." в настоящий путь на диске.
func core_path(system: Dictionary) -> String:
	var file_name: String = system.get("default_core", "")
	# В systems.json ядра записаны по-виндовому: fceumm_libretro.dll.
	# В Linux те же ядра называются fceumm_libretro.so.
	file_name = file_name.replace(".dll", core_extension())
	return ProjectSettings.globalize_path(CORES_DIR.path_join(file_name))


## Расширение файлов ядер: ".dll" в Windows, ".so" в Linux (и на Steam Deck).
func core_extension() -> String:
	return ".dll" if OS.get_name() == "Windows" else ".so"


## Открыть папку с ядрами в Проводнике (в Linux — в Dolphin, Nautilus и т.п.).
func open_cores_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path(CORES_DIR))
