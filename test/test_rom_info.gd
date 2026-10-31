extends TestCase
## Разбор имён файлов игр (RomInfo) и файлов описаний (GameInfo).


func before_each() -> void:
	Lang.apply("ru")


func after_each() -> void:
	Lang.apply(Settings.get_value("general", "language"))


func test_title_and_region() -> void:
	about("Из имени файла получаются название и регион")
	var info := RomInfo.parse("Contra (USA).nes")
	check_eq(info["title"], "Contra")
	check_eq(info["label"], "США")


func test_versions_share_group() -> void:
	about("Версии одной игры попадают в одну группу")
	check_eq(RomInfo.parse("Contra (USA).nes")["group"], RomInfo.parse("Contra (Japan).nes")["group"])
	check(RomInfo.parse("Contra (USA).nes")["group"] != RomInfo.parse("Super Contra (USA).nes")["group"],
			"Super Contra — другая игра")


func test_tags() -> void:
	about("Метки [!], (Rev 1), [b1], (Disc 2) понятны по-русски")
	check_eq(RomInfo.parse("Battletoads (USA, Europe) [!].nes")["label"], "США и Европа · проверенная")
	check_eq(RomInfo.parse("Zelda (USA) (Rev 1).nes")["label"], "США · ревизия 1")
	check(RomInfo.parse("Zelda (USA) [b1].nes")["label"].contains("повреждённая"), "[b1] — повреждённая")
	check(RomInfo.parse("Final Fantasy VII (Disc 2).cue")["label"].contains("диск 2"), "(Disc 2) — диск 2")
	check_eq(RomInfo.parse("Tetris.gb")["label"], "без пометок")


func test_best_version_scores_higher() -> void:
	about("Проверенная версия ценится выше повреждённой")
	var good: int = RomInfo.parse("Contra (USA) [!].nes")["score"]
	var bad: int = RomInfo.parse("Contra (USA) [b1].nes")["score"]
	check(good > bad, "[!] = %d, [b1] = %d" % [good, bad])


func test_description_languages() -> void:
	about("Файл описания: текст и название на языке интерфейса")
	var sample := "[ru]\ntitle: Боевые жабы\nТри жабы.\n\n[en]\nThree toads.\n[ja]\ntitle: バトルトード\n"
	Lang.apply("ru")
	check_eq(GameInfo.parse_description(sample), {"title": "Боевые жабы", "text": "Три жабы."})
	Lang.apply("en")
	check_eq(GameInfo.parse_description(sample), {"title": "", "text": "Three toads."},
			"по-английски русское название не показываем")
	Lang.apply("de")
	check_eq(GameInfo.parse_description(sample)["text"], "Three toads.", "нет немецкого — берём английский")


func test_description_old_format() -> void:
	about("Старый файл описания без языковых меток тоже читается")
	check_eq(GameInfo.parse_description("Просто текст\nбез меток")["text"], "Просто текст\nбез меток")


func _twins(paths: Array) -> Array:
	var variants := []
	for path: String in paths:
		var info := RomInfo.parse(path.get_file())
		variants.append({"path": path, "title": info["title"], "version": info["label"]})
	RomInfo.tell_apart(variants)
	return variants.map(func(v: Dictionary) -> String: return v["version"])


func test_tell_apart() -> void:
	about("Одинаковые подписи версий дополняются отличием: формат, имя, папка")
	check_eq(_twins(["D:/PS1/Crash (USA).cue", "D:/PS1/Crash (USA).chd"]), ["США · CUE", "США · CHD"])
	check_eq(_twins(["D:/PS1/Rayman (USA) (En,Fr).bin", "D:/PS1/Rayman (USA) (De).bin"]),
			["США · (USA) (En,Fr)", "США · (USA) (De)"])
	check_eq(_twins(["D:/PS1/Rus/Silent Hill (Japan).cue", "D:/PS1/Old/Silent Hill (Japan).cue"]),
			["Япония · папка Rus", "Япония · папка Old"])
	check_eq(_twins(["D:/NES/Contra (USA).nes", "D:/NES/Contra (Japan).nes"]), ["США", "Япония"], "разные подписи не трогаем")
	# Три файла: два .cue и один .chd — формат различает не всех, а
	# полное имя файла — всех.
	check_eq(_twins(["D:/a/Doom (USA).cue", "D:/b/Doom (USA).cue", "D:/b/Doom (USA).chd"]),
			["США · папка a · Doom (USA).cue", "США · папка b · Doom (USA).cue", "США · папка b · Doom (USA).chd"])
