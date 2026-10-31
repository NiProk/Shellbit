extends TestCase
## Слоты в меню паузы: пустой — сохранить, занятый — спросить «загрузить или перезаписать».

const GAME := {"title": "Test", "path": "/roms/slot test.nes", "system": "nes"}
var menu: Control
var saved := []
var loaded := []


func before_each() -> void:
	saved.clear()
	loaded.clear()
	menu = load("res://scenes/pause/PauseMenu.tscn").instantiate()
	add_child(menu)
	await frames(1)
	menu.save_requested.connect(func(slot: String) -> void: saved.append(slot))
	menu.load_requested.connect(func(slot: String) -> void: loaded.append(slot))
	menu.open(GAME)
	await frames(1)


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveStates._state_path(GAME, "1")))
	Settings.set_value(Family.SECTION, "kids_mode", null)
	menu.queue_free()
	await frames(1)


func test_empty_slot_saves() -> void:
	about("Пустой слот: A сразу сохраняет")
	menu._on_slot_pressed("1")
	check_eq(saved, ["1"])


func test_full_slot_asks() -> void:
	about("Занятый слот: A спрашивает — загрузить или сохранить сюда (перезаписать)")
	_make_slot("1")
	menu._on_slot_pressed("1")
	check(menu._slot_menu != null and menu._slot_menu.visible, "показан выбор")
	check_eq(saved + loaded, [], "пока ничего не сделано")
	menu._slot_menu.id_pressed.emit(menu.SlotChoice.SAVE)
	check_eq(saved, ["1"], "«Сохранить сюда» — перезапись")
	menu._on_slot_pressed("1")
	menu._slot_menu.id_pressed.emit(menu.SlotChoice.LOAD)
	check_eq(loaded, ["1"], "«Загрузить»")
	menu._slot_menu.hide()


func test_kids_mode_only_loads() -> void:
	about("Детский режим: занятый слот только загружается (прогресс не пропадёт)")
	_make_slot("1")
	Settings.set_value(Family.SECTION, "kids_mode", true)
	menu._on_slot_pressed("1")
	check_eq(loaded, ["1"])
	check_eq(saved, [])


func _make_slot(slot: String) -> void:
	var path := ProjectSettings.globalize_path(SaveStates._state_path(GAME, slot))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	FileAccess.open(path, FileAccess.WRITE).store_string("state")
