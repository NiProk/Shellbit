class_name GameCard
extends Button
## Карточка игры.
##
## Карточка — это кнопка (Button), поэтому Godot сам умеет
## выделять её геймпадом и «нажимать» кнопкой A.
## Внутри лежат надписи: плашка приставки, название и строка с информацией.
##
## Картинка на карточке:
##   • широкая («Продолжить играть») — кадр, на котором вышли из игры;
##     если его нет — обложка;
##   • вертикальная (библиотека) — обложка.
## Пока обложки нет — «обложка-заглушка» (см. _build_placeholder):
## градиент цвета приставки, большая первая буква названия
## и силуэт приставки в углу. У каждой игры оттенок чуть свой.

## Три вида карточки: большая и обычная (для «Продолжить играть»)
## и вертикальная «обложка» (для сетки библиотеки).
enum Style { WIDE_BIG, WIDE, COVER }

## Картинка на карточке сменилась (например, обложка докачалась).
## Её слушает Backdrop — фон по выбранной игре.
signal picture_changed
## Карточку долго держали пальцем (или нажали правой кнопкой мыши):
## экран покажет меню «В избранное / Версия / Обложка» (GameMenu).
signal long_pressed

## Сколько секунд держать палец, чтобы открылось меню.
const LONG_PRESS := 0.5

var game: Dictionary = {}
var _style := Style.WIDE
var _has_cover := false  # на вертикальной карточке показана обложка
var _has_snapshot := false  # на широкой карточке показан кадр из игры

# --- Выделение карточки: увеличение + подсветка ---
const FOCUS_SCALE := 1.06  # во сколько раз увеличивается выделенная карточка
const FOCUS_TIME := 0.15   # за сколько секунд проходит анимация
var _glow := 0.0           # сила подсветки: 0.0 — нет, 1.0 — полная
var _accent := UiTheme.ACCENT  # цвет рамки — цвет приставки этой игры
var _focus_tween: Tween    # текущая анимация (чтобы остановить её при новой)

# % —«уникальное имя» узла в сцене. Так скрипт находит узел,
# даже если его потом переложат в другой контейнер.
@onready var _tag: Label = %SystemTag
@onready var _title: Label = %Title
@onready var _info: Label = %Info
@onready var _shot: TextureRect = %Shot
@onready var _shade: TextureRect = $Shot/Shade

# --- Обложка-заглушка ---
const PlaceholderShader := preload("res://scenes/components/placeholder.gdshader")
const SilhouetteShader := preload("res://scenes/components/silhouette.gdshader")
# Скругление углов обложки и затемнения — тот же шейдер, что у плиток приставок.
const RoundedShader := preload("res://scenes/components/RoundedCorners.gdshader")
const CORNER_RADIUS := 14.0  # как у фона карточки (UiTheme: _box(CARD, 14))

# --- «Живая» картинка (эффект Кена Бёрнса) ---
# На широких карточках («Продолжить играть») кадр из игры еле-еле
# приближается и медленно сдвигается, потом так же возвращается — по кругу.
# Так делают в документальных фильмах с фотографиями: картинка будто живёт.
const KB_ZOOM := 1.08    # насколько приближаем: 1,08 — на 8%
const KB_TIME := 12.0    # секунд на одно приближение (и столько же — обратно)
var _kb_tween: Tween
# Один материал силуэта на все карточки: настройки у всех одинаковые.
static var _silhouette_material: ShaderMaterial
var _placeholder: ColorRect  # градиент (рисует шейдер placeholder.gdshader)
var _letter: Label           # большая первая буква названия
var _console_art: TextureRect  # силуэт приставки


# --- Долгое нажатие -----------------------------------------------------------
# Палец коснулся — заводим таймер на LONG_PRESS секунд. Отпустили раньше —
# это обычное нажатие (открыть игру). Повели палец — это прокрутка списка,
# таймер не в счёт. Продержали — меню, а отпускание пальца после этого
# не должно открыть игру: для этого consume_long_press().

var _hold_id := 0          # номер касания: старый таймер узнаёт, что он устарел
var _hold_pos := Vector2.ZERO
var _holding := false
var _long_fired := false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_hold_id += 1
		_holding = true
		_long_fired = false
		_hold_pos = event.position
		var id := _hold_id
		get_tree().create_timer(LONG_PRESS).timeout.connect(func() -> void:
			if _holding and id == _hold_id and is_inside_tree():
				_fire_long_press())
	elif event is InputEventScreenTouch:
		_holding = false
	elif event is InputEventScreenDrag and _holding and event.position.distance_to(_hold_pos) > 24.0:
		_holding = false  # палец повели — это прокрутка, а не долгое нажатие
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		grab_focus()  # на компьютере то же меню — правой кнопкой мыши
		long_pressed.emit()
		accept_event()


