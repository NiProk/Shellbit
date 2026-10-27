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
## Пока обложки нет, видны цветная плашка и название текстом.

## Три вида карточки: большая и обычная (для «Продолжить играть»)
## и вертикальная «обложка» (для сетки библиотеки).
enum Style { WIDE_BIG, WIDE, COVER }

## Картинка на карточке сменилась (например, обложка докачалась).
## Её слушает Backdrop — фон по выбранной игре.
signal picture_changed

var game: Dictionary = {}
var _style := Style.WIDE
var _has_cover := false  # на вертикальной карточке показана обложка
var _has_snapshot := false  # на широкой карточке показан кадр из игры

# --- Выделение карточки: увеличение + подсветка ---
const FOCUS_SCALE := 1.06  # во сколько раз увеличивается выделенная карточка
const FOCUS_TIME := 0.15   # за сколько секунд проходит анимация
var _glow := 0.0           # сила подсветки: 0.0 — нет, 1.0 — полная
var _glow_box: StyleBoxFlat  # «кисть», которой рисуем рамку со свечением
var _focus_tween: Tween    # текущая анимация (чтобы остановить её при новой)

# % —«уникальное имя» узла в сцене. Так скрипт находит узел,
# даже если его потом переложат в другой контейнер.
@onready var _tag: Label = %SystemTag
@onready var _title: Label = %Title
@onready var _info: Label = %Info
@onready var _shot: TextureRect = %Shot
@onready var _shade: TextureRect = $Shot/Shade


func _ready() -> void:
	focus_entered.connect(_on_focus_changed.bind(true))
	focus_exited.connect(_on_focus_changed.bind(false))
	# Мышь и геймпад работают одинаково: навели мышью — карточка в фокусе.
	mouse_entered.connect(grab_focus)
	# Увеличиваться карточка должна от центра, а не от левого угла.
	resized.connect(func() -> void: pivot_offset = size / 2.0)

	# Рамку берём из общей темы (UiTheme), чтобы она была такой же,
	# как у остальных кнопок: бирюзовая, со свечением.
	# duplicate() — делаем свою копию: мы будем менять ей прозрачность,
	# и это не должно задеть другие кнопки.
	_glow_box = UiTheme.theme.get_stylebox("focus", "Button").duplicate() as StyleBoxFlat
	# Стандартная рамка фокуса появляется мгновенно, а нам нужно плавно.
	# Поэтому стандартную отключаем (пустой стиль) и рисуем свою в _draw().
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())


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
	_shot.texture = null
	_shot.visible = false
	_has_cover = false
	_shade.visible = true
	_tag.visible = true
	if had:
		picture_changed.emit()


func _show_picture(texture: Texture2D) -> void:
	_shot.texture = texture
	_shot.visible = true
	_has_cover = _style == Style.COVER
	# На обложке уже нарисовано название — затемнение и текст не нужны.
	_shade.visible = not _has_cover
	_tag.visible = not _has_cover
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
	if _glow <= 0.0:
		return  # карточка не выделена — рисовать нечего
	# Прозрачность цвета зависит от _glow — так рамка плавно проявляется и гаснет.
	_glow_box.border_color = Color(UiTheme.ACCENT, _glow)
	_glow_box.shadow_color = Color(UiTheme.ACCENT, 0.35 * _glow)
	draw_style_box(_glow_box, Rect2(Vector2.ZERO, size))
