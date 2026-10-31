extends TestCase
## Tab — «Обновить список» / «Версия», а не переход между кнопками.


func test_tab_is_details_not_focus_next() -> void:
	about("Tab — это действие details, Godot не уводит по нему фокус")
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	tab.keycode = KEY_TAB
	tab.pressed = true
	check(tab.is_action_pressed("details"), "Tab = details")
	check(not tab.is_action_pressed("ui_focus_next"), "Tab больше не «следующая кнопка»")
