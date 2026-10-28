extends Node
## Family — детский режим.
##
## Когда он включён, ребёнок может только играть: выбирать игры,
## добавлять в избранное, сохраняться в пустые слоты. А всё, чем можно
## что-то сломать или потерять, спрятано:
##   • настройки (и папки с играми, и ядра, и управление);
##   • «+ Папка с играми» и «Выход» на главном экране;
##   • смена обложки, «Начать заново», настройки ядра;
##   • перезапись занятых слотов сохранений (так пропал бы прошлый прогресс);
##   • игры из жанра «Для взрослых».
##
## Выйти из режима может только взрослый — по PIN-коду из 4 цифр.
## Окно для кода — PinDialog (его показывает SceneRouter, когда
## кто-то пытается открыть настройки).
##
## Забыли PIN? Закройте Shellbit, откройте файл %APPDATA%\Shellbit\settings.cfg
## (на Linux — ~/.local/share/Shellbit/settings.cfg) и удалите раздел [family].

## Режим включили или выключили — экраны прячут или показывают кнопки.
signal changed

const SECTION := "family"


## Включён ли детский режим.
func is_on() -> bool:
	return Settings.get_value(SECTION, "kids_mode", false)


## Включить с новым PIN-кодом.
func enable(pin: String) -> void:
	Settings.set_value(SECTION, "pin_hash", _hash(pin))
	Settings.set_value(SECTION, "kids_mode", true)
	changed.emit()


## Выключить (PIN уже проверен).
func disable() -> void:
	Settings.set_value(SECTION, "kids_mode", false)
	changed.emit()


## Правильный ли PIN.
func check_pin(pin: String) -> bool:
	return _hash(pin) == Settings.get_value(SECTION, "pin_hash", "")


## Можно ли показывать эту игру (группу). Игры «Для взрослых»
## в детском режиме не показываются нигде: ни в библиотеке, ни
## в избранном, ни в «Продолжить играть».
func allows(group: Dictionary) -> bool:
	return not (is_on() and group.get("genre", "") == "adult")


# Храним не сам PIN, а его «отпечаток» — хеш SHA-256: по коду отпечаток
# считается легко, а обратно — никак. Так PIN нельзя просто прочитать
# в settings.cfg. (Честно: 4 цифры — это всего 10 000 вариантов, и упорный
# взрослый их переберёт. Но от ребёнка, который откроет файл, это защитит.)
# «shellbit:» в начале — «соль»: у такого же PIN в другой программе
# отпечаток будет другой.
func _hash(pin: String) -> String:
	return ("shellbit:" + pin).sha256_text()
