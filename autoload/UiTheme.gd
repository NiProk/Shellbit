extends Node
## UiTheme — единый внешний вид приложения.
##
## Тема (Theme) в Godot — это набор правил: «у всех кнопок такой фон»,
## «у всех надписей такой шрифт». Мы собираем тему в коде и вешаем её
## на главное окно — тогда она действует на все экраны сразу.
##
## Цвета взяты из макетов.

const BG := Color("0b0f17")          # фон
const PANEL := Color("121823")       # панели
const CARD := Color("161e2c")        # карточки и кнопки
const CARD_HOVER := Color("1f2838")  # карточка под мышью
const BAR := Color("080b11")         # нижняя строка подсказок
const TEXT := Color("e6eaf2")        # основной текст
const TEXT_DIM := Color("9aa4b8")    # второстепенный текст
const ACCENT := Color("5eead4")      # бирюзовый акцент — только для фокуса

## Шрифты для каждого языка. Берётся первый, который есть на компьютере.
## Для китайского и японского нужны свои шрифты: иероглифы в них
## нарисованы по-разному, даже если код символа одинаковый.
const FONTS := {
	"default": ["Segoe UI", "Noto Sans", "DejaVu Sans", "sans-serif"],
	"zh": ["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Noto Sans SC", "sans-serif"],
	"ja": ["Yu Gothic UI", "Meiryo UI", "Meiryo", "Noto Sans CJK JP", "Noto Sans JP", "sans-serif"],
	# Корейский: Malgun Gothic есть в любой Windows.
	"ko": ["Malgun Gothic", "Noto Sans CJK KR", "Noto Sans KR", "sans-serif"],
}

var theme := Theme.new()
var font := SystemFont.new()
var bold := SystemFont.new()


func _ready() -> void:
	# Шрифт берём системный: Segoe UI есть в любой Windows,
	# а для китайского и японского — шрифты, которые тоже идут с Windows.
	bold.font_weight = 700
	apply_fonts()
	Lang.language_changed.connect(apply_fonts)

	theme.default_font = font
	theme.default_font_size = 20

	# --- Надписи ---
	theme.set_color("font_color", "Label", TEXT)
	_label_variation("LogoLabel", bold, 30, ACCENT)
	_label_variation("TitleLabel", bold, 32, TEXT)
	_label_variation("HeaderLabel", bold, 24, TEXT)
	_label_variation("CardTitleLabel", bold, 20, TEXT)
	_label_variation("DimLabel", font, 17, TEXT_DIM)

	# --- Кнопки ---
	theme.set_stylebox("normal", "Button", _box(CARD, 14))
	theme.set_stylebox("hover", "Button", _box(CARD_HOVER, 14))
	theme.set_stylebox("pressed", "Button", _box(CARD_HOVER, 14))
	theme.set_stylebox("disabled", "Button", _box(CARD, 14))
	theme.set_stylebox("focus", "Button", _focus_box())
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", TEXT)
	theme.set_color("font_focus_color", "Button", TEXT)
	theme.set_color("font_pressed_color", "Button", ACCENT)

	# --- Панель с информацией об игре ---
	theme.set_type_variation("InfoPanel", "PanelContainer")
	var info_box := _box(PANEL, 16)
	info_box.set_content_margin_all(24)
	theme.set_stylebox("panel", "InfoPanel", info_box)

	# Вешаем тему на главное окно — её унаследуют все экраны.
	get_tree().root.theme = theme


## Подобрать шрифт под текущий язык. Тема ссылается на эти же объекты
## font и bold, поэтому все надписи обновятся сами.
func apply_fonts() -> void:
	var names: Array = FONTS.get(Lang.language, FONTS["default"])
	font.font_names = PackedStringArray(names)
	bold.font_names = PackedStringArray(names)


# Вариация — это «подвид» Label со своим шрифтом и размером.
# В сцене у надписи указывается theme_type_variation = "HeaderLabel".
func _label_variation(type_name: StringName, label_font: Font, size: int, color: Color) -> void:
	theme.set_type_variation(type_name, "Label")
	theme.set_font("font", type_name, label_font)
	theme.set_font_size("font_size", type_name, size)
	theme.set_color("font_color", type_name, color)


