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
		# "desktop_only": true — приставка только для компьютера (PlayStation 2:
		# её ядро есть только для процессоров x86-64, телефону оно не по силам).
		if system.get("desktop_only", false) and not Platform.is_desktop():
			continue
		systems.append(system)
		# Папка BIOS со своим местом (PS2 — system/pcsx2/bios): создаём её
		# заранее, чтобы человеку было куда положить файл.
		if system.has("bios_dir"):
			DirAccess.make_dir_recursive_absolute(SYSTEM_DIR.path_join(system["bios_dir"]))
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
	return ProjectSettings.globalize_path(CORES_DIR.path_join(core_file(system)))


## Имя файла ядра для этой системы. В systems.json ядра записаны
## по-виндовому: fceumm_libretro.dll. В Linux то же ядро — fceumm_libretro.so,
## а на Android — fceumm_libretro_android.so (так их называет сервер libretro).
func core_file(system: Dictionary) -> String:
	var file_name: String = system.get("default_core", "")
	if file_name == "":
		return ""
	if Platform.is_android():
		var base := file_name.trim_suffix("_libretro.dll")
		return ANDROID_CORES.get(base, base) + "_libretro_android.so"
	return file_name.replace(".dll", core_extension())


## Ядра, которые для Android собраны под другим именем. У Nintendo 64
## на телефонах нет «большого» OpenGL — только OpenGL ES 3 (gles3).
const ANDROID_CORES := {"mupen64plus_next": "mupen64plus_next_gles3"}


## Расширение файлов ядер: ".dll" в Windows, ".so" в Linux (и на Steam Deck).
func core_extension() -> String:
	return ".dll" if OS.get_name() == "Windows" else ".so"


## Скопировать файлы BIOS в папку BIOS (нужно на Android: туда не положить
## файл руками). Возвращает, сколько файлов скопировано.
## Архивы аркад (neogeo.zip) FBNeo ищет и в system/fbneo — копируем и туда.
func import_bios(paths: PackedStringArray) -> int:
	var count := 0
	DirAccess.make_dir_recursive_absolute(SYSTEM_DIR.path_join("fbneo"))
	for path in paths:
		var target := SYSTEM_DIR.path_join(path.get_file())
		if path.get_extension().to_lower() == "zip":
			target = SYSTEM_DIR.path_join("fbneo").path_join(path.get_file())
		if DirAccess.copy_absolute(path, ProjectSettings.globalize_path(target)) == OK:
			count += 1
	return count


## Есть ли BIOS у приставки, которой нужна целая папка BIOS ("bios_dir"
## в systems.json). Ядру PS2 годится любой файл BIOS — имя не важно, поэтому
## проверяем просто, что в папке что-то лежит. Без "bios_dir" — всегда true.
func has_bios_dir_files(system: Dictionary) -> bool:
	if not system.has("bios_dir"):
		return true
	var dir := SYSTEM_DIR.path_join(system["bios_dir"])
	for file in DirAccess.get_files_at(dir):
		if file.get_extension().to_lower() == "bin":
			return true
	return false


## Полный путь к папке BIOS приставки (для сообщений и кнопки «Открыть папку»).
func bios_dir_path(system: Dictionary) -> String:
	return ProjectSettings.globalize_path(SYSTEM_DIR.path_join(system.get("bios_dir", "")))


## Открыть папку с ядрами в Проводнике (в Linux — в Dolphin, Nautilus и т.п.).
func open_cores_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path(CORES_DIR))
