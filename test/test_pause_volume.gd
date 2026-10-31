extends TestCase
## Громкость в меню паузы: ◀ ▶ меняют, A выключает и возвращает.

var menu: Control


func before_each() -> void:
	Settings.set_value("audio", "volume", 50)
	menu = load("res://scenes/pause/PauseMenu.tscn").instantiate()
	add_child(menu)
	await frames(1)
	menu.open({"title": "Test", "path": "test.nes", "system": "nes"})
	await frames(1)


func after_each() -> void:
	menu.queue_free()
	Settings.set_value("audio", "volume", null)
	Settings.apply_volume()
	await frames(1)


func test_volume_row() -> void:
	about("Строка «Громкость»: сразу под «Продолжить», ◀ ▶ по 10 %, A — без звука и обратно")
	var row: VolumeRow = menu._volume
	check_eq(row.get_index(), menu.get_node("%ContinueButton").get_index() + 1, "сразу под «Продолжить»")
	row.grab_focus()
	_press(row, "ui_right")
	check_eq(Settings.get_value("audio", "volume"), 60, "▶ — громче на 10")
	_press(row, "ui_left")
	_press(row, "ui_left")
	check_eq(Settings.get_value("audio", "volume"), 40, "◀ ◀ — тише")
	check(is_equal_approx(AudioServer.get_bus_volume_db(0), linear_to_db(0.4)), "громкость сразу применилась")
	row.pressed.emit()
	check_eq(Settings.get_value("audio", "volume"), 0, "A — без звука")
	check(AudioServer.is_bus_mute(0), "звук выключен")
	row.pressed.emit()
	check_eq(Settings.get_value("audio", "volume"), 40, "A ещё раз — снова 40 %, как было")
	for i in 8:
		_press(row, "ui_right")
	check_eq(Settings.get_value("audio", "volume"), 100, "больше 100 % — не бывает")


func _press(row: Control, action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	row._gui_input(event)
