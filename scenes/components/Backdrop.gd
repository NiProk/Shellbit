class_name Backdrop
extends Control
## Фон по выбранной игре — как на PS5 и в Steam Big Picture.
##
## Встал на карточку игры — весь фон плавно превращается в сильно
## размытый и затемнённый кадр из неё (или обложку). Ушёл с игры —
## картинка так же плавно гаснет.
##
## Как размываем. Честное размытие в шейдере — это десятки чтений
## картинки на КАЖДУЮ точку экрана в КАЖДОМ кадре: для 1920×1080 —
## около ста миллионов в кадр. Для Steam Deck многовато. Поэтому делаем
## хитрее, один раз при смене картинки: уменьшаем её до 32×18 точек
## (все мелкие детали при этом сливаются) и растягиваем обратно до
## 384×216 плавной интерполяцией. Получается мягкое пятно цветов —
## то же размытие, но почти бесплатно. Шейдер (backdrop.gdshader)
## потом только смешивает его с цветом фона.
##
## А ещё — свечение цвета приставки (glow.gdshader): встал на плитку NES —
## из левого нижнего угла мягко разливается красный свет, на SNES —
## фиолетовый, на Game Boy — зелёный. На карточке игры — цвет её приставки.
## Цвет не появляется и не гаснет, а ПЕРЕТЕКАЕТ из одного в другой.
##
## И узор фона (раздел настроек «Оформление»): пиксельная сетка, звёзды,
## дизеринг или строки кинескопа — поверх картинки и свечения.
##
## Использование — добавить в сцену сразу после фона (Background):
##   var backdrop := Backdrop.new()
##   add_child(backdrop)
##   move_child(backdrop, %Background.get_index() + 1)
##   backdrop.follow_focus = true      # сам следит за карточками игр
##   backdrop.show_picture(texture)    # или показывать картинку вручную
##   backdrop.show_glow(Color("#E05252"))  # и свечение — тоже вручную

const BackdropShader := preload("res://scenes/components/backdrop.gdshader")
const GlowShader := preload("res://scenes/components/glow.gdshader")
## Узоры фона: значение настройки → шейдер (папка patterns).
const PATTERNS := {
	"grid": preload("res://scenes/components/patterns/grid.gdshader"),
	"stars": preload("res://scenes/components/patterns/stars.gdshader"),
	"dither": preload("res://scenes/components/patterns/dither.gdshader"),
	"scanlines": preload("res://scenes/components/patterns/scanlines.gdshader"),
}
## Сила свечения: 0 — нет, 1 — во всю силу цвета. Больше 0,5 — уже ярко.
const GLOW_STRENGTH := 0.32
const FADE_TIME := 0.6               # за сколько секунд одна картинка сменяет другую
const DELAY := 0.15                  # пауза перед сменой: листаешь быстро — фон не мелькает
const BLUR_SIZE := Vector2i(32, 18)  # до какого размера сжимаем (меньше — сильнее размытие)
const SHOW_SIZE := Vector2i(384, 216)

## Сам следить за фокусом: на карточке игры — её картинка.
var follow_focus := false
## Фокус ушёл с игры (на плитку приставки, кнопку): true — погасить картинку,
## false — оставить последнюю (так в библиотеке: перешёл к поиску — фон остался).
var clear_off_games := true

# Два слоя: пока один гаснет, другой проявляется («наплыв», как в кино).
var _layers: Array[TextureRect] = []
var _front := 0                 # какой слой сейчас виден
var _source: Texture2D = null   # что показываем (до размытия)
var _pending: Texture2D = null  # что покажем после паузы DELAY
var _timer := Timer.new()
var _card: GameCard = null      # карточка в фокусе (её картинка может смениться)
var _tween: Tween               # идущий «наплыв» — остановим, если начнётся новый
var _glow: ColorRect            # слой свечения
var _glow_color := Color(0, 0, 0, 0)  # какое свечение сейчас (alpha — сила)
var _glow_tween: Tween
var _pattern: ColorRect         # слой узора

# Уже размытые картинки: исходная → размытая. Вернулся к той же игре —
# размывать заново не нужно. static — общий для всех экранов.
# Ключ — сама картинка (а не её номер RID): номер освободившейся
# картинки Godot может отдать другой, и фон показал бы чужую игру.
static var _blurred := {}
const CACHE_SIZE := 40


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # мышь проходит насквозь к кнопкам
	for i in 2:
		var layer := TextureRect.new()
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# «Накрыть» весь экран, лишнее по краям обрезать.
		layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # плавно, без пикселей
		var material := ShaderMaterial.new()
		material.shader = BackdropShader
		material.set_shader_parameter("base_color", UiTheme.BG)
		layer.material = material
		layer.modulate.a = 0.0
		add_child(layer)
		_layers.append(layer)

	# Свечение — поверх картинки: свет ложится и на неё.
	_glow = ColorRect.new()
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glow_material := ShaderMaterial.new()
	glow_material.shader = GlowShader
	_glow.material = glow_material
	_glow.visible = false
	add_child(_glow)

	# Узор — самым верхним слоем фона: и поверх картинки, и поверх свечения.
	_pattern = ColorRect.new()
	_pattern.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pattern.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pattern.material = ShaderMaterial.new()
	add_child(_pattern)
	_apply_pattern()
	# Поменяли узор в настройках — сразу показать новый.
	Settings.changed.connect(func(section: String, key: String) -> void:
		if section == "look" and key == "pattern":
			_apply_pattern())

	_timer.one_shot = true
	_timer.wait_time = DELAY
	_timer.timeout.connect(func() -> void: _apply(_pending))
	add_child(_timer)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


