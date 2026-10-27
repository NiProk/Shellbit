extends TestCase
## Переходы между экранами: затемнение, мозаика, рассыпание.


func after_each() -> void:
	Settings.set_value("look", "transition", "fade")


func test_every_transition_finishes() -> void:
	about("Каждый переход доходит до конца: экран сменился, шторка убрана")
	for mode in ["fade", "mosaic", "dissolve"]:
		Settings.set_value("look", "transition", mode)
		for screen in ["settings", "home"]:
			while SceneRouter._busy:
				await frames(1)
			SceneRouter.go_to(screen)
			await frames(1)
			check(SceneRouter._busy, "%s: переход начался" % mode)
			var waited := 0
			while SceneRouter._busy and waited < 300:
				await frames(1)
				waited += 1
			check(not SceneRouter._busy, "%s: переход закончился" % mode)
			check_eq(get_tree().current_scene.scene_file_path, SceneRouter.SCENES[screen], "%s: открылся экран %s" % [mode, screen])
			check(SceneRouter._fade.material == null, "%s: шейдер шторки убран" % mode)
			check_eq(SceneRouter._fade.color.a, 0.0, "%s: шторка прозрачная" % mode)
