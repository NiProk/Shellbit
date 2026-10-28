shader_type canvas_item;
// Обрезает картинку кругом: всё, что дальше половины ширины от центра,
// становится прозрачным. UV — координаты внутри картинки: (0,0) — левый
// верхний угол, (1,1) — правый нижний, (0.5, 0.5) — центр.

void fragment() {
	float distance_from_center = length(UV - vec2(0.5));
	// fwidth — на сколько меняется значение между соседними пикселями экрана.
	// Делаем край мягким шириной в один пиксель — круг без «лесенки».
	float edge = fwidth(distance_from_center);
	COLOR.a *= 1.0 - smoothstep(0.5 - edge, 0.5, distance_from_center);
}
