extends TestCase
## Экран игры: ускорение и перемотка назад — на ненастоящем ядре (MockCore).

const FRAME := 1.0 / 60.0

var player: Control
var core: Node


func before_each() -> void:
	Settings.set_value("play", "rewind_seconds", 20)
	Settings.set_value("play", "ff_speed", 3)
	Settings.set_value("play", "ff_mode", "hold")
	SceneRouter.params = {"game": {"system": "snes", "path": "test.sfc", "title": "Test"}}
	player = load("res://scenes/player/Player.tscn").instantiate()
	add_child(player)
	await frames(2)
	# Настоящего ядра в тестах нет — Player показал ошибку. Подставляем своё.
	player.get_node("%Error").visible = false
	core = load("res://test/MockCore.gd").new()
	player.add_child(core)
	player.core = core
	player._has_rumble = true  # MockCore «умеет» вибрацию
	player.game = SceneRouter.params["game"]
	player._frame_time = FRAME
	player._setup_rewind()


func after_each() -> void:
	_key(KEY_SPACE, false)
	_key(KEY_BACKSPACE, false)
	player.core = null  # иначе Player при удалении «сохранит» ненастоящую игру
	player.queue_free()
	for key in ["rewind_seconds", "ff_speed", "ff_mode"]:
		Settings.set_value("play", key, null)
	await frames(2)


func test_normal_speed() -> void:
	about("Обычная скорость: 60 кадров приставки за секунду")
	_play(60)
	check_eq(core.frame, 60)
	check(not player._speed_label.visible, "значок скорости спрятан")


func test_fast_forward_hold() -> void:
	about("Ускорение ×3, пока держишь кнопку")
	_key(KEY_SPACE, true)
	_play(60)
	check_eq(core.frame, 180, "за секунду — 180 кадров")
	check_eq(player._speed_label.text, "▶▶ ×3")
	_key(KEY_SPACE, false)
	var before: int = core.frame
	_play(60)
	check_eq(core.frame - before, 60, "отпустили — обычная скорость")


func test_fast_forward_toggle() -> void:
	about("Ускорение «нажать один раз»: включается и выключается")
	Settings.set_value("play", "ff_mode", "toggle")
	_tap(KEY_SPACE)
	var before: int = core.frame
	_play(30)
	check_eq(core.frame - before, 90, "включилось")
	_tap(KEY_SPACE)
	before = core.frame
	_play(30)
	check_eq(core.frame - before, 30, "выключилось")


func test_rewind() -> void:
	about("Перемотка возвращает игру назад и не пускает нажатия в игру")
	_play(300)
	check_eq(core.frame, 300)
	_key(KEY_BACKSPACE, true)
	_play(60)
	check(core.frame < 300 and core.frame > 150, "отмотали назад примерно вдвое быстрее игры: кадр %d" % core.frame)
	check_eq(core.inputs, [0, 0], "во время перемотки кнопки в игру не идут")
	check_eq(player._speed_label.text, "◀◀")
	_play(3000)
	check(core.frame < 10, "дошли до начала ленты и остановились: кадр %d" % core.frame)


func test_rewind_memory_limit() -> void:
	about("Перемотка укладывается в лимит памяти даже у тяжёлых приставок")
	core.state_size = 4500 * 1024  # как у PlayStation
	player._setup_rewind()
	var total: int = player._tape_max * core.state_size
	check(total <= Settings.REWIND_BUDGET_MB * 1024 * 1024, "лента %d МБ" % (total / 1024 / 1024))
	check(player._snap_every > 2, "снимки делаются реже: раз в %d кадров" % player._snap_every)


func test_rewind_off() -> void:
	about("Перемотку можно выключить — тогда память на неё не тратится")
	Settings.set_value("play", "rewind_seconds", 0)
	player._setup_rewind()
	check_eq(player._tape_max, 0)
	_play(30)
	check(player._tape.is_empty(), "снимков нет")


# --- Помощники ----------------------------------------------------------------

# «Прокрутить» экран игры на count кадров монитора 60 Гц.
func _play(count: int) -> void:
	for i in count:
		player._process(FRAME)


