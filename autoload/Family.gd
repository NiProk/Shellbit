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
## Ещё можно ограничить время игры в день (Настройки → Семья → «Время игры
## в день»). Считается только время, когда игра идёт, — меню паузы не в счёт.
## За 5 минут и за 1 минуту до конца — предупреждение; время вышло — игра
## сохраняется и закрывается. Запустить игру снова можно завтра — или раньше,
## если взрослый введёт PIN: тогда добавится EXTRA_MINUTES.
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
## Сколько минут добавляет взрослый по PIN-коду, когда время вышло.
const EXTRA_MINUTES := 30
## Как часто записывать наигранное время в settings.cfg (секунды).
## Не каждый кадр: запись файла — это медленно. Если программу закроют
## «грубо», потеряется не больше этих секунд.
const SAVE_EVERY := 15.0

var _unsaved := 0.0  # наиграно, но ещё не записано в файл (секунды)


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


# =====================================================================
# Время игры в день
# =====================================================================

## Лимит в минутах (0 — без ограничений).
func time_limit() -> int:
	return int(Settings.get_value(SECTION, "time_limit", 0))


## Действует ли лимит прямо сейчас: детский режим включён и лимит задан.
func limit_active() -> bool:
	return is_on() and time_limit() > 0


## Сколько секунд осталось на сегодня (может быть меньше нуля).
func seconds_left() -> float:
	_new_day_check()
	var allowed := time_limit() * 60.0 + float(Settings.get_value(SECTION, "extra_today", 0))
	return allowed - played_today()


## Сколько секунд сегодня уже наиграно.
func played_today() -> float:
	_new_day_check()
	return float(Settings.get_value(SECTION, "played_today", 0)) + _unsaved


func time_is_up() -> bool:
	return limit_active() and seconds_left() <= 0.0


## Засчитать seconds секунд игры (экран игры зовёт каждый кадр).
func add_play_time(seconds: float) -> void:
	if not limit_active():
		return
	_new_day_check()
	_unsaved += seconds
	if _unsaved >= SAVE_EVERY:
		save_play_time()


## Записать накопленное время в файл (и при выходе из игры).
func save_play_time() -> void:
	if _unsaved <= 0.0:
		return
	var total := float(Settings.get_value(SECTION, "played_today", 0)) + _unsaved
	_unsaved = 0.0
	Settings.set_value(SECTION, "played_today", int(total))


## Взрослый ввёл PIN — ещё EXTRA_MINUTES минут на сегодня. Если время
## уже «ушло в минус» (игра закрылась чуть позже нуля), минус прощаем.
func add_extra_time() -> void:
	var extra := float(Settings.get_value(SECTION, "extra_today", 0))
	extra += maxf(0.0, -seconds_left()) + EXTRA_MINUTES * 60.0
	Settings.set_value(SECTION, "extra_today", int(extra))


# Наступил новый день — счётчики с нуля. Дату храним строкой «2026-10-30».
func _new_day_check() -> void:
	var today := Time.get_date_string_from_system()
	if Settings.get_value(SECTION, "day", "") == today:
		return
	_unsaved = 0.0
	Settings.set_value(SECTION, "day", today)
	Settings.set_value(SECTION, "played_today", 0)
	Settings.set_value(SECTION, "extra_today", 0)


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