## Показать картинку (null — погасить). Смена — после короткой паузы.
func show_picture(texture: Texture2D) -> void:
	_pending = texture
	_timer.start()  # если таймер уже шёл — начнёт отсчёт заново


## Свечение цвета приставки. Color(0, 0, 0, 0) (или alpha = 0) — погасить.
func show_glow(color: Color) -> void:
	var target := Color(color, GLOW_STRENGTH if color.a > 0.0 else 0.0)
	if color.a == 0.0:
		target = Color(_glow_color, 0.0)  # гаснет тем же цветом, а не через чёрный
	if target == _glow_color:
		return
	if _glow_tween:
		_glow_tween.kill()
	_glow_tween = create_tween().set_trans(Tween.TRANS_SINE)
	# tween_method вызывает функцию много раз, передавая промежуточный цвет:
	# красный → (красно-фиолетовый) → фиолетовый. Так цвет «перетекает».
	_glow_tween.tween_method(_set_glow, _glow_color, target, FADE_TIME)


func _set_glow(color: Color) -> void:
	_glow_color = color
	_glow.material.set_shader_parameter("glow_color", color)
	_glow.visible = color.a > 0.001  # не светим — не рисуем вовсе


## Показать узор, выбранный в настройках. "none" (или незнакомый) — без узора.
func _apply_pattern() -> void:
	var shader: Shader = PATTERNS.get(Settings.get_value("look", "pattern"))
	_pattern.visible = shader != null  # нет узора — слой вообще не рисуется
	(_pattern.material as ShaderMaterial).shader = shader


## Цвет приставки по её id ("nes"). Избранное — золотой.
static func system_color(system_id: String) -> Color:
	if system_id == Library.FAVORITES:
		return Color(Library.FAVORITES_COLOR)
	return Color(CoreManager.get_system(system_id).get("color", "#888888"))


func _on_focus_changed(node: Control) -> void:
	if not follow_focus or not is_visible_in_tree():
		return
	if _card and is_instance_valid(_card) and _card.picture_changed.is_connected(_on_card_picture):
		_card.picture_changed.disconnect(_on_card_picture)
	_card = null
	if node is GameCard:
		_card = node
		# Обложка может докачаться, пока карточка в фокусе, — тогда обновим фон.
		_card.picture_changed.connect(_on_card_picture)
		show_picture(_card.picture())
		show_glow(system_color(_card.game.get("system", "")))
	elif node is ConsoleTile:
		show_picture(null)
		show_glow(node.color)
	elif clear_off_games:
		show_picture(null)
		show_glow(Color(0, 0, 0, 0))


func _on_card_picture() -> void:
	if _card and is_instance_valid(_card):
		show_picture(_card.picture())


func _apply(texture: Texture2D) -> void:
	if texture == _source:
		return
	_source = texture
	var back := _layers[1 - _front]
	var front := _layers[_front]
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	# Гасим все слои, кроме нового (вдруг прошлый наплыв не успел закончиться).
	for layer in _layers:
		if layer != back or texture == null:
			_tween.tween_property(layer, "modulate:a", 0.0, FADE_TIME)
	if texture == null:
		return
	back.texture = _blur(texture)
	back.modulate.a = 0.0
	_tween.tween_property(back, "modulate:a", 1.0, FADE_TIME)
	_front = 1 - _front


## Размыть картинку (см. в начале файла). null — если не получилось.
static func _blur(texture: Texture2D) -> Texture2D:
	if _blurred.has(texture):
		return _blurred[texture]
	var image := texture.get_image()
	if image == null or image.is_empty():
		return null
	image = image.duplicate()  # не портить саму обложку
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGB8)

	# Сначала вырезаем середину в пропорции экрана (16:9): иначе
	# вертикальная обложка при сжатии в 32×18 сплющилась бы.
	var width := image.get_width()
	var height := image.get_height()
	var crop := Rect2i(0, 0, width, height)
	if float(width) / height > 16.0 / 9.0:
		crop.size.x = int(height * 16.0 / 9.0)
		crop.position.x = (width - crop.size.x) / 2
	else:
		crop.size.y = int(width * 9.0 / 16.0)
		crop.position.y = (height - crop.size.y) / 2
	image = image.get_region(crop)

	image.resize(BLUR_SIZE.x, BLUR_SIZE.y, Image.INTERPOLATE_LANCZOS)
	image.resize(SHOW_SIZE.x, SHOW_SIZE.y, Image.INTERPOLATE_CUBIC)
	var result := ImageTexture.create_from_image(image)

	if _blurred.size() >= CACHE_SIZE:
		_blurred.erase(_blurred.keys()[0])  # самую старую — вон
	_blurred[texture] = result
	return result