func _key(key: Key, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _tap(key: Key) -> void:
	_key(key, true)
	_play(1)
	_key(key, false)


func test_sticks_n64_keyboard() -> void:
	about("Nintendo 64: стрелки — это стик игры, а не крестовина")
	player.game = {"system": "n64", "path": "test.z64", "title": "Test"}
	player._analog = true
	_key(KEY_RIGHT, true)
	_play(2)
	check_eq(core.sticks.get(Vector2i(0, 0)), Vector2(1, 0), "стик вправо до упора")
	check_eq(core.inputs[0] & (1 << InputMapper.PAD_RIGHT), 0, "крестовина не нажата")
	_key(KEY_RIGHT, false)
	_play(2)
	check_eq(core.sticks.get(Vector2i(0, 0)), Vector2.ZERO, "отпустили — стик в центре")


func test_sticks_snes_dpad() -> void:
	about("SNES: стиков нет — стрелки нажимают крестовину")
	_key(KEY_RIGHT, true)
	_play(2)
	check(core.inputs[0] & (1 << InputMapper.PAD_RIGHT) != 0, "крестовина вправо")
	check(core.sticks.is_empty(), "стики в ядро не передаются")
	_key(KEY_RIGHT, false)


func test_stick_deadzone() -> void:
	about("Мёртвая зона стика: дрожание — ноль, дальше — плавно до 1")
	check_eq(InputMapper.apply_deadzone(Vector2(0.05, -0.08)), Vector2.ZERO, "дрожание в покое")
	check(InputMapper.apply_deadzone(Vector2(0.2, 0)).x < 0.1, "чуть за краем зоны — маленькое значение")
	check_eq(InputMapper.apply_deadzone(Vector2(1, 0)), Vector2(1, 0), "до упора — 1")


func test_pick_dualshock() -> void:
	about("PlayStation: из контроллеров ядра выбирается DualShock")
	var types := [{"name": "standard", "id": 1}, {"name": "analog", "id": 5}, {"name": "dualshock", "id": 261}]
	check_eq(player._pick_analog_type(types), 261)
	check_eq(player._pick_analog_type(types.slice(0, 2)), 5, "без DualShock — любой со стиками")
	check_eq(player._pick_analog_type([]), -1, "список пуст")


func test_rumble() -> void:
	about("Вибрация: Player передаёт её дальше, на паузе и при перемотке — выключает")
	core.rumble = Vector2(1.0, 0.5)
	_play(1)
	check_eq(player._rumble_sent[0], Vector2(1.0, 0.5), "игра хочет вибрацию — отправили")
	_key(KEY_BACKSPACE, true)  # перемотка
	_play(1)
	check_eq(player._rumble_sent[0], Vector2.ZERO, "при перемотке моторы выключены")
	_key(KEY_BACKSPACE, false)
	Settings.set_value("play", "rumble", false)
	_play(1)
	check_eq(player._rumble_sent[0], Vector2.ZERO, "вибрация выключена в настройках")
	Settings.set_value("play", "rumble", null)


func test_emulation_thread() -> void:
	about("Поток эмуляции: кадры идут сами, даже если главный поток «завис»")
	player._start_emulation()
	var start: int = core.frame
	# Главный поток «зависает» на 0,3 с — как будто интерфейс что-то грузит.
	OS.delay_msec(300)
	var counted: int = core.frame - start
	check(counted >= 12 and counted <= 24, "за 0,3 с — около 18 кадров (вышло %d)" % counted)
	# Меню паузы — поток стоит.
	player._paused = true
	await frames(2)
	var paused_at: int = core.frame
	OS.delay_msec(100)
	check_eq(core.frame, paused_at, "на паузе кадры не идут")
	player._paused = false
	player._stop_emulation()
	check(player._thread == null, "поток остановлен")


func test_light_gun() -> void:
	about("Duck Hunt: пистолет во втором порту, прицел мышью/стиком доходит до ядра")
	check_eq(LightGun.port_for({"system": "nes", "title": "Duck Hunt"}), 1, "Duck Hunt — пистолет в порт 2")
	check_eq(LightGun.port_for({"system": "nes", "title": "Super Mario Bros. + Duck Hunt"}), 1, "сборник с Duck Hunt — тоже")
	check_eq(LightGun.port_for({"system": "nes", "title": "Contra"}), -1, "Contra — без пистолета")
	check_eq(LightGun.port_for({"system": "snes", "title": "Duck Hunt"}), -1, "только у NES")

	var gun := LightGun.new()
	player.get_node("%Screen").add_child(gun)
	check(gun.plug_in(core, 1), "Zapper нашёлся в списке ядра")
	check_eq(core.plugged, {1: 258}, "и вставлен во второй порт")
	player._gun = gun
	gun.set_active(true)
	gun._aim = Vector2(0.25, 0.75)
	player._process(FRAME)
	check_eq(core.gun.slice(0, 3), [1, 0.25, 0.75], "ядро знает, куда целимся")
	check(not core.gun[3], "курок не нажат")
	_key(KEY_SPACE, true)
	player._process(FRAME)
	check_eq(player._fast_forward_speed("nes"), 3, "пробел — по-прежнему ускорение")
	_key(KEY_SPACE, false)
	gun.set_active(false)
	player._gun = null
	gun.queue_free()