func _fire_long_press() -> void:
	_holding = false
	_long_fired = true
	grab_focus()
	if Haptics.enabled():
		Input.vibrate_handheld(25)  # телефон коротко дрогнет: «меню открылось»
	long_pressed.emit()


## Было ли только что долгое нажатие? Тогда отпускание пальца — не «открыть
## игру». Обработчик pressed спрашивает это первым делом (и сбрасывает).
func consume_long_press() -> bool:
	var fired := _long_fired
	_long_fired = false
	return fired


func _ready() -> void:
	focus_entered.connect(_on_focus_changed.bind(true))
	focus_exited.connect(_on_focus_changed.bind(false))
	# Мышь и геймпад работают одинаково: навели мышью — карточка в фокусе.
	mouse_entered.connect(grab_focus)
	# Увеличиваться карточка должна от центра, а не от левого угла.
	resized.connect(func() -> void: pivot_offset = size / 2.0)

	# Рамку и тень рисует UiTheme.draw_focus_lift — цвета приставки.
	# Стандартная рамка фокуса появляется мгновенно, а нам нужно плавно.
	# Поэтому стандартную отключаем (пустой стиль) и рисуем свою в _draw().
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# Обложка и затемнение под текстом — прямоугольные картинки. Без этого
	# у карточки скруглён только фон, а углы картинки поверх него — острые.
	for picture: TextureRect in [_shot, _shade]:
		var rounded := ShaderMaterial.new()
		rounded.shader = RoundedShader
		rounded.set_shader_parameter("radius", CORNER_RADIUS)
		picture.material = rounded
	_build_placeholder()


## Заполнить карточку данными игры. Вызывается после add_child().
## Можно вызывать снова для другой игры — так делает VirtualGrid,
## когда карточка «переезжает» при прокрутке.
func setup(new_game: Dictionary, style: Style = Style.WIDE) -> void:
	game = new_game
	_style = style
	# Картинка прошлой игры этой карточке больше не нужна.
	_has_snapshot = false
	_hide_picture()

	match style:
		Style.WIDE_BIG:
			custom_minimum_size = Vector2(420, 236)
		Style.WIDE:
			custom_minimum_size = Vector2(300, 190)
		Style.COVER:
			custom_minimum_size = Vector2(168, 224)

	var system := CoreManager.get_system(game["system"])
	_setup_placeholder(system)
	_accent = Color(system.get("color", UiTheme.ACCENT))
	_tag.text = system.get("short", "?")
	_tag.add_theme_stylebox_override("normal", UiTheme.tag_box(Color(system.get("color", "#888888"))))

	if game.has("variants"):
		if style != Style.COVER:
			# Кадр последнего выхода из игры.
			var snapshot := SaveStates.thumbnail(Library.chosen_variant(game), SaveStates.AUTO)
			if snapshot:
				_has_snapshot = true
				_show_picture(snapshot)
		if not _has_snapshot:
			var cover := Covers.get_cover(game)
			if cover:
				_show_picture(cover)
		# Слушаем сервис обложек: обложка может скачаться позже,
		# а пользователь может поставить или убрать свою.
		if not Covers.cover_ready.is_connected(_on_cover_ready):
			Covers.cover_ready.connect(_on_cover_ready)
	refresh()


func _on_cover_ready(group_key: String, texture: Texture2D) -> void:
	if group_key != game["key"] or _has_snapshot:
		return  # не наша игра, или на карточке кадр из игры — он важнее
	if texture:
		_show_picture(texture)
	else:
		_hide_picture()
	refresh()


## Что сейчас нарисовано на карточке: кадр из игры, обложка или null.
func picture() -> Texture2D:
	return _shot.texture


func _hide_picture() -> void:
	var had := _shot.texture != null
	_stop_ken_burns()
	_shot.texture = null
	_shot.visible = false
	_has_cover = false
	_shade.visible = true
	_tag.visible = true
	_placeholder.visible = true
	if had:
		picture_changed.emit()


func _show_picture(texture: Texture2D) -> void:
	_shot.texture = texture
	_shot.visible = true
	_start_ken_burns()
	_has_cover = _style == Style.COVER
	# На обложке уже нарисовано название — затемнение и текст не нужны.
	_shade.visible = not _has_cover
	_tag.visible = not _has_cover
	_placeholder.visible = false  # картинка закрывает всю карточку — заглушка не нужна
	picture_changed.emit()


