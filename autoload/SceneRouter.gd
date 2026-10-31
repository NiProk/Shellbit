extends Node
## SceneRouter — переходы между экранами и кнопка «Назад».
##
## Вместо того чтобы каждый экран сам вызывал change_scene_to_file(),
## все переходы идут через этот синглтон:
##   SceneRouter.go_to("library", {"system": "snes"})  — открыть экран
##   SceneRouter.back()                                 — вернуться назад
##
## Он помнит историю (стопку экранов), поэтому «Назад» всегда работает.

const SCENES := {
	"home": "res://scenes/home/Home.tscn",
	"library": "res://scenes/library/Library.tscn",
	"details": "res://scenes/details/GameDetails.tscn",
	"player": "res://scenes/player/Player.tscn",
	"settings": "res://scenes/settings/SettingsScreen.tscn",
	"pad_map": "res://scenes/settings/PadMapScreen.tscn",
	"who": "res://scenes/profiles/WhoScreen.tscn",
}

## Параметры текущего экрана. Экран читает их в своём _ready():
##   var system_id = SceneRouter.params.get("system", "")
var params: Dictionary = {}

var _current := "home"
var _history: Array[Dictionary] = []
var _busy := false

var _layer: CanvasLayer
var _fade: ColorRect

## Переходы между экранами (раздел настроек «Оформление»).
## "fade" — обычное затемнение (без шейдера), остальные — шейдеры.
const TRANSITIONS := {
	"mosaic": preload("res://scenes/components/transitions/mosaic.gdshader"),
	"dissolve": preload("res://scenes/components/transitions/dissolve.gdshader"),
}
# Шейдерные переходы чуть длиннее затемнения: глазу нужно время,
# чтобы увидеть, как экран рассыпается.
const FADE_OUT := 0.12
const FADE_IN := 0.18
const PIXEL_OUT := 0.22
const PIXEL_IN := 0.28


func _ready() -> void:
	# Android: попросить доступ к папкам с играми (один раз, пока его нет).
	# Разрешили — пересобрать библиотеку: папки наконец стали видны.
	if Platform.is_android():
		get_tree().on_request_permissions_result.connect(func(_permission: String, granted: bool) -> void:
			if granted:
				Library.scan())
		Platform.request_storage_permission.call_deferred()
	# CanvasLayer рисуется поверх всех экранов. На нём живут
	# чёрная «шторка» для плавных переходов и всплывающие сообщения.
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_fade)
	_create_back_button()


# =====================================================================
# Кнопка «←» для пальцев
# =====================================================================
#
# На телефоне назад можно и системным жестом, но он не всем привычен
# (а на некоторых телефонах его легко сделать случайно). Поэтому в левом
# нижнем углу — круглая кнопка со стрелкой. Там же внизу на компьютере
# строка подсказок, а на телефоне она спрятана — место свободно.
#
# Кнопка делает то же, что B / Esc / жест «Назад» (ui_cancel): закрывает
# открытое окно (клавиатуру, список, PIN), а если окон нет — экран назад.
# На главном экране её нет (назад некуда), в игре — тоже: там своя ❚❚.

var _back_button: Button


func _create_back_button() -> void:
	if not Platform.touch_first():
		return
	_back_button = Button.new()
	_back_button.text = "←"
	_back_button.focus_mode = Control.FOCUS_NONE  # геймпаду не мешает
	_back_button.custom_minimum_size = Vector2(68, 68)
	_back_button.add_theme_font_size_override("font_size", 34)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		_back_button.add_theme_color_override(state, UiTheme.TEXT)
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(UiTheme.CARD_HOVER if state == "pressed" else UiTheme.CARD, 0.92)
		box.set_corner_radius_all(34)  # круглая
		box.border_color = Color(1, 1, 1, 0.12)
		box.set_border_width_all(2)
		box.shadow_color = Color(0, 0, 0, 0.35)
		box.shadow_size = 8
		_back_button.add_theme_stylebox_override(state, box)
	_layer.add_child(_back_button)
	_layer.move_child(_back_button, _fade.get_index())  # шторка перехода — поверх
	# В левый нижний угол, с отступом 12 от краёв экрана.
	_back_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	_back_button.pressed.connect(func() -> void:
		Haptics.tap()
		_press_action(&"ui_cancel"))
	_back_button.visible = false


