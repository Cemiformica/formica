shader_type spatial;
// Césped de juguete al estilo de Solarpunk (C5.6, D-179).
// world_vertex_coords: en vertex() VERTEX y NORMAL ya están en coordenadas del mundo,
// así el viento y el empuje del jugador se suman directamente en metros.
render_mode cull_disabled, world_vertex_coords;

// Posición del jugador: Project Settings → Shader Globals (vec3).
// La actualiza player.gd con RenderingServer.global_shader_parameter_set().
global uniform vec3 player_position;

// El color sale del suelo que hay debajo de cada mata: la misma cuenta que la hierba de `terrain.gdshader`
// (mismos colores y mismos ruidos), así la raíz se funde con el terreno (César: que se parezca al suelo, como en
// Solarpunk). Si se cambian los verdes del terreno, hay que cambiarlos también aquí.
group_uniforms ground;
uniform vec3 grass_low : source_color = vec3(0.32, 0.52, 0.23);
uniform vec3 grass_high : source_color = vec3(0.39, 0.55, 0.23);
uniform vec3 grass_dry : source_color = vec3(0.55, 0.58, 0.30);
uniform float level_height = 6.0;          // altura de la explanada alta (IslandLayout.LEVEL_HEIGHT)
// Claros de tierra de las explanadas (los mismos de `terrain.gdshader`): ahí no crece césped. Lo metida que está
// cada mata en su explanada llega en INSTANCE_CUSTOM.g (lo da `TerrainView`; 1 en el sandbox).
uniform float clearing_threshold = 0.53;
uniform float flat_dirt_amount = 1.0;
// Roca del terreno (los mismos valores que `terrain.gdshader`): ahí tampoco crece. La pendiente y lo que es pared de cada
// mata llegan en INSTANCE_CUSTOM.b y .a (1 y 0 en el sandbox: sin roca).
uniform float slope_rock_up = 0.74;
uniform float wall_rock_up = 0.8;
uniform float rock_edge = 0.03;
// Casillas ocupadas por construcciones y estructuras por reparar (C5.6, paso 3): ahí no crece. La pone `IslandView`, un
// píxel por casilla; `block_rect` = (x, z de la primera casilla, ancho y fondo en casillas). Con filtro lineal, las
// matas se quitan también unos 30 cm fuera de la huella, para que las que se inclinan no se metan en las paredes.
uniform sampler2D block_mask : hint_default_black, filter_linear, repeat_disable;
uniform vec4 block_rect = vec4(0.0);

group_uniforms colors;
// La raíz, algo más oscura que el suelo (sombra dentro de la mata); la punta, solo un poco más clara y cálida.
// Casi toda la brizna lleva el color del suelo: solo el último tramo se aclara (`tip_from`), para que el césped 3D
// no parezca una capa aparte del pintado (César).
uniform float tip_from : hint_range(0.0, 1.0) = 0.55;
uniform float base_shade : hint_range(0.3, 1.2) = 0.8;
uniform float tip_light : hint_range(0.8, 2.0) = 1.1;
uniform vec3 tip_warm : source_color = vec3(0.80, 0.82, 0.38);
uniform float tip_warmth : hint_range(0.0, 1.0) = 0.1;
// Tono distinto por mata (como el tono por casilla de los árboles, D-181).
uniform float tint_variation : hint_range(0.0, 0.5) = 0.08;
// Brillo extra de las puntas cuando pasa una ráfaga (el «oleaje» claro de Ghibli).
uniform float gust_brightness : hint_range(0.0, 0.5) = 0.08;

group_uniforms lighting;
// Difusa envolvente: más suave que Lambert, sin sombras duras.
uniform float light_wrap : hint_range(0.0, 1.0) = 0.35;
// Translucidez cuando el sol está detrás de la hierba.
uniform vec3 translucency_color : source_color = vec3(0.90, 1.0, 0.45);
uniform float translucency_strength : hint_range(0.0, 2.0) = 0.3;
uniform float translucency_power : hint_range(1.0, 16.0) = 4.0;

group_uniforms wind;
// NoiseTexture2D con FastNoiseLite y seamless = true.
uniform sampler2D wind_noise : hint_default_black, filter_linear, repeat_enable;
uniform vec2 wind_direction = vec2(1.0, 0.35);
uniform float wind_scale = 0.025;      // mundo → UV: con 0,025, la textura cubre 40 m
uniform float wind_speed = 0.05;       // UV por segundo (≈ 2 m/s de ráfaga)
uniform float gust_threshold : hint_range(0.0, 1.0) = 0.4; // más alto = ráfagas más sueltas
uniform float gust_strength = 0.30;    // metros en la punta
uniform float sway_strength = 0.06;    // onda lenta amplia
uniform float sway_speed = 1.3;
uniform float sway_frequency = 0.35;
uniform float flutter_strength = 0.025; // vibración rápida
uniform float flutter_speed = 7.0;

