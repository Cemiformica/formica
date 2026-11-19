// Agua de juguete (C5.4d, D-156; referencias de César: Fortnite y Solarpunk). Un solo shader para el canal y el
// estanque del sandbox, el río, el lago y el mar. La hondura sale de lo que hay debajo (la profundidad de la escena,
// medida en vertical: así no cambia de tono según desde dónde se mire): turquesa claro donde cubre poco, azul
// profundo donde cubre mucho, espuma blanca en las orillas y alrededor de lo que toca el agua, una red de brillos que
// se desliza, ondas suaves y, en el río, líneas de corriente.
// UV = velocidad de la corriente en ese punto (m/s, x y z del mundo), que pasa suave de una casilla a otra
// (ver `TerrainView._build_water()`). Todo lo demás se dibuja en coordenadas del mundo: sin cortes entre casillas.
// Dónde tocar: los colores y los valores de abajo.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

uniform vec3 shallow_color : source_color = vec3(0.42, 0.88, 0.86);
uniform vec3 deep_color : source_color = vec3(0.07, 0.38, 0.62);
uniform vec3 foam_color : source_color = vec3(0.97, 1.0, 1.0);
uniform vec3 glint_color : source_color = vec3(0.85, 1.0, 0.98);
// Metros de agua (en vertical) a partir de los que ya es azul profundo.
uniform float deep_distance = 1.6;
// Transparencia: en la orilla se ve el fondo; en lo hondo, casi nada.
uniform float alpha_shallow = 0.45;
uniform float alpha_deep = 0.88;
// Espuma: ancho de la franja de la orilla (m de hondura) y cuánto respira.
uniform float foam_width = 0.18;
uniform float foam_breath = 0.05;
// Cuánto se nota la corriente en las líneas (más es más rápido) y cada cuánto se reinicia el dibujo (s).
uniform float flow_visual = 1.6;
uniform float flow_cycle = 3.0;
// Ondas: cuánto mueven la luz.
uniform float wave_strength = 0.18;
// El agua que se alarga por la orilla (COLOR.g = 1) desaparece donde debajo hay más de esta caída (m): así su borde
// sigue el filo de un acantilado o de la cascada en lugar de quedar en el aire (César).
uniform float shore_max_depth = 0.7;
// A lo lejos, los brillos y las ondas se apagan (si no, a distancia se vuelven ruido, César): desde dónde empiezan
// a apagarse y dónde ya no se ven (m).
uniform float detail_fade_start = 150.0;
uniform float detail_fade_end = 500.0;
// Distancia (m) en la que las ondas pequeñas pasan a ser grandes.
uniform float wave_far_start = 12.0;
uniform float wave_far_end = 45.0;

varying vec3 world_pos;

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

// Red de brillos (como las cáusticas de Solarpunk): las líneas donde dos ruidos que se mueven distinto se cruzan.
// A lo lejos, la línea se ensancha y se apaga sola según lo que ocupa cada píxel (si no, vibraba al moverse, César).
float glints(vec2 p, float t) {
	mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float a = value_noise(p * 0.9 + vec2(t * 0.11, t * 0.07));
	float b = value_noise(turn * p * 0.9 - vec2(t * 0.09, -t * 0.12) + 13.0);
	float d = abs(a - b);
	float pixel = fwidth(d);
	return (1.0 - smoothstep(0.0, 0.07 + pixel * 1.5, d)) * (1.0 - smoothstep(0.04, 0.2, pixel));
}

// Líneas de corriente: ruido estirado a lo largo de la corriente.
float streaks(vec2 p, vec2 dir) {
	vec2 side = vec2(-dir.y, dir.x);
	vec2 q = vec2(dot(p, side) * 2.2, dot(p, dir) * 0.35);
	return smoothstep(0.72, 0.82, value_noise(q));
}

