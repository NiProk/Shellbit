extends TestCase
## Игроки: у каждого своё избранное, время в игре и сохранения.

const FOLDER := "user://test_profiles"


func before_each() -> void:
	for file in ["NES/Mario (USA).nes", "NES/Contra (USA).nes"]:
		var path := FOLDER.path_join(file)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		FileAccess.open(path, FileAccess.WRITE).store_string("x")
	Settings.set_value("library", "folders", PackedStringArray([ProjectSettings.globalize_path(FOLDER)]))
	Library.scan()


func after_each() -> void:
	Profiles.switch_to(Profiles.MAIN)
	for id: String in Profiles.ids():
		Profiles.remove(id)  # первого remove не тронет
	for group in Library.groups:
		if group["favorite"]:
			Library.toggle_favorite(group)
	Settings.set_value("library", "folders", PackedStringArray())
	Library.scan()
	_remove(ProjectSettings.globalize_path(FOLDER))
	await _open("home")


func test_own_favorites() -> void:
	about("У каждого игрока своё избранное и своё «Продолжить играть»")
	var marina := Profiles.add()
	Profiles.rename(marina, "Марина")
	var mario := _group("Mario")
	Library.toggle_favorite(mario)
	Library.mark_played(Library.chosen_variant(_group("Contra")))
	check_eq(Library.favorite_groups().size(), 1, "у первого игрока — Mario в избранном")
	check_eq(Library.get_recent(10).size(), 1, "и Contra в недавних")

	Profiles.switch_to(marina)
	check(Library.favorite_groups().is_empty(), "у Марины избранное пустое")
	check(Library.get_recent(10).is_empty(), "и недавних нет")
	Library.toggle_favorite(_group("Contra"))
	check_eq(Library.favorite_groups()[0]["title"], "Contra", "Марина добавила своё")

	Profiles.switch_to(Profiles.MAIN)
	check_eq(Library.favorite_groups()[0]["title"], "Mario", "у первого — снова Mario")

	Library.scan()  # пересканировали папки — ничего не потерялось
	Profiles.switch_to(marina)
	check_eq(Library.favorite_groups()[0]["title"], "Contra", "после поиска игр у Марины по-прежнему Contra")


func test_own_saves() -> void:
	about("Сохранения у каждого игрока в своей папке; первый — в старой")
	check_eq(Profiles.states_dir(), "user://states", "первый игрок — в старой папке (старые сохранения на месте)")
	check_eq(Profiles.saves_dir(), "user://saves")
	var marina := Profiles.add()
	Profiles.switch_to(marina)
	check_eq(Profiles.states_dir(), "user://profiles/%s/states" % marina, "у Марины — своя")
	# Слот Марины не виден первому игроку.
	var game := {"path": "D:/Games/Mario.nes"}
	var slot := ProjectSettings.globalize_path(SaveStates._dir(game))
	DirAccess.make_dir_recursive_absolute(slot)
	FileAccess.open(slot.path_join("1.state"), FileAccess.WRITE).store_string("x")
	check(SaveStates.exists(game, "1"), "Марина видит свой слот")
	Profiles.switch_to(Profiles.MAIN)
	check(not SaveStates.exists(game, "1"), "первый игрок — нет")
	Profiles.remove(marina)
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://profiles".path_join(marina))),
			"удалили Марину — её сохранения удалены")


func test_old_library_goes_to_first() -> void:
	about("Избранное из старой версии (без игроков) достаётся первому игроку")
	var game: Dictionary = Library.games[0]
	game.erase("stats")
	game["favorite"] = true
	Library._save()
	Library._load()
	Library._apply_profile()
	Library._rebuild_groups()
	check_eq(Library.favorite_groups().size(), 1, "первый игрок — избранное на месте")
	Profiles.switch_to(Profiles.add())
	check(Library.favorite_groups().is_empty(), "у нового игрока — нет")


