shader_type canvas_item;
// Сетка LCD: тонкие тёмные линии между пикселями,
// как на экране Game Boy и других портативных приставок.

uniform float grid_strength = 0.3; // насколько тёмная сетка (0 — нет)
uniform float line_width = 0.14;   // толщина линии в долях пикселя

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	// cell — место внутри одного пикселя приставки: от (0,0) до (1,1).
	vec2 cell = fract(UV / TEXTURE_PIXEL_SIZE);
	// step(a, b) = 1, если b >= a. Внутри пикселя — 1, на краю (линия) — 0.
	float inside = step(line_width, cell.x) * step(line_width, cell.y);
	color.rgb *= mix(1.0 - grid_strength, 1.0, inside);
	color.rgb *= 1.08;
	COLOR = color;
}
