extends Control
## Экран игры: запускает ядро libretro через наш C++-узел RetroCore,
## показывает картинку, проигрывает звук и передаёт нажатия кнопок.
##
## Открывается так: SceneRouter.go_to("player", {"game": game})
##
## Меню паузы: правый стик (R3), Select + Start или Esc.
## При выходе игра сохраняется сама, а при следующем запуске
## продолжается с того же места.

var core: Node  # RetroCore (создаём из кода — см. _start_game)
var game: Dictionary = {}

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

	var error := _start_game(true)
	if error != "":
		_show_error(error)
		return

	Library.mark_played(game)
	_start_msec = Time.get_ticks_msec()


## Запустить игру. resume = true — продолжить с автосохранения, если оно есть.
## Возвращает "" если всё хорошо, иначе — текст ошибки.
func _start_game(resume: bool) -> String:
	if game.is_empty():
		return "Не передана игра."

	# Класс RetroCore появляется, только если C++-модуль собран.
	# Проверяем через ClassDB, чтобы проект открывался и без модуля.
	if not ClassDB.class_exists("RetroCore"):
		return "C++-модуль shellbit_core не собран. Запустите native/build.bat и перезапустите Godot."

	var system := CoreManager.get_system(game["system"])
	var core_path := CoreManager.core_path(system)
	if not FileAccess.file_exists(core_path):
		return "Нет ядра %s.\nСкачайте его и положите в папку ядер:\n%s" % [
			core_path.get_file(), core_path.get_base_dir()]

	core = ClassDB.instantiate("RetroCore")
	add_child(core)
	core.set_system_directory(ProjectSettings.globalize_path(CoreManager.SYSTEM_DIR))
	core.set_save_directory(ProjectSettings.globalize_path(CoreManager.SAVES_DIR))

	if not core.load_core(core_path):
		return "Ядро %s не загрузилось (подробности — во вкладке Output)." % core_path.get_file()
	if not core.load_game(game["path"]):
		return "Ядро не смогло открыть файл игры:\n" + game["path"]

	# Сведения о картинке и звуке: размер, пропорции, кадры/с, частота звука.
	var av: Dictionary = core.get_av_info()
	print("Запущено ядро: ", core.get_system_info(), " | ", av)
	%AspectBox.ratio = av["aspect"]
	_frame_time = 1.0 / float(av["fps"])

	# Звук: генератор, в который мы сами подкладываем звуковые кадры.
	var generator := %Audio.stream as AudioStreamGenerator
	generator.mix_rate = av["sample_rate"]
	%Audio.play()
	_playback = %Audio.get_stream_playback()

	# Продолжаем с того места, где вышли в прошлый раз.
	# Подсказка при запуске: как открыть меню.
	var hint := "Esc — меню" if InputMapper.style == "keyboard" else "Правый стик — меню"
	if resume and SaveStates.load_slot(core, game, SaveStates.AUTO):
		SceneRouter.toast("Продолжаем с места выхода · " + hint)
	else:
		SceneRouter.toast(hint)
	return ""


func _process(delta: float) -> void:
	if core == null or not core.is_running() or _paused:
		return

	var mask0: int = InputMapper.get_retropad_mask(0)
	var mask1: int = InputMapper.get_retropad_mask(1)
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
	else:
		_texture.update(image)  # быстро: просто обновить пиксели


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
		SceneRouter.toast("Сохранено в слот " + slot)
	else:
		SceneRouter.toast("Это ядро не умеет сохранять состояние")
	%PauseMenu.refresh_slots()


func _on_load_requested(slot: String) -> void:
	if SaveStates.load_slot(core, game, slot):
		_resume()
		_show_frame()
		SceneRouter.toast("Загружен слот " + slot)
	else:
		SceneRouter.toast("Не удалось загрузить слот " + slot)


func _restart() -> void:
	# Самый надёжный «сброс» — заново загрузить ядро и игру,
	# но без автосохранения.
	core.unload()
	core.queue_free()
	_texture = null
	var error := _start_game(false)
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
