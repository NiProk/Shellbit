shader_type canvas_item;
// Размытый и затемнённый кадр для полей по бокам от картинки.
// Каждая точка — среднее цвета 49 соседних точек (сетка 7×7).

uniform float radius = 0.04;    // насколько далеко брать соседей (в долях картинки)
uniform float darkness = 0.4;   // яркость: 1 — как есть, 0 — чёрный

void fragment() {
	vec3 sum = vec3(0.0);
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			vec2 offset = vec2(float(x), float(y)) * radius / 3.0;
			sum += texture(TEXTURE, UV + offset).rgb;
		}
	}
	COLOR = vec4(sum / 49.0 * darkness, 1.0);
}
