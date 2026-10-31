extends Control
## Экран игры: запускает ядро libretro через наш C++-узел RetroCore,
## показывает картинку, проигрывает звук и передаёт нажатия кнопок.
##
## Открывается так: SceneRouter.go_to("player", {"game": game})
##
## Меню паузы: правый стик (R3), Select + Start или Esc.
## При выходе игра сохраняется сама, а при следующем запуске
## продолжается с того же места.
##
## Ускорение (RT / пробел) и перемотка назад (LT / Backspace) —
## см. раздел «Ускорение и перемотка» внизу.
##
## Кадры приставки считаются В ОТДЕЛЬНОМ ПОТОКЕ (см. раздел «Поток эмуляции»):
## главный поток рисует интерфейс и читает кнопки, а поток эмуляции
## считает кадры, звук и снимки перемотки. Так подвисание интерфейса
## (открылось меню, Windows подгрузила что-то с диска) не сбивает игру.

const CRT_SHADER := preload("res://scenes/player/crt.gdshader")
const LCD_SHADER := preload("res://scenes/player/lcd.gdshader")

var core: Node  # RetroCore (создаём из кода — см. _start_game)
var game: Dictionary = {}

var _core_aspect := 4.0 / 3.0  # пропорции картинки, которые сообщило ядро

var _texture: ImageTexture
var _playback: AudioStreamGeneratorPlayback
var _frame_time := 1.0 / 60.0  # сколько секунд длится один кадр приставки
var _time_bank := 0.0          # накопленное время, которое ещё не «отыграно»
var _sync := AudioSync.new()   # синхронизация по звуку (scripts/AudioSync.gd)
var _has_rumble := false       # ядро умеет вибрацию (shellbit_core новый)
var _start_msec := 0

var _paused := false
var _missing_core := false  # игра не запустилась, потому что нет ядра
var _missing_bios := false  # …или потому что нет BIOS (кнопка тогда открывает папку BIOS)
var _bios_folder := ""      # какую папку открывает кнопка при нехватке BIOS
# Файл, который отдаём ядру: сам файл игры или распакованный из архива.
var _content_path := ""
var _status_label: Label     # «Распаковываю игру…» по центру экрана
# После закрытия меню ждём, пока игрок отпустит все кнопки.
# Иначе нажатие «A — Продолжить» дошло бы до игры как прыжок,
# а Esc, которым закрыли меню, тут же открыл бы его снова.
var _wait_release := false

# --- Ускорение и перемотка ---
var _ff_on := false          # ускорение включено (в режиме «нажать один раз»)
var _ff_was_down := false    # кнопка ускорения была зажата в прошлом кадре
# «Лента» перемотки: снимки состояния приставки, от старых к новым.
var _tape: Array[PackedByteArray] = []
var _tape_max := 0           # сколько снимков помещается (0 — перемотка выключена)
var _snap_every := 2         # делать снимок раз в столько кадров приставки
var _snap_count := 0         # кадров с прошлого снимка
var _rewind_wait := 0        # при перемотке: сколько кадров ждать до следующего шага назад
var _speed_label: Label      # значок «▶▶ ×3» / «◀◀» в углу экрана
var _gun: LightGun           # световой пистолет (Duck Hunt и т.п.), null — игра без него


func _ready() -> void:
	game = SceneRouter.params.get("game", {})
	%OpenCoresButton.pressed.connect(func() -> void:
		if _missing_bios and not Platform.can_open_folders():
			_pick_bios_files()  # Android: папку не открыть — выбираем файлы и копируем
		elif _missing_bios:
			OS.shell_open(_bios_folder)
		else:
			CoreManager.open_cores_folder())
	%DownloadButton.pressed.connect(_download_core)
	CoreDownloader.progress.connect(_on_core_progress)
	CoreDownloader.finished.connect(_on_core_finished)

	# Подписываемся на сигналы меню паузы.
	%PauseMenu.resume_requested.connect(_resume)
	%PauseMenu.restart_requested.connect(_restart)
	%PauseMenu.exit_requested.connect(_exit_game)
	%PauseMenu.save_requested.connect(_on_save_requested)
	%PauseMenu.load_requested.connect(_on_load_requested)
	%PauseMenu.screenshot_requested.connect(_take_screenshot)
	%PauseMenu.disc_requested.connect(_on_disc_requested)
	%PauseMenu.options_requested.connect(_open_core_options)
	add_child(_options_panel)
	_options_panel.option_changed.connect(_on_option_changed)
	_options_panel.reset_requested.connect(_on_options_reset)
	_options_panel.closed.connect(func() -> void: %PauseMenu.get_node("%OptionsButton").grab_focus())
	%PauseMenu.cheats_requested.connect(_open_cheats)
	add_child(_cheats_panel)
	_cheats_panel.changed.connect(_on_cheats_changed)
	_cheats_panel.closed.connect(func() -> void:
		%PauseMenu.refresh_cheats()  # «Читы · включено 2»
		%PauseMenu.get_node("%CheatsButton").grab_focus())

	# Окно поменяло размер — пересчитать, где и какого размера картинка.
	resized.connect(_apply_layout)
	_create_speed_label()
	_create_touch_pause()

	# С какого сохранения начать: "auto" — с места выхода (по умолчанию),
	# "1".."3" — с ручного слота (их выбирают на странице игры).
	_begin()


## Запустить игру; не получилось — показать почему.
## Вызывается при открытии экрана и ещё раз — когда скачалось ядро.
func _begin() -> void:
	_content_path = game.get("path", "")
	# Игра в архиве (.zip, .7z) — сначала распаковать. Это может занять
	# несколько секунд, поэтому ждём (await) и показываем надпись.
	if Archives.needs_extraction(game):
		_show_status(tr("Распаковываю игру…"))
		var result: Dictionary = await Archives.prepare(game)
		_show_status("")
		if not is_inside_tree():
			return  # пока распаковывали, человек ушёл с экрана
		if result["error"] != "":
			_show_error(result["error"])
			return
		_content_path = result["path"]

	# Один из дисков многодисковой игры («…(Disc 2).cue»)? Составим список
	# всех дисков (.m3u), чтобы их можно было менять. Начнём с выбранного.
	_start_disc = {}
	if not Archives.needs_extraction(game):
		var playlist := Discs.playlist_for(_content_path, game["system"])
		if not playlist.is_empty():
			_content_path = playlist["path"]
			_start_disc = {"index": playlist["index"], "path": playlist["disc_path"]}

	var error := _start_game(SceneRouter.params.get("slot", SaveStates.AUTO))
	if error != "":
		_show_error(error)
		return

	Library.mark_played(game)
	_start_msec = Time.get_ticks_msec()
	_setup_rewind()
	_start_emulation()


# --- Стики ----------------------------------------------------------------

## Передаём ли стики в игру (только PlayStation и Nintendo 64).
var _analog := false


## Включить стики, если приставка их знает. Вызывается после load_game.
func _setup_analog() -> void:
	# has_method — на случай старого shellbit_core.dll, собранного до стиков:
	# тогда игра просто работает как раньше, без стиков.
	_analog = InputMapper.has_analog(game["system"]) and core.has_method("set_analog")
	if not _analog:
		return
	# Ядро PlayStation по умолчанию «вставляет» обычный геймпад без стиков.
	# Список контроллеров, которые оно умеет, ядро присылает само —
	# выбираем из него DualShock (или любой другой со стиками).
	for port in 2:
		var types: Array = core.get_controller_types(port)
		var chosen := _pick_analog_type(types)
		if chosen >= 0:
			core.set_controller_type(port, chosen)
			print("Порт %d: контроллер %d (%s)" % [port + 1, chosen,
					", ".join(types.map(func(t: Dictionary) -> String: return "%s=%d" % [t["name"], t["id"]]))])


