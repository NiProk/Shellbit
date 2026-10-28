class_name ProfileAvatar
extends Control
## Аватар игрока: цветной кружок, а в нём — картинка игрока (лиса, сова…)
## или, если картинку не выбрали, первая буква имени: «Н» — Никита.
##
## Кружок и букву рисуем сами в _draw() — они чёткие при любом размере.
## Картинку показывает дочерний TextureRect с шейдером avatar_circle.gdshader:
## шейдер обрезает её кругом. Цвет игрока остаётся ободком вокруг картинки.
##
## Использование:
##   var avatar := ProfileAvatar.new()
##   avatar.profile_id = "p2"
##   avatar.custom_minimum_size = Vector2(96, 96)

## Чей аватар. Поменяли — аватар перерисуется.
var profile_id := Profiles.MAIN:
	set(value):
		profile_id = value
		queue_redraw()


const CIRCLE_SHADER := preload("res://scenes/components/avatar_circle.gdshader")

var _picture := TextureRect.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # размер задаём мы, а не картинка
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var material := ShaderMaterial.new()
	material.shader = CIRCLE_SHADER
	_picture.material = material
	add_child(_picture)
	Profiles.changed.connect(queue_redraw)  # переименовали, сменили цвет или картинку
	resized.connect(queue_redraw)


func _draw() -> void:
	var radius := minf(size.x, size.y) / 2.0
	var center := size / 2.0
	var color := Profiles.color_of(profile_id)
	draw_circle(center, radius, color)

	var texture := Profiles.avatar_texture(profile_id)
	_picture.visible = texture != null
	if texture != null:
		# Ободок цвета игрока — 7% радиуса (но не тоньше 2 пикселей),
		# внутри — тёмный круг того же оттенка, на нём картинка.
		var inner := radius - maxf(2.0, radius * 0.07)
		draw_circle(center, inner, color.darkened(0.6))
		_picture.texture = texture
		_picture.position = center - Vector2(inner, inner)
		_picture.size = Vector2(inner, inner) * 2.0
		return
	# Первая буква имени — большая, тёмная (на светлом кружке так читается лучше).
	var letter := Profiles.name_of(profile_id).left(1).to_upper()
	var font := get_theme_font("font", "Label")
	var font_size := int(radius * 1.05)
	# Где писать, чтобы буква встала ровно по центру: ширину буквы
	# и высоту строки шрифт сообщает сам.
	var text_size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	draw_string(font, Vector2(center.x - text_size.x / 2.0, baseline), letter,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiTheme.BG)
