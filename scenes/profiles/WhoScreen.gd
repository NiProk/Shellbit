extends Control
## Экран «Кто играет?» — выбор игрока (autoload/Profiles.gd).
##
## Показывается при запуске, если игроков больше одного, и по кнопке
## с аватаром в шапке главного экрана. Как в Netflix: большие плитки
## с аватарами, выбрал свою — и на главном экране твоё избранное
## и твои «Продолжить играть».

const ButtonHintsScene := preload("res://scenes/components/ButtonHints.tscn")
const TILE_SIZE := Vector2(190, 230)  # плитка, если места хватает
const GAP := 28

var _tile_size := TILE_SIZE

var _tiles: HBoxContainer


func _ready() -> void:
	var background := ColorRect.new()
	background.color = UiTheme.BG
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(Backdrop.new())  # узор фона, как на остальных экранах

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_bottom = -56  # не залезать на строку подсказок
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 36)
	center.add_child(column)

	var title := Label.new()
	title.text = tr("Кто играет?")
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	# Игроков до шести, а при крупном интерфейсе экран в «точках» узкий:
	# если плитки не влезают в ряд — делаем их уже (но не меньше 130).
	var count := Profiles.count()
	var room := get_viewport_rect().size.x - 112.0
	var width := clampf((room - GAP * (count - 1)) / count, 130.0, TILE_SIZE.x)
	_tile_size = Vector2(width, width * TILE_SIZE.y / TILE_SIZE.x)

	_tiles = HBoxContainer.new()
	_tiles.alignment = BoxContainer.ALIGNMENT_CENTER
	_tiles.add_theme_constant_override("separation", GAP)
	column.add_child(_tiles)
	for id: String in Profiles.ids():
		_tiles.add_child(_make_tile(id))

	var hints := ButtonHintsScene.instantiate()
	add_child(hints)
	var list := [["accept", "Выбрать"]]
	if _came_from_home():
		list.append(["cancel", "Назад"])
	hints.set_hints(list)

	# Фокус — на того, кто играл последним.
	var index := Profiles.ids().find(Profiles.current())
	_tiles.get_child(maxi(index, 0)).grab_focus.call_deferred()


# Плитка игрока: кнопка, внутри — аватар и имя.
func _make_tile(id: String) -> Button:
	var tile := Button.new()
	tile.custom_minimum_size = _tile_size
	tile.focus_mode = Control.FOCUS_ALL
	# Рамка выделения — цвета игрока (у Марины — розовая, у Никиты — бирюзовая).
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.set_border_width_all(4)
	frame.border_color = Profiles.color_of(id).lightened(0.2)
	frame.set_corner_radius_all(22)
	frame.set_expand_margin_all(5)
	frame.shadow_color = Color(Profiles.color_of(id), 0.35)
	frame.shadow_size = 20
	tile.add_theme_stylebox_override("focus", frame)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var avatar := ProfileAvatar.new()
	avatar.profile_id = id
	avatar.custom_minimum_size = Vector2.ONE * _tile_size.x * 0.59
	avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(avatar)

	var name_label := Label.new()
	name_label.text = Profiles.name_of(id)
	name_label.theme_type_variation = &"CardTitleLabel"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size.x = _tile_size.x - 24
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)

	tile.mouse_entered.connect(tile.grab_focus)
	tile.pressed.connect(_choose.bind(id))
	return tile


func _choose(id: String) -> void:
	Profiles.switch_to(id)
	SceneRouter.reset_to("home")


func _came_from_home() -> bool:
	return SceneRouter.params.get("from_home", false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _came_from_home():
		SceneRouter.back()
		get_viewport().set_input_as_handled()