## Из списка контроллеров ядра — номер DualShock, иначе первого со стиками.
## -1 — список пуст (так у ядра Nintendo 64: стик у него есть всегда).
static func _pick_analog_type(types: Array) -> int:
	const DEVICE_ANALOG := 5   # RETRO_DEVICE_ANALOG в libretro.h
	const DEVICE_MASK := 0xff  # младший байт — «вид» контроллера, старшие — разновидность
	for type: Dictionary in types:
		if String(type["name"]).to_lower().contains("dualshock"):
			return type["id"]
	for type: Dictionary in types:
		if int(type["id"]) & DEVICE_MASK == DEVICE_ANALOG:
			return type["id"]
	return -1


## Долгое сообщение внизу экрана (дольше обычного всплывающего —
## чтобы успеть прочитать, что делать).
func _show_notice(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size.x = 640
	var box := UiTheme.badge_box(Color("7a2e2e"))
	box.set_content_margin_all(16)
	box.set_corner_radius_all(14)
	label.add_theme_stylebox_override("normal", box)
	add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 40)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var tween := create_tween()
	tween.tween_interval(10.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)


## Каждый кадр — где сейчас стики. muted — во время перемотки и после
## меню, пока человек не отпустил кнопки: тогда стики «в центре».
## Где сейчас стики: [порт 1 левый, порт 1 правый, порт 2 левый, порт 2 правый].
## Читаем в главном потоке, а в ядро передаёт поток эмуляции (_emulate).
## muted — во время перемотки и после меню, пока не отпустили кнопки.
func _read_sticks(system_id: String, muted: bool) -> Array[Vector2]:
	var sticks: Array[Vector2] = []
	if not _analog:
		return sticks
	for port in 2:
		for stick in 2:
			sticks.append(Vector2.ZERO if muted else InputMapper.get_analog(port, stick, system_id))
	return sticks


# --- Вибрация -------------------------------------------------------------
#
# Ядро говорит, с какой силой крутить моторы геймпада (их обычно два:
# тяжёлый «сильный» — гул, лёгкий «слабый» — дрожь). Мы каждый кадр
# смотрим, что оно хочет, и передаём это в Godot: Input.start_joy_vibration.

## Что мы последний раз отправили на геймпады игроков 1 и 2.
var _rumble_sent: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
## Когда отправили (мс). Вибрацию включаем на 1 секунду и, пока игра
## её не выключила, продлеваем каждые полсекунды: если Shellbit вдруг
## зависнет или вылетит, геймпад не будет трястись бесконечно.
var _rumble_msec: Array[int] = [0, 0]


## stop = true — выключить моторы (пауза, перемотка, выход из игры).
func _update_rumble(stop := false) -> void:
	if core == null or not _has_rumble:
		return  # старый shellbit_core без вибрации
	# Что хочет игра, узнаёт поток эмуляции — берём у него.
	_shared_lock.lock()
	var wanted := _rumble_now.duplicate()
	_shared_lock.unlock()
	var enabled: bool = Settings.get_value("play", "rumble")
	var pads := Input.get_connected_joypads()
	var now := Time.get_ticks_msec()
	for port in 2:
		var value: Vector2 = Vector2.ZERO if stop or not enabled else wanted[port]
		var renew := value != Vector2.ZERO and now - _rumble_msec[port] > 500
		if value == _rumble_sent[port] and not renew:
			continue  # ничего не изменилось
		_rumble_sent[port] = value
		_rumble_msec[port] = now
		if port >= pads.size():
			continue  # у этого игрока нет геймпада
		if value == Vector2.ZERO:
			Input.stop_joy_vibration(pads[port])
		else:
			# weak — лёгкий мотор, strong — тяжёлый, duration — секунды.
			Input.start_joy_vibration(pads[port], value.x, value.y, 1.0)


