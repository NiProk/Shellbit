extends CanvasLayer
## PadNotifier — всплывающая панель «Геймпад подключён / отключён».
##
## Появляется в правом нижнем углу на любом экране (даже во время игры),
## висит несколько секунд и уезжает. Если подключить сразу два геймпада,
## панели встанут столбиком одна над другой.
##
## Это синглтон (Autoload), как SceneRouter: создаётся один раз при запуске
## и живёт всё время, пока работает программа. Поэтому панель не пропадает,
## когда меняется экран.

const SHOW_TIME := 3.0      # сколько секунд панель видна
const SLIDE_TIME := 0.25    # сколько длится выезд и уезд
const MARGIN_RIGHT := 24    # отступ от правого края экрана
const MARGIN_BOTTOM := 72   # отступ снизу: над строкой подсказок (её высота 56)

const COLOR_ON := Color("5eead4")     # бирюзовый (как UiTheme.ACCENT): подключили
const COLOR_OFF := Color("e05252")    # красный: отключили

# Имена геймпадов: номер устройства → имя.
# Зачем: когда геймпад отключён, Godot уже не может сказать его имя,
# поэтому запоминаем имя заранее, пока он подключён.
var _names := {}

# Столбик, в который складываются панели. Прижат к правому нижнему углу.
var _stack: VBoxContainer


func _ready() -> void:
	# layer — «этаж» рисования. SceneRouter со своей шторкой на этаже 100,
	# мы ещё выше, чтобы панель была видна даже во время смены экрана.
	layer = 110
	# PROCESS_MODE_ALWAYS — работать, даже когда игра на паузе
	# (иначе в меню паузы панель застыла бы на месте).
	process_mode = Node.PROCESS_MODE_ALWAYS

	_stack = VBoxContainer.new()
	# Узлы внутри CanvasLayer не получают тему главного окна сами,
	# поэтому даём её явно — тогда работают шрифты и стили из UiTheme.
	_stack.theme = UiTheme.theme
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.add_theme_constant_override("separation", 10)
	add_child(_stack)

	# Прижимаем столбик к правому нижнему углу.
	# grow = BEGIN: когда панелей станет больше, столбик растёт
	# влево и вверх, а не уезжает за край экрана.
	_stack.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_stack.offset_left = -MARGIN_RIGHT
	_stack.offset_right = -MARGIN_RIGHT
	_stack.offset_top = -MARGIN_BOTTOM
	_stack.offset_bottom = -MARGIN_BOTTOM
	_stack.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# Запоминаем имена геймпадов, подключённых ещё до запуска программы.
	for device in Input.get_connected_joypads():
		_names[device] = Input.get_joy_name(device)

	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		var pad_name := Input.get_joy_name(device)
		_names[device] = pad_name
		# Номер игрока — место геймпада в списке подключённых.
		# Тот же порядок использует InputMapper.get_retropad_mask().
		var player := Input.get_connected_joypads().find(device) + 1
		var details := pad_name
		if player > 0:
			details += " · " + tr("Игрок %d") % player
		show_panel(true, tr("Геймпад подключён"), details)
		UiSounds.play_pad(true)
		Haptics.hello(device)  # подключённый геймпад сам коротко дрогнет
	else:
		var pad_name: String = _names.get(device, tr("Геймпад"))
		_names.erase(device)
		show_panel(false, tr("Геймпад отключён"), pad_name)
		UiSounds.play_pad(false)


