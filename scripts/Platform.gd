class_name Platform
extends RefCounted
## Platform — на чём запущен Shellbit: компьютер, телефон или Android TV.
##
## Почти весь Shellbit одинаков везде, но кое-что зависит от устройства:
##   • на Android нет «окна» и кнопки «Выход» — приложения закрывают жестом;
##   • на Android нельзя открыть папку в «Проводнике» — вместо этого
##     файлы (BIOS) выбирают и копируют к себе;
##   • на телефоне без геймпада нужен экранный геймпад, а на Android TV
##     сенсорного экрана нет — там всё как на компьютере с геймпадом.
##
## static func — функции «класса», их зовут без создания объекта:
##   if Platform.is_android(): ...

## Папка «внутренней памяти» телефона, которую видно в файловом менеджере.
const ANDROID_STORAGE := "/storage/emulated/0"


## Android (телефон, планшет или TV-приставка).
static func is_android() -> bool:
	return OS.has_feature("android")


## Компьютер: Windows или Linux (и Steam Deck).
static func is_desktop() -> bool:
	return not is_android()


## Притвориться сенсорным экраном — для автотестов и снимков экрана на компьютере.
static var pretend_touch := false


## Есть ли сенсорный экран. На Android TV его нет — там пульт и геймпад.
static func has_touch() -> bool:
	return pretend_touch or DisplayServer.is_touchscreen_available()


## Сенсорный экран — главный способ управления: телефон или планшет.
## (Ноутбук с сенсорным экраном сюда не относится — там есть мышь.)
## Тогда нужны кнопка «Пауза», экранный геймпад и крупные кнопки.
static func touch_first() -> bool:
	return pretend_touch or (is_android() and has_touch())


## Android TV-приставка: Android без сенсорного экрана.
static func is_tv() -> bool:
	return is_android() and not has_touch()


## Можно ли показать папку в файловом менеджере (OS.shell_open).
## На Android — нет: папки программы спрятаны от других приложений.
static func can_open_folders() -> bool:
	return is_desktop()


## Откуда начинать выбор папки или файла: на Android — внутренняя память,
## на компьютере — папка «Документы» (как раньше, по умолчанию).
static func start_dir() -> String:
	return ANDROID_STORAGE if is_android() else OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)


## Настроить окно выбора файла/папки под устройство. На компьютере —
## системное окно Windows/Linux. На Android — встроенное окно Godot:
## оно читает папки напрямую (после разрешения «Доступ ко всем файлам»)
## и управляется и пальцем, и геймпадом.
static func setup_file_dialog(dialog: FileDialog) -> void:
	dialog.use_native_dialog = is_desktop()
	if is_android():
		dialog.current_dir = ANDROID_STORAGE


## Попросить у Android разрешение читать папки с играми.
## Разрешение «Доступ ко всем файлам» (MANAGE_EXTERNAL_STORAGE) записано
## в настройках экспорта; Godot сам откроет нужный экран настроек Android.
## Спрашиваем один раз при запуске — пока разрешения нет.
static func request_storage_permission() -> void:
	if not is_android():
		return
	if not "android.permission.MANAGE_EXTERNAL_STORAGE" in OS.get_granted_permissions():
		OS.request_permissions()
