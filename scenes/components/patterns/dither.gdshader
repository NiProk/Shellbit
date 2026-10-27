shader_type canvas_item;
// Узор фона «Дизеринг» (см. Backdrop.gd): шахматные клеточки, которыми
// в играх NES и Game Boy рисовали полутени — цветов было мало,
// и промежуточный оттенок получали, чередуя точки двух цветов.

void fragment() {
	vec2 pos = SCREEN_UV * vec2(1920.0, 1080.0);
	vec2 cell = floor(pos / 4.0);
	float checker = mod(cell.x + cell.y, 2.0);  // 0, 1, 0, 1… — как шахматная доска
	float fade = 1.0 - SCREEN_UV.y;             // сверху заметнее, к низу исчезает
	COLOR = vec4(1.0, 1.0, 1.0, checker * 0.035 * fade);
}
