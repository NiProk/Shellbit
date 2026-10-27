class_name PipBlink
extends Node
## Пип моргает. Добавь этот узел ребёнком к картинке Пипа (TextureRect):
##   %Pip.add_child(PipBlink.new())
##
## Моргание рисует шейдер pip_blink.gdshader: поверх белых глаз
## наезжает веко цвета панциря. Новые картинки не нужны.
##
## Почему интервал случайный. Живые существа моргают не по метроному:
## то через 2 секунды, то через 6, иногда дважды подряд. Если моргать
## ровно раз в 4 секунды, глаз сразу заметит «механику».
##
## Координаты глаз заданы в шейдере для картинки pip_front.png.
## Если перерисуешь Пипа — поправь eye_left, eye_right и eye_size там.

const BlinkShader := preload("res://scenes/components/pip_blink.gdshader")
const MIN_WAIT := 2.5      # самая короткая пауза между морганиями, с
const MAX_WAIT := 6.5      # самая длинная
const CLOSE_TIME := 0.07   # за сколько закрываются глаза
const HOLD_TIME := 0.04    # сколько держатся закрытыми
const OPEN_TIME := 0.12    # за сколько открываются (чуть медленнее — так естественнее)
const DOUBLE_CHANCE := 0.2 # шанс моргнуть дважды подряд (каждый пятый раз)

var _material := ShaderMaterial.new()
var _timer := Timer.new()


func _ready() -> void:
	_material.shader = BlinkShader
	(get_parent() as CanvasItem).material = _material
	_timer.one_shot = true
	_timer.timeout.connect(_blink)
	add_child(_timer)
	_wait()


# Подождать случайное время до следующего моргания.
func _wait() -> void:
	_timer.start(randf_range(MIN_WAIT, MAX_WAIT))


func _blink() -> void:
	var tween := create_tween()
	_add_blink(tween)
	if randf() < DOUBLE_CHANCE:
		tween.tween_interval(0.1)
		_add_blink(tween)
	tween.finished.connect(_wait)


# Одно моргание: закрыть → подержать → открыть. Шаги tween идут по очереди.
func _add_blink(tween: Tween) -> void:
	tween.tween_method(_set_blink, 0.0, 1.0, CLOSE_TIME)
	tween.tween_interval(HOLD_TIME)
	tween.tween_method(_set_blink, 1.0, 0.0, OPEN_TIME)


func _set_blink(value: float) -> void:
	_material.set_shader_parameter("blink", value)
