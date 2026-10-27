shader_type canvas_item;
// Узор фона «Строки кинескопа» (см. Backdrop.gd): тонкие тёмные линии
// через строку и затемнённые края — как на старом телевизоре.

void fragment() {
	vec2 pos = SCREEN_UV * vec2(1920.0, 1080.0);
	float line = step(2.0, mod(pos.y, 4.0));   // две строки светлые, две тёмные
	vec2 p = SCREEN_UV - 0.5;
	float vignette = smoothstep(0.35, 0.85, length(p * vec2(1.0, 1.3)));  // края темнее
	COLOR = vec4(0.0, 0.0, 0.0, line * 0.18 + vignette * 0.35);
}
