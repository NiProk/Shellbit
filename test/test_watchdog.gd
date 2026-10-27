extends TestCase
## Сторож зависаний и чтение обложек с неправильным расширением.


func test_watchdog_notices_stall() -> void:
	about("Сторож замечает, что главный поток замер дольше 2 секунд")
	await frames(2)
	check(not Watchdog._stall_reported, "сначала всё спокойно")
	OS.delay_msec(2700)  # «зависаем»: главный поток ничего не делает 2,7 с
	check(Watchdog._stall_reported, "сторож заметил зависание (пока мы стояли)")
	await frames(2)
	check(not Watchdog._stall_reported, "кадр прошёл — сторож отметил, что всё снова работает")


func test_cover_with_wrong_extension() -> void:
	about("JPG с расширением .png читается (формат узнаём по содержимому)")
	var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
	image.fill(Color.RED)
	var path := ProjectSettings.globalize_path("user://wrong_extension.png")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(image.save_jpg_to_buffer())  # внутри JPG, а называется .png
	file.close()
	var loaded := Covers.load_any_image(path)
	check(loaded != null and loaded.get_width() == 8, "картинка прочиталась")
	FileAccess.open(path, FileAccess.WRITE).store_string("это не картинка, просто текст")
	check_eq(Covers.load_any_image(path), null, "текстовый файл — не картинка")
	DirAccess.remove_absolute(path)
