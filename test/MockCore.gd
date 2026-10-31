extends Node
## «Ненастоящее» ядро для тестов экрана игры.
##
## Умеет то же, что нужно Player.gd от RetroCore, но ничего не эмулирует:
## просто считает кадры. Сохранение — это номер кадра в начале «снимка».
## Так видно, перематывает ли Player назад и ускоряет ли игру.

var frame := 0             # сколько кадров «просчитано»
var inputs := [0, 0]       # что Player передал как нажатые кнопки
var state_size := 300 * 1024  # сколько весит снимок (у SNES — около 300 КБ)
var _audio := 0


func is_running() -> bool:
	return true


func set_input(port: int, mask: int) -> void:
	inputs[port] = mask


var sticks := {}  # Vector2i(порт, стик) → Vector2

func set_analog(port: int, stick: int, x: float, y: float) -> void:
	sticks[Vector2i(port, stick)] = Vector2(x, y)


var gun := []           # что Player передал пистолету: [порт, x, y, курок, мимо экрана]
var plugged := {}       # порт → какой контроллер «вставили»

func set_lightgun(port: int, x: float, y: float, trigger: bool, reload: bool) -> void:
	gun = [port, x, y, trigger, reload]

func get_controller_types(_port: int) -> Array:
	return [{"name": "Auto", "id": 1}, {"name": "Zapper", "id": 258}]

func set_controller_type(port: int, device: int) -> void:
	plugged[port] = device


var disk_count := 1   # сколько «дисков» у игры
var disk_index := 0

func get_disk_count() -> int:
	return disk_count

func get_disk_index() -> int:
	return disk_index

func get_disk_path(index: int) -> String:
	return "disc%d.cue" % (index + 1)

func set_disk(index: int) -> bool:
	disk_index = index
	return true


var rumble := Vector2.ZERO  # какую вибрацию «хочет игра»
var rumble_asked := 0       # сколько раз Player спросил про вибрацию

func get_rumble(_port: int) -> Vector2:
	rumble_asked += 1
	return rumble


func run_frame() -> void:
	frame += 1
	_audio += 800  # звуковые кадры, как будто ядро что-то сыграло


func save_state() -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(state_size)
	data.encode_u32(0, frame)
	return data


func load_state(data: PackedByteArray) -> bool:
	frame = data.decode_u32(0)
	return true


func has_new_frame() -> bool:
	return false


func get_frame() -> Image:
	return null  # картинки у ненастоящего ядра нет


func take_audio() -> PackedVector2Array:
	var audio := PackedVector2Array()
	audio.resize(_audio)
	_audio = 0
	return audio


func save_sram() -> void:
	pass


func unload() -> void:
	pass


var cheats := {}          # номер → [включён, код]: что Player передал ядру
var cheats_supported := true

func has_cheats() -> bool:
	return cheats_supported

func cheat_reset() -> void:
	cheats.clear()

func cheat_set(index: int, enabled: bool, code: String) -> void:
	cheats[index] = [enabled, code]