func _box(color: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(14)
	return box


# Рамка выделенного элемента: бирюзовая, со свечением.
# Главное правило интерфейса для геймпада — всегда видно, где фокус.
func _focus_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.set_border_width_all(4)
	box.border_color = ACCENT
	box.set_corner_radius_all(18)
	box.set_expand_margin_all(5)
	box.shadow_color = Color(ACCENT, 0.3)
	box.shadow_size = 18
	return box


## Цветная плашка (например, «SNES» на карточке).
func tag_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color.darkened(0.45)
	box.set_corner_radius_all(6)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	return box


## Круглый значок кнопки геймпада в подсказках.
func badge_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(15)
	box.content_margin_left = 8
	box.content_margin_right = 8
	return box


# --- «Приподнятая» выделенная карточка ------------------------------------
# Карточки игр и плитки приставок при выделении рисуют рамку ЦВЕТА СВОЕЙ
# ПРИСТАВКИ (NES — красная, GBA — оранжевая) и тёмную тень снизу, будто
# карточку приподняли над экраном. Кнопки меню остаются бирюзовыми (ACCENT).

var _lift_shadow: StyleBoxFlat  # тень под карточкой
var _lift_frame: StyleBoxFlat   # рамка со свечением


## Нарисовать рамку и тень выделения. amount — от 0 (нет) до 1 (полностью):
## анимация выделения плавно меняет его, и рамка с тенью проявляются.
## Вызывать из _draw() карточки: item.draw_… работает только там.
func draw_focus_lift(item: CanvasItem, rect: Rect2, color: Color, amount: float) -> void:
	if amount <= 0.0:
		return
	if _lift_shadow == null:
		_lift_shadow = StyleBoxFlat.new()
		_lift_shadow.draw_center = false  # только тень, саму карточку не закрашиваем
		_lift_shadow.set_corner_radius_all(18)
		# Размер и сдвиг тени — в сумме меньше 26 пикселей: столько отступа
		# под карточками в рядах с прокруткой, иначе тень обрежется.
		_lift_shadow.shadow_size = 14
		_lift_frame = _focus_box()
	# Тень уходит вниз тем дальше, чем выше «подняли» карточку.
	_lift_shadow.shadow_color = Color(0, 0, 0, 0.55 * amount)
	_lift_shadow.shadow_offset = Vector2(0, 9 * amount)
	item.draw_style_box(_lift_shadow, rect)
	# Рамка — цвета приставки, но заметно светлее: так она видна и на тёмном
	# фоне, и на обложке-заглушке того же цвета (красная рамка на красной карточке).
	var frame_color := color.lightened(0.35)
	_lift_frame.border_color = Color(frame_color, amount)
	_lift_frame.shadow_color = Color(frame_color, 0.35 * amount)
	item.draw_style_box(_lift_frame, rect)


## «Тесно»: интерфейс крупный (для телевизора), и места на экране мало.
## Экраны тогда перестраиваются: меньше колонок, уже панели и т.д.
## Ширина — в «точках интерфейса»: экран 1280 точек при масштабе 115%
## превращается в 1113, при 130% — в 985. Оба случая — «тесно».
func is_compact(node: CanvasItem) -> bool:
	return node.get_viewport_rect().size.x < 1200.0


## Прокрутить scroll так, чтобы item был виден ЦЕЛИКОМ — вместе со свечением
## рамки выделения (room — запас вокруг, в пикселях). Встроенное follow_focus
## у ScrollContainer двигает ровно до края кнопки, и свечение обрезалось.
## Работает в обе стороны: ряды карточек на главном экране листаются вбок,
## а сам экран — вверх-вниз.
## Ждёт кадр: после смены экрана или раздела кнопки могли ещё не встать на места.
func scroll_into_view(scroll: ScrollContainer, item: Control, room := 28.0) -> void:
	await get_tree().process_frame
	if not is_instance_valid(item) or not is_instance_valid(scroll) or not item.is_inside_tree():
		return
	# Где кнопка относительно видимого окошка: (0, 0) — его левый верхний угол.
	var start: Vector2 = item.global_position - scroll.global_position
	var end: Vector2 = start + item.size
	if scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		if start.y - room < 0.0:
			scroll.scroll_vertical += int(start.y - room)
		elif end.y + room > scroll.size.y:
			scroll.scroll_vertical += int(end.y + room - scroll.size.y)
	if scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		if start.x - room < 0.0:
			scroll.scroll_horizontal += int(start.x - room)
		elif end.x + room > scroll.size.x:
			scroll.scroll_horizontal += int(end.x + room - scroll.size.x)
