class_name ConsoleTile
extends Button
## Плитка приставки на главном экране: цветная полоска, название, число игр.

var system_id := ""

@onready var _strip: ColorRect = %Strip
@onready var _name: Label = %SystemName
@onready var _count: Label = %Count


func _ready() -> void:
	mouse_entered.connect(grab_focus)
	focus_entered.connect(_on_focus_changed.bind(true))
	focus_exited.connect(_on_focus_changed.bind(false))
	resized.connect(func() -> void: pivot_offset = size / 2.0)


func setup(system: Dictionary, game_count: int) -> void:
	system_id = system["id"]
	_strip.color = Color(system["color"])
	_name.text = system["short"]
	_count.text = Library.count_text(game_count)
	tooltip_text = system["name"]


func _on_focus_changed(focused: bool) -> void:
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE * (1.06 if focused else 1.0), 0.15)
	z_index = 1 if focused else 0