// Una capa de ondas a una escala (las pequeñas cerca, las grandes lejos).
float waves(vec2 p, float scale, float seed) {
	return value_noise(p * scale + vec2(TIME * 0.2, TIME * 0.17) * (seed > 0.0 ? vec2(0.0, 1.0) : vec2(1.0, 0.0)) + seed);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	vec2 flow = UV * flow_visual;
	float speed = length(flow);
	vec2 dir = speed > 0.001 ? flow / speed : vec2(0.0, 1.0);

	// La corriente arrastra el dibujo en dos fases que se cruzan (así no se estira ni se corta con el tiempo).
	float phase_a = fract(TIME / flow_cycle);
	float phase_b = fract(TIME / flow_cycle + 0.5);
	// El cruce entre las dos fases, corto (César: mientras coincidían parecía que había demasiadas ondas). En el agua
	// quieta (mar, lagos) no hace falta: un solo dibujo.
	float blend = speed > 0.001 ? smoothstep(0.3, 0.7, abs(phase_a * 2.0 - 1.0)) : 0.0;
	vec2 pa = p - flow * phase_a * flow_cycle;
	vec2 pb = p - flow * phase_b * flow_cycle + 5.3;

	// Hondura en vertical: el punto que hay detrás del agua, en coordenadas del mundo.
	float scene_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	scene_view.xyz /= scene_view.w;
	vec3 scene_world = (INV_VIEW_MATRIX * vec4(scene_view.xyz, 1.0)).xyz;
	float thickness = max(world_pos.y - scene_world.y, 0.0);
	float deep = smoothstep(0.0, deep_distance, thickness);
	if (COLOR.g > 0.5 && thickness > shore_max_depth) {
		discard;
	}

	float near = 1.0 - smoothstep(detail_fade_start, detail_fade_end, length(VERTEX));

	vec3 color = mix(shallow_color, deep_color, deep);
	float alpha = mix(alpha_shallow, alpha_deep, deep);

	// Ondas: la normal se mueve con un ruido suave que sigue la corriente. De lejos, ondas más grandes: el mar sigue
	// teniendo oleaje, pero sin la vibración de las pequeñas.
	float far = smoothstep(wave_far_start, wave_far_end, length(VERTEX));
	float n1 = mix(waves(pa, 1.3, 0.0), waves(pa, 0.3, 0.0), far);
	float n2 = mix(waves(pa, 1.3, 7.0), waves(pa, 0.3, 7.0), far);
	n1 = mix(n1, mix(waves(pb, 1.3, 0.0), waves(pb, 0.3, 0.0), far), blend);
	n2 = mix(n2, mix(waves(pb, 1.3, 7.0), waves(pb, 0.3, 7.0), far), blend);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(vec3(n1 - 0.5, 0.0, n2 - 0.5) * wave_strength * near, 0.0)).xyz);

	// Brillos que se deslizan, más en lo poco hondo.
	float g = mix(glints(pa, TIME), glints(pb, TIME), blend);
	color = mix(color, glint_color, g * mix(0.55, 0.25, deep) * near);

	// Corriente: líneas alargadas que avanzan río abajo, más fuertes donde corre más.
	if (speed > 0.001) {
		float s = mix(streaks(pa, dir), streaks(pb, dir), blend);
		color = mix(color, foam_color, s * 0.4 * smoothstep(0.0, 0.4, speed) * near);
	}

	// Espuma de la orilla: una franja que respira, con el borde roto.
	float breath = sin(TIME * 1.3 + p.x * 0.4 + p.y * 0.3) * foam_breath;
	float edge = 1.0 - smoothstep(0.0, foam_width + breath, thickness);
	float foam_noise = mix(value_noise(pa * 3.0), value_noise(pb * 3.0), blend);
	float foam = step(0.45, edge * (0.65 + foam_noise * 0.7));
	color = mix(color, foam_color, foam);
	alpha = mix(alpha, 0.95, foam);

	ALBEDO = color;
	ALPHA = alpha;
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
