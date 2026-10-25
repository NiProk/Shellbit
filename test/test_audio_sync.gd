extends TestCase
## Синхронизация по звуку (scripts/AudioSync.gd): подстройка частоты и модель
## «эмулятор + звуковая карта с неточными часами».


func test_ratio() -> void:
	about("Подстройка частоты: не больше ±0,5%, в нужную сторону")
	var sync := AudioSync.new()
	check(is_equal_approx(sync.ratio(AudioSync.TARGET_FILL), 1.0), "буфер как надо — звук как есть")
	check(sync.ratio(0.0) > 1.0 and sync.ratio(0.0) <= 1.005 + 0.0001, "пусто — растягиваем (больше сэмплов)")
	check(sync.ratio(1.0) < 1.0 and sync.ratio(1.0) >= 0.995 - 0.0001, "полно — сжимаем")
	check_eq(sync.extra_frames(0.05), 1, "почти пусто — лишний кадр")
	check_eq(sync.extra_frames(0.95), -1, "почти полно — пропустить кадр")
	check_eq(sync.extra_frames(0.4), 0)


func test_resample_smooth() -> void:
	about("Растяжение звука: нужное число сэмплов и без «ступенек» на стыках")
	var sync := AudioSync.new()
	var out := PackedVector2Array()
	var phase := 0.0
	for chunk in 50:  # 50 кадров синусоиды по 800 сэмплов
		var input := PackedVector2Array()
		for i in 800:
			var v := sin(phase)
			input.append(Vector2(v, v))
			phase += TAU * 440.0 / 48000.0
		out.append_array(sync.resample(input, 1.004))
	check(absf(out.size() - 40000 * 1.004) < 3, "сэмплов стало на 0,4% больше (%d)" % out.size())
	var biggest := 0.0
	for i in range(1, out.size()):
		biggest = maxf(biggest, absf(out[i].x - out[i - 1].x))
	# Соседние сэмплы синусоиды 440 Гц отличаются не больше чем на ~0,058.
	check(biggest < 0.07, "нет скачков на стыках кадров (самый большой шаг %.3f)" % biggest)


func test_drift_model() -> void:
	about("Модель: часы звука спешат или отстают на 0,2% — 5 минут игры без щелчков")
	# 0,2% — с большим запасом: кварц в звуковой карте ошибается
	# обычно на сотые доли процента.
	for drift: float in [1.002, 0.998, 1.0005, 0.9995]:
		var result := _simulate(drift, 300.0)
		check_eq(result["silence_ms"], 0.0, "звук не прерывался (часы %+.1f%%)" % ((drift - 1.0) * 100))
		check_eq(result["dropped"], 0, "звук не выбрасывался (часы %+.1f%%)" % ((drift - 1.0) * 100))


# Тот же расчёт, что в Player._process и _push_audio, но вместо звуковой
# карты — число: сколько звука в буфере.
func _simulate(drift: float, seconds: float) -> Dictionary:
	var sync := AudioSync.new()
	sync.capacity = 4096
	var buffer := float(sync.capacity) * AudioSync.TARGET_FILL
	var fps := 60.0988  # NES
	var per_frame := 48000.0 / fps
	var bank := 0.0
	var silence_ms := 0.0
	var dropped := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var t := 0.0
	while t < seconds:
		var delta := 1.0 / 60.0 * (1.0 + rng.randf_range(-0.05, 0.05))
		t += delta
		var played := 48000.0 * drift * delta
		if buffer < played:
			silence_ms += (played - buffer) / 48.0
			buffer = 0.0
		else:
			buffer -= played
		bank += delta
		var due := 0
		while bank >= 1.0 / fps and due < 3:
			bank -= 1.0 / fps
			due += 1
		var fill := buffer / sync.capacity
		due = maxi(0, due + sync.extra_frames(fill))
		var produced := per_frame * due * sync.ratio(fill)
		if produced > sync.capacity - buffer:
			dropped += int(produced - (sync.capacity - buffer))
			produced = sync.capacity - buffer
		buffer += produced
	return {"silence_ms": silence_ms, "dropped": dropped}