## Показать панель. connected выбирает цвет и картинку.
## Функция открытая — её можно вызвать и из других скриптов.
func show_panel(connected: bool, title: String, details: String) -> void:
	var accent := COLOR_ON if connected else COLOR_OFF

	# --- Сама панель: картинка слева, две строки текста справа ---
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(accent))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)

	var icon := PadIcon.new()
	icon.connected = connected
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(texts)

	var title_label := Label.new()
	title_label.text = title
	title_label.theme_type_variation = &"CardTitleLabel"
	title_label.add_theme_font_size_override("font_size", 18)
	texts.add_child(title_label)

	var details_label := Label.new()
	details_label.text = details
	details_label.theme_type_variation = &"DimLabel"
	details_label.add_theme_font_size_override("font_size", 15)
	texts.add_child(details_label)

	# --- «Гнездо» для панели ---
	# Столбик (VBoxContainer) сам расставляет своих детей и не даёт
	# двигать их вручную. Поэтому кладём в столбик пустое «гнездо»,
	# а панель — внутрь гнезда. Гнездо стоит на месте, а панель внутри
	# можно двигать как угодно: так и сделаем выезд справа.
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.size_flags_horizontal = Control.SIZE_SHRINK_END  # прижать вправо
	slot.add_child(panel)
	_stack.add_child(slot)

	# Узнаём, сколько места нужно панели, и делаем гнездо такого же размера.
	panel.size = panel.get_combined_minimum_size()
	slot.custom_minimum_size = panel.size

	# Старт: панель спрятана за правым краем экрана и прозрачна.
	var hidden_x := panel.size.x + MARGIN_RIGHT
	panel.position.x = hidden_x
	panel.modulate.a = 0.0

	# Tween — цепочка анимаций. Шаги идут по очереди,
	# а chain()/parallel() управляют тем, что идёт одновременно.
	var tween := create_tween()
	# 1) Выезд: движение и проявление одновременно.
	tween.set_parallel(true)
	tween.tween_property(panel, "position:x", 0.0, SLIDE_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate:a", 1.0, SLIDE_TIME)
	# 2) Подождать.
	tween.chain().tween_interval(SHOW_TIME)
	# 3) Уезд обратно вправо с исчезновением.
	tween.chain().tween_property(panel, "position:x", hidden_x, SLIDE_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(panel, "modulate:a", 0.0, SLIDE_TIME)
	# 4) Плавно схлопнуть гнездо, чтобы панели выше мягко опустились.
	tween.chain().tween_property(slot, "custom_minimum_size:y", 0.0, 0.15)
	# 5) Удалить гнездо вместе с панелью.
	tween.chain().tween_callback(slot.queue_free)


# Фон панели: тёмный, со скруглёнными углами и цветной полоской слева.
func _panel_style(accent: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = UiTheme.PANEL
	box.set_corner_radius_all(14)
	box.border_width_left = 4
	box.border_color = accent
	box.content_margin_left = 16
	box.content_margin_right = 22
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	box.shadow_color = Color(0, 0, 0, 0.4)
	box.shadow_size = 10
	return box


# =====================================================================
# Картинка геймпада
# =====================================================================
# Рисуем геймпад сами в _draw() из простых фигур — кругов и прямоугольников.
# Так не нужен отдельный файл картинки, и цвета легко менять в коде.
#
# «class» внутри скрипта — это маленький отдельный тип узла,
# которым пользуется только этот файл.
class PadIcon extends Control:
	var connected := true

	func _init() -> void:
		custom_minimum_size = Vector2(56, 40)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var body := UiTheme.TEXT if connected else UiTheme.TEXT_DIM.darkened(0.3)
		var dark := UiTheme.PANEL

		# Корпус: скруглённый прямоугольник + две «ручки»-круга снизу.
		var shape := StyleBoxFlat.new()
		shape.bg_color = body
		shape.set_corner_radius_all(11)
		draw_style_box(shape, Rect2(4, 6, 48, 22))
		draw_circle(Vector2(14, 27), 9.0, body)
		draw_circle(Vector2(42, 27), 9.0, body)

		# Крестовина слева: две перекрещённые полоски.
		draw_rect(Rect2(9, 15, 12, 4), dark)
		draw_rect(Rect2(13, 11, 4, 12), dark)

		# Четыре кнопки справа. У подключённого — цвета как на Xbox.
		var center := Vector2(41, 17)
		var buttons := [
			[Vector2(0, -4.5), Color("c9a227")],  # Y — сверху, жёлтая
			[Vector2(4.5, 0), Color("c0392b")],   # B — справа, красная
			[Vector2(0, 4.5), Color("3fa34d")],   # A — снизу, зелёная
			[Vector2(-4.5, 0), Color("2f6fd6")],  # X — слева, синяя
		]
		for button: Array in buttons:
			var color: Color = button[1] if connected else dark
			draw_circle(center + button[0], 2.4, color)

		# Отключённый геймпад перечёркиваем красной линией.
		# Сначала толстая тёмная линия (обводка), потом красная поверх,
		# чтобы черта читалась на светлом корпусе.
		if not connected:
			draw_line(Vector2(6, 37), Vector2(50, 3), UiTheme.PANEL, 7.0, true)
			draw_line(Vector2(6, 37), Vector2(50, 3), Color("e05252"), 3.5, true)
