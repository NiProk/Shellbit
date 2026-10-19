class_name SaveSlot
extends Button
## Кнопка слота сохранения в меню паузы: миниатюра кадра + номер + время.

var slot := ""

@onready var _thumb: TextureRect = %Thumb
@onready var _name: Label = %SlotName
@onready var _time: Label = %SlotTime


func _ready() -> void:
	mouse_entered.connect(grab_focus)


## Показать данные слота. Вызывается при открытии меню и после сохранения.
func setup(game: Dictionary, new_slot: String) -> void:
	slot = new_slot
	_name.text = tr("Место выхода") if slot == SaveStates.AUTO else tr("Слот %s") % slot
	_time.text = SaveStates.time_text(game, slot)
	_thumb.texture = SaveStates.thumbnail(game, slot)
	# Пустой слот — полупрозрачный, чтобы сразу было видно, где пусто.
	_thumb.self_modulate.a = 1.0 if _thumb.texture else 0.0
	modulate.a = 1.0 if SaveStates.exists(game, slot) else 0.75