## Запустить игру и загрузить сохранение из слота start_slot ("" — с самого начала).
## Возвращает "" если всё хорошо, иначе — текст ошибки.
func _start_game(start_slot: String) -> String:
	_missing_core = false
	if game.is_empty():
		return tr("Не передана игра.")

	# Класс RetroCore появляется, только если C++-модуль собран.
	# Проверяем через ClassDB, чтобы проект открывался и без модуля.
	if not ClassDB.class_exists("RetroCore"):
		var script := "native/build.bat" if OS.get_name() == "Windows" else "native/build.sh"
		return tr("C++-модуль shellbit_core не собран. Запустите %s и перезапустите Godot.") % script

	var system := CoreManager.get_system(game["system"])
	var core_path := CoreManager.core_path(system)
	_missing_core = not FileAccess.file_exists(core_path)
	if _missing_core and not Platform.can_open_folders():
		# Android: в папку программы файл руками не положить — только «Скачать».
		return tr("Нет ядра %s.\nНажмите «Скачать ядро» — Shellbit скачает его сам.") % core_path.get_file()
	if _missing_core:
		return tr("Нет ядра %s.\nНажмите «Скачать ядро» — Shellbit скачает его сам. Или положите файл в папку ядер:\n%s") % [
			core_path.get_file(), core_path.get_base_dir()]

	# PlayStation 2 без BIOS не запускает ни одной игры, а ядро пишет об этом
	# только в журнал. Своя папка BIOS ("bios_dir") пуста — говорим сразу.
	if not CoreManager.has_bios_dir_files(system):
		_missing_bios = true
		_bios_folder = CoreManager.bios_dir_path(system)
		return tr("Для игр %s нужен BIOS — файл из самой приставки (например, scph39001.bin).\n\nShellbit не может скачать его сам: раздавать его свободно нельзя. Если у вас есть этот файл, положите его в папку:\n%s") % [
			tr(system.get("name", "")), _bios_folder]

	# Диск, а у приставки для дисков нужен свой BIOS (PC Engine CD — syscard3.pce)?
	# Без него ядро просто отказывается открывать игру, и человек видел бы
	# непонятное «ядро не смогло открыть файл». Проверяем заранее и говорим прямо.
	var missing := _missing_disc_bios(system)
	_missing_bios = missing != ""
	_bios_folder = ProjectSettings.globalize_path(CoreManager.SYSTEM_DIR)
	var arcade_bios := _missing_arcade_bios()
	if arcade_bios != "":
		# Аркада без BIOS автомата (neogeo.zip у Metal Slug и KOF). FBNeo сам
		# показал бы только английский экран «romset is missing files».
		_missing_bios = true
		_bios_folder = _content_path.get_base_dir()
		if not Platform.can_open_folders():
			return tr("Этой игре нужен BIOS автомата %s — файл %s.\n\nЭто «прошивка» самого игрового автомата, раздавать её свободно нельзя, поэтому Shellbit её не скачивает. Если у вас есть этот файл, нажмите «Добавить файлы BIOS…» и выберите его — Shellbit скопирует его к себе. Или положите его в ту же папку, что и игра.") % [
				ArcadeNames.bios_title(arcade_bios), arcade_bios + ".zip"]
		return tr("Этой игре нужен BIOS автомата %s — файл %s.\n\nЭто «прошивка» самого игрового автомата, раздавать её свободно нельзя, поэтому Shellbit её не скачивает. Положите %s в ту же папку, что и игра:\n%s") % [
			ArcadeNames.bios_title(arcade_bios), arcade_bios + ".zip", arcade_bios + ".zip", _bios_folder]
	if _missing_bios and not Platform.can_open_folders():
		return tr("Для дисков %s нужен BIOS %s.\n\nShellbit не может скачать его сам: это программа из самой приставки, раздавать её свободно нельзя. Если у вас есть этот файл, нажмите «Добавить файлы BIOS…» и выберите его — Shellbit скопирует его к себе.") % [
			tr(system.get("name", "")) + " CD", missing]
	if _missing_bios:
		return tr("Для дисков %s нужен BIOS %s.\n\nShellbit не может скачать его сам: это программа из самой приставки, раздавать её свободно нельзя. Если у вас есть этот файл, положите его в папку BIOS:\n%s") % [
			tr(system.get("name", "")) + " CD", missing, ProjectSettings.globalize_path(CoreManager.SYSTEM_DIR)]

	core = ClassDB.instantiate("RetroCore")
	add_child(core)
	# На каком языке ядру описывать свои настройки (если у него есть перевод).
	if core.has_method("set_language"):
		core.set_language(RETRO_LANGUAGES.get(Lang.language, 0))
	core.set_system_directory(_native(ProjectSettings.globalize_path(CoreManager.SYSTEM_DIR)))
	# Сохранения самой игры — в папку текущего игрока (autoload/Profiles.gd).
	var saves := ProjectSettings.globalize_path(Profiles.saves_dir())
	DirAccess.make_dir_recursive_absolute(saves)
	core.set_save_directory(_native(saves))

	if not core.load_core(core_path):
		return tr("Ядро %s не загрузилось (подробности — во вкладке Output).") % core_path.get_file()
	# Настройки ядра, которые человек поменял (Пауза → Настройки ядра).
	# Отдаём их ДО загрузки игры: многие ядра читают настройки при запуске.
	var saved_options := Settings.get_section(_options_section())
	for key: String in saved_options:
		core.set_option(key, str(saved_options[key]))
	# Игра со световым пистолетом (scenes/player/LightGun.gd)? Тогда ядру —
	# «пистолет с прицелом» и без своего крестика: прицел рисуем мы.
	# has_method — на случай старого shellbit_core, собранного до пистолета.
	var gun_port := LightGun.port_for(game) if core.has_method("set_lightgun") else -1
	if gun_port >= 0:
		var gun_options := LightGun.core_options(game)
		for key: String in gun_options:
			core.set_option(key, gun_options[key])

	# С какого диска начать: на каком сохранились в этот слот,
	# а если не знаем — какой выбрал человек. Ядро должно узнать это ДО load_game.
	var disc: Dictionary = SaveStates.disc_of(game, start_slot) if start_slot != "" else {}
	if disc.is_empty():
		disc = _start_disc
	var can_swap: bool = core.has_method("set_initial_disk")
	if can_swap and not disc.is_empty():
		core.set_initial_disk(disc["index"], _native(disc["path"]))
	if not core.load_game(_native(_content_path)):
		# Ядро просило видеокарту (OpenGL), а она не дала? Это другая беда —
		# файл игры тут ни при чём, так и говорим.
		var hw_error: String = core.get_hw_error() if core.has_method("get_hw_error") else ""
		if hw_error != "":
			return tr("Этой приставке нужна видеокарта с OpenGL 3.3, но запустить его не вышло:\n%s\n\nОбновите драйвер видеокарты.") % hw_error
		return tr("Ядро не смогло открыть файл игры:\n%s") % game["path"]
	# Ядро не умеет «начать с диска N»? Тогда меняем диск сразу после запуска.
	if can_swap and not disc.is_empty() and core.get_disk_count() > 1 \
			and core.get_disk_index() != disc["index"]:
		core.set_disk(disc["index"])
	_setup_analog()
	_apply_cheats()  # включённые читы — сразу с первого кадра
	_has_rumble = core.has_method("get_rumble")
	if gun_port >= 0:
		_gun = LightGun.new()
		%Screen.add_child(_gun)  # поверх картинки игры, ровно по её размеру
		if _gun.plug_in(core, gun_port):
			_gun.set_active(true)
		else:
			_gun.queue_free()  # ядро не знает Zapper — играем без пистолета
			_gun = null
	if _touch_pad != null:
		_touch_pad.configure(game["system"], _gun != null)

	# Сведения о картинке и звуке: размер, пропорции, кадры/с, частота звука.
	var av: Dictionary = core.get_av_info()
	print("Запущено ядро: ", core.get_system_info(), " | ", av)
	_core_aspect = av["aspect"]
	_frame_time = 1.0 / float(av["fps"])

	# Звук: генератор, в который мы сами подкладываем звуковые кадры.
	var generator := %Audio.stream as AudioStreamGenerator
	generator.mix_rate = av["sample_rate"]
	%Audio.play()
	_playback = %Audio.get_stream_playback()
	# Пустой буфер — это сколько звука он вмещает. Сразу заполняем его
	# тишиной до нормы (40%): так у звука с первого кадра есть запас.
	_sync.capacity = _playback.get_frames_available()
	_sync.reset()
	var silence := PackedVector2Array()
	silence.resize(int(_sync.capacity * AudioSync.TARGET_FILL))
	_playback.push_buffer(silence)

	# Продолжаем с того места, где вышли в прошлый раз.
	# Подсказка при запуске: как открыть меню.
	var hint := tr("Esc — меню") if InputMapper.style == "keyboard" else tr("Правый стик — меню")
	var touch := TouchGamepad.wanted()
	if touch:
		hint = tr("❚❚ — меню")
	# Аркада: игра ждёт «монету», как настоящий автомат. Подсказываем, где она.
	if game.get("system", "") == "arcade" and not touch:
		var keyboard := InputMapper.style == "keyboard"
		hint += " · " + tr("Монета — %s, старт — %s") % [
			"Shift" if keyboard else InputMapper.glyph("back"),
			"Enter" if keyboard else InputMapper.glyph("start")]
	if _gun != null and touch:
		hint += " · " + tr("Стрелять — касанием экрана")
	elif _gun != null:
		hint += " · " + tr("Целиться — мышью или стиком, стрелять — левой кнопкой мыши, RT или RB")
	elif LightGun.port_for(game) >= 0:
		# Игра с пистолетом, а модуль shellbit_core собран до пистолета —
		# не молчим, а говорим, что делать (иначе непонятно, куда делся прицел).
		var script := "native\\build.bat" if OS.get_name() == "Windows" else "native/build.sh"
		_show_notice(tr("Для светового пистолета нужен новый модуль shellbit_core. Закройте Godot, запустите %s и откройте проект снова.") % script)
	if start_slot != "" and SaveStates.load_slot(core, game, start_slot):
		if start_slot == SaveStates.AUTO:
			SceneRouter.toast(tr("Продолжаем с места выхода") + " · " + hint)
		else:
			SceneRouter.toast(tr("Загружен слот %s") % start_slot + " · " + hint)
	elif start_slot == "":
		SceneRouter.toast(tr("Новая игра") + " · " + hint)  # «Начать заново»
	else:
		SceneRouter.toast(hint)
	return ""


