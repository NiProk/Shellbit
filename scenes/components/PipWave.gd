class_name PipWave
extends Node
## Пип машет клешнёй. Добавь этот узел ребёнком к картинке Пипа (TextureRect):
##   %Pip.add_child(PipWave.new())
##
## Это «перекладная» (cut-out) анимация, как в 2D-играх: Пип разрезан
## на две картинки — тело без левой клешни (pip_body.png) и саму клешню
## (pip_claw.png), обе на холсте 310×248, как pip_front.png. Клешня —
## отдельный узел поверх тела, и мы поворачиваем её вокруг «плеча» —
## точки, где она крепится к телу.
##
## Когда машет: через пару секунд после открытия главного экрана
## («привет!») и потом время от времени, через случайные паузы.

const BODY := preload("res://data/ui/pip_body.png")
const CLAW := preload("res://data/ui/pip_claw.png")
## Где клешня крепится к телу — в пикселях картинки. Вокруг этой точки
## она и поворачивается. Перерисуешь Пипа — поправь.
const JOINT := Vector2(88, 158)
const FIRST_WAVE := 1.5   # первое «привет» — через столько секунд после открытия
const MIN_WAIT := 12.0    # пауза между помахиваниями, с
const MAX_WAIT := 25.0
## Как качается клешня: углы в градусах по очереди (минус — против часовой
## стрелки, то есть наружу, от тела) и время на каждый шаг.
const SWINGS := [-16.0, 6.0, -14.0, 4.0, 0.0]
const SWING_TIME := 0.18

var _pip: TextureRect
var _claw := TextureRect.new()
var _timer := Timer.new()


func _ready() -> void:
	_pip = get_parent() as TextureRect
	_pip.texture = BODY  # тело без левой клешни — клешню рисуем отдельно

	# Клешня — во всю картинку Пипа и растягивается так же, как она:
	# тогда на холсте 310×248 клешня встаёт ровно на своё место.
	_claw.texture = CLAW
	_claw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_claw.expand_mode = _pip.expand_mode
	_claw.stretch_mode = _pip.stretch_mode
	_claw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pip.add_child(_claw)
	_claw.resized.connect(_update_pivot)
	_update_pivot()

	_timer.one_shot = true
	_timer.timeout.connect(_wave)
	add_child(_timer)
	_timer.start(FIRST_WAVE)


## Помахать клешнёй (можно вызвать и снаружи — например, когда нашлись игры).
func wave() -> void:
	_wave()


func _wave() -> void:
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for angle: float in SWINGS:
		# rotation — в радианах, поэтому deg_to_rad: градусы → радианы.
		tween.tween_property(_claw, "rotation", deg_to_rad(angle), SWING_TIME)
	tween.finished.connect(func() -> void: _timer.start(randf_range(MIN_WAIT, MAX_WAIT)))


# pivot_offset — точка, вокруг которой узел поворачивается (по умолчанию —
# левый верхний угол). Нам нужно «плечо» клешни. Картинка вписана в узел
# с сохранением пропорций (stretch_mode), поэтому считаем, где на самом
# деле оказалась точка JOINT: масштаб картинки и отступ от края узла.
func _update_pivot() -> void:
	var texture_size := Vector2(CLAW.get_size())
	var scale := minf(_claw.size.x / texture_size.x, _claw.size.y / texture_size.y)
	var offset := (_claw.size - texture_size * scale) / 2.0  # поля по бокам (картинка по центру)
	_claw.pivot_offset = offset + JOINT * scale
