shader_type canvas_item;
// Пип моргает (см. PipBlink.gd): поверх белых глаз сверху вниз
// наезжает «веко» цвета панциря, а по его краю — тёмная линия,
// как контур на самой картинке.

uniform vec2 eye_left = vec2(131.0, 40.0);   // центр левого глаза, в пикселях картинки
uniform vec2 eye_right = vec2(218.5, 40.0);  // центр правого глаза
uniform vec2 eye_size = vec2(29.5, 29.5);    // радиус глаза по ширине и высоте (с каймой)
uniform float blink = 0.0;                   // 0 — глаза открыты, 1 — закрыты
uniform vec4 lid_color : source_color = vec4(0.92, 0.42, 0.24, 1.0);   // цвет панциря
uniform vec4 line_color : source_color = vec4(0.38, 0.13, 0.12, 1.0);  // цвет контура

// modulate узла. В fragment() встроенный COLOR — это уже цвет картинки,
// умноженный на modulate; а нам нужен modulate отдельно (иначе веко
// «умножилось» бы на глаз под ним, и сквозь него проступил бы зрачок).
// Поэтому берём его в vertex(), где COLOR — ещё только modulate.
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

// Закрыть веком точку, если она внутри глаза. d — положение точки
// относительно центра глаза: (0,0) — центр, длина 1 — край глаза.
vec4 lid(vec4 color, vec2 d) {
	if (length(d) > 1.0 || blink <= 0.0) {
		return color;  // точка не в глазу или глаза открыты
	}
	// Край века опускается сверху (-1) вниз по мере моргания — и при
	// blink = 1 уходит чуть ниже глаза (1,25), чтобы закрыть его целиком,
	// вместе с тёмной линией и светлой каймой у нижнего края.
	float edge = mix(-1.0, 1.25, blink);
	// Прозрачность — всегда 1: зрачки на картинке полупрозрачные,
	// и с их прозрачностью сквозь веко просвечивал бы фон.
	if (d.y < edge - 0.18) {
		// Глаз почти закрыт — по середине тёмная «складка» века,
		// иначе закрытый глаз выглядел бы просто оранжевым шариком.
		if (blink > 0.85 && abs(d.y - 0.2) < 0.1) {
			return vec4(line_color.rgb, 1.0);
		}
		return vec4(lid_color.rgb, 1.0);   // под веком
	}
	if (d.y < edge) {
		return vec4(line_color.rgb, 1.0);  // тёмная линия по краю века
	}
	return color;
}

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	vec2 pixel = UV / TEXTURE_PIXEL_SIZE;  // где мы на картинке, в её пикселях
	color = lid(color, (pixel - eye_left) / eye_size);
	color = lid(color, (pixel - eye_right) / eye_size);
	COLOR = color * tint;
}
