// Ruidos de la «textura de juguete» (sin texturas), compartidos por el terreno (`terrain.gdshader`), la naturaleza
// (`nature.gdshader`) y, más adelante, el césped 3D. Se usan con `#include "res://entities/nature/toy_noise.gdshaderinc"`.

// Número aleatorio por punto, sin `sin()`: con `sin()` la tarjeta gráfica pierde precisión y salen dibujos
// repetidos (anillos y cortes rectos, capturas de César).
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Ruido de valor suave, de 0 a 1.
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Ruido de varias capas, cada una girada respecto a la anterior: sin las líneas rectas que deja una sola capa.
float fbm(vec2 p) {
	mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float value = 0.0;
	float weight = 0.5;
	for (int i = 0; i < 4; i++) {
		value += weight * value_noise(p);
		p = turn * p * 2.03 + vec2(11.0, 5.0);
		weight *= 0.5;
	}
	return value / 0.9375;
}