## Обновить надписи (например, после добавления в избранное).
func refresh() -> void:
	_title.text = ("★ " if game["favorite"] else "") + game["title"]
	if _style == Style.COVER:
		_info.visible = false
		_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_title.max_lines_visible = 3
		# На обложке оставляем только звёздочку избранного.
		if _has_cover:
			_title.text = "★" if game["favorite"] else ""
	else:
		_info.text = tr("Запуск: %s · %s") % [
			Library.last_played_text(int(game["last_played"])),
			Library.playtime_text(int(game["play_seconds"])),
		]


func _on_focus_changed(focused: bool) -> void:
	# Если прошлая анимация ещё идёт (быстро листают карточки) — останавливаем,
	# чтобы две анимации не тянули карточку в разные стороны.
	if _focus_tween:
		_focus_tween.kill()
	# Tween — плавное изменение свойства за заданное время.
	# set_parallel(true) — все шаги идут одновременно, а не по очереди.
	_focus_tween = create_tween().set_parallel(true) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 1) Увеличение.
	_focus_tween.tween_property(self, "scale",
			Vector2.ONE * (FOCUS_SCALE if focused else 1.0), FOCUS_TIME)
	# 2) Подсветка. tween_method много раз вызывает _set_glow(),
	# передавая число, которое плавно идёт от текущего _glow к 1.0 (или к 0.0).
	_focus_tween.tween_method(_set_glow, _glow, 1.0 if focused else 0.0, FOCUS_TIME)
	# Выделенная карточка рисуется поверх соседей.
	z_index = 1 if focused else 0


func _set_glow(value: float) -> void:
	_glow = value
	queue_redraw()  # попросить Godot перерисовать карточку — он вызовет _draw()


## _draw() — здесь карточка рисует сама себя.
## Всё, что нарисовано тут, оказывается ПОД дочерними узлами (обложкой, текстом).
## Но рамка лежит снаружи карточки (expand_margin), поэтому обложка её не закрывает.
func _draw() -> void:
	# Тень снизу и рамка цвета приставки; _glow — насколько проявились.
	UiTheme.draw_focus_lift(self, Rect2(Vector2.ZERO, size), _accent, _glow)


# =====================================================================
# Обложка-заглушка
# =====================================================================
#
# Без неё у игры без обложки — пустой тёмный прямоугольник, и на
# коллекции в 2800 игр NES большая часть сетки одинаковая. Заглушка:
#   • градиент цвета приставки (шейдер placeholder.gdshader);
#   • большая полупрозрачная первая буква названия — по ней глаз
#     быстро понимает, где в алфавите ты сейчас листаешь;
#   • тёмный силуэт приставки в правом верхнем углу.
# Узлы создаём один раз, а при смене игры (VirtualGrid переиспользует
# карточки) меняем только цвета, букву и картинку.

func _build_placeholder() -> void:
	_placeholder = ColorRect.new()
	_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = PlaceholderShader
	_placeholder.material = material
	# Буква и силуэт не вылезают за карточку (обрезка по прямоугольнику — дёшево).
	_placeholder.clip_contents = true
	add_child(_placeholder)
	move_child(_placeholder, 0)  # самым нижним: над ним картинка и надписи

	_console_art = TextureRect.new()
	_console_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_console_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_console_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Шейдер silhouette.gdshader вырезает фон картинки и красит приставку
	# одним тёмным цветом. alpha 0.3 — полупрозрачно, чтобы не спорил с надписями.
	if _silhouette_material == null:
		_silhouette_material = ShaderMaterial.new()
		_silhouette_material.shader = SilhouetteShader
	_console_art.material = _silhouette_material
	_console_art.modulate = Color(1, 1, 1, 0.3)
	_placeholder.add_child(_console_art)

	_letter = Label.new()
	_letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_letter.add_theme_font_override("font", UiTheme.bold)
	_letter.add_theme_color_override("font_color", Color(1, 1, 1, 0.22))
	_letter.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # буква — не перевод
	_placeholder.add_child(_letter)

	# Шейдеру нужен размер карточки (для скругления углов). Передаём
	# сразу и при каждом изменении размера. «Сразу» важно: если карточка
	# с самого начала нужного размера, сигнал resized не придёт вовсе.
	resized.connect(_place_placeholder_parts)
	_place_placeholder_parts()


