shader_type canvas_item;
// Обложка-заглушка для игры без обложки (см. GameCard.gd):
// градиент цвета приставки со скруглёнными углами и мягким бликом.
//
// Почему шейдер, а не картинка-градиент: карточек в библиотеке много,
// и при прокрутке они всё время меняют игру. Шейдеру достаточно
// поменять два цвета — новую картинку создавать не нужно.

uniform vec2 size = vec2(168.0, 224.0);  // размер карточки в пикселях (задаёт скрипт)
uniform float radius = 14.0;             // скругление углов — как у фона карточки
uniform vec4 top_color : source_color = vec4(0.5, 0.2, 0.2, 1.0);     // сверху — цвет приставки
uniform vec4 bottom_color : source_color = vec4(0.08, 0.08, 0.1, 1.0); // снизу — тёмный, под текст

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;  // координата точки внутри карточки (от 0,0 до size)
}

void fragment() {
	vec2 uv = local_pos / size;  // 0..1 по ширине и высоте

	// Градиент чуть наискосок: в основном сверху вниз, немного слева направо.
	float t = clamp(uv.y * 0.85 + (1.0 - uv.x) * 0.15, 0.0, 1.0);
	// smoothstep вместо прямой — переход мягче, без заметной «полосы».
	vec3 color = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.0, 1.0, t));

	// Блик: светлое пятно в правом верхнем углу, как отражение на пластике.
	// Умножение на size делает пятно круглым, а не вытянутым по карточке.
	vec2 from_light = (uv - vec2(0.9, 0.05)) * size / max(size.x, size.y);
	float shine = 1.0 - smoothstep(0.0, 0.75, length(from_light));
	color += top_color.rgb * 0.35 * shine;

	// Скруглённые углы — как в RoundedCorners.gdshader: расстояние до края
	// скруглённого прямоугольника, снаружи — прозрачно.
	vec2 half_size = size * 0.5;
	vec2 p = abs(local_pos - half_size) - (half_size - vec2(radius));
	float dist = length(max(p, 0.0)) - radius;
	COLOR = vec4(color, clamp(0.5 - dist, 0.0, 1.0));
}
