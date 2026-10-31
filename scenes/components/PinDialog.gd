class_name PinDialog
extends Control
## Окно ввода PIN-кода из 4 цифр — для детского режима (см. autoload/Family.gd).
##
## Работает и с геймпада, и с клавиатуры:
##   • геймпад — кнопки-цифры, как на телефоне: крестовина + A;
##   • клавиатура — просто печатать цифры, Backspace стирает;
##   • B / Esc — отмена.
## Когда набраны 4 цифры, окно само сообщает об этом сигналом entered.
##
## Использование:
##   var dialog := PinDialog.new()
##   add_child(dialog)
##   dialog.entered.connect(func(pin): ...)
##   dialog.open("Введите PIN-код")
##   dialog.show_error("Неверный PIN-код")   # стереть набранное и сказать, что не так

signal entered(pin: String)
signal cancelled

const ButtonHintsScene := preload("res://scenes/components/ButtonHints.tscn")
const LENGTH := 4  # сколько цифр в коде

var _pin := ""
var _title: Label
var _message: Label
var _dots: Array[Label] = []
var _keys: GridContainer
var _hints: Control


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # клики не проходят к экрану под окном
	z_index = 20
	# Тема Shellbit висит на главном окне и по цепочке родителей доходит
	# до всех экранов. Но окно PIN-кода может лежать на CanvasLayer
	# (так его показывает SceneRouter) — там цепочка обрывается, и кнопки
	# были бы серыми, «как в голом Godot». Поэтому задаём тему явно.
	theme = UiTheme.theme

	var dim := ColorRect.new()
	dim.color = Color(UiTheme.BG, 0.9)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Всё — в колонке по центру экрана.
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)

	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)

	# Четыре кружка: ○ — пусто, ● — цифра набрана (саму цифру не показываем).
	var dots := HBoxContainer.new()
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.add_theme_constant_override("separation", 18)
	column.add_child(dots)
	for i in LENGTH:
		var dot := Label.new()
		dot.add_theme_font_size_override("font_size", 34)
		dot.add_theme_color_override("font_color", UiTheme.ACCENT)
		dots.add_child(dot)
		_dots.append(dot)

	_message = Label.new()
	_message.theme_type_variation = &"DimLabel"
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.custom_minimum_size = Vector2(360, 0)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_message)

	# Цифровая клавиатура 3×4, как на телефоне.
	_keys = GridContainer.new()
	_keys.columns = 3
	_keys.add_theme_constant_override("h_separation", 10)
	_keys.add_theme_constant_override("v_separation", 10)
	var holder := CenterContainer.new()
	holder.add_child(_keys)
	column.add_child(holder)
	for key in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", "✕"]:
		var button := Button.new()
		button.text = key
		button.custom_minimum_size = Vector2(76, 60)
		button.add_theme_font_size_override("font_size", 26)
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.mouse_entered.connect(button.grab_focus)
		button.pressed.connect(_on_key.bind(key))
		_keys.add_child(button)

	_hints = ButtonHintsScene.instantiate()
	add_child(_hints)


## Показать окно. title — что просим («Введите PIN-код»), note — пояснение.
func open(title: String, note := "") -> void:
	_title.text = tr(title)
	_message.text = tr(note)
	_message.remove_theme_color_override("font_color")
	_pin = ""
	_update_dots()
	_fit_to_screen()
	_hints.set_hints([["accept", "Нажать"], ["cancel", "Отмена"]])
	visible = true
	_keys.get_child(4).grab_focus.call_deferred()  # «5» — в середине, откуда ближе до любой цифры


# Крупный интерфейс («Для телевизора»): экран в «точках» ниже, и
# клавиатура 3×4 залезала бы на строку подсказок. Кнопки чуть ниже.
func _fit_to_screen() -> void:
	var compact := UiTheme.is_compact(self)
	for button: Button in _keys.get_children():
		button.custom_minimum_size = Vector2(70, 48) if compact else Vector2(76, 60)
	_keys.add_theme_constant_override("v_separation", 8 if compact else 10)


func close() -> void:
	visible = false


## Код не подошёл: стереть набранное и показать, что не так.
func show_error(text: String) -> void:
	_pin = ""
	_update_dots()
	_message.text = tr(text)
	_message.add_theme_color_override("font_color", Color("ff8a8a"))
	Haptics.error()  # два толчка геймпада — «не то!»
	# Окно «встряхивается» — так понятно без слов, что код неверный.
	var tween := create_tween()
	for offset in [14.0, -12.0, 8.0, -5.0, 0.0]:
		tween.tween_property(self, "position:x", offset, 0.05)


func _on_key(key: String) -> void:
	match key:
		"⌫":
			_pin = _pin.left(-1)  # убрать последнюю цифру
		"✕":
			_cancel()
			return
		_:
			_add_digit(key)
	_update_dots()


func _add_digit(digit: String) -> void:
	if _pin.length() >= LENGTH:
		return
	_pin += digit
	_update_dots()
	if _pin.length() == LENGTH:
		# Отдаём код чуть позже: пусть четвёртый кружок успеет закраситься.
		var pin := _pin
		get_tree().create_timer(0.15).timeout.connect(func() -> void:
			if visible:
				entered.emit(pin))


func _update_dots() -> void:
	for i in LENGTH:
		_dots[i].text = "●" if i < _pin.length() else "○"


func _cancel() -> void:
	close()
	cancelled.emit()


# Клавиатура: цифры, Backspace, Esc. Ловим в _input — раньше экрана под окном.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_cancel()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.keycode
		if key >= KEY_0 and key <= KEY_9:
			_add_digit(str(key - KEY_0))
		elif key >= KEY_KP_0 and key <= KEY_KP_9:
			_add_digit(str(key - KEY_KP_0))
		elif key == KEY_BACKSPACE:
			_on_key("⌫")
		else:
			return
	else:
		return
	get_viewport().set_input_as_handled()
