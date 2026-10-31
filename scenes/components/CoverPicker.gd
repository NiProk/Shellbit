class_name CoverPicker
extends Node
## Меню «Обложка»: выбрать свою картинку или убрать её.
##
## Компонент, который можно добавить на любой экран:
##   var picker := CoverPicker.new()
##   add_child(picker)
##   picker.open(group, кнопка_куда_вернуть_фокус)
##
## Раньше этот код жил прямо в Library.gd. Когда он понадобился ещё
## и в карточке игры, мы вынесли его в отдельный узел — так не нужно
## копировать одно и то же в два места.

enum Item { PICK, REMOVE, CANCEL }

var _menu: PopupMenu
var _dialog: FileDialog
var _group: Dictionary = {}
var _focus_back: Control  # кому вернуть фокус, когда меню закроется


func _ready() -> void:
	# PopupMenu — всплывающий список пунктов. Им можно управлять
	# и мышью, и геймпадом: стрелки + A, а B закрывает.
	_menu = PopupMenu.new()
	_menu.add_item(tr("Выбрать свою обложку…"), Item.PICK)
	_menu.add_item(tr("Убрать свою обложку"), Item.REMOVE)
	_menu.add_separator()
	_menu.add_item(tr("Отмена"), Item.CANCEL)
	_menu.add_theme_font_size_override("font_size", 20)
	_menu.id_pressed.connect(_on_item_pressed)
	_menu.popup_hide.connect(_restore_focus)
	add_child(_menu)

	# Системное окно Windows «Открыть файл».
	_dialog = FileDialog.new()
	_dialog.title = tr("Картинка для обложки")
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	Platform.setup_file_dialog(_dialog)  # на Android — своё окно Godot
	_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; " + tr("Картинки")])
	_dialog.file_selected.connect(_on_file_selected)
	_dialog.canceled.connect(_restore_focus)
	add_child(_dialog)


## Показать меню для игры (группы).
func open(group: Dictionary, focus_back: Control) -> void:
	_group = group
	_focus_back = focus_back
	# «Убрать» имеет смысл, только если своя обложка уже выбрана.
	_menu.set_item_disabled(_menu.get_item_index(Item.REMOVE), not Covers.has_custom_cover(group))
	_menu.popup_centered()
	_menu.grab_focus()


func _on_item_pressed(id: int) -> void:
	match id:
		Item.PICK:
			_dialog.popup_centered_ratio(0.6)
		Item.REMOVE:
			Covers.remove_custom_cover(_group)
			SceneRouter.toast(tr("Своя обложка убрана"))


func _on_file_selected(path: String) -> void:
	if Covers.set_custom_cover(_group, path):
		SceneRouter.toast(tr("Обложка обновлена"))
	else:
		SceneRouter.toast(tr("Не получилось открыть картинку"))
	_restore_focus()


func _restore_focus() -> void:
	if is_instance_valid(_focus_back):
		_focus_back.grab_focus.call_deferred()
