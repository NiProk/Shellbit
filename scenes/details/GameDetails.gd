extends Control
## Страница игры: обложка, название, год и жанр, кнопки и сохранения.
##
## Открывается из библиотеки:  SceneRouter.go_to("details", {"key": "nes_battletoads"})
## Мы передаём КЛЮЧ, а не саму игру: пока человек играет, библиотека
## пересобирает свои данные, и при возврате сюда мы найдём свежие.

const SaveCardScene := preload("res://scenes/components/SaveCard.tscn")

var group: Dictionary = {}
var _viewer := TextViewer.new()  # окно с полным описанием
var _picker := CoverPicker.new()


func _ready() -> void:
	group = Library.find_group(SceneRouter.params.get("key", ""))
	if group.is_empty():
		SceneRouter.back.call_deferred()  # игру удалили с диска — возвращаемся
		return

	add_child(_picker)
	add_child(_viewer)
	_style_buttons()

	%PlayButton.pressed.connect(_play.bind(SaveStates.AUTO))
	%RestartButton.pressed.connect(_on_restart_pressed)
	# Ушли с кнопки, не нажав второй раз, — отменяем «Нажмите ещё раз».
	%RestartButton.focus_exited.connect(_disarm_restart)
	%FavButton.pressed.connect(_toggle_favorite)
	%VersionButton.pressed.connect(_next_version)
	%CoverButton.pressed.connect(func() -> void: _picker.open(group, %CoverButton))
	%MoreButton.pressed.connect(func() -> void: _viewer.open(%Title.text, %Description.text))
	# Окно закрыли — фокус обратно на кнопку, которая его открыла.
	_viewer.closed.connect(%MoreButton.grab_focus)
	Covers.cover_ready.connect(_on_cover_ready)

	# Карточки сохранений: «место выхода» и три ручных слота.
	for slot: String in [SaveStates.AUTO] + SaveStates.MANUAL_SLOTS:
		var card: SaveSlot = SaveCardScene.instantiate()
		card.slot = slot
		%Saves.add_child(card)
		card.pressed.connect(_play.bind(slot))

	%Hints.set_hints([
		["accept", "Выбрать"],
		["favorite", "Избранное"],
		["details", "Версия"],
		["menu", "Обложка"],
		["cancel", "Назад"],
	])
	_refresh()
	%PlayButton.grab_focus.call_deferred()
	# Всё, что справа от обложки, лежит в InfoScroll — ScrollContainer,
	# «окошке с прокруткой». Колесо мыши он прокручивает сам, а для
	# геймпада следим, куда ушёл фокус, и прокручиваем к нему.
	get_viewport().gui_focus_changed.connect(_scroll_to)


## Заполнить экран данными игры. Вызывается и после смены версии.
func _refresh() -> void:
	var system := CoreManager.get_system(group["system"])
	var variant := Library.chosen_variant(group)
	var info := GameInfo.lookup(group)

	%SystemTag.text = tr(system.get("name", "?"))
	%SystemTag.add_theme_stylebox_override("normal", UiTheme.tag_box(Color(system.get("color", "#888888"))))
	# Название на языке интерфейса — если оно есть в файле описания
	# (строка «title:»). Иначе — название из имени файла.
	var title: String = info["title"] if info["title"] != "" else group["title"]
	%Title.text = title
	%CoverPlaceholder.text = title

	# «1991 · Beat 'em up · 1–2 игрока · Rareware» — каждое сведение своим цветом.
	_fill_meta(info)

	# Под обложкой: сколько наиграно и когда запускали.
	var seconds := int(group["play_seconds"])
	%PlayTime.text = tr("Время в игре: %s") % Library.playtime_text(seconds)
	%PlayTime.visible = seconds > 0  # ни разу не играли — время не показываем
	%LastPlayed.text = tr("Последний запуск: %s") % Library.last_played_text(int(group["last_played"]))

	%Description.text = info["description"]
	%Description.visible = info["description"] != ""
	_update_more_button()

	var count: int = group["variants"].size()
	%Version.text = tr("Версия: %s") % variant["version"]
	if count > 1:
		%Version.text += "  " + tr("(всего %d)") % count
	%VersionButton.visible = count > 1

	%FavButton.text = tr("★ В избранном") if group["favorite"] else tr("В избранное")

	# Сохранения относятся к конкретному файлу, поэтому берём выбранную версию.
	var has_auto := SaveStates.exists(variant, SaveStates.AUTO)
	%PlayButton.text = "▶  " + (tr("Продолжить") if has_auto else tr("Играть"))
	# «Начать заново» нужна, только если есть место выхода, — иначе
	# «Играть» и так запускает игру с самого начала.
	%RestartButton.visible = has_auto
	_disarm_restart()
	for card: SaveSlot in %Saves.get_children():
		card.setup(variant, card.slot)
		# «Место выхода» показываем, только если оно есть.
		if card.slot == SaveStates.AUTO:
			card.visible = has_auto

	_show_cover(Covers.get_cover(group))


# Цвета сведений об игре. Можно менять на свой вкус.
const META_COLORS := {
	"year": Color("5eead4"),       # год — бирюзовый (как акцент приложения)
	"genre": Color("e6eaf2"),      # жанр — светлый
	"players": Color("f0a04c"),    # число игроков — оранжевый
	"developer": Color("a78bfa"),  # разработчик — сиреневый
}