group_uniforms interaction;
uniform float push_radius = 1.1;
uniform float push_strength = 0.45;

group_uniforms distance;
// Las briznas se encogen entre estas distancias a la cámara (sin cortes bruscos).
uniform float fade_start = 25.0;
uniform float fade_end = 33.0;

varying vec3 v_ground;
varying float v_tip;
varying float v_tint;
varying float v_gust;
varying float v_glow; // se escribe en fragment() para leerla en light()

#include "res://entities/nature/toy_noise.gdshaderinc"

// Mismas coordenadas giradas 30° que `terrain.gdshader`.
vec2 ground_p(vec3 pos) {
	return mat2(vec2(0.866, 0.5), vec2(-0.5, 0.866)) * pos.xz;
}

// Color de la hierba del terreno en un punto (copia de la parte de la hierba de `terrain.gdshader`).
vec3 ground_grass(vec3 pos, float flat_area) {
	vec2 p = ground_p(pos);
	float big = fbm(p * 0.07);
	float fine = value_noise(p * 2.3 + 41.0);
	float patches = mix(1.0, 0.5, flat_area);
	vec3 color = mix(grass_low, grass_high, smoothstep(0.35, 0.75, clamp(pos.y / level_height, 0.0, 1.0)));
	color = mix(color, grass_dry, smoothstep(0.55, 0.85, big) * 0.45 * patches);
	color *= 1.0 + ((big - 0.5) * 0.35 + (fine - 0.5) * 0.08) * patches;
	color *= mix(1.0, 1.05, flat_area);
	return color;
}

// Cuánto claro de tierra hay en un punto (copia de `terrain.gdshader`, sin la parte del agua).
float clearing_at(vec3 pos, float flat_area) {
	if (flat_area <= 0.0) {
		return 0.0;
	}
	vec2 p = ground_p(pos);
	float mid = fbm(p * 0.35 + 17.0);
	vec2 warp = vec2(fbm(p * 0.05 + 3.1), fbm(p * 0.05 + 9.7)) - 0.5;
	float clearing_noise = fbm(p * 0.06 + warp * 0.8 + 73.0) + (mid - 0.5) * 0.12;
	return smoothstep(clearing_threshold, clearing_threshold + 0.1, clearing_noise) * flat_area * flat_dirt_amount;
}

// Cuánta roca pinta el terreno en un punto (copia de `terrain.gdshader`, con la pendiente de la rejilla).
float rock_at(vec3 pos, float up, float wall) {
	vec2 p = ground_p(pos);
	float mid = fbm(p * 0.35 + 17.0);
	float fine = value_noise(p * 2.3 + 41.0);
	float wall_zone = smoothstep(0.12, 0.25, wall + (mid - 0.5) * 0.15);
	float rock_mid = mix(slope_rock_up, wall_rock_up, wall_zone);
	return 1.0 - smoothstep(rock_mid - rock_edge, rock_mid + rock_edge, up + (mid - 0.5) * 0.22 + (fine - 0.5) * 0.05);
}

