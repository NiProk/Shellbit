shader_type canvas_item;
// Силуэт приставки для обложки-заглушки (см. GameCard.gd).
//
// Картинки приставок в data/consoles нарисованы не на прозрачном фоне,
// а на тёмном — под цвет плитки главного экрана. Здесь мы этот фон
// «вырезаем»: берём цвет левого верхнего угла (там точно фон) и всё,
// что на него похоже, делаем прозрачным. Остальное закрашиваем одним
// цветом — получается силуэт.

uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);  // цвет силуэта

void fragment() {
	vec3 background = texture(TEXTURE, vec2(0.01, 0.01)).rgb;
	vec4 pixel = texture(TEXTURE, UV);
	// Насколько точка отличается от фона: 0 — это фон, больше — приставка.
	float difference = distance(pixel.rgb, background);
	// Плавно, чтобы у силуэта не было «лесенки» по краям.
	float mask = smoothstep(0.06, 0.2, difference) * pixel.a;
	// COLOR.a — прозрачность из modulate (её задаёт скрипт).
	COLOR = vec4(tint.rgb, mask * COLOR.a);
}
