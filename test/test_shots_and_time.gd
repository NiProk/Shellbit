extends TestCase
## Галерея скриншотов (какие снимки чьи) и лимит времени в детском режиме.

const SHOTS := "user://test_shots"
const FAMILY_KEYS := ["kids_mode", "time_limit", "day", "played_today", "extra_today"]


func after_each() -> void:
	for file in DirAccess.get_files_at(SHOTS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SHOTS.path_join(file)))
	for key: String in FAMILY_KEYS:
		Settings.set_value(Family.SECTION, key, null)
	Family._unsaved = 0.0


func test_screenshots_of_game() -> void:
	about("Скриншоты игры: по названию и дате в имени, новые первыми, чужие не берём")
	DirAccess.make_dir_recursive_absolute(SHOTS)
	for file in ["Contra 2026-10-29 10-00-00.png", "Contra 2026-10-30 21-15-02.png",
			"Contra Force 2026-10-30 22-00-00.png", "Contra notes.png", "Mario 2026-10-30 09-00-00.png"]:
		FileAccess.open(SHOTS.path_join(file), FileAccess.WRITE).store_string("png")
	var folder := ProjectSettings.globalize_path(SHOTS)
	var found := Array(Screenshots.list_for(["Contra"], folder)).map(func(p: String) -> String: return p.get_file())
	check_eq(found, ["Contra 2026-10-30 21-15-02.png", "Contra 2026-10-29 10-00-00.png"])
	check_eq(Screenshots.list_for(["Contra Force", "Mario"], folder).size(), 2, "две игры сразу")
	check_eq(Screenshots.date_text("x/Contra 2026-10-30 21-15-02.png"), "30.10.2026  21:15")
	check_eq(Screenshots.clean_title("Zelda: A Link?"), "Zelda A Link", "запрещённые в имени файла знаки убраны")


func test_no_limit() -> void:
	about("Лимит не действует без детского режима и при «Без ограничений»")
	Settings.set_value(Family.SECTION, "time_limit", 30)
	check(not Family.limit_active(), "детский режим выключен")
	Settings.set_value(Family.SECTION, "kids_mode", true)
	Settings.set_value(Family.SECTION, "time_limit", 0)
	check(not Family.limit_active(), "0 — без ограничений")
	Family.add_play_time(1000.0)
	check_eq(Family.played_today(), 0.0, "без лимита время не считаем")


func test_time_runs_out_and_extra() -> void:
	about("Лимит: время копится, кончается, PIN добавляет 30 минут")
	Settings.set_value(Family.SECTION, "kids_mode", true)
	Settings.set_value(Family.SECTION, "time_limit", 30)
	check(Family.limit_active())
	check_eq(Family.seconds_left(), 1800.0, "сначала — все 30 минут")
	Family.add_play_time(10.0)
	check_eq(Settings.get_value(Family.SECTION, "played_today"), 0, "10 секунд ещё не записаны в файл")
	Family.add_play_time(10.0)
	check_eq(Settings.get_value(Family.SECTION, "played_today"), 20, "набралось 15+ — записали")
	Family.add_play_time(1785.0)
	check(Family.time_is_up(), "время вышло")
	check_eq(Family.seconds_left(), -5.0)
	Family.add_extra_time()
	check_eq(Family.seconds_left(), 1800.0, "PIN: ещё 30 минут, минус прощён")
	check(not Family.time_is_up())


func test_new_day_resets() -> void:
	about("Новый день — счётчик с нуля")
	Settings.set_value(Family.SECTION, "kids_mode", true)
	Settings.set_value(Family.SECTION, "time_limit", 60)
	Settings.set_value(Family.SECTION, "day", "2000-01-01")
	Settings.set_value(Family.SECTION, "played_today", 5000)
	Settings.set_value(Family.SECTION, "extra_today", 1800)
	check_eq(Family.seconds_left(), 3600.0)
	check_eq(Settings.get_value(Family.SECTION, "day"), Time.get_date_string_from_system())


func test_router_asks_pin_when_time_is_up() -> void:
	about("Время вышло — игра не запускается, вместо неё окно PIN-кода")
	Settings.set_value(Family.SECTION, "kids_mode", true)
	Settings.set_value(Family.SECTION, "time_limit", 30)
	Settings.set_value(Family.SECTION, "day", Time.get_date_string_from_system())
	Settings.set_value(Family.SECTION, "played_today", 1800)
	var screen_before: String = SceneRouter._current
	SceneRouter.go_to("player", {"game": {"system": "nes", "path": "x.nes", "title": "X"}})
	await frames(1)
	check_eq(SceneRouter._current, screen_before, "экран игры не открылся")
	check(SceneRouter._pin_dialog != null and SceneRouter._pin_dialog.visible, "показано окно PIN")
	SceneRouter._pin_dialog.close()