func _process(delta: float) -> void:
	var playing: bool = core != null and core.is_running() and not _paused
	if _touch_pause != null:
		_touch_pause.visible = playing
	if _touch_pad != null:
		_touch_pad.visible = playing and TouchGamepad.wanted()
	# Скриншот работает и в игре, и в меню паузы — поэтому проверяем
	# его до строчки, которая на паузе останавливает всё остальное.
	if core != null and Input.is_action_just_pressed("screenshot"):
		_take_screenshot()

	if core == null or not core.is_running() or _paused:
		return

	# Детский режим с лимитом времени: считаем, пока игра идёт (пауза не в счёт).
	if Family.limit_active():
		_count_kids_time(delta)
		if core == null:
			return  # время вышло — игра уже закрыта

	# Раскладка кнопок — своя для каждой приставки (Настройки → Управление).
	var mask0: int = InputMapper.get_retropad_mask(0, game["system"])
	var mask1: int = InputMapper.get_retropad_mask(1, game["system"])
	if _touch_pad != null:
		mask0 |= _touch_pad.mask()  # экранный геймпад — тоже первый игрок
	var raw0 := mask0  # нажатия как есть — для проверки комбинации

	# Select работает как «модификатор»: пока он зажат, Start не уходит
	# в игру. Так Select + Start открывает НАШЕ меню, а не паузу в игре.
	if mask0 & (1 << InputMapper.PAD_SELECT):
		mask0 &= ~(1 << InputMapper.PAD_START)

	if _wait_release:
		# Ждём, пока всё отпущено; до этого игра не получает нажатий.
		if mask0 == 0 and mask1 == 0 and not Input.is_action_pressed("game_menu"):
			_wait_release = false
		mask0 = 0
		mask1 = 0
	elif _wants_menu(raw0):
		_open_menu()
		return

	# Перемотка и ускорение. Пока ждём отпускания кнопок после меню — ни то ни другое.
	var system_id: String = game["system"]
	var rewinding := _tape_max > 0 and not _wait_release \
			and (InputMapper.is_hotkey_pressed(system_id, "rewind") \
				or (_touch_pad != null and _touch_pad.hotkey_held("rewind")))
	var speed := 1 if rewinding or _wait_release else _fast_forward_speed(system_id)

	# Что делать потоку эмуляции: какие кнопки нажаты, ускорение, перемотка.
	# Целиком заменяем словарь под замком — поток всегда видит
	# «согласованный» набор, а не половину старого и половину нового.
	_shared_lock.lock()
	_cmd = {
		"mask0": 0 if rewinding else mask0,
		"mask1": 0 if rewinding else mask1,
		"speed": speed,
		"rewinding": rewinding,
		"sticks": _touch_sticks(_read_sticks(system_id, rewinding or _wait_release)),
		# Пистолет: [порт, x, y, курок, выстрел мимо экрана] — или пусто.
		"gun": [_gun.port] + _gun.aim(delta, rewinding or _wait_release) if _gun != null else [],
	}
	_shared_lock.unlock()

	if _thread == null:
		# Потока нет (автотесты подставляют своё ядро) — считаем кадры здесь.
		_emulate(delta)

	_update_speed_label(rewinding, speed)
	_update_rumble(rewinding)
	_show_frame()


# =====================================================================
# Поток эмуляции
# =====================================================================
#
# Thread — отдельная «нить» выполнения: она идёт ОДНОВРЕМЕННО с главной,
# на другом ядре процессора. Главная нить рисует экран и читает кнопки,
# наша — в цикле считает кадры приставки (_emulation_loop).
#
# Главное правило потоков: две нити не должны одновременно трогать одно
# и то же. Иначе одна, например, сохраняет игру в слот, а другая в этот
# момент меняет память приставки — сохранение выйдет испорченным.
# Поэтому есть «замки» — Mutex. lock() — «занято, жди»; unlock() — «свободно».
#   _core_lock   — на ядро: кадр, сохранение, загрузка, смена диска;
#   _shared_lock — на обмен данными: команды (_cmd), картинка, вибрация.

var _thread: Thread              # null — поток не запущен
var _stop_thread := false        # просьба потоку закончить работу
var _core_lock := Mutex.new()
var _shared_lock := Mutex.new()
## Команды потоку (пишет главный поток в _process).
var _cmd := {"mask0": 0, "mask1": 0, "speed": 1, "rewinding": false, "sticks": []}
var _new_image: Image            # свежая картинка от потока (забирает _show_frame)
var _rumble_now: Array = [Vector2.ZERO, Vector2.ZERO]  # какую вибрацию хочет игра


func _start_emulation() -> void:
	if _thread != null or core == null:
		return
	# Некоторым ядрам нужен ОДИН поток на всё: и запуск игры, и кадры.
	# Ядро Nintendo 64 (mupen64plus-next) внутри устроено на «сопрограммах»
	# (библиотека libco): при запуске оно создаёт вторую «нить» исполнения
	# и потом прыгает между ней и основной. В Windows такие прыжки работают
	# только в том потоке, где «нить» создали, — то есть в главном, где
	# игра запускалась. Прыжок из нашего потока эмуляции = вылет программы.
	# (В Linux libco устроена иначе — там это работало, поэтому ошибку
	# не поймали автотесты.) Таким ядрам — без отдельного потока: кадры
	# считает главный поток в _process, как было раньше.
	if CoreManager.get_system(game.get("system", "")).get("one_thread", false):
		return
	_stop_thread = false
	_thread = Thread.new()
	_thread.start(_emulation_loop)


## Остановить поток и дождаться, пока он закончит кадр.
## Нужно перед выгрузкой ядра: иначе поток обратился бы к ядру, которого уже нет.
func _stop_emulation() -> void:
	if _thread == null:
		return
	_stop_thread = true
	_thread.wait_to_finish()  # ждём, пока цикл в потоке увидит просьбу и выйдет
	_thread = null


## Цикл потока эмуляции. Работает, пока не попросят остановиться.
func _emulation_loop() -> void:
	var last := Time.get_ticks_usec()  # микросекунды — точнее, чем миллисекунды
	while not _stop_thread:
		var now := Time.get_ticks_usec()
		var delta := (now - last) / 1000000.0
		last = now
		if _paused:
			OS.delay_msec(5)  # меню паузы — просто ждём, не тратя процессор
			continue
		_emulate(delta)
		# Спим до следующего кадра приставки. На 1 мс меньше, чем нужно:
		# сон в Windows бывает неточным, а проспать кадр хуже, чем проснуться
		# чуть раньше (тогда цикл просто пройдёт ещё раз, ничего не посчитав).
		var wait := int((_frame_time - _time_bank) * 1000000.0) - 1000
		if wait > 0:
			OS.delay_usec(mini(wait, 20000))


## Посчитать кадры приставки, которые «положены» за delta секунд, и
## отдать звук. Вызывается в потоке эмуляции (или в _process, если потока нет).
## Здесь нельзя трогать узлы интерфейса — только ядро и свои переменные.
func _emulate(delta: float) -> void:
	_shared_lock.lock()
	var cmd := _cmd
	_shared_lock.unlock()
	var speed: int = cmd["speed"]
	var rewinding: bool = cmd["rewinding"]

	_core_lock.lock()
	if not core.is_running():
		_core_lock.unlock()
		return
	core.set_input(0, cmd["mask0"])
	core.set_input(1, cmd["mask1"])
	var sticks: Array = cmd["sticks"]
	for i in sticks.size():
		core.set_analog(i / 2, i % 2, sticks[i].x, sticks[i].y)
	var gun: Array = cmd.get("gun", [])
	if gun.size() == 5:
		core.set_lightgun(gun[0], gun[1], gun[2], gun[3], gun[4])

	# Монитор может обновляться 60, 75 или 144 раза в секунду, а NES
	# всегда работает на ~60 кадрах. Поэтому копим прошедшее время и
	# просчитываем столько кадров приставки, сколько «положено».
	# При ускорении ×3 за каждый «положенный» кадр просчитываем три.
	_time_bank += delta
	var due := 0  # сколько кадров приставки «положено» посчитать сейчас
	while _time_bank >= _frame_time and due < 3:
		_time_bank -= _frame_time
		due += 1
	if due == 3:
		_time_bank = 0.0  # компьютер не успевает — не пытаемся догнать

	# Синхронизация по звуку: если буфер звука почти пуст — досчитываем
	# кадр (иначе щелчок), если почти полон — этот кадр пропускаем.
	# При ускорении и перемотке не нужно: там звук и так урезан.
	if not rewinding and speed == 1 and _playback != null:
		due = maxi(0, due + _sync.extra_frames(_audio_fill()))

	for slot in due:
		if rewinding:
			_rewind_step()
		else:
			for i in speed:
				_run_frame()

	var image: Image = core.get_frame() if core.has_new_frame() else null
	_push_audio(speed, rewinding)
	var rumble: Array = [core.get_rumble(0), core.get_rumble(1)] if _has_rumble else [Vector2.ZERO, Vector2.ZERO]
	_core_lock.unlock()

	# Картинку и вибрацию отдаём главному потоку — он их покажет.
	_shared_lock.lock()
	if image != null:
		_new_image = image  # ядро каждый кадр делает новую картинку — можно отдать как есть
	_rumble_now = rumble
	_shared_lock.unlock()