## Строка сведений: отдельная надпись на каждое поле, между ними — « · ».
## Meta — это HFlowContainer: он ставит детей в ряд, а если ряд
## не помещается по ширине, переносит остаток на следующую строку.
func _fill_meta(info: Dictionary) -> void:
	for child in %Meta.get_children():
		%Meta.remove_child(child)
		child.queue_free()

	var empty := true
	for field: String in ["year", "genre", "players", "developer"]:
		if info[field] == "":
			continue  # в базе нет — пропускаем, чтобы не было « ·  · »
		if not empty:
			%Meta.add_child(_meta_label(" · ", UiTheme.TEXT_DIM))
		%Meta.add_child(_meta_label(info[field], META_COLORS[field]))
		empty = false
	%Meta.visible = not empty


func _meta_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_color", color)
	# Не переводить автоматически: название студии или жанр уже готовы.
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	return label


## Показать «Читать полностью», если описание не влезло в 3 строки.
## Сколько строк получится, станет известно только после того, как Godot
## расставит элементы по местам — поэтому сначала ждём один кадр.
func _update_more_button() -> void:
	%MoreButton.visible = false
	await get_tree().process_frame
	# get_line_count() — сколько строк занимает ВЕСЬ текст,
	# max_lines_visible — сколько из них мы показываем (3).
	%MoreButton.visible = %Description.visible \
			and %Description.get_line_count() > %Description.max_lines_visible


func _show_cover(texture: Texture2D) -> void:
	%Cover.texture = texture
	%CoverPlaceholder.visible = texture == null


func _on_cover_ready(key: String, texture: Texture2D) -> void:
	if key == group["key"]:
		_show_cover(texture)


## Фокус перешёл на control — прокрутить так, чтобы его было видно.
## У ScrollContainer есть готовый follow_focus, но он прокручивает
## «впритык» — и светящаяся рамка фокуса обрезается краем. Поэтому сами:
##  - карточки сохранений — в самом низу, туда и прокручиваем до упора
##    (с отступом Pad, рамка поместится целиком);
##  - всё остальное — сначала наверх, а если и там не видно — к самой кнопке.
func _scroll_to(control: Control) -> void:
	var scroll: ScrollContainer = %InfoScroll
	if control == null or not scroll.is_ancestor_of(control):
		return  # фокус где-то ещё (например, в окне выбора обложки)
	if control.get_parent() == %Saves:
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	else:
		scroll.scroll_vertical = 0
		scroll.ensure_control_visible(control)


# --- Действия --------------------------------------------------------------

## Запустить игру. slot = AUTO — с места выхода (или с начала, если его нет),
## "1".."3" — с ручного сохранения.
## "" — с самого начала, без сохранений.
func _play(slot: String) -> void:
	var variant := Library.chosen_variant(group)
	if slot != SaveStates.AUTO and slot != "" and not SaveStates.exists(variant, slot):
		SceneRouter.toast(tr("Слот %s пуст — сохраниться можно в меню паузы") % slot)
		return
	SceneRouter.go_to("player", {"game": variant, "slot": slot})


## «Начать заново» — в два нажатия. При выходе из игры место выхода
## перезапишется, и прошлый прогресс (если он не сохранён в слот) пропадёт.
## Поэтому первое нажатие только предупреждает.
func _on_restart_pressed() -> void:
	if not %RestartButton.get_meta("armed", false):
		%RestartButton.set_meta("armed", true)  # meta — своя пометка на узле
		%RestartButton.text = "↺  " + tr("Нажмите ещё раз")
		SceneRouter.toast(tr("Игра начнётся с самого начала. Место выхода заменится новым, ручные слоты останутся."))
		return
	_disarm_restart()
	_play("")  # "" — без загрузки сохранения


func _disarm_restart() -> void:
	%RestartButton.set_meta("armed", false)
	%RestartButton.text = "↺  " + tr("Начать заново")


func _toggle_favorite() -> void:
	Library.toggle_favorite(group)
	_refresh()


func _next_version() -> void:
	if group["variants"].size() < 2:
		return
	var variant := Library.choose_next_variant(group)
	_refresh()
	SceneRouter.toast(tr("Версия: %s") % variant["version"])


func _unhandled_input(event: InputEvent) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if event.is_action_pressed("ui_cancel"):
		SceneRouter.back()
	elif event.is_action_pressed("favorite"):
		_toggle_favorite()
	elif event.is_action_pressed("details"):
		_next_version()
	elif event.is_action_pressed("menu"):
		_picker.open(group, focused if focused else %PlayButton)
	elif focused == null and (event.is_action_pressed("ui_down") or event.is_action_pressed("ui_right")):
		%PlayButton.grab_focus()
	else:
		return
	get_viewport().set_input_as_handled()


# --- Оформление кнопок -----------------------------------------------------
# Кнопки-«пилюли» как на макете. «Играть» — залитая акцентным цветом.

func _style_buttons() -> void:
	_pill(%PlayButton, UiTheme.ACCENT, UiTheme.ACCENT.lightened(0.15), UiTheme.BG)
	for button: Button in [%RestartButton, %FavButton, %VersionButton, %CoverButton]:
		_pill(button, UiTheme.CARD, UiTheme.CARD_HOVER, UiTheme.TEXT)
	_pill(%MoreButton, UiTheme.CARD, UiTheme.CARD_HOVER, UiTheme.ACCENT)


func _pill(button: Button, color: Color, hover: Color, text: Color) -> void:
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = hover if state != "normal" else color
		box.set_corner_radius_all(28)
		box.content_margin_left = 22
		box.content_margin_right = 22
		button.add_theme_stylebox_override(state, box)
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		button.add_theme_color_override(state, text)
	# Рамка фокуса — тоже скруглённая, чтобы обнимала «пилюлю».
	var focus: StyleBoxFlat = UiTheme.theme.get_stylebox("focus", "Button").duplicate()
	focus.set_corner_radius_all(32)
	button.add_theme_stylebox_override("focus", focus)
