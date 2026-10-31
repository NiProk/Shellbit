extends Control
## Меню паузы поверх игры.
##
## Само меню ничего не сохраняет и не загружает — оно только сообщает
## экрану игры, ЧТО хочет пользователь. Для этого есть сигналы.
## Player.gd подписывается на них и делает работу:
##   %PauseMenu.save_requested.connect(_on_save_requested)
##
## Почему так: меню не знает про ядро RetroCore и не зависит от него.
## Его можно проверить отдельно, а Player остаётся главным.

signal resume_requested                 ## «Продолжить» или B
signal restart_requested                ## «Начать заново»
signal exit_requested                   ## «Выйти в библиотеку»
signal save_requested(slot: String)     ## X на слоте (или A на пустом)
signal load_requested(slot: String)     ## A на заполненном слоте
signal screenshot_requested             ## «Скриншот»
signal disc_requested(index: int)       ## «Сменить диск» → выбрали диск (с нуля)
signal options_requested                ## «Настройки ядра»
signal cheats_requested                 ## «Читы»

const SaveSlotScene := preload("res://scenes/components/SaveSlot.tscn")

var _game: Dictionary = {}
var _discs: Dictionary = {}  # {"count": 3, "index": 0} — у многодисковых игр
var _dropdown: DropdownList  # список дисков
## «Громкость» ◀ ▶ — сразу под «Продолжить» (scenes/components/VolumeRow.gd).
var _volume := VolumeRow.new()
## «Осталось сегодня: 25 мин» — под названием игры, если в детском режиме есть лимит.
var _time_left := Label.new()


func _ready() -> void:
	visible = false

	# Сигналы кнопок пересылаем как свои: pressed → resume_requested и т.д.
	%ContinueButton.pressed.connect(resume_requested.emit)
	%RestartButton.pressed.connect(restart_requested.emit)
	%ExitButton.pressed.connect(exit_requested.emit)
	%ScreenshotButton.pressed.connect(screenshot_requested.emit)
	%DiscButton.pressed.connect(_choose_disc)
	%OptionsButton.pressed.connect(options_requested.emit)
	%CheatsButton.pressed.connect(cheats_requested.emit)
	%ContinueButton.add_sibling(_volume)  # add_sibling — встать сразу после «Продолжить»
	# На Android громкость удобнее кнопками сбоку телефона (или пультом TV).
	_volume.visible = not Platform.is_android()
	# Тап по игре справа от меню — вернуться в игру (как B).
	$Dim.gui_input.connect(_on_dim_input)
	_time_left.theme_type_variation = &"DimLabel"
	%GameTitle.add_sibling(_time_left)
	_volume.focus_entered.connect(_update_hints)
	_volume.pressed.connect(_update_hints)  # «Без звука» ↔ «Включить звук» в подсказке
	_dropdown = DropdownList.new()
	add_child(_dropdown)
	_dropdown.chosen.connect(func(index: Variant) -> void: disc_requested.emit(int(index)))
	_dropdown.closed.connect(%DiscButton.grab_focus)

	# Слоты создаём один раз. При обновлении меняем только надписи —
	# иначе кнопка в фокусе исчезла бы, и фокус «потерялся».
	for slot: String in SaveStates.MANUAL_SLOTS:
		var button: SaveSlot = SaveSlotScene.instantiate()
		button.slot = slot
		%Slots.add_child(button)
		button.pressed.connect(_on_slot_pressed.bind(slot))
		button.focus_entered.connect(_update_hints)

	for button: Button in [%ContinueButton, %DiscButton, %RestartButton, %ScreenshotButton, %CheatsButton, %OptionsButton, %ExitButton]:
		button.focus_entered.connect(_update_hints)
		button.mouse_entered.connect(button.grab_focus)


## Показать меню для игры. discs — {"count": 3, "index": 0}, если у игры
## несколько дисков: тогда в меню есть «Сменить диск».
## has_options = false — у ядра нет списка настроек (старый shellbit_core).
## has_cheats = false — ядро этой приставки не умеет читы: кнопку прячем.
func open(game: Dictionary, discs := {}, has_options := true, has_cheats := true) -> void:
	_game = game
	_discs = discs
	# Детский режим (autoload/Family.gd): без настроек ядра и «Начать заново».
	%OptionsButton.visible = has_options and not Family.is_on()
	%RestartButton.visible = not Family.is_on()
	%GameTitle.text = game["title"]
	%CheatsButton.visible = has_cheats
	_time_left.visible = Family.limit_active()
	if _time_left.visible:
		_time_left.text = tr("Осталось сегодня: %s") % Library.playtime_text(maxi(0, int(Family.seconds_left())))
	refresh_cheats()
	%DiscButton.visible = discs.get("count", 0) > 1
	if %DiscButton.visible:
		%DiscButton.text = tr("Сменить диск") + "  ·  " + tr("сейчас %d из %d") % [discs["index"] + 1, discs["count"]]
	refresh_slots()
	_volume.queue_redraw()  # громкость могли поменять в настройках
	visible = true
	# Меню в ScrollContainer: если пунктов больше, чем влезает в экран
	# (маленькое окно, длинное название игры), его можно прокрутить.
	# Открываем всегда с самого верха.
	%Scroll.scroll_vertical = 0
	$Panel.position.x = 0.0  # после смахивания панель могла остаться сдвинутой
	%ContinueButton.grab_focus()


