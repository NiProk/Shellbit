extends Control
## Экран игры: запускает ядро libretro через наш C++-узел RetroCore,
## показывает картинку, проигрывает звук и передаёт нажатия кнопок.
##
## Открывается так: SceneRouter.go_to("player", {"game": game})
##
## Меню паузы: правый стик (R3), Select + Start или Esc.
## При выходе игра сохраняется сама, а при следующем запуске
## продолжается с того же места.

const CRT_SHADER := preload("res://scenes/player/crt.gdshader")
const LCD_SHADER := preload("res://scenes/player/lcd.gdshader")

var core: Node  # RetroCore (создаём из кода — см. _start_game)
var game: Dictionary = {}

var _core_aspect := 4.0 / 3.0  # пропорции картинки, которые сообщило ядро

var _texture: ImageTexture
var _playback: AudioStreamGeneratorPlayback
var _frame_time := 1.0 / 60.0  # сколько секунд длится один кадр приставки
var _time_bank := 0.0          # накопленное время, которое ещё не «отыграно»
var _start_msec := 0

var _paused := false
# После закрытия меню ждём, пока игрок отпустит все кнопки.
# Иначе нажатие «A — Продолжить» дошло бы до игры как прыжок,
# а Esc, которым закрыли меню, тут же открыл бы его снова.
var _wait_release := false


func _ready() -> void:
	game = SceneRouter.params.get("game", {})
	%OpenCoresButton.pressed.connect(CoreManager.open_cores_folder)

	# Подписываемся на сигналы меню паузы.
	%PauseMenu.resume_requested.connect(_resume)
	%PauseMenu.restart_requested.connect(_restart)
	%PauseMenu.exit_requested.connect(_exit_game)
	%PauseMenu.save_requested.connect(_on_save_requested)
	%PauseMenu.load_requested.connect(_on_load_requested)
	%PauseMenu.screenshot_requested.connect(_take_screenshot)

	# Окно поменяло размер — пересчитать, где и какого размера картинка.
	resized.connect(_apply_layout)

	# С какого сохранения начать: "auto" — с места выхода (по умолчанию),
	# "1".."3" — с ручного слота (их выбирают на странице игры).
	var error := _start_game(SceneRouter.params.get("slot", SaveStates.AUTO))
	if error != "":
		_show_error(error)
		return

	Library.mark_played(game)
	_start_msec = Time.get_ticks_msec()


## Запустить игру и загрузить сохранение из слота start_slot ("" — с самого начала).
## Возвращает "" если всё хорошо, иначе — текст ошибки.
func _start_game(start_slot: String) -> String:
	if game.is_empty():
		return tr("Не передана игра.")

	# Класс RetroCore появляется, только если C++-модуль собран.
	# Проверяем через ClassDB, чтобы проект открывался и без модуля.
	if not ClassDB.class_exists("RetroCore"):
		return tr("C++-модуль shellbit_core не собран. Запустите native/build.bat и перезапустите Godot.")

	var system := CoreManager.get_system(game["system"])
	var core_path := CoreManager.core_path(system)
	if not FileAccess.file_exists(core_path):
		return tr("Нет ядра %s.\nСкачайте его и положите в папку ядер:\n%s") % [
			core_path.get_file(), core_path.get_base_dir()]

	core = ClassDB.instantiate("RetroCore")
	add_child(core)
	core.set_system_directory(ProjectSettings.globalize_path(CoreManager.SYSTEM_DIR))
	core.set_save_directory(ProjectSettings.globalize_path(CoreManager.SAVES_DIR))

	if not core.load_core(core_path):
		return tr("Ядро %s не загрузилось (подробности — во вкладке Output).") % core_path.get_file()
	if not core.load_game(game["path"]):
		return tr("Ядро не смогло открыть файл игры:\n%s") % game["path"]

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

	# Продолжаем с того места, где вышли в прошлый раз.
	# Подсказка при запуске: как открыть меню.
	var hint := tr("Esc — меню") if InputMapper.style == "keyboard" else tr("Правый стик — меню")
	if start_slot != "" and SaveStates.load_slot(core, game, start_slot):
		if start_slot == SaveStates.AUTO:
			SceneRouter.toast(tr("Продолжаем с места выхода") + " · " + hint)
		else:
			SceneRouter.toast(tr("Загружен слот %s") % start_slot + " · " + hint)
	else:
		SceneRouter.toast(hint)
	return ""


