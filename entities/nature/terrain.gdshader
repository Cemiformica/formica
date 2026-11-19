// Suelo de las islas con plano (C5.4a). La malla trae en cada esquina lo que la rodea (ver
// `TerrainView._build_layout_ground()`): COLOR.r arena, COLOR.g mojado, COLOR.b sendero, COLOR.a altura (0 abajo,
// 1 arriba); UV2.x hondura bajo el agua (m), UV2.y explanada. La roca sale de la pendiente. Las manchas, de un ruido
// en coordenadas del mundo (sin texturas). Dónde tocar: los colores y los umbrales de abajo.
shader_type spatial;
render_mode cull_disabled;

// Colores con Solarpunk como referencia (César): hierba más viva, tierra beis clara y roca rojiza.
// Hierba: la de abajo, la de arriba (algo más cálida, para distinguirla desde abajo) y la seca de las manchas.
uniform vec3 grass_low : source_color = vec3(0.32, 0.52, 0.23);
uniform vec3 grass_high : source_color = vec3(0.39, 0.55, 0.23);
uniform vec3 grass_dry : source_color = vec3(0.55, 0.58, 0.30);
uniform vec3 sand : source_color = vec3(0.88, 0.81, 0.64);
uniform vec3 wet_sand : source_color = vec3(0.68, 0.59, 0.45);
uniform vec3 dirt : source_color = vec3(0.71, 0.62, 0.49);
uniform vec3 rock : source_color = vec3(0.66, 0.44, 0.32);
uniform vec3 bed_deep : source_color = vec3(0.10, 0.38, 0.50);
// Fondo del mar lejos de la costa: se pierde en la oscuridad, del color del fondo del cielo (`isla_alba.tscn`).
uniform vec3 abyss : source_color = vec3(0.04, 0.14, 0.22);
// Pendiente (componente vertical de la normal) en la que la hierba pasa a roca.
uniform float rock_from = 0.55;
uniform float rock_to = 0.75;
// Cuánto manchan los ruidos (en las explanadas, la mitad: ahí se construye y se tiene que leer bien).
uniform float patch_strength = 1.0;
// Claros de tierra pisada sueltos por las explanadas, como en Solarpunk (0 = ninguno) y cuánta explanada cubren
// (más bajo = más claros).
uniform float flat_dirt_amount = 1.0;
uniform float clearing_threshold = 0.53;
// Piedrecitas y motas oscuras en la tierra, para que se lea como suelo pisado.
uniform float pebble_amount = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Coordenadas giradas 30°: así las manchas no siguen la cuadrícula de construcción.
	vec2 p = mat2(vec2(0.866, 0.5), vec2(-0.5, 0.866)) * world_pos.xz;
	float big = fbm(p * 0.07);
	float mid = fbm(p * 0.35 + 17.0);
	float fine = value_noise(p * 2.3 + 41.0);
	float flat_area = UV2.y;
	float patches = patch_strength * mix(1.0, 0.5, flat_area);

	// Hierba: más cálida arriba, con manchas secas grandes y motas finas.
	vec3 color = mix(grass_low, grass_high, smoothstep(0.35, 0.75, COLOR.a));
	color = mix(color, grass_dry, smoothstep(0.55, 0.85, big) * 0.45 * patches);
	color *= 1.0 + ((big - 0.5) * 0.35 + (fine - 0.5) * 0.08) * patches;
	color *= mix(1.0, 1.05, flat_area);

	// Roca donde es empinado (acantilados y bordes de las alturas). Se mira la cara del triángulo, no la normal
	// suavizada de las esquinas: con esa, la hierba subía en vetas por el acantilado. Se calcula antes para que la
	// tierra no la pise.
	vec3 face_normal = normalize(cross(dFdy(world_pos), dFdx(world_pos)));
	float steepness = min(abs(face_normal.y), world_normal.y);
	float cliff = 1.0 - smoothstep(rock_from, rock_to, steepness + (mid - 0.5) * 0.1);

	// Tierra pisada: el sendero y sus extremos, más claros sueltos por las explanadas, con el borde irregular.
	float worn = COLOR.b + (mid - 0.5) * 0.3 + (fine - 0.5) * 0.15;
	// Claros sueltos: manchas redondeadas, con el borde roto por el ruido medio y el fino.
	vec2 warp = vec2(fbm(p * 0.05 + 3.1), fbm(p * 0.05 + 9.7)) - 0.5;
	float clearing_noise = fbm(p * 0.06 + warp * 0.8 + 73.0) + (mid - 0.5) * 0.12;
	float clearing = smoothstep(clearing_threshold, clearing_threshold + 0.1, clearing_noise) * flat_area * flat_dirt_amount;
	float path = smoothstep(0.3, 0.6, max(worn, clearing + (fine - 0.5) * 0.15)) * smoothstep(rock_to, rock_to + 0.1, steepness);
	vec3 soil = dirt * (0.9 + 0.12 * fine + 0.08 * mid);
	// Piedrecitas: motas pequeñas y redondeadas, algo más oscuras o algo más claras.
	vec2 speck_p = mat2(vec2(0.6, 0.8), vec2(-0.8, 0.6)) * p * 6.0;
	float pebble = smoothstep(0.78, 0.84, value_noise(speck_p + 29.0)) * pebble_amount;
	float pebble_tone = step(0.5, value_noise(speck_p * 0.5 + 91.0)); // unas más oscuras y otras más claras
	soil = mix(soil, dirt * mix(0.7, 1.1, pebble_tone), pebble * 0.8);
	color = mix(color, soil, path);

	// Arena de la playa y franja de arena mojada pegada al agua.
	float beach = smoothstep(0.3, 0.6, COLOR.r + (mid - 0.5) * 0.35);
	color = mix(color, sand * (0.95 + 0.1 * mid), beach);
	float wet = smoothstep(0.45, 0.9, COLOR.g + (fine - 0.5) * 0.25);
	color = mix(color, wet_sand * (0.96 + 0.08 * fine), wet);

	color = mix(color, rock * (0.88 + 0.24 * mid), cliff);

	// Bajo el agua: arena mojada en la orilla y cada vez más oscuro con la hondura.
	float depth = UV2.x;
	color = mix(color, wet_sand, smoothstep(0.0, 0.12, depth));
	color = mix(color, bed_deep, smoothstep(0.1, 1.2, depth));
	color = mix(color, abyss, smoothstep(2.0, 10.0, depth));

	ALBEDO = color;
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
}