func _process(_delta: float) -> void:
	if _back_button == null:
		return
	# Назад некуда (главный экран, «Кто играет?» при запуске) — кнопки нет.
	var show := not _busy and not _history.is_empty()
	# В игре — своя кнопка ❚❚. А вот если игра не запустилась (ошибка) —
	# «←» нужна, чтобы уйти с экрана ошибки.
	if show and _current == "player":
		var scene := get_tree().current_scene
		show = scene != null and scene.get("core") == null
	_back_button.visible = show


## Экраны, закрытые в детском режиме (см. autoload/Family.gd):
## чтобы их открыть, нужен PIN-код взрослого.
const LOCKED_SCREENS := ["settings", "pad_map"]

var _pin_dialog: PinDialog       # окно PIN-кода (создаётся при первом запросе)
var _focus_before_pin: Control   # куда вернуть фокус, если PIN не ввели


## Открыть экран и запомнить текущий в истории.
func go_to(screen: String, new_params: Dictionary = {}) -> void:
	if _busy:
		return
	if screen in LOCKED_SCREENS and Family.is_on():
		_ask_pin(screen, new_params)  # детский режим — сначала PIN взрослого
		return
	if screen == "player" and Family.time_is_up():
		_ask_extra_time(new_params)  # время игры на сегодня вышло
		return
	_history.append({"screen": _current, "params": params})
	_open(screen, new_params)


## Открыть экран «с чистого листа»: история забывается, «Назад» некуда.
## Так открываем главный экран, когда включили детский режим, — иначе
## «Назад» вернул бы ребёнка в настройки.
func reset_to(screen: String, new_params: Dictionary = {}) -> void:
	if _busy:
		return
	_history.clear()
	_open(screen, new_params)


# Детский режим: спросить PIN. Верный — режим выключается и экран открывается.
func _ask_pin(screen: String, new_params: Dictionary) -> void:
	_prepare_pin_dialog()
	_pin_dialog.entered.connect(func(pin: String) -> void:
		if not Family.check_pin(pin):
			_pin_dialog.show_error("Неверный PIN-код")
			return
		_pin_dialog.close()
		Family.disable()
		toast(tr("Детский режим выключен"))
		go_to(screen, new_params))
	_pin_dialog.cancelled.connect(func() -> void:
		if is_instance_valid(_focus_before_pin):
			_focus_before_pin.grab_focus())
	_focus_before_pin = get_viewport().gui_get_focus_owner()
	_pin_dialog.open("Детский режим", "Чтобы выйти из детского режима, введите PIN-код взрослого.")


## Время игры на сегодня вышло (Family.time_limit). Взрослый может
## добавить ещё полчаса по PIN-коду — тогда игра запустится.
func _ask_extra_time(new_params: Dictionary) -> void:
	_prepare_pin_dialog()
	_pin_dialog.entered.connect(func(pin: String) -> void:
		if not Family.check_pin(pin):
			_pin_dialog.show_error("Неверный PIN-код")
			return
		_pin_dialog.close()
		Family.add_extra_time()
		toast(tr("Добавлено %d минут") % Family.EXTRA_MINUTES)
		go_to("player", new_params))
	_pin_dialog.cancelled.connect(func() -> void:
		if is_instance_valid(_focus_before_pin):
			_focus_before_pin.grab_focus())
	_focus_before_pin = get_viewport().gui_get_focus_owner()
	Haptics.error()
	_pin_dialog.open("Время игры на сегодня закончилось",
			tr("Можно поиграть завтра. Чтобы добавить %d минут сейчас, нужен PIN-код взрослого.") % Family.EXTRA_MINUTES)


# Окно PIN создаём один раз; перед каждым показом убираем старые
# подключения: что делать после ввода, каждый раз своё.
func _prepare_pin_dialog() -> void:
	if _pin_dialog == null:
		_pin_dialog = PinDialog.new()
		_layer.add_child(_pin_dialog)
		_layer.move_child(_pin_dialog, _fade.get_index())  # под шторкой перехода
	for connection in _pin_dialog.entered.get_connections():
		_pin_dialog.entered.disconnect(connection["callable"])
	for connection in _pin_dialog.cancelled.get_connections():
		_pin_dialog.cancelled.disconnect(connection["callable"])