## Надпись «Читы · включено 2» — сколько читов работает прямо сейчас.
func refresh_cheats() -> void:
	var count := Cheats.enabled_codes(_game).size()
	%CheatsButton.text = tr("Читы") + ("  ·  " + tr("включено: %d") % count if count > 0 else "")


func close() -> void:
	visible = false  # скрытая кнопка сама теряет фокус


## Перечитать слоты с диска (после сохранения).
func refresh_slots() -> void:
	for button: SaveSlot in %Slots.get_children():
		button.setup(_game, button.slot)
	_update_hints()


## Список дисков: «Диск 1», «Диск 2»… Выбранный — тот, что сейчас в приставке.
func _choose_disc() -> void:
	var items := []
	for i in _discs["count"]:
		items.append([i, tr("Диск %d") % (i + 1)])
	_dropdown.open(items, _discs["index"], %DiscButton)


func _on_slot_pressed(slot: String) -> void:
	if SaveStates.exists(_game, slot):
		load_requested.emit(slot)
	else:
		save_requested.emit(slot)  # в пустой слот A сразу сохраняет


# =====================================================================
# Пальцем: смахнуть меню влево — вернуться в игру
# =====================================================================
#
# Панель едет за пальцем. Отпустили, сдвинув больше чем на SWIPE_CLOSE
# точек (или резко махнули), — панель уезжает и игра продолжается;
# меньше — панель возвращается на место.
#
# Смотрим в _input — раньше кнопок и прокрутки: ведём палец вверх-вниз —
# это прокрутка списка, ничего не трогаем; ведём вбок — это смахивание,
# и тогда «съедаем» касание, чтобы кнопка под пальцем не нажалась.

const SWIPE_START := 24.0   # с какого сдвига вбок считать, что это смахивание
const SWIPE_CLOSE := 120.0  # на сколько сдвинуть, чтобы закрыть
const SWIPE_FLING := 900.0  # или с какой скоростью махнуть (точек в секунду)

var _touch_start := Vector2.ZERO
var _touching := false
var _swiping := false
var _fling := 0.0  # последняя скорость пальца по X


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch and event.index == 0:
		if event.pressed:
			_touch_start = event.position
			_touching = true
			_swiping = false
			_fling = 0.0
		else:
			_touching = false
			if _swiping:
				_swiping = false
				_finish_swipe(event.position.x - _touch_start.x)
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == 0 and _touching:
		var moved: Vector2 = event.position - _touch_start
		if not _swiping and moved.x < -SWIPE_START and absf(moved.x) > absf(moved.y) * 1.5:
			_swiping = true  # палец явно идёт влево, а не вверх-вниз
		if _swiping:
			_fling = event.velocity.x
			$Panel.position.x = minf(0.0, moved.x)  # за пальцем, но не правее места
			get_viewport().set_input_as_handled()
	elif _swiping and (event is InputEventMouseButton or event is InputEventMouseMotion) \
			and event.device == InputEvent.DEVICE_ID_EMULATION:
		# Из касаний Godot делает ещё и «мышь» — её тоже не пускаем к кнопкам.
		get_viewport().set_input_as_handled()


func _finish_swipe(moved_x: float) -> void:
	var panel: Control = $Panel
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if moved_x < -SWIPE_CLOSE or _fling < -SWIPE_FLING:
		tween.tween_property(panel, "position:x", -panel.size.x, 0.15)
		tween.tween_callback(resume_requested.emit)
	else:
		tween.tween_property(panel, "position:x", 0.0, 0.15)  # не дотянули — обратно


# Тап (или клик) по затемнённой игре справа от меню — назад в игру.
func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		resume_requested.emit()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _dropdown.visible:
		return  # пока открыт список дисков, B закрывает его, а не меню
	var focused := get_viewport().gui_get_focus_owner()

	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("game_menu"):
		resume_requested.emit()
	elif event.is_action_pressed("details") and focused is SaveSlot:
		if Family.is_on() and SaveStates.exists(_game, focused.slot):
			# Детский режим: занятый слот не перезаписываем — пропал бы прошлый прогресс.
			SceneRouter.toast(tr("В детском режиме можно сохраняться только в пустые слоты"))
		else:
			save_requested.emit(focused.slot)
	else:
		return
	get_viewport().set_input_as_handled()


# Подсказки внизу зависят от того, что выделено.
func _update_hints() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused is SaveSlot:
		if SaveStates.exists(_game, focused.slot) and Family.is_on():
			%Hints.set_hints([["accept", "Загрузить"], ["cancel", "В игру"]])
		elif SaveStates.exists(_game, focused.slot):
			%Hints.set_hints([["accept", "Загрузить"], ["details", "Сохранить сюда"], ["cancel", "В игру"]])
		else:
			%Hints.set_hints([["accept", "Сохранить сюда"], ["cancel", "В игру"]])
	elif focused == _volume:
		var mute := "Включить звук" if _volume.volume() == 0 else "Без звука"
		%Hints.set_hints([["change", "Тише / громче"], ["accept", mute], ["cancel", "В игру"]])
	else:
		%Hints.set_hints([["accept", "Выбрать"], ["cancel", "В игру"]])
