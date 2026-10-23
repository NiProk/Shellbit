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

const SaveSlotScene := preload("res://scenes/components/SaveSlot.tscn")

var _game: Dictionary = {}
var _discs: Dictionary = {}  # {"count": 3, "index": 0} — у многодисковых игр
var _dropdown: DropdownList  # список дисков


func _ready() -> void:
	visible = false

	# Сигналы кнопок пересылаем как свои: pressed → resume_requested и т.д.
	%ContinueButton.pressed.connect(resume_requested.emit)
	%RestartButton.pressed.connect(restart_requested.emit)
	%ExitButton.pressed.connect(exit_requested.emit)
	%ScreenshotButton.pressed.connect(screenshot_requested.emit)
	%DiscButton.pressed.connect(_choose_disc)
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

	for button: Button in [%ContinueButton, %DiscButton, %RestartButton, %ScreenshotButton, %ExitButton]:
		button.focus_entered.connect(_update_hints)
		button.mouse_entered.connect(button.grab_focus)


## Показать меню для игры. discs — {"count": 3, "index": 0}, если у игры
## несколько дисков: тогда в меню есть «Сменить диск».
func open(game: Dictionary, discs := {}) -> void:
	_game = game
	_discs = discs
	%GameTitle.text = game["title"]
	%DiscButton.visible = discs.get("count", 0) > 1
	if %DiscButton.visible:
		%DiscButton.text = tr("Сменить диск") + "  ·  " + tr("сейчас %d из %d") % [discs["index"] + 1, discs["count"]]
	refresh_slots()
	visible = true
	# Меню в ScrollContainer: если пунктов больше, чем влезает в экран
	# (маленькое окно, длинное название игры), его можно прокрутить.
	# Открываем всегда с самого верха.
	%Scroll.scroll_vertical = 0
	%ContinueButton.grab_focus()


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


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _dropdown.visible:
		return  # пока открыт список дисков, B закрывает его, а не меню
	var focused := get_viewport().gui_get_focus_owner()

	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("game_menu"):
		resume_requested.emit()
	elif event.is_action_pressed("details") and focused is SaveSlot:
		save_requested.emit(focused.slot)
	else:
		return
	get_viewport().set_input_as_handled()


# Подсказки внизу зависят от того, что выделено.
func _update_hints() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused is SaveSlot:
		if SaveStates.exists(_game, focused.slot):
			%Hints.set_hints([["accept", "Загрузить"], ["details", "Сохранить сюда"], ["cancel", "В игру"]])
		else:
			%Hints.set_hints([["accept", "Сохранить сюда"], ["cancel", "В игру"]])
	else:
		%Hints.set_hints([["accept", "Выбрать"], ["cancel", "В игру"]])
