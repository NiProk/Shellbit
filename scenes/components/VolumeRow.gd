class_name VolumeRow
extends Button
## Строка «Громкость» в меню паузы: ◀ ▶ — тише или громче, A — выключить
## звук или вернуть, как было.
##
## Справа нарисована шкала из 10 делений, как громкость на телевизоре:
##   Громкость        ▮▮▮▮▮▯▯▯▯▯  50 %
##
## Громкость та же, что в Настройки → Звук (Settings: audio/volume), и
## запоминается: поменяли в игре — так и останется.
##
## Звук игры на паузе молчит, поэтому каждое изменение коротко «щёлкает»
## (UiSounds.play_click) — сразу слышно, насколько стало громче.

const STEP := 10           # на сколько процентов за одно нажатие
const SEGMENTS := 10       # делений на шкале
const SEGMENT_SIZE := Vector2(9, 16)
const SEGMENT_GAP := 4
const PERCENT_WIDTH := 64  # место справа под «100 %»

## Громкость до выключения — чтобы A вернула её, а не включила на 100 %.
var _before_mute := 50


func _ready() -> void:
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	text = tr("Громкость")
	custom_minimum_size.y = 40  # как у остальных кнопок меню паузы
	pressed.connect(_toggle_mute)
	mouse_entered.connect(grab_focus)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func volume() -> int:
	return int(Settings.get_value("audio", "volume"))


func set_volume(percent: int) -> void:
	percent = clampi(percent, 0, 100)
	if percent == volume():
		return
	Settings.set_value("audio", "volume", percent)
	Settings.apply_volume()
	UiSounds.play_click()  # послушать, насколько громко
	queue_redraw()


# ◀ ▶ (крестовина, стик, стрелки) меняют громкость. accept_event — «нажатие
# обработано»: иначе Godot попробовал бы увести фокус влево или вправо.
func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left", true):
		set_volume(volume() - STEP)
		accept_event()
	elif event.is_action_pressed("ui_right", true):
		set_volume(volume() + STEP)
		accept_event()


# A (или клик): звук выключить — или вернуть ту громкость, что была.
func _toggle_mute() -> void:
	if volume() > 0:
		_before_mute = volume()
		set_volume(0)
	else:
		set_volume(maxi(_before_mute, STEP))


func _draw() -> void:
	var percent := volume()
	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	var dim := UiTheme.TEXT_DIM
	var bright := UiTheme.ACCENT if has_focus() else UiTheme.TEXT
	var right := size.x - get_theme_stylebox("normal").get_margin(SIDE_RIGHT)
	var baseline := (size.y + font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0

	# Звук выключен — вместо шкалы просто «Без звука».
	if percent == 0:
		var muted := tr("Без звука")
		var width := font.get_string_size(muted, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2(right - width, baseline), muted, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, dim)
		return

	# Справа — «60 %», левее — шкала. Место под проценты постоянное
	# (PERCENT_WIDTH), чтобы шкала не «прыгала», когда 90 % сменится на 100 %.
	var label := "%d %%" % percent
	var label_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(right - label_width, baseline), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, bright)

	var bar_width := SEGMENTS * (SEGMENT_SIZE.x + SEGMENT_GAP) - SEGMENT_GAP
	var x := right - PERCENT_WIDTH - 14 - bar_width
	var y := (size.y - SEGMENT_SIZE.y) / 2.0
	var lit := percent / (100 / SEGMENTS)  # сколько делений «горит»
	for i in SEGMENTS:
		# Деления чуть растут к правому краю — как значок громкости.
		var height := SEGMENT_SIZE.y * (0.55 + 0.45 * i / (SEGMENTS - 1.0))
		var rect := Rect2(x + i * (SEGMENT_SIZE.x + SEGMENT_GAP), y + SEGMENT_SIZE.y - height, SEGMENT_SIZE.x, height)
		draw_rect(rect, bright if i < lit else Color(dim, 0.3))
