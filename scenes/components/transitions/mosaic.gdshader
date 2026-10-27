shader_type canvas_item;
// Переход «Мозаика» (см. SceneRouter.gd): экран укрупняется до больших
// квадратов и темнеет, а новый экран проявляется наоборот — из крупных
// квадратов в чёткую картинку. Так переходили между сценами игры SNES.

// hint_screen_texture — то, что уже нарисовано на экране ПОД этим узлом.
// filter_nearest — без сглаживания: квадраты должны быть чёткими.
uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float progress = 0.0;  // 0 — обычный экран, 1 — самые крупные квадраты и темнота

void fragment() {
	vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;  // размер экрана в пикселях
	// Размер квадрата растёт от 1 (обычные пиксели) до 72 — сначала медленно,
	// потом быстрее (progress в квадрате).
	float block = floor(mix(1.0, 72.0 * resolution.y / 720.0, progress * progress));
	// Округляем координату до центра своего квадрата — весь квадрат
	// получает цвет одной точки.
	vec2 uv = (floor(SCREEN_UV * resolution / block) + 0.5) * block / resolution;
	vec3 color = texture(screen, uv).rgb * (1.0 - 0.75 * progress);  // и темнеем
	COLOR = vec4(color, 1.0);
}
