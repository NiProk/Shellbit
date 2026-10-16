class_name GameCard
extends Button
## Карточка игры.
##
## Карточка — это кнопка (Button), поэтому Godot сам умеет
## выделять её геймпадом и «нажимать» кнопкой A.
## Внутри лежат надписи: плашка приставки, название и строка с информацией.

## Три вида карточки: большая и обычная (для «Продолжить играть»)
## и вертикальная «обложка» (для сетки библиотеки).
enum Style { WIDE_BIG, WIDE, COVER }

var game: Dictionary = {}
var _style := Style.WIDE

# % — «уникальное имя» узла в сцене. Так скрипт находит узел,
# даже если его потом переложат в другой контейнер.
@onready var _tag: Label = %SystemTag
@onready var _title: Label = %Title
@onready var _info: Label = %Info
@onready var _shot: TextureRect = %Shot


func _ready() -> void:
	focus_entered.connect(_on_focus_changed.bind(true))
	focus_exited.connect(_on_focus_changed.bind(false))
	# Мышь и геймпад работают одинаково: навели мышью — карточка в фокусе.
	mouse_entered.connect(grab_focus)
	# Увеличиваться карточка должна от центра, а не от левого угла.
	resized.connect(func() -> void: pivot_offset = size / 2.0)


## Заполнить карточку данными игры. Вызывается после add_child().
func setup(new_game: Dictionary, style: Style = Style.WIDE) -> void:
	game = new_game
	_style = style

	match style:
		Style.WIDE_BIG:
			custom_minimum_size = Vector2(420, 236)
		Style.WIDE:
			custom_minimum_size = Vector2(300, 190)
		Style.COVER:
			custom_minimum_size = Vector2(168, 224)

	var system := CoreManager.get_system(game["system"])
	_tag.text = system.get("short", "?")
	_tag.add_theme_stylebox_override("normal", UiTheme.tag_box(Color(system.get("color", "#888888"))))

	# Широкие карточки («Продолжить играть») показывают кадр,
	# на котором игрок вышел из игры в прошлый раз.
	if style != Style.COVER and game.has("variants"):
		var variant := Library.chosen_variant(game)
		_shot.texture = SaveStates.thumbnail(variant, SaveStates.AUTO)
		_shot.visible = _shot.texture != null
	refresh()


## Обновить надписи (например, после добавления в избранное).
func refresh() -> void:
	_title.text = ("★ " if game["favorite"] else "") + game["title"]
	if _style == Style.COVER:
		_info.visible = false
		_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_title.max_lines_visible = 3
	else:
		_info.text = "Запуск: %s · %s" % [
			Library.last_played_text(int(game["last_played"])),
			Library.playtime_text(int(game["play_seconds"])),
		]


func _on_focus_changed(focused: bool) -> void:
	# Tween — плавное изменение свойства за заданное время.
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE * (1.06 if focused else 1.0), 0.15)
	# Выделенная карточка рисуется поверх соседей.
	z_index = 1 if focused else 0