void vertex() {
	// Con MultiMesh, MODEL_MATRIX incluye la transformación de la instancia:
	// su origen es la raíz de esta brizna en el mundo.
	// (NODE_POSITION_WORLD sería el del trozo entero, igual para todas las briznas.)
	vec3 root = MODEL_MATRIX[3].xyz;
	float blade_scale = length(MODEL_MATRIX[1].xyz);

	// Raíz fija, punta libre. UV.y = 1 en la raíz y 0 en la punta.
	float tip = clamp(1.0 - UV.y, 0.0, 1.0);
	float bend = tip * tip;

	// 0) Encoger con la distancia a la cámara y en los claros de tierra (con el borde suave, como el del claro).
	float flat_area = INSTANCE_CUSTOM.g;
	float shrink = 1.0 - smoothstep(fade_start, fade_end, distance(root, CAMERA_POSITION_WORLD));
	// El terreno pinta tierra hacia 0,45: las matas llegan hasta ahí y alguna, pequeña, se mete dentro.
	shrink *= 1.0 - smoothstep(0.42, 0.65, clearing_at(root, flat_area));
	shrink *= 1.0 - smoothstep(0.3, 0.7, rock_at(root, INSTANCE_CUSTOM.b, INSTANCE_CUSTOM.a));
	if (block_rect.z > 0.0) {
		vec2 block_uv = (root.xz - block_rect.xy) / block_rect.zw;
		if (all(greaterThanEqual(block_uv, vec2(0.0))) && all(lessThanEqual(block_uv, vec2(1.0)))) {
			// Sesión 28: máscara de 4 píxeles por casilla y fundido más estrecho (antes 0,12 a 0,3, con 1 píxel por
			// casilla): las matas llegan casi hasta el borde de cada construcción.
			shrink *= 1.0 - smoothstep(0.35, 0.6, textureLod(block_mask, block_uv, 0.0).r);
		}
	}
	VERTEX = root + (VERTEX - root) * shrink;

	// 1) Viento. Se muestrea en la raíz para que la brizna se doble entera, sin retorcerse.
	vec2 dir = normalize(wind_direction);
	vec3 wind_dir = vec3(dir.x, 0.0, dir.y);
	vec3 side_dir = vec3(-dir.y, 0.0, dir.x);
	vec2 wind_uv = root.xz * wind_scale - dir * (TIME * wind_speed); // el dibujo avanza hacia dir
	float gust = smoothstep(gust_threshold, 1.0, textureLod(wind_noise, wind_uv, 0.0).r);
	float sway = sin(dot(root.xz, dir) * sway_frequency - TIME * sway_speed);
	float flutter = sin(TIME * flutter_speed + INSTANCE_CUSTOM.r * TAU) * (0.35 + gust);
	vec3 offset = wind_dir * (gust * gust_strength + sway * sway_strength)
			+ side_dir * flutter * flutter_strength;

	// 2) El jugador aparta la hierba hacia fuera (solo si está a su altura).
	vec3 away = root - player_position;
	float height_gap = abs(away.y);
	away.y = 0.0;
	float dist = length(away);
	float push = (1.0 - smoothstep(push_radius * 0.3, push_radius, dist))
			* (1.0 - smoothstep(1.0, 2.0, height_gap));
	vec3 away_dir = dist > 0.001 ? away / dist : wind_dir;
	offset += away_dir * push * push_strength;

	// Aplicar: la punta se aparta y baja un poco para que la brizna no se estire.
	offset *= bend * blade_scale * shrink;
	VERTEX.xz += offset.xz;
	VERTEX.y -= length(offset.xz) * 0.5;

	// Normal hacia arriba: todas las briznas reciben la luz igual, sin sombras duras entre ellas.
	NORMAL = vec3(0.0, 1.0, 0.0);

	v_ground = ground_grass(root, flat_area);
	v_tip = tip;
	v_tint = INSTANCE_CUSTOM.r;
	v_gust = gust;
}

void fragment() {
	// Con cull_disabled, Godot da la vuelta a la normal en la cara de atrás:
	// se vuelve a poner hacia arriba (aquí NORMAL va en espacio de vista).
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);

	vec3 tip_color = mix(v_ground * tip_light, tip_warm, tip_warmth);
	// De la raíz al color del suelo en la primera mitad; después, poco a poco hacia la punta.
	vec3 body = mix(v_ground * base_shade, v_ground, smoothstep(0.0, tip_from, v_tip));
	vec3 color = mix(body, tip_color, smoothstep(tip_from, 1.0, v_tip));
	color *= 1.0 + (v_tint - 0.5) * 2.0 * tint_variation;
	color *= 1.0 + v_gust * v_tip * gust_brightness;
	ALBEDO = color;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	v_glow = v_tip;
}

void light() {
	// Difusa envolvente (Godot multiplica luego por ALBEDO).
	vec3 light_in = LIGHT_COLOR * ATTENUATION / PI;
	float wrapped = clamp((dot(NORMAL, LIGHT) + light_wrap) / (1.0 + light_wrap), 0.0, 1.0);
	DIFFUSE_LIGHT += light_in * wrapped;

	// Translucidez: brilla cuando miras hacia el sol a través de la hierba.
	// (No se usa BACKLIGHT: con la normal forzada hacia arriba y el sol arriba nunca se activaría.)
	float behind = pow(clamp(dot(LIGHT, -VIEW), 0.0, 1.0), translucency_power);
	DIFFUSE_LIGHT += light_in * translucency_color * behind * translucency_strength * v_glow;
}