func test_who_screen() -> void:
	about("Экран «Кто играет?»: плитка на каждого игрока, выбор меняет игрока")
	var marina := Profiles.add()
	await _open("who", {"from_home": true})
	var screen := get_tree().current_scene
	check_eq(screen._tiles.get_child_count(), 2, "две плитки")
	screen._tiles.get_child(1).pressed.emit()
	await _wait_router()
	check_eq(Profiles.current(), marina, "выбрали Марину")
	check_eq(get_tree().current_scene.scene_file_path, SceneRouter.SCENES["home"], "и открылся главный экран")
	check(get_tree().current_scene._profile_button.visible, "на главном — кнопка игрока")


func test_first_cannot_be_removed() -> void:
	about("Первого игрока удалить нельзя")
	Profiles.remove(Profiles.MAIN)
	check(Profiles.MAIN in Profiles.ids())


func _group(title: String) -> Dictionary:
	for group in Library.groups:
		if group["title"] == title:
			return group
	return {}


func _open(screen: String, params := {}) -> void:
	while SceneRouter._busy:
		await frames(1)
	SceneRouter.go_to(screen, params)
	await _wait_router()


func _wait_router() -> void:
	await frames(2)
	while SceneRouter._busy:
		await frames(1)
	await frames(2)


func _remove(path: String) -> void:
	for sub in DirAccess.get_directories_at(path):
		_remove(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


func test_settings_page() -> void:
	about("Настройки → Игроки: список, настройки игрока, удаление в два нажатия")
	var marina := Profiles.add()
	Profiles.rename(marina, "Марина")
	await _open("settings", {"page": "players", "rows": true})
	var screen := get_tree().current_scene
	# Строки: первый игрок, Марина, «+ Добавить», «Спрашивать…»
	check_eq(screen.get_node("%Rows").get_child_count(), 4, "две строки игроков и ещё две")
	screen._open_player(marina)
	await frames(2)
	var rows: Array = screen.get_node("%Rows").get_children()
	var remove: SettingRow = rows.filter(func(r: SettingRow) -> bool: return r.title == "Удалить игрока")[0]
	remove.grab_focus()
	remove.pressed.emit()
	check(marina in Profiles.ids(), "первое нажатие — ещё не удалили")
	remove.pressed.emit()
	check(not marina in Profiles.ids(), "второе — удалили")
	await frames(2)
	check_eq(screen._editing_player, "", "вернулись к списку игроков")


func test_avatars() -> void:
	about("Аватары: встроенные картинки есть все, своя картинка копируется квадратом 256×256")
	for avatar: Array in Profiles.AVATARS:
		check(load(Profiles.AVATAR_DIR.path_join(avatar[0] + ".png")) is Texture2D, "есть картинка " + avatar[0])
	var marina := Profiles.add()
	check(Profiles.avatar_texture(marina) == null, "сначала картинки нет — буква")
	Settings.set_value(Profiles.section_of(marina), "avatar", Profiles.AVATAR_DIR.path_join("fox.png"))
	check(Profiles.avatar_texture(marina) != null, "встроенная загружается")
	# Своя: прямоугольная картинка 400×300 → квадрат 256×256.
	var photo := Image.create(400, 300, false, Image.FORMAT_RGB8)
	photo.fill(Color.ORANGE)
	var photo_path := ProjectSettings.globalize_path(FOLDER.path_join("photo.jpg"))
	photo.save_jpg(photo_path)
	check(Profiles.set_custom_avatar(marina, photo_path), "своя картинка принята")
	var texture := Profiles.avatar_texture(marina)
	check(texture != null and texture.get_size() == Vector2(256, 256), "копия — 256×256")
	check(not Profiles.set_custom_avatar(marina, ProjectSettings.globalize_path(FOLDER.path_join("NES/Mario (USA).nes"))),
			"не картинка — отказ")
	await _open("settings", {"page": "players", "rows": true})
	get_tree().current_scene._open_player(marina)
	await frames(2)
	check(get_tree().current_scene._player_preview.visible, "справа — большой кружок игрока")