## Показать свежую картинку от потока эмуляции, если она есть.
func _show_frame() -> void:
	_shared_lock.lock()
	var image := _new_image
	_new_image = null
	_shared_lock.unlock()
	if image == null:
		return  # новой картинки нет — на экране остаётся прошлая
	if _texture == null or _texture.get_size() != Vector2(image.get_size()):
		_texture = ImageTexture.create_from_image(image)  # первый кадр или новый размер
		%Screen.texture = _texture
		_apply_video()  # размер кадра известен — можно расставить картинку
	else:
		_texture.update(image)  # быстро: просто обновить пиксели


# --- Лимит времени в детском режиме (autoload/Family.gd) ----------------------

func _count_kids_time(delta: float) -> void:
	var before := Family.seconds_left()
	Family.add_play_time(delta)
	var left := Family.seconds_left()
	# Предупреждаем один раз — в тот кадр, когда «перешли черту».
	if before > 300.0 and left <= 300.0:
		Haptics.confirm()
		SceneRouter.toast(tr("Осталось 5 минут игры на сегодня"))
	elif before > 60.0 and left <= 60.0:
		Haptics.confirm()
		SceneRouter.toast(tr("Осталась 1 минута — потом игра сохранится и закроется"))
	if left <= 0.0:
		_time_up()


## Время вышло: сохраняем место выхода и закрываем игру, как «Выйти в библиотеку».
## Завтра (или после PIN взрослого) игра продолжится с этого места.
func _time_up() -> void:
	Haptics.error()
	SceneRouter.toast(tr("Время игры на сегодня закончилось. Игра сохранена."))
	_exit_game()


# --- Скриншот ------------------------------------------------------------------

## Сохранить кадр игры в «Изображения\Shellbit».
## Берём чистый кадр приставки — без меню паузы, подсказок и сообщений.
func _take_screenshot() -> void:
	if _texture == null:
		return  # игра ещё не показала ни одного кадра
	# get_image() — копия пикселей текстуры. Это маленькая картинка
	# приставки, например 256×240.
	var image := _texture.get_image()

	# Увеличиваем до размера, который был на экране (с пропорциями и масштабом
	# из настроек). INTERPOLATE_NEAREST — без сглаживания: пиксели остаются
	# чёткими квадратами, как в игре.
	var shown := Vector2i(%AspectBox.size)
	if shown.x > 0 and shown.y > 0:
		image.resize(shown.x, shown.y, Image.INTERPOLATE_NEAREST)

	# Имя файла: «Battletoads 2026-10-19 16-23-05.png». По нему галерея
	# на странице игры узнаёт, чей это снимок (scripts/Screenshots.gd).
	var file_name := Screenshots.file_name(game.get("title", "Shellbit"))
	var folder := Settings.screenshots_dir()
	DirAccess.make_dir_recursive_absolute(folder)  # создать папку, если её ещё нет

	if image.save_png(folder.path_join(file_name)) == OK:
		_flash()
		SceneRouter.toast(tr("Скриншот сохранён: %s") % file_name)
	else:
		SceneRouter.toast(tr("Не удалось сохранить скриншот"))


# Короткая белая вспышка, как у фотоаппарата: понятно, что снимок сделан.
func _flash() -> void:
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.5)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.0, 0.25)
	tween.tween_callback(flash.queue_free)


# --- Видеонастройки (раздел «Видео» в настройках) ----------------------------

## Фильтр и поля по бокам.
func _apply_video() -> void:
	var filter: String = Settings.get_value("video", "filter")
	# NEAREST — пиксели остаются чёткими квадратами, LINEAR — сглаживаются.
	%Screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if filter == "smooth" \
			else CanvasItem.TEXTURE_FILTER_NEAREST
	match filter:
		"crt":
			%Screen.material = _shader_material(CRT_SHADER)
		"lcd":
			%Screen.material = _shader_material(LCD_SHADER)
		_:
			%Screen.material = null

	# Размытый кадр по бокам: та же текстура, но со своим шейдером размытия.
	# ImageTexture.update() меняет пиксели в той же текстуре,
	# поэтому фон обновляется вместе с игрой сам.
	%Backdrop.visible = Settings.get_value("video", "sides") == "blur"
	%Backdrop.texture = _texture
	_apply_layout()


