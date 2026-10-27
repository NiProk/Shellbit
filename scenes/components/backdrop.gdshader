shader_type canvas_item;
// Фон по выбранной игре (см. Backdrop.gd): уже размытая картинка
// смешивается с обычным цветом фона Shellbit.
//
// Картинка видна сильнее всего в правом верхнем углу (там пусто),
// а к краям, к низу и к левой стороне уходит в обычный фон — там
// надписи и плитки, и им нужен спокойный тёмный фон, чтобы читаться.

uniform vec4 base_color : source_color = vec4(0.043, 0.059, 0.09, 1.0);
uniform float strength = 0.5;     // сколько картинки в самом ярком месте: 0 — нет, 1 — вся
uniform float saturation = 1.25;  // насыщенность: 1 — как есть, больше — сочнее

void fragment() {
	vec3 picture = texture(TEXTURE, UV).rgb;

	// Насыщенность: отодвигаем цвет от серого (яркость по формуле для глаза).
	float gray = dot(picture, vec3(0.299, 0.587, 0.114));
	picture = mix(vec3(gray), picture, saturation);

	// SCREEN_UV — где на экране эта точка: (0,0) — левый верх, (1,1) — правый низ.
	// Самое яркое место — справа сверху, дальше от него — темнее.
	vec2 from_light = (SCREEN_UV - vec2(0.75, 0.2)) * vec2(1.0, 1.4);
	float light = 1.0 - smoothstep(0.1, 0.95, length(from_light));
	// Ещё и общая подсветка всего экрана, чуть-чуть — чтобы картинка
	// угадывалась и под плитками, а не обрывалась.
	light = max(light, 0.35);

	vec3 color = mix(base_color.rgb, picture, strength * light);
	// COLOR.a — прозрачность от modulate: так Backdrop плавно проявляет картинку.
	COLOR = vec4(color, COLOR.a);
}
