class_name GameMenu
extends Node
## Меню игры по долгому нажатию на карточку (на компьютере — правая кнопка мыши):
##
##   ★ В избранное
##   ── Версия ──
##   ◉ США
##   ○ Япония · перевод Rus
##   Обложка…
##   Отмена
##
## На телефоне нет клавиш F (избранное), Tab (версия) и F1 (обложка) —
## всё это теперь здесь. Работает и с геймпадом, и с мышью.
##
## Использование:
##   var menu := GameMenu.new()
##   add_child(menu)
##   menu.changed.connect(...)          # избранное или версия поменялись
##   menu.open(group, карточка)

## Поменяли избранное или версию — экран обновит карточку и панель.
signal changed(group: Dictionary)

enum Item { FAVORITE = 1, COVER = 2, CANCEL = 3, VERSION = 100 }

var _menu: PopupMenu
var _picker := CoverPicker.new()  # «Обложка…» — то же меню, что по F1
var _group: Dictionary = {}
var _focus_back: Control


func _ready() -> void:
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_item)
	_menu.popup_hide.connect(_restore_focus.call_deferred)
	add_child(_menu)
	add_child(_picker)


func open(group: Dictionary, focus_back: Control) -> void:
	_group = group
	_focus_back = focus_back
	_menu.clear()
	_menu.add_item(tr("★ Убрать из избранного") if group["favorite"] else tr("В избранное"), Item.FAVORITE)
	var variants: Array = group["variants"]
	if variants.size() > 1:
		_menu.add_separator(tr("Версия"))
		var chosen := Library.chosen_variant(group)
		for i in variants.size():
			_menu.add_radio_check_item(String(variants[i]["version"]), Item.VERSION + i)
			_menu.set_item_checked(_menu.get_item_count() - 1, variants[i] == chosen)
	# В детском режиме обложку не меняем (как и по F1).
	if not Family.is_on():
		_menu.add_item(tr("Обложка…"), Item.COVER)
	_menu.add_separator()
	_menu.add_item(tr("Отмена"), Item.CANCEL)

	# На телефоне пункты крупнее, чтобы попадать пальцем.
	var touch := Platform.touch_first()
	_menu.add_theme_font_size_override("font_size", 26 if touch else 20)
	_menu.add_theme_constant_override("v_separation", 22 if touch else 10)
	_menu.reset_size()
	_menu.popup_centered()
	_menu.grab_focus()


# Фокус — обратно на карточку. Экран мог её уже пересоздать (главный
# экран после «В избранное» собирает ряды заново) — тогда ничего не делаем.
func _restore_focus() -> void:
	if is_instance_valid(_focus_back) and _focus_back.is_inside_tree() and _focus_back.is_visible_in_tree():
		_focus_back.grab_focus()


func _on_item(id: int) -> void:
	if id == Item.FAVORITE:
		Library.toggle_favorite(_group)
		Haptics.tap()
		SceneRouter.toast(tr("★ В избранном") if _group["favorite"] else tr("Убрано из избранного"))
		changed.emit(_group)
	elif id == Item.COVER:
		_picker.open(_group, _focus_back)
	elif id >= Item.VERSION:
		var variant: Dictionary = _group["variants"][id - Item.VERSION]
		Library.choose_variant(_group, variant)
		SceneRouter.toast(tr("Версия: %s") % variant["version"])
		changed.emit(_group)
