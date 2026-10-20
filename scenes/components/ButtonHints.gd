extends PanelContainer
## Строка подсказок внизу экрана: «Ⓐ Играть · Ⓑ Назад».
##
## Экран вызывает set_hints() и передаёт список пар [действие, текст]:
##   %Hints.set_hints([["accept", "Играть"], ["cancel", "Назад"]])
## Значки сами меняются под Xbox, PlayStation или клавиатуру.

const LABELS := {
	"xbox": {"accept": "A", "cancel": "B", "details": "X", "favorite": "Y", "page": "LB RB", "menu": "Start", "change": "←→", "scroll": "↑↓", "search": "↑"},
	"playstation": {"accept": "✕", "cancel": "○", "details": "□", "favorite": "△", "page": "L1 R1", "menu": "Options", "change": "←→", "scroll": "↑↓", "search": "↑"},
	"keyboard": {"accept": "Enter", "cancel": "Esc", "details": "Tab", "favorite": "F", "page": "Q E", "menu": "F1", "change": "←→", "scroll": "↑↓", "search": "Ctrl+F"},
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


func _rebuild() -> void:
	for child in _row.get_children():
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
		_row.add_child(item)