func _setup_placeholder(system: Dictionary) -> void:
	var base := Color(system.get("color", "#888888"))
	# Свой оттенок для каждой игры: hash() превращает название в число,
	# одно и то же для одного названия. Из него — небольшой сдвиг цвета
	# (±0,04 по кругу оттенков, ±15% яркости). Карточки остаются «цвета NES»,
	# но соседние уже не одинаковые.
	var number: int = abs(hash(game.get("title", "")))
	var hue_shift := ((number % 1000) / 1000.0 - 0.5) * 0.08
	var value_shift := (((number / 1000) % 1000) / 1000.0 - 0.5) * 0.3
	var top := Color.from_hsv(fposmod(base.h + hue_shift, 1.0), base.s * 0.85,
			clampf(base.v * 0.62 + value_shift * 0.4, 0.2, 0.8))
	var bottom := UiTheme.CARD.lerp(top, 0.18).darkened(0.25)
	_placeholder.material.set_shader_parameter("top_color", top)
	_placeholder.material.set_shader_parameter("bottom_color", bottom)

	# Первая буква или цифра названия: «Battletoads» → B, «1942» → 1.
	# Genres.simplify оставляет только буквы и цифры (и делает их маленькими).
	var simple := Genres.simplify(game.get("title", ""))
	_letter.text = simple.substr(0, 1).to_upper()

	# Картинка приставки — та же, что на плитке главного экрана.
	var image_path: String = system.get("image", "")
	_console_art.texture = load(image_path) if image_path != "" and ResourceLoader.exists(image_path) else null
	_place_placeholder_parts()


# Размер буквы и силуэта — от размера карточки (у трёх видов они разные).
func _place_placeholder_parts() -> void:
	if _letter == null:
		return
	_placeholder.material.set_shader_parameter("size", size)
	# Обложке и затемнению тоже нужен размер — для скругления углов.
	_shot.material.set_shader_parameter("size", size)
	_shade.material.set_shader_parameter("size", size)
	var font_size := int(size.y * 0.5)
	_letter.add_theme_font_size_override("font_size", font_size)
	# Буква — слева сверху; немного «вылезает» за отступы, так смотрится крупнее.
	_letter.position = Vector2(size.x * 0.08, -font_size * 0.12)
	_letter.size = Vector2.ZERO  # ужаться по тексту
	# На картинках приставок много пустого фона вокруг (силуэт его вырезает),
	# поэтому сама картинка крупнее, чем видимый силуэт.
	var art := Vector2(size.x * 0.7, size.y * 0.42)
	_console_art.size = art
	_console_art.position = Vector2(size.x - art.x, size.y * 0.02)


# =====================================================================
# «Живая» картинка — эффект Кена Бёрнса
# =====================================================================
#
# Приближение делает шейдер обложки (RoundedCorners.gdshader): у него
# есть zoom — во сколько раз приблизить — и pivot — к какой точке.
# Мы медленно меняем оба: приближаемся, одновременно смещая точку,
# и картинка будто плывёт. Обложки в сетке библиотеки не трогаем:
# там карточек много, и всё бы шевелилось — рябило бы в глазах.

func _start_ken_burns() -> void:
	_stop_ken_burns()
	if _style == Style.COVER:
		return
	# Откуда и куда «плывём» — своё для каждой игры (из названия, через hash),
	# чтобы соседние карточки не двигались одинаково, как по команде.
	var number: int = abs(hash(game.get("key", "")))
	var from := Vector2(0.35 + (number % 30) / 100.0, 0.4 + ((number / 30) % 20) / 100.0)
	var to := Vector2(1.0, 1.0) - from  # в противоположную сторону от центра
	# tween_method вызывает функцию, передавая число от 0 до 1 и обратно.
	# set_loops() — повторять бесконечно (пока карточка существует).
	_kb_tween = create_tween().set_loops()
	_kb_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)  # плавно разгоняется и тормозит
	var step := func(t: float) -> void: _set_ken_burns(t, from, to)
	_kb_tween.tween_method(step, 0.0, 1.0, KB_TIME)
	_kb_tween.tween_method(step, 1.0, 0.0, KB_TIME)


func _stop_ken_burns() -> void:
	if _kb_tween:
		_kb_tween.kill()
		_kb_tween = null
	_set_ken_burns(0.0, Vector2(0.5, 0.5), Vector2(0.5, 0.5))


# t = 0 — картинка как есть, t = 1 — приближена к точке to.
func _set_ken_burns(t: float, from: Vector2, to: Vector2) -> void:
	var material := _shot.material as ShaderMaterial
	material.set_shader_parameter("zoom", lerpf(1.0, KB_ZOOM, t))
	material.set_shader_parameter("pivot", from.lerp(to, t))
