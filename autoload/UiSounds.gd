extends Node
## UiSounds — звуки интерфейса: тихий «щелчок» при переходе между
## кнопками и карточками и «бульк» при запуске игры.
##
## Это синглтон (Autoload): он живёт всё время работы программы,
## поэтому звук не обрывается, когда меняется экран.
##
## Щелчок срабатывает сам: Godot сообщает сигналом gui_focus_changed
## о КАЖДОЙ смене фокуса в любом месте приложения. Так не нужно
## добавлять код в каждый экран.
##
## Звуки лежат в data/sounds/ — их можно заменить своими .wav
## с теми же именами.

const CLICK := preload("res://data/sounds/click.wav")
const LAUNCH := preload("res://data/sounds/launch.wav")

## Не чаще одного щелчка за столько секунд. Если зажать стик,
## фокус бежит по карточкам очень быстро — пулемётная очередь
## щелчков раздражает.
const CLICK_COOLDOWN := 0.045

# AudioStreamPlayer — узел, который проигрывает звук.
# У щелчка и булька свои плееры, чтобы они не обрывали друг друга.
var _click := AudioStreamPlayer.new()
var _launch := AudioStreamPlayer.new()
var _last_focus: Control = null
var _last_click_msec := 0


func _ready() -> void:
	# Работать и на паузе — например, в меню паузы игры.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_click.stream = CLICK
	_click.volume_db = -14.0  # щелчок — тихий, он звучит очень часто
	add_child(_click)

	_launch.stream = LAUNCH
	_launch.volume_db = -6.0
	add_child(_launch)

	get_viewport().gui_focus_changed.connect(_on_focus_changed)


## Включены ли звуки интерфейса (переключатель в Настройки → Звук).
func enabled() -> bool:
	return bool(Settings.get_value("audio", "ui_sounds"))


## «Бульк» при запуске игры. Вызывает SceneRouter, когда открывает экран игры.
func play_launch() -> void:
	if enabled():
		_launch.play()


## Щелчок — можно вызвать и вручную (например, чтобы послушать в настройках).
func play_click() -> void:
	if not enabled():
		return
	var now := Time.get_ticks_msec()
	if now - _last_click_msec < CLICK_COOLDOWN * 1000:
		return
	_last_click_msec = now
	# Чуть-чуть меняем высоту звука каждый раз (±4 %): одинаковые
	# щелчки подряд звучат механически, а так — «живее».
	_click.pitch_scale = randf_range(0.96, 1.04)
	_click.play()


func _on_focus_changed(control: Control) -> void:
	# Если прошлого фокуса не было (его узел удалён вместе со старым экраном),
	# значит, это новый экран сам поставил фокус на первую кнопку.
	# Человек ничего не нажимал — щёлкать не нужно.
	var had_focus := is_instance_valid(_last_focus) and _last_focus.is_inside_tree()
	_last_focus = control
	if had_focus:
		play_click()
