extends PanelContainer
## Строка подсказок внизу экрана: «Ⓐ Играть · Ⓑ Назад».
##
## Экран вызывает set_hints() и передаёт список пар [действие, текст]:
##   %Hints.set_hints([["accept", "Играть"], ["cancel", "Назад"]])
## Значки сами меняются под Xbox, PlayStation или клавиатуру.

const LABELS := {
	"xbox": {"accept": "A", "cancel": "B", "details": "X", "favorite": "Y", "page": "LB RB", "menu": "Start", "genre": "View", "change": "←→", "scroll": "↑↓", "search": "↑"},
	"playstation": {"accept": "✕", "cancel": "○", "details": "□", "favorite": "△", "page": "L1 R1", "menu": "Options", "genre": "Share", "change": "←→", "scroll": "↑↓", "search": "↑"},
	"keyboard": {"accept": "Enter", "cancel": "Esc", "details": "Tab", "favorite": "F", "page": "Q E", "menu": "F1", "genre": "G", "change": "←→", "scroll": "↑↓", "search": "Ctrl+F"},
}

# Цвета кнопок как на геймпаде Xbox. Для остальных — серый значок.
const XBOX_COLORS := {
	"accept": Color("3fa34d"),
	"cancel": Color("c0392b"),
	"details": Color("2f6fd6"),
	"favorite": Color("c9a227"),
}
const NEUTRAL := Color("2a3344")

var _hints: Array = []

@onready var _row: HBoxContainer = $Row


func _ready() -> void:
	InputMapper.style_changed.connect(func(_style: String) -> void: _rebuild())


func set_hints(hints: Array) -> void:
	_hints = hints
	_rebuild()


## Какие подсказки прятать первыми, если строка не помещается
## (при крупном интерфейсе на телевизоре). «Выбрать» и «Назад» не прячем никогда.
const HIDE_ORDER := ["search", "genre", "menu", "details", "page", "favorite", "change", "scroll"]


func _rebuild() -> void:
	for child in _row.get_children():
		_row.remove_child(child)  # убрать сразу — иначе _fit посчитал бы и старые
		child.queue_free()

	var style := InputMapper.style
	for hint: Array in _hints:
		var action: String = hint[0]

		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 8)

		var badge := Label.new()
		badge.text = LABELS[style].get(action, "?")
		badge.custom_minimum_size = Vector2(30, 30)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 15)
		var color: Color = XBOX_COLORS.get(action, NEUTRAL) if style == "xbox" else NEUTRAL
		badge.add_theme_stylebox_override("normal", UiTheme.badge_box(color))

		var text := Label.new()
		text.text = tr(hint[1])  # подписи переводим здесь — для всех экранов сразу
		text.add_theme_font_size_override("font_size", 17)
		text.add_theme_color_override("font_color", Color("b8c0d0"))

		item.add_child(badge)
		item.add_child(text)
		item.set_meta("action", action)
		_row.add_child(item)
	_row.add_theme_constant_override("separation", 28)
	_fit.call_deferred()


# Строка не помещается по ширине (крупный интерфейс, длинные подписи
# на немецком…)? Сначала делаем всё плотнее и мельче, а если и это
# не помогло — прячем второстепенные подсказки по списку HIDE_ORDER.
#
# После каждого изменения ждём кадр: размеры надписей Godot пересчитывает
# не сразу, а при следующей расстановке элементов.
func _fit() -> void:
	await get_tree().process_frame
	if not _too_wide():
		return
	_row.add_theme_constant_override("separation", 16)
	for item in _row.get_children():
		item.get_child(0).add_theme_font_size_override("font_size", 13)  # значок
		item.get_child(1).add_theme_font_size_override("font_size", 15)  # подпись
	for action: String in HIDE_ORDER:
		await get_tree().process_frame
		if not is_inside_tree() or not _too_wide():
			return
		for item in _row.get_children():
			if item.get_meta("action") == action:
				item.visible = false


func _too_wide() -> bool:
	if not is_inside_tree():
		return false
	# Меряем ширину ЭКРАНА, а не своей панели: если строка не влезает,
	# панель сама растягивается под неё (шире экрана) — и по своей
	# ширине мы бы никогда не узнали, что что-то вылезло за край.
	var room := get_viewport_rect().size.x - 112.0  # минус отступы панели слева и справа
	return room > 0.0 and _row.get_combined_minimum_size().x > room
