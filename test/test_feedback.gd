extends TestCase
## Звук подключения геймпада и вибрация в меню.


func test_pad_sounds() -> void:
	about("Подключили геймпад — перезвон вверх, отключили — вниз")
	PadNotifier._on_joy_connection_changed(7, true)
	check(UiSounds._pad.stream == UiSounds.PAD_ON, "подключили — pad_on.wav")
	PadNotifier._on_joy_connection_changed(7, false)
	check(UiSounds._pad.stream == UiSounds.PAD_OFF, "отключили — pad_off.wav")
	UiSounds._pad.stop()


func test_haptics_safe_without_pad() -> void:
	about("Вибрация без геймпада (с клавиатуры) ничего не ломает, и её можно выключить")
	check(Haptics.enabled(), "по умолчанию включена")
	Haptics.tap()
	Haptics.confirm()
	await Haptics.error()
	Settings.set_value("controls", "ui_rumble", false)
	check(not Haptics.enabled(), "выключили в настройках")
	Settings.set_value("controls", "ui_rumble", null)
