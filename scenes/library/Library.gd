extends Control
## Экран библиотеки одной приставки: сетка игр + панель с информацией.
##
## Какую приставку показать, экран узнаёт из SceneRouter.params:
##   SceneRouter.go_to("library", {"system": "snes"})
##
## Каждая карточка — это ИГРА (группа версий), а не отдельный файл.

const GameCardScene := preload("res://scenes/components/GameCard.tscn")
const MAX_VERSION_LINES := 8  # сколько версий показывать в панели

var system_id := ""


func _ready() -> void:
	system_id = SceneRouter.params.get("system", "")
	var system := CoreManager.get_system(system_id)
	var groups := Library.groups_for_system(system_id)

	%Strip.color = Color(system.get("color", "#888888"))
	%SystemName.text = system.get("name", "Неизвестная приставка")
	%Count.text = Library.count_text(groups.size())

	for group: Dictionary in groups:
		var card: GameCard = GameCardScene.instantiate()
		%Grid.add_child(card)
		card.setup(group, GameCard.Style.COVER)
		card.pressed.connect(_on_game_pressed.bind(group))
		# Когда карточка получает фокус — показываем её данные справа.
		card.focus_entered.connect(_show_info.bind(group))

	%Hints.set_hints([
		["page", "Другая приставка"],
		["accept", "Играть"],
		["details", "Версия"],
		["favorite", "Избранное"],
		["cancel", "Назад"],
	])

	if %Grid.get_child_count() > 0:
		%Grid.get_child(0).grab_focus.call_deferred()


func _show_info(group: Dictionary) -> void:
	var chosen := Library.chosen_variant(group)
	%InfoTitle.text = group["title"]
	%InfoText.text = "\n".join([
		"Время в игре: " + Library.playtime_text(int(group["play_seconds"])),
		"Последний запуск: " + Library.last_played_text(int(group["last_played"])),
	])

	# Список версий. RichTextLabel понимает BBCode — разметку в [квадратных]
	# скобках: [color=#ffffff]текст[/color] красит часть строки.
	var variants: Array = group["variants"]
	%VersionsTitle.text = "%d %s" % [variants.size(), Library.plural(variants.size(), "версия", "версии", "версий")]
	var lines: Array[String] = []
	for i in mini(variants.size(), MAX_VERSION_LINES):
		var variant: Dictionary = variants[i]
		var line: String = variant["version"]
		if variant == chosen:
			line = "[color=#5eead4]▶ " + line + "[/color]"
		else:
			line = "   " + line
		lines.append(line)
	if variants.size() > MAX_VERSION_LINES:
		lines.append("   …и ещё %d" % (variants.size() - MAX_VERSION_LINES))
	%Versions.text = "\n".join(lines)
	# Если версия одна — переключать нечего, список не нужен.
	%Versions.visible = variants.size() > 1


func _unhandled_input(event: InputEvent) -> void:
	var focused := get_viewport().gui_get_focus_owner()

	if event.is_action_pressed("ui_cancel"):
		SceneRouter.back()
	elif event.is_action_pressed("favorite") and focused is GameCard:
		Library.toggle_favorite(focused.game)
		focused.refresh()
	elif event.is_action_pressed("details") and focused is GameCard:
		_next_version(focused.game)
	elif event.is_action_pressed("page_left"):
		_switch_system(-1)
	elif event.is_action_pressed("page_right"):
		_switch_system(1)
	elif focused == null and event.is_action_pressed("ui_down"):
		if %Grid.get_child_count() > 0:
			%Grid.get_child(0).grab_focus()
	else:
		return  # нажатие нам не нужно — пусть идёт дальше
	get_viewport().set_input_as_handled()


func _next_version(group: Dictionary) -> void:
	if group["variants"].size() < 2:
		SceneRouter.toast("У этой игры только одна версия")
		return
	var variant := Library.choose_next_variant(group)
	_show_info(group)
	SceneRouter.toast("Версия: " + variant["version"])


# Переключиться на соседнюю приставку (по кругу).
func _switch_system(step: int) -> void:
	var ids := Library.systems_with_games()
	if ids.size() < 2:
		return
	var index := ids.find(system_id)
	var next_id := ids[(index + step + ids.size()) % ids.size()]
	SceneRouter.replace("library", {"system": next_id})


# Карточка — это игра (группа версий). Запускаем выбранную версию.
func _on_game_pressed(group: Dictionary) -> void:
	SceneRouter.go_to("player", {"game": Library.chosen_variant(group)})
