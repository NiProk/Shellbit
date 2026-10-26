extends TestCase
## Настройки ядра: окно со списком, хранение только изменённого, умолчания ядра.

const SECTION := "core_test"
const OPTIONS := [
	{"key": "test_region", "label": "Region", "info": "Which region.", "category": "system",
		"category_label": "System", "values": [["auto", "Auto"], ["NTSC", "NTSC"], ["PAL", "PAL"]],
		"default": "auto", "value": "auto", "visible": true},
	{"key": "test_res", "label": "Resolution", "info": "", "category": "video",
		"category_label": "Video", "values": [["1x", "1x"], ["2x", "2x"]],
		"default": "1x", "value": "1x", "visible": false},
	{"key": "test_dither", "label": "Dithering", "info": "", "category": "video",
		"category_label": "Video", "values": [["enabled", "enabled"], ["disabled", "disabled"]],
		"default": "enabled", "value": "enabled", "visible": true},
]


func after_each() -> void:
	for key: String in Settings.get_section(SECTION):
		Settings.set_value(SECTION, key, null)


func test_panel_rows() -> void:
	about("Окно настроек ядра: строки, категории, спрятанные настройки")
	var panel := CoreOptionsPanel.new()
	add_child(panel)
	panel.open(OPTIONS, SECTION, "Test core")
	await frames(2)
	var rows: Array = panel._rows.get_children().filter(func(c: Node) -> bool: return c is SettingRow)
	check_eq(rows.size(), 4, "три настройки и «Вернуть всё как было»")
	check(not panel._by_key["test_res"].visible, "спрятанная ядром настройка не видна")
	var dither: SettingRow = panel._by_key["test_dither"]
	check_eq(dither.options[0][1], "Вкл", "«enabled» → «Вкл»")
	panel.queue_free()


func test_only_changes_are_stored() -> void:
	about("Хранится только то, что поменяли; умолчание — запись удаляется")
	var panel := CoreOptionsPanel.new()
	add_child(panel)
	var changed := []
	panel.option_changed.connect(func(key: String, value: String) -> void: changed.append([key, value]))
	panel.open(OPTIONS, SECTION, "Test core")
	await frames(1)
	var region: SettingRow = panel._by_key["test_region"]
	region.change(1)  # Auto → NTSC
	check_eq(Settings.get_value(SECTION, "test_region"), "NTSC", "записано")
	check_eq(changed, [["test_region", "NTSC"]], "ядру сообщили")
	region.change(-1)  # обратно на Auto (умолчание)
	check_eq(Settings.get_value(SECTION, "test_region"), null, "умолчание — записи нет")
	panel.queue_free()


func test_section_name() -> void:
	about("Раздел настроек — по имени ядра, без .dll/.so")
	var player: Control = load("res://scenes/player/Player.tscn").instantiate()
	player.game = {"system": "psx"}
	check_eq(player._options_section(), "core_pcsx_rearmed")
	player.free()
