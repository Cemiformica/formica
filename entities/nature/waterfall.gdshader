// Cascada de juguete (C5.4e). Una cortina de agua pegada a la caída, con franjas blancas que bajan deprisa, el borde
// de arriba más claro donde el agua se asoma y, al pie, espuma que hierve sobre el río y se va apagando.
// UV: x a lo ancho (m) e y lo recorrido por la cortina (m, desde el borde; medido sobre ella, así las franjas no
// parpadean en la parte vertical). UV2.x: 0 en la caída, 1 en la espuma del pie; UV2.y: de 0 arriba a 1 donde cae.
// COLOR.r: de 0 a 1 de un lado al otro; COLOR.a: 1 donde los lados se deshilachan; COLOR.b: 1 en la cortina de dentro;
// COLOR.g: 0 donde una pared de los lados aún no se ve (1 en lo demás). Dónde tocar: los colores y los valores de abajo.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

uniform vec3 water_color : source_color = vec3(0.45, 0.86, 0.9);
uniform vec3 foam_color : source_color = vec3(0.97, 1.0, 1.0);
// Velocidad a la que bajan las franjas (m/s).
uniform float fall_speed = 3.2;
// Cuánta parte de la cortina es franja blanca (más bajo = más blanco).
uniform float streak_threshold = 0.55;
uniform float alpha_fall = 0.82;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 p = UV;
	float pool = UV2.x;
	vec3 color;
	float alpha;
	if (pool < 0.5) {
		// La caída: franjas alargadas que bajan; dos capas a distinta velocidad para que no se vea un dibujo fijo.
		float a = value_noise(vec2(p.x * 3.0, (p.y - TIME * fall_speed) * 0.5));
		float b = value_noise(vec2(p.x * 5.0 + 11.0, (p.y - TIME * fall_speed * 1.35) * 0.8));
		float streak = smoothstep(streak_threshold, streak_threshold + 0.12, max(a, b));
		color = mix(water_color, foam_color, streak);
		// Arriba, donde el agua se asoma, más clara; abajo, la espuma del golpe.
		float lip = smoothstep(-0.6, 0.0, p.y) * (1.0 - smoothstep(0.0, 0.6, p.y));
		color = mix(color, foam_color, lip * 0.5);
		color = mix(color, foam_color, smoothstep(0.75, 1.0, UV2.y) * 0.8);
		alpha = mix(alpha_fall, 0.95, streak);
		// Lo que entra en el lago (antes del borde) se funde con su agua.
		alpha *= smoothstep(-1.0, -0.1, p.y);
		// Los lados, deshilachados: el agua se abre y se rompe en los bordes al caer.
		float side = min(COLOR.r, 1.0 - COLOR.r);
		float fray = value_noise(vec2(p.x * 4.0, (p.y - TIME * fall_speed) * 0.7) + 31.0);
		alpha *= mix(1.0, smoothstep(0.0, 0.08 + fray * 0.12 + UV2.y * 0.08, side), COLOR.a);
		// La cortina de dentro (COLOR.b = 1), algo más transparente: da volumen sin tapar la de fuera.
		alpha *= mix(1.0, 0.8, COLOR.b);
		// Las paredes de los lados (COLOR.g < 1 arriba) aparecen poco a poco al empezar el salto.
		alpha *= COLOR.g;
	} else {
		// La espuma del pie: hierve y se va apagando río abajo (UV2.y va de 0 junto a la caída a 1 al final).
		float churn = value_noise(p * 3.0 + vec2(TIME * 0.8, -TIME * 1.1));
		churn = max(churn, value_noise(p * 5.5 - vec2(TIME * 1.3, TIME * 0.6) + 7.0));
		float fade = 1.0 - smoothstep(0.1, 1.0, UV2.y);
		float foam = smoothstep(0.45 - fade * 0.35, 0.6 - fade * 0.3, churn) * fade;
		color = foam_color;
		alpha = foam * 0.95;
	}
	ALBEDO = color;
	ALPHA = alpha;
	ROUGHNESS = 0.2;
	SPECULAR = 0.5;
}
