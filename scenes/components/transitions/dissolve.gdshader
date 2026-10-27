shader_type canvas_item;
// Переход «Рассыпание» (см. SceneRouter.gd): экран делится на квадраты,
// и они гаснут в случайном порядке; новый экран так же собирается
// из квадратов. Как загрузка уровня в старых играх.

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float progress = 0.0;  // 0 — обычный экран, 1 — всё погасло

// «Случайное» число от 0 до 1 для каждой клетки — всегда одно и то же
// для одной клетки, поэтому квадраты гаснут в своём постоянном порядке.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
	float size = 40.0 * resolution.y / 720.0;            // квадраты 40×40 при 720 строках
	vec2 cell = floor(SCREEN_UV * resolution / size);    // в какой клетке эта точка
	// Пока квадраты гаснут, оставшиеся ещё и чуть укрупняются (до 12 пикселей).
	float block = floor(mix(1.0, 12.0 * resolution.y / 720.0, progress));
	vec2 uv = (floor(SCREEN_UV * resolution / block) + 0.5) * block / resolution;
	vec3 color = texture(screen, uv).rgb;
	// Квадрат гаснет, когда progress обгоняет его случайное число.
	float gone = step(hash(cell), progress);
	COLOR = vec4(mix(color, vec3(0.0), gone), 1.0);
}