func _shader_material(shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


## Где и какого размера картинка: пропорции и масштаб.
func _apply_layout() -> void:
	if _texture == null:
		return
	var frame := Vector2(_texture.get_size())  # размер кадра приставки, например 256×240
	var area := size                           # размер экрана

	# Пропорции картинки (ширина / высота).
	var ratio := _core_aspect
	match Settings.get_value("video", "aspect"):
		"square":
			ratio = frame.x / frame.y  # каждый пиксель квадратный
		"stretch":
			ratio = area.x / area.y    # как у экрана — без полей

	var box := Vector2.ZERO
	if Settings.get_value("video", "scale") == "integer" and Settings.get_value("video", "aspect") != "stretch":
		# Целые пиксели: высота кадра × целое число (2, 3, 4…).
		# Берём самое большое число, при котором картинка влезает в экран.
		var factor := floorf(area.y / frame.y)
		while factor > 1.0 and frame.y * factor * ratio > area.x:
			factor -= 1.0
		factor = maxf(factor, 1.0)
		box = Vector2(frame.y * factor * ratio, frame.y * factor)
	else:
		# Во весь экран: как можно больше, но с нужными пропорциями.
		box = area
		if area.x / area.y > ratio:
			box.x = area.y * ratio  # экран шире картинки — поля по бокам
		else:
			box.y = area.x / ratio  # экран уже — поля сверху и снизу

	# Ставим рамку с картинкой по центру экрана.
	%AspectBox.set_anchors_preset(Control.PRESET_TOP_LEFT)
	%AspectBox.ratio = box.x / box.y
	%AspectBox.position = ((area - box) / 2.0).round()
	%AspectBox.size = box.round()


func _push_audio(speed := 1, rewinding := false) -> void:
	var frames: PackedVector2Array = core.take_audio()
	if frames.is_empty() or _playback == null or rewinding:
		return  # при перемотке звук не играем — назад он звучит странно
	if speed > 1:
		# Звука в speed раз больше, чем успеют проиграть динамики.
		# Оставляем только последний кусочек — звук прерывистый, но слышен.
		frames = frames.slice(frames.size() - frames.size() / speed)
	else:
		# Обычная скорость: чуть растягиваем или сжимаем звук, чтобы буфер
		# оставался заполненным на 40% (см. scripts/AudioSync.gd).
		var current_fill := _audio_fill()
		if current_fill <= 0.0:
			_sync.underruns += 1  # звук успел кончиться — был щелчок
		frames = _sync.resample(frames, _sync.ratio(current_fill))
	var room := _playback.get_frames_available()
	if frames.size() > room:
		frames = frames.slice(0, room)  # буфер полон — лишнее выбрасываем
	_playback.push_buffer(frames)


## Насколько заполнен буфер звука: 0 — пуст, 1 — полон.
func _audio_fill() -> float:
	return _sync.fill(_playback.get_frames_available())


func _wants_menu(mask: int) -> bool:
	if Input.is_action_just_pressed("game_menu"):
		return true
	# Select + Start одновременно на первом геймпаде.
	var combo := (1 << InputMapper.PAD_SELECT) | (1 << InputMapper.PAD_START)
	return mask & combo == combo


# --- Меню паузы ------------------------------------------------------------

## Android: приложение свернули (звонок, кнопка «Домой», другое приложение).
## Свёрнутое приложение Android может закрыть в любой момент без
## предупреждения — поэтому сразу ставим игру на паузу и сохраняем место
## выхода. Вернулись — видим меню паузы, «Продолжить» — и играем дальше.
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_PAUSED:
		return
	if core == null or not core.is_running():
		return
	if not _paused:
		_open_menu()
	Family.save_play_time()
	_core_lock.lock()
	SaveStates.save_slot(core, game, SaveStates.AUTO)
	_core_lock.unlock()


func _open_menu() -> void:
	_paused = true
	_update_rumble(true)  # на паузе геймпад не трясётся
	_speed_label.visible = false
	# Записываем внутриигровые сохранения на диск (на случай, если
	# программу потом закроют неаккуратно). Замок: поток эмуляции может
	# как раз досчитывать кадр — ждём его, а потом сохраняем.
	_core_lock.lock()
	core.save_sram()
	_core_lock.unlock()
	%Audio.stream_paused = true  # звук замирает вместе с игрой
	if _gun != null:
		_gun.set_active(false)  # в меню — обычный курсор мыши вместо прицела
	# Читы: у старого модуля (без cheat_set) кнопку оставляем — окно
	# подскажет пересобрать модуль. Прячем, только если само ядро не умеет.
	var has_cheats: bool = not core.has_method("has_cheats") or core.has_cheats()
	%PauseMenu.open(game, _disc_info(), core.has_method("get_option_list"), has_cheats)


func _resume() -> void:
	%PauseMenu.close()
	%Audio.stream_paused = false
	_time_bank = 0.0  # время, проведённое в меню, не «догоняем»
	_wait_release = true
	_paused = false
	if _gun != null:
		_gun.set_active(true)


# --- Настройки ядра -----------------------------------------------------------

# --- Читы ----------------------------------------------------------------------
# Какие коды включены — помнит autoload Cheats, окно — CheatsPanel.
# Ядру передаём всегда ВЕСЬ список включённых: сначала cheat_reset()
# («забудь все»), потом каждый код по номеру 0, 1, 2… Так проще, чем
# помнить, какой чит под каким номером и что выключили.

var _cheats_panel := CheatsPanel.new()


func _open_cheats() -> void:
	_cheats_panel.open(game, core.has_method("cheat_set"))


func _on_cheats_changed() -> void:
	_core_lock.lock()  # поток эмуляции на паузе стоит, но замок — правило
	_apply_cheats()
	_core_lock.unlock()


## Передать ядру включённые коды. Вызывать под _core_lock (или до запуска потока).
func _apply_cheats() -> void:
	if not core.has_method("cheat_set") or not core.has_cheats():
		return  # старый модуль или ядро без читов
	core.cheat_reset()
	var codes := Cheats.enabled_codes(game)
	for i in codes.size():
		core.cheat_set(i, true, codes[i])
	if not codes.is_empty():
		print("Читы включены: ", codes)


## Номера языков из libretro.h (RETRO_LANGUAGE_*): ядро опишет
## свои настройки на этом языке, если у него есть перевод.
const RETRO_LANGUAGES := {"en": 0, "ja": 1, "fr": 2, "es": 3, "de": 4,
		"pt": 7, "ru": 9, "ko": 10, "zh": 12}

var _options_panel := CoreOptionsPanel.new()


## Раздел settings.cfg для настроек этого ядра: «core_pcsx_rearmed».
## Без .dll/.so — чтобы настройки были общими для Windows и Linux.
func _options_section() -> String:
	var file := CoreManager.core_path(CoreManager.get_system(game.get("system", ""))).get_file()
	return "core_" + file.get_basename().trim_suffix("_libretro")


func _open_core_options() -> void:
	_core_lock.lock()
	var options: Array = core.get_option_list()
	var core_name: String = core.get_system_info().get("name", "")
	_core_lock.unlock()
	_options_panel.open(options, _options_section(), core_name)


## Поменяли настройку. Ядро узнает о ней на следующем кадре
## (оно само спрашивает «поменялось ли что-нибудь?»).
func _on_option_changed(key: String, value: String) -> void:
	_core_lock.lock()
	core.set_option(key, value)
	# Ядро может спрятать или показать зависимые настройки.
	var changed: bool = core.refresh_option_display()
	var options: Array = core.get_option_list() if changed else []
	_core_lock.unlock()
	if changed:
		_options_panel.update_visibility(options)


## «Вернуть всё как было»: стираем сохранённое и отдаём ядру его умолчания.
func _on_options_reset() -> void:
	var section := _options_section()
	for key: String in Settings.get_section(section):
		Settings.set_value(section, key, null)
	_core_lock.lock()
	var options: Array = core.get_option_list()
	for option: Dictionary in options:
		core.set_option(option["key"], option["default"])
	core.refresh_option_display()
	options = core.get_option_list()
	_core_lock.unlock()
	_options_panel.refresh_values()
	_options_panel.update_visibility(options)
	SceneRouter.toast(tr("Настройки ядра — как в самом начале"))


# --- Диски ------------------------------------------------------------------

## С какого диска начинать, если про слот ничего не известно:
## {"index": 1, "path": "…(Disc 2).cue"} — когда человек выбрал второй диск.
var _start_disc: Dictionary = {}


## Сколько у игры дисков и какой вставлен — для меню паузы. {} — один диск.
func _disc_info() -> Dictionary:
	if core == null or not core.has_method("get_disk_count"):
		return {}
	_core_lock.lock()
	var info := {"count": core.get_disk_count(), "index": core.get_disk_index()}
	_core_lock.unlock()
	return info if info["count"] > 1 else {}


## «Сменить диск» → выбрали диск index (с нуля).
func _on_disc_requested(index: int) -> void:
	_core_lock.lock()
	var same: bool = index == core.get_disk_index()
	var swapped: bool = not same and core.set_disk(index)
	_core_lock.unlock()
	if same:
		_resume()  # выбрали тот же диск — просто возвращаемся в игру
		return
	if swapped:
		# Лента перемотки — с прошлого диска. Отмотать туда нельзя: игра
		# увидела бы старые данные на новом диске. Начинаем ленту заново.
		_setup_rewind()
		_resume()
		SceneRouter.toast(tr("Вставлен диск %d") % (index + 1))
	else:
		SceneRouter.toast(tr("Не удалось сменить диск"))


func _on_save_requested(slot: String) -> void:
	_core_lock.lock()
	var saved := SaveStates.save_slot(core, game, slot)
	_core_lock.unlock()
	if saved:
		SceneRouter.toast(tr("Сохранено в слот %s") % slot)
		Haptics.tap()
	else:
		SceneRouter.toast(tr("Это ядро не умеет сохранять состояние"))
	%PauseMenu.refresh_slots()


func _on_load_requested(slot: String) -> void:
	_core_lock.lock()
	var loaded := SaveStates.load_slot(core, game, slot)
	_core_lock.unlock()
	if loaded:
		_setup_rewind()  # старая «лента» — от другого места игры
		_resume()
		SceneRouter.toast(tr("Загружен слот %s") % slot)
	else:
		SceneRouter.toast(tr("Не удалось загрузить слот %s") % slot)


func _restart() -> void:
	# Самый надёжный «сброс» — заново загрузить ядро и игру,
	# но без автосохранения. Сначала останавливаем поток эмуляции.
	_stop_emulation()
	core.unload()
	core.queue_free()
	_texture = null
	var error := _start_game("")
	if error != "":
		_paused = true
		%PauseMenu.close()
		_show_error(error)
		return
	_setup_rewind()
	_start_emulation()
	_resume()


func _exit_game() -> void:
	Family.save_play_time()  # наигранное в детском режиме — в файл
	if _sync.underruns > 0:
		print("Звук прерывался %d раз(а) за игру" % _sync.underruns)
	_update_rumble(true)
	_stop_emulation()  # поток больше не нужен — и не помешает сохранению
	# Автосохранение: при следующем запуске продолжим отсюда.
	SaveStates.save_slot(core, game, SaveStates.AUTO)
	var seconds := (Time.get_ticks_msec() - _start_msec) / 1000
	Library.add_playtime(game, seconds)
	core.unload()
	core = null
	SceneRouter.back()


## Путь «как принято в системе». Godot везде пишет «/» (D:/Games/mslug.zip),
## а в Windows родной разделитель — «\» (D:\Games\mslug.zip). Большинству ядер
## всё равно, но некоторые ищут папку игры по последнему «\». Аркадное ядро
## FBNeo так ищет архивы (neogeo.zip) рядом с игрой — и с «/» не находило
## ни одного: «None of those archives was found in your paths».
## Поэтому ядрам отдаём пути с «\» — как RetroArch.
static func _native(path: String) -> String:
	return path.replace("/", "\\") if OS.get_name() == "Windows" else path


## BIOS автомата, которого не хватает аркадной игре ("" — не нужен или на месте).
## FBNeo ищет его рядом с игрой и в папке system/fbneo — проверяем там же.
func _missing_arcade_bios() -> String:
	if game.get("system", "") != "arcade" or not ArcadeNames.knows(_content_path):
		return ""
	var bios := ArcadeNames.bios_of(_content_path)
	if bios == "":
		return ""
	var places := [_content_path.get_base_dir(), ProjectSettings.globalize_path(CoreManager.SYSTEM_DIR.path_join("fbneo"))]
	for folder: String in places:
		for extension in ["zip", "7z"]:
			if FileAccess.file_exists(folder.path_join(bios + "." + extension)):
				return ""
	return bios


## BIOS для дисков, которого нет в папке system ("" — всё на месте или это не диск).
func _missing_disc_bios(system: Dictionary) -> String:
	if not _content_path.get_extension().to_lower() in Library.DISC_EXTENSIONS:
		return ""  # картридж — BIOS для дисков не нужен
	for bios: String in system.get("disc_bios", []):
		if not FileAccess.file_exists(CoreManager.SYSTEM_DIR.path_join(bios)):
			return bios
	return ""


func _show_error(text: String) -> void:
	# Ядро могло загрузиться, а игра — нет. Выключаем ядро, иначе экран
	# будет считать, что игра идёт, и кнопка «Назад» не сработает.
	_stop_emulation()
	if core != null:
		core.unload()
		core.queue_free()
		core = null
	%ErrorText.text = text
	%Error.visible = true
	%Hints.visible = true
	%Hints.set_hints([["accept", "Выбрать"], ["cancel", "Назад"]])
	# Нет ядра — главная кнопка «Скачать ядро».
	%DownloadButton.visible = _missing_core
	%DownloadButton.text = tr("Скачать ядро")
	%DownloadButton.disabled = false
	%OpenCoresButton.text = tr("Открыть папку BIOS") if _missing_bios else tr("Открыть папку ядер")
	if not Platform.can_open_folders():
		# Android: папки не открыть. BIOS — выбрать файлы; ядро — только скачать.
		%OpenCoresButton.text = tr("Добавить файлы BIOS…")
		%OpenCoresButton.visible = _missing_bios
	if _missing_core:
		%DownloadButton.grab_focus()
	else:
		%OpenCoresButton.grab_focus()


# Надпись по центру экрана («Распаковываю игру…»); "" — спрятать.
func _show_status(text: String) -> void:
	if _status_label == null:
		_status_label = Label.new()
		_status_label.theme_type_variation = &"HeaderLabel"
		_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_status_label)
		_status_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_status_label.text = text
	_status_label.visible = text != ""


