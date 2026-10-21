class_name TestCase
extends Node
## Основа для набора тестов. Каждый файл test/test_*.gd наследуется от неё.
##
## Как написать тест:
##   extends TestCase
##
##   func test_two_plus_two() -> void:
##       about("Сложение работает")          # описание — его покажет Test.bat
##       check_eq(2 + 2, 4, "2 + 2 должно быть 4")
##
## Каждая функция, чьё имя начинается с test_, — отдельный тест.
## Запускалка (TestRunner.gd) находит их сама. Внутри можно ждать кадры:
##   await frames(5)
##
## Проверки:
##   check(условие, "что не так")            — условие должно быть true
##   check_eq(получилось, ожидали, "…")     — два значения должны совпасть
##   check_has(список_или_словарь, что, "…") — внутри должно быть «что»
## Проверка не останавливает тест: он идёт дальше и соберёт все ошибки.

## Описание текущего теста (по-русски) — запускалка печатает его.
var description := ""
## Что пошло не так в текущем тесте.
var failures: PackedStringArray = []


## Вызывается перед каждым тестом этого файла. Переопределите, если нужно.
func before_each() -> void:
	pass


## Вызывается после каждого теста — чтобы убрать за собой.
func after_each() -> void:
	pass


func about(text: String) -> void:
	description = text


func check(condition: bool, message := "условие не выполнено") -> bool:
	if not condition:
		failures.append(message)
	return condition


func check_eq(actual: Variant, expected: Variant, message := "") -> bool:
	# Значения разных типов (число и строка) Godot сравнивать не умеет —
	# такую ошибку считаем просто несовпадением. Целое и дробное число — можно.
	var numbers := [TYPE_INT, TYPE_FLOAT]
	var comparable := typeof(actual) == typeof(expected) \
			or (typeof(actual) in numbers and typeof(expected) in numbers)
	if comparable and actual == expected:
		return true
	failures.append("%s\n        получилось: %s\n        ожидали:    %s" % [
		message if message != "" else "значения не совпали", var_to_str(actual), var_to_str(expected)])
	return false


func check_has(container: Variant, item: Variant, message := "") -> bool:
	if container.has(item):
		return true
	failures.append("%s\n        нет %s в %s" % [
		message if message != "" else "не нашли значение", var_to_str(item), var_to_str(container)])
	return false


## Подождать count кадров (например, пока экран соберётся).
func frames(count := 1) -> void:
	for i in count:
		await get_tree().process_frame
