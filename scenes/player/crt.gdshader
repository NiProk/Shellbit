shader_type canvas_item;
// ЭЛТ-телевизор: тёмные полосы между строками, лёгкая выпуклость
// и затемнение краёв, как у кинескопа.

uniform float scanline_strength = 0.35; // насколько тёмные полосы (0 — нет)
uniform float curvature = 0.06;         // выпуклость экрана (0 — плоский)
uniform float vignette = 0.5;           // затемнение углов

void fragment() {
	// 1) Выпуклость: сдвигаем точку тем сильнее, чем дальше она от центра.
	vec2 centered = UV - 0.5;
	vec2 uv = UV + centered * dot(centered, centered) * curvature;

	// За краем «кинескопа» — чёрное.
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		vec4 color = texture(TEXTURE, uv);

		// 2) Полосы развёртки. TEXTURE_PIXEL_SIZE — размер одного пикселя
		// картинки приставки, поэтому row — номер строки этой картинки.
		// fract(row) — место внутри строки: 0 сверху, 1 снизу.
		// sin делает середину строки яркой, а края — тёмными.
		float row = uv.y / TEXTURE_PIXEL_SIZE.y;
		float line = sin(fract(row) * 3.14159);
		color.rgb *= mix(1.0 - scanline_strength, 1.0, line);

		// 3) Углы чуть темнее.
		vec2 d = uv - 0.5;
		color.rgb *= 1.0 - dot(d, d) * vignette;

		// Полосы съедают яркость — немного добавим.
		color.rgb *= 1.15;
		COLOR = color;
	}
}
