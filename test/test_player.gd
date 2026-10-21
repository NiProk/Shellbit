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