## Заменить текущий экран, не добавляя его в историю
## (например, переключение приставок кнопками LB/RB).
func replace(screen: String, new_params: Dictionary = {}) -> void:
	if not _busy:
		_open(screen, new_params)


## Вернуться на предыдущий экран.
func back() -> void:
	if _busy or _history.is_empty():
		return
	var previous: Dictionary = _history.pop_back()
	_open(previous["screen"], previous["params"])


func _open(screen: String, new_params: Dictionary) -> void:
	_busy = true
	if screen == "player":
		UiSounds.play_launch()  # «бульк» — игра запускается
	_current = screen
	params = new_params

	var shader: Shader = TRANSITIONS.get(Settings.get_value("look", "transition"))
	if shader == null:
		# Затемнить → сменить сцену → проявить.
		var tween := create_tween()
		tween.tween_property(_fade, "color:a", 1.0, FADE_OUT)
		await tween.finished
		get_tree().change_scene_to_file(SCENES[screen])
		tween = create_tween()
		tween.tween_property(_fade, "color:a", 0.0, FADE_IN)
		await tween.finished
	else:
		await _pixel_transition(shader, screen)
	_busy = false


# Пиксельный переход: тот же «затемнить → сменить → проявить», но шторку
# рисует шейдер (scenes/components/transitions). Он берёт уже нарисованный
# экран и рассыпает его на квадраты; progress: 0 — экран как есть, 1 — рассыпан.
func _pixel_transition(shader: Shader, screen: String) -> void:
	var material := ShaderMaterial.new()
	material.shader = shader
	_fade.material = material
	_fade.color = Color.BLACK  # непрозрачная шторка — дальше цвет решает шейдер
	var set_progress := func(value: float) -> void:
		material.set_shader_parameter("progress", value)
	set_progress.call(0.0)

	var tween := create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_method(set_progress, 0.0, 1.0, PIXEL_OUT)
	await tween.finished
	get_tree().change_scene_to_file(SCENES[screen])
	# Ждём кадр: новый экран должен нарисоваться, иначе шейдер
	# «проявит» ещё старую картинку.
	await get_tree().process_frame
	tween = create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_method(set_progress, 1.0, 0.0, PIXEL_IN)
	await tween.finished

	# Переход закончен: убрать шейдер и вернуть прозрачную шторку.
	# Иначе шейдер каждый кадр копировал бы весь экран — зря.
	_fade.material = null
	_fade.color = Color(0, 0, 0, 0)


## Короткое всплывающее сообщение сверху экрана.
func toast(text: String) -> void:
	var label := Label.new()
	label.text = text
	var box := UiTheme.badge_box(UiTheme.CARD_HOVER)
	box.set_content_margin_all(12)
	box.content_margin_left = 24
	box.content_margin_right = 24
	label.add_theme_stylebox_override("normal", box)
	_layer.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 24)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.modulate.a = 0.0

	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.15)
	tween.tween_interval(2.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.3)
	tween.tween_callback(label.queue_free)


# Кнопка (или жест) «Назад» на Android. Godot сообщает о ней уведомлением,
# а не нажатием клавиши, — превращаем его в обычную кнопку:
#   • в игре — «меню» (game_menu): открыть паузу, а в паузе — вернуться в игру;
#   • на остальных экранах — «B / Esc» (ui_cancel): закрыть окно или назад.
# Чтобы «Назад» не закрывал приложение, в project.godot выключено
# application/config/quit_on_go_back.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_press_action(&"game_menu" if _current == "player" else &"ui_cancel")


# «Нажать» кнопку из кода: нажали — и через мгновение отпустили. Отпускаем
# не сразу, а в следующих кадрах: экран игры проверяет «только что нажата?»
# раз в кадр и иначе мог бы нажатие пропустить.
func _press_action(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().create_timer(0.05).timeout
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