# --- Скачивание ядра с экрана ошибки --------------------------------------------

func _core_file() -> String:
	return CoreManager.core_path(CoreManager.get_system(game.get("system", ""))).get_file()


func _download_core() -> void:
	CoreDownloader.download(CoreManager.get_system(game["system"]))
	%DownloadButton.text = tr("Скачиваю…")
	%DownloadButton.disabled = true  # второй раз не нажмёшь
	%OpenCoresButton.grab_focus()


func _on_core_progress(core_file: String, percent: int) -> void:
	if core_file == _core_file() and percent >= 0:
		%DownloadButton.text = tr("Скачиваю…") + " %d %%" % percent


# Android: выбрать файлы BIOS, скопировать к себе (CoreManager.import_bios)
# и сразу попробовать запустить игру ещё раз.
var _bios_dialog: FileDialog


func _pick_bios_files() -> void:
	if _bios_dialog == null:
		_bios_dialog = FileDialog.new()
		_bios_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
		_bios_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_bios_dialog.title = tr("Файлы BIOS")
		Platform.setup_file_dialog(_bios_dialog)
		add_child(_bios_dialog)
		_bios_dialog.files_selected.connect(func(paths: PackedStringArray) -> void:
			var copied := CoreManager.import_bios(paths)
			SceneRouter.toast(tr("Скопировано файлов BIOS: %d") % copied)
			if copied > 0:
				%Error.visible = false
				%Hints.visible = false
				_begin())
		_bios_dialog.canceled.connect(%OpenCoresButton.grab_focus)
	_bios_dialog.popup_centered_ratio(0.8)


func _on_core_finished(core_file: String, ok: bool, message: String) -> void:
	if core_file != _core_file() or not %Error.visible:
		return
	if ok:
		# Ядро на месте — прячем ошибку и запускаем игру ещё раз.
		%Error.visible = false
		%Hints.visible = false
		SceneRouter.toast(tr("Ядро %s скачано") % core_file)
		_begin()
	else:
		_show_error(tr("Не удалось скачать ядро %s: %s") % [core_file, message])


func _unhandled_input(event: InputEvent) -> void:
	# Пока игра идёт, ui_cancel (B) — это кнопка игры, а не «Назад».
	if core == null and event.is_action_pressed("ui_cancel"):
		SceneRouter.back()
		get_viewport().set_input_as_handled()


# Если окно закрыли прямо во время игры — сохраняемся и выключаем ядро.
func _exit_tree() -> void:
	_update_rumble(true)
	_stop_emulation()
	if core != null:
		SaveStates.save_slot(core, game, SaveStates.AUTO)
		core.unload()