func _process(delta: float) -> void:
	# Скриншот работает и в игре, и в меню паузы — поэтому проверяем
	# его до строчки, которая на паузе останавливает всё остальное.
	if core != null and Input.is_action_just_pressed("screenshot"):
		_take_screenshot()

	if core == null or not core.is_running() or _paused:
		return

	# Раскладка кнопок — своя для каждой приставки (Настройки → Управление).
	var mask0: int = InputMapper.get_retropad_mask(0, game["system"])
	var mask1: int = InputMapper.get_retropad_mask(1, game["system"])
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

	core.set_input(0, mask0)
	core.set_input(1, mask1)

	# Монитор может обновляться 60, 75 или 144 раза в секунду, а NES
	# всегда работает на ~60 кадрах. Поэтому копим прошедшее время и
	# просчитываем столько кадров приставки, сколько «положено».
	_time_bank += delta
	var frames := 0
	while _time_bank >= _frame_time and frames < 3:
		core.run_frame()
		_time_bank -= _frame_time
		frames += 1
	if frames == 3:
		_time_bank = 0.0  # компьютер не успевает — не пытаемся догнать

	_show_frame()
	_push_audio()


func _show_frame() -> void:
	if not core.has_new_frame():
		return
	var image: Image = core.get_frame()
	if _texture == null or _texture.get_size() != Vector2(image.get_size()):
		_texture = ImageTexture.create_from_image(image)  # первый кадр или новый размер
		%Screen.texture = _texture
		_apply_video()  # размер кадра известен — можно расставить картинку
	else:
		_texture.update(image)  # быстро: просто обновить пиксели


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

	# Имя файла: «Battletoads 2026-10-19 16-23-05.png».
	# В именах файлов Windows нельзя использовать \ / : * ? " < > | —
	# убираем их из названия игры, а двоеточия во времени меняем на «-».
	var title: String = game.get("title", "Shellbit")
	for bad in ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]:
		title = title.replace(bad, "")
	var stamp := Time.get_datetime_string_from_system().replace("T", " ").replace(":", "-")
	var file_name := "%s %s.png" % [title.strip_edges(), stamp]
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


func _push_audio() -> void:
	var frames: PackedVector2Array = core.take_audio()
	if frames.is_empty() or _playback == null:
		return
	var room := _playback.get_frames_available()
	if frames.size() > room:
		frames = frames.slice(0, room)  # буфер полон — лишнее выбрасываем
	_playback.push_buffer(frames)


func _wants_menu(mask: int) -> bool:
	if Input.is_action_just_pressed("game_menu"):
		return true
	# Select + Start одновременно на первом геймпаде.
	var combo := (1 << InputMapper.PAD_SELECT) | (1 << InputMapper.PAD_START)
	return mask & combo == combo


# --- Меню паузы ------------------------------------------------------------

func _open_menu() -> void:
	_paused = true
	# Записываем внутриигровые сохранения на диск (на случай, если
	# программу потом закроют неаккуратно).
	core.save_sram()
	%Audio.stream_paused = true  # звук замирает вместе с игрой
	%PauseMenu.open(game)


func _resume() -> void:
	%PauseMenu.close()
	%Audio.stream_paused = false
	_time_bank = 0.0  # время, проведённое в меню, не «догоняем»
	_wait_release = true
	_paused = false


func _on_save_requested(slot: String) -> void:
	if SaveStates.save_slot(core, game, slot):
		SceneRouter.toast(tr("Сохранено в слот %s") % slot)
	else:
		SceneRouter.toast(tr("Это ядро не умеет сохранять состояние"))
	%PauseMenu.refresh_slots()


func _on_load_requested(slot: String) -> void:
	if SaveStates.load_slot(core, game, slot):
		_resume()
		_show_frame()
		SceneRouter.toast(tr("Загружен слот %s") % slot)
	else:
		SceneRouter.toast(tr("Не удалось загрузить слот %s") % slot)


func _restart() -> void:
	# Самый надёжный «сброс» — заново загрузить ядро и игру,
	# но без автосохранения.
	core.unload()
	core.queue_free()
	_texture = null
	var error := _start_game("")
	if error != "":
		_paused = true
		%PauseMenu.close()
		_show_error(error)
		return
	_resume()


func _exit_game() -> void:
	# Автосохранение: при следующем запуске продолжим отсюда.
	SaveStates.save_slot(core, game, SaveStates.AUTO)
	var seconds := (Time.get_ticks_msec() - _start_msec) / 1000
	Library.add_playtime(game, seconds)
	core.unload()
	core = null
	SceneRouter.back()


func _show_error(text: String) -> void:
	# Ядро могло загрузиться, а игра — нет. Выключаем ядро, иначе экран
	# будет считать, что игра идёт, и кнопка «Назад» не сработает.
	if core != null:
		core.unload()
		core.queue_free()
		core = null
	%ErrorText.text = text
	%Error.visible = true
	%Hints.visible = true
	%Hints.set_hints([["cancel", "Назад"]])
	%OpenCoresButton.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	# Пока игра идёт, ui_cancel (B) — это кнопка игры, а не «Назад».
	if core == null and event.is_action_pressed("ui_cancel"):
		SceneRouter.back()
		get_viewport().set_input_as_handled()


# Если окно закрыли прямо во время игры — сохраняемся и выключаем ядро.
func _exit_tree() -> void:
	if core != null:
		SaveStates.save_slot(core, game, SaveStates.AUTO)
		core.unload()
