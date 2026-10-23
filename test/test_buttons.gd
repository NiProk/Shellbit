extends TestCase
## Кнопки: описания геймпадов в pads.json и раскладки в InputMapper.


func after_each() -> void:
	# Стираем раскладки, которые меняли тесты.
	for system_id in InputMapper.pads:
		Settings.set_value("pads", system_id, null)


func test_every_console_has_pad() -> void:
	about("У каждой приставки из systems.json есть геймпад в pads.json")
	for system: Dictionary in CoreManager.systems:
		check(InputMapper.pads.has(system["id"]), "нет геймпада для «%s»" % system["id"])


func test_pads_are_valid() -> void:
	about("В pads.json правильные кнопки, раскладки и места на рисунке")
	for system_id: String in InputMapper.pads:
		var pad: Dictionary = InputMapper.pads[system_id]
		var ids := {}
		for button: Dictionary in pad["buttons"]:
			var where := "%s/%s" % [system_id, button["id"]]
			check(not ids.has(button["id"]), "повторяется id кнопки " + where)
			ids[button["id"]] = true
			check_has(InputMapper.PAD_BY_NAME, button["pad"], "pad у " + where)
			check_has(InputMapper.PHYSICAL, button["default"], "default у " + where)
			if button.has("by_label"):
				check_has(InputMapper.PHYSICAL, button["by_label"], "by_label у " + where)
			check(button["label"] != "", "пустая надпись у " + where)
			var pos: Array = button["pos"]
			check(pos[0] >= 0 and pos[0] <= 600 and pos[1] >= 0 and pos[1] <= 260,
					"кнопка %s вне рисунка 600×260: %s" % [where, pos])


func test_no_shared_buttons_by_default() -> void:
	about("В готовых раскладках у двух кнопок не бывает одной кнопки геймпада")
	for system_id: String in InputMapper.pads:
		for preset in ["default", "by_label"]:
			if preset == "by_label" and not InputMapper.has_label_preset(system_id):
				continue
			var used := {}
			var mapping := InputMapper.preset_mapping(system_id, preset)
			for button_id in mapping:
				var physical: String = mapping[button_id]
				if physical == "":
					continue
				check(not used.has(physical), "%s (%s): %s и %s на одной кнопке %s" % [
						system_id, preset, used.get(physical, ""), button_id, physical])
				used[physical] = button_id


func test_snes_by_position() -> void:
	about("SNES по положению: нижняя кнопка Xbox (A) — это B приставки")
	var mapping := InputMapper.get_mapping("snes")
	check_eq(mapping["b"], "a")
	check_eq(mapping["a"], "b")
	check_eq(mapping["rewind"], "lt", "перемотка на LT")
	check_eq(mapping["fast_forward"], "rt", "ускорение на RT")
	check_eq(InputMapper.current_preset("snes"), "default")
	# Таблица для ядра: A геймпада → бит B RetroPad.
	check_has(InputMapper._table("snes"), ["a", InputMapper.PAD_B])


func test_psx_triggers_are_taken() -> void:
	about("У PlayStation курки заняты игрой — перемотка без кнопки геймпада")
	var mapping := InputMapper.get_mapping("psx")
	check_eq(mapping["l2"], "lt")
	check_eq(mapping["rewind"], "", "перемотка на PS1 по умолчанию только с клавиатуры")


func test_assign_swaps() -> void:
	about("Назначили занятую кнопку — две кнопки меняются местами")
	InputMapper.assign("snes", "b", "b")  # B приставки → кнопка B геймпада (была у A)
	var mapping := InputMapper.get_mapping("snes")
	check_eq(mapping["b"], "b")
	check_eq(mapping["a"], "a", "A приставки забрала освободившуюся кнопку")
	check_eq(InputMapper.current_preset("snes"), "custom")
	check(Settings.get_value("pads", "snes", {}) != {}, "своя раскладка сохранена")


func test_default_layout_is_not_stored() -> void:
	about("Обычная раскладка не хранится в настройках")
	InputMapper.assign("snes", "b", "b")
	InputMapper.set_mapping("snes", InputMapper.preset_mapping("snes"))
	check_eq(Settings.get_value("pads", "snes", "нет"), "нет", "запись удалена")
	check_eq(InputMapper.current_preset("snes"), "default")


func test_label_preset() -> void:
	about("Раскладка «по надписям»: A на A, B на B")
	InputMapper.set_mapping("snes", InputMapper.preset_mapping("snes", "by_label"))
	var mapping := InputMapper.get_mapping("snes")
	check_eq([mapping["a"], mapping["b"], mapping["x"], mapping["y"]], ["a", "b", "x", "y"])
	check_eq(InputMapper.current_preset("snes"), "by_label")
	check(not InputMapper.has_label_preset("md"), "у Mega Drive раскладки по надписям нет")


func test_table_follows_changes() -> void:
	about("После смены раскладки ядро получает новые кнопки")
	check_has(InputMapper._table("snes"), ["a", InputMapper.PAD_B])
	InputMapper.assign("snes", "b", "x")
	check_has(InputMapper._table("snes"), ["x", InputMapper.PAD_B], "B приставки теперь на X")


func test_back_trigger_combo() -> void:
	about("Back + курок — перемотка там, где курки заняты игрой")
	check_eq(InputMapper.combo_trigger("psx", "rewind"), "lt", "PlayStation: Back + LT")
	check_eq(InputMapper.combo_trigger("psx", "fast_forward"), "rt", "PlayStation: Back + RT")
	check_eq(InputMapper.combo_trigger("n64", "rewind"), "lt", "Nintendo 64: Z на LT")
	check_eq(InputMapper.combo_trigger("snes", "rewind"), "", "SNES: курок свободен — сочетание не нужно")
	# Перенесли L2 приставки на другую кнопку — курок свободен, сочетание не нужно.
	InputMapper.assign("psx", "rewind", "lt")
	check_eq(InputMapper.combo_trigger("psx", "rewind"), "", "LT отдан перемотке напрямую")