# =====================================================================
# Ускорение и перемотка
# =====================================================================
#
# УСКОРЕНИЕ: за один кадр экрана просчитываем не один кадр приставки,
# а несколько (×2, ×3…). Показываем только последний.
#
# ПЕРЕМОТКА: «играть назад» компьютер не умеет. Поэтому каждые несколько
# кадров мы делаем быстрое сохранение (снимок всей памяти приставки)
# и складываем снимки на «ленту». Пока зажата кнопка перемотки, берём
# снимки с конца ленты и загружаем их по одному — игра идёт назад.
# Лента ограничена: самые старые снимки выбрасываются.


## Подготовить пустую ленту перемотки под текущую игру.
func _setup_rewind() -> void:
	# Лентой пользуется поток эмуляции — меняем её под замком.
	_core_lock.lock()
	_fill_rewind_settings()
	_core_lock.unlock()


func _fill_rewind_settings() -> void:
	_tape.clear()
	_snap_count = 0
	_tape_max = 0
	var seconds := int(Settings.get_value("play", "rewind_seconds"))
	if seconds <= 0 or core == null:
		return
	# "rewind": false в systems.json — у приставки перемотки нет. Снимок
	# PlayStation 2 весит десятки мегабайт и делается долго: игра бы дёргалась.
	if not CoreManager.get_system(game.get("system", "")).get("rewind", true):
		return
	# Пробный снимок — узнать, сколько весит один.
	var size: int = core.save_state().size()
	if size == 0:
		return  # ядро не умеет сохранять состояние — перемотки не будет
	var frames_total := seconds / _frame_time            # кадров приставки за seconds
	var budget := Settings.REWIND_BUDGET_MB * 1024 * 1024
	var fit := maxi(1, budget / size)                    # сколько снимков влезет в память
	# Снимок не чаще, чем раз в 2 кадра, и не реже, чем нужно, чтобы влезть.
	_snap_every = maxi(2, ceili(frames_total / fit))
	_tape_max = ceili(frames_total / _snap_every)
	print("Перемотка: снимок %d КБ, раз в %d кадров, до %d снимков (%d МБ)" % [
		size / 1024, _snap_every, _tape_max, _tape_max * size / 1024 / 1024])


## Просчитать один кадр приставки и, если пора, положить снимок на ленту.
func _run_frame() -> void:
	core.run_frame()
	if _tape_max == 0:
		return
	_snap_count += 1
	if _snap_count >= _snap_every:
		_snap_count = 0
		_tape.append(core.save_state())
		if _tape.size() > _tape_max:
			_tape.pop_front()  # лента полна — самый старый снимок выбрасываем


## Один шаг назад по ленте.
func _rewind_step() -> void:
	_rewind_wait -= 1
	if _rewind_wait > 0:
		return
	# Идём назад примерно вдвое быстрее, чем шла игра.
	_rewind_wait = maxi(1, _snap_every / 2)
	if _tape.is_empty():
		return
	# Последний (самый старый) снимок не выбрасываем — на нём и «стоим».
	var state: PackedByteArray = _tape.back() if _tape.size() == 1 else _tape.pop_back()
	core.load_state(state)
	core.run_frame()  # чтобы появилась картинка этого момента
	_snap_count = 0


## Во сколько раз ускорить игру сейчас (1 — обычная скорость).
func _fast_forward_speed(system_id: String) -> int:
	var down := InputMapper.is_hotkey_pressed(system_id, "fast_forward")
	if _gun != null:
		# В играх с пистолетом правый курок — это курок пистолета.
		# Ускорение остаётся только на клавиатуре (пробел).
		down = Input.is_physical_key_pressed(InputMapper.HOTKEY_KEYS["fast_forward"])
	if _touch_pad != null and _touch_pad.hotkey_held("fast_forward"):
		down = true  # ▶▶ на экране
	var on := down
	if Settings.get_value("play", "ff_mode") == "toggle":
		if down and not _ff_was_down:  # кнопку только что нажали
			_ff_on = not _ff_on
		on = _ff_on
	_ff_was_down = down
	return int(Settings.get_value("play", "ff_speed")) if on else 1


# --- Кнопка «Пауза» для сенсорного экрана --------------------------------------
# На телефоне без геймпада нет кнопок Start или Select — меню паузы
# открывает эта кнопка в левом верхнем углу (меню выезжает оттуда же,
# слева). Полупрозрачная, чтобы не закрывать игру. Закрывают меню, смахнув
# его влево или тапнув по игре (scenes/pause/PauseMenu.gd).

var _touch_pause: Button
var _touch_pad: TouchGamepad


## Экранный стик (Nintendo 64) — вместо левого стика первого игрока,
## пока его касается палец.
func _touch_sticks(sticks: Array[Vector2]) -> Array[Vector2]:
	if _touch_pad == null or sticks.is_empty():
		return sticks
	var touch := _touch_pad.stick()
	if touch != Vector2.ZERO:
		sticks[0] = touch
	var c_buttons := _touch_pad.stick("cstick")  # C-кнопки Nintendo 64 = правый стик
	if c_buttons != Vector2.ZERO and sticks.size() > 1:
		sticks[1] = c_buttons
	return sticks


func _create_touch_pause() -> void:
	if not Platform.touch_first():
		return  # компьютер или Android TV — там есть клавиатура, геймпад или пульт
	# Экранный геймпад (scenes/player/TouchGamepad.gd) — под кнопкой паузы.
	_touch_pad = TouchGamepad.new()
	add_child(_touch_pad)
	move_child(_touch_pad, %PauseMenu.get_index())
	_touch_pad.configure(game.get("system", ""))
	_touch_pause = Button.new()
	_touch_pause.text = "❚❚"
	_touch_pause.focus_mode = Control.FOCUS_NONE  # геймпаду эта кнопка не нужна
	_touch_pause.custom_minimum_size = Vector2(64, 64)
	_touch_pause.add_theme_font_size_override("font_size", 22)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		_touch_pause.add_theme_color_override(state, Color(1, 1, 1, 0.85))
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0.55 if state == "pressed" else 0.35)
		box.set_corner_radius_all(32)  # круглая
		_touch_pause.add_theme_stylebox_override(state, box)
	add_child(_touch_pause)
	_touch_pause.position = Vector2(20, 20)
	move_child(_touch_pause, %PauseMenu.get_index())  # меню паузы — поверх кнопки
	_touch_pause.pressed.connect(func() -> void:
		if core != null and not _paused:
			_open_menu())


func _create_speed_label() -> void:
	_speed_label = Label.new()
	_speed_label.visible = false
	_speed_label.add_theme_font_size_override("font_size", 22)
	_speed_label.add_theme_color_override("font_color", UiTheme.BG)
	var box := UiTheme.badge_box(UiTheme.ACCENT)
	box.set_corner_radius_all(18)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	_speed_label.add_theme_stylebox_override("normal", box)
	add_child(_speed_label)
	# Значок — в правом верхнем углу. grow влево и вниз: при любой длине
	# текста правый край остаётся на месте.
	_speed_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_speed_label.offset_left = -24
	_speed_label.offset_right = -24
	_speed_label.offset_top = 24
	_speed_label.offset_bottom = 24
	_speed_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	# Меню паузы должно быть поверх значка — ставим значок перед ним.
	move_child(_speed_label, %PauseMenu.get_index())


func _update_speed_label(rewinding: bool, speed: int) -> void:
	if rewinding:
		_speed_label.text = "◀◀"
	elif speed > 1:
		_speed_label.text = "▶▶ ×%d" % speed
	_speed_label.visible = rewinding or speed > 1
