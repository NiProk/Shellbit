extends Node
## Watchdog — «сторож»: замечает, когда программа перестаёт отвечать,
## и записывает это в журнал (Output в редакторе, а в готовой программе —
## файл %APPDATA%\Shellbit\logs\godot.log).
##
## Зачем. «Программа зависла» может значить очень разное:
##   1) главный поток чем-то занят (долгий расчёт, ожидание) — тогда
##      окно не перерисовывается и не реагирует ни на что;
##   2) программа работает, но ввод забрал кто-то другой — например,
##      Xbox Game Bar по кнопке с логотипом Xbox. Он бывает не виден
##      поверх полноэкранного окна, а все нажатия уходят в него.
## Снаружи это выглядит одинаково, а чинится совсем по-разному.
## Сторож различает эти случаи и пишет, что было.
##
## Как он работает. Главный поток каждый кадр отмечается: «я жив»
## (_heartbeat). А отдельный поток раз в полсекунды проверяет отметку.
## Если её давно не обновляли — главный поток завис. Отдельный поток
## при этом продолжает работать и может это записать.

const STALL_LIMIT_MS := 2000  # сколько молчать, чтобы считать это зависанием

var _heartbeat := 0           # когда главный поток последний раз отметился (мс)
var _stall_reported := false  # о текущем зависании уже написали
var _running := true
var _thread := Thread.new()

# Что происходило перед зависанием. Строки меняет главный поток, а читает
# поток сторожа — поэтому через Mutex («замок»): пока один читает или пишет,
# другой ждёт. Иначе строка могла бы поменяться посреди чтения.
var _mutex := Mutex.new()
var _screen := ""
var _last_input := ""


func _ready() -> void:
	# Работать всегда, даже если игру поставят на паузу через get_tree().paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_heartbeat = Time.get_ticks_msec()
	_thread.start(_watch)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _stall_reported:
		# Зависание закончилось — пишем, сколько длилось.
		print("Сторож: программа снова отвечает (не отвечала %.1f с)" % ((now - _heartbeat) / 1000.0))
		_stall_reported = false
	_heartbeat = now
	if SceneRouter._current != _screen:
		_mutex.lock()
		_screen = SceneRouter._current
		_mutex.unlock()


# Запоминаем последнее нажатие — чтобы знать, после чего всё замерло.
func _input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or event is InputEventMouseMotion:
		return
	if event is InputEventJoypadMotion:
		return  # стики шлют события непрерывно — их не записываем
	_mutex.lock()
	_last_input = event.as_text()
	_mutex.unlock()


# Окно потеряло или вернуло фокус: ввод ушёл другой программе (или вернулся).
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			print("Сторож: окно Shellbit потеряло фокус — нажатия получает другая программа (например, Xbox Game Bar)")
		NOTIFICATION_APPLICATION_FOCUS_IN:
			print("Сторож: окно Shellbit снова в фокусе")


# Работает В ОТДЕЛЬНОМ ПОТОКЕ.
func _watch() -> void:
	while _running:
		OS.delay_msec(500)
		var silent := Time.get_ticks_msec() - _heartbeat
		if silent > STALL_LIMIT_MS and not _stall_reported:
			_stall_reported = true
			_mutex.lock()
			var context := "экран: %s, последнее нажатие: %s" % [_screen, _last_input]
			_mutex.unlock()
			# print можно вызывать из любого потока.
			print("Сторож: программа не отвечает уже %.1f с (%s)" % [silent / 1000.0, context])


func _exit_tree() -> void:
	_running = false
	_thread.wait_to_finish()  # дождаться, пока поток сторожа закончит
