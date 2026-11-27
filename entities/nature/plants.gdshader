shader_type spatial;
// Plantas de juguete (C5.6, sesión 31): flores, tréboles, helechos, arbustos y juncos de `plants.glb`.
// Mismo viento que el césped (`grass.gdshader`: misma textura de ruido, dirección y ritmo), así las ráfagas mueven
// césped y plantas a la vez; cuanto más arriba en la planta, más se dobla. Se apartan al pasar Mira y se encogen con
// la distancia. Van en un MultiMesh por pieza; cada instancia trae en INSTANCE_CUSTOM:
//   r = tono (0 a 1, 0,5 = sin cambio), g = rigidez (0 = junco que se dobla mucho, 1 = arbusto firme),
//   b = alcance a lo lejos (0 = como el césped; 1 = el doble de lejos, para los arbustos).
// Con `use_ground_masks` (flores y tréboles del césped, `plants_ground.tres`) INSTANCE_CUSTOM lleva lo mismo que una
// mata de césped (r = azar, g = lo metido en su explanada, b = pendiente, a = pared) y la planta se encoge donde el
// césped: claros de tierra, roca y casillas construidas (`block_mask`, que pone `IslandView`). La rigidez sale entonces
// de `ground_stiffness`.
// world_vertex_coords: en vertex() VERTEX ya está en el mundo, así el viento y el empuje se suman en metros.
render_mode cull_disabled, world_vertex_coords;

// Posición del jugador (Project Settings → Shader Globals); la pone player.gd.
global uniform vec3 player_position;

group_uniforms colors;
// La paleta de siempre (`palette.png`), sin filtrar: cada cara lleva el color de su casilla.
uniform sampler2D palette_texture : source_color, filter_nearest, repeat_disable;
// Tono distinto por instancia (como el césped y los árboles, D-181).
uniform float tint_variation : hint_range(0.0, 0.5) = 0.08;
// Un poco más oscuro abajo (sombra dentro de la mata), hasta esta altura (m).
uniform float base_shade : hint_range(0.3, 1.0) = 0.75;
uniform float base_shade_height = 0.25;

// Tallos de los tréboles más parecidos al césped (sesión 31, César: destacaban demasiado). Lo que está pintado con
// la casilla de los tallos de la paleta (`STEM` = fila 2, columna 4 en `plants_blockout.py`; en UV de Godot, este
// rectángulo: u mín, v mín, u máx, v máx) se mezcla con `stem_tint_color`. Solo el material de los tréboles lo usa.
uniform vec3 stem_tint_color : source_color = vec3(0.42, 0.66, 0.29);   // el de las briznas con luz
uniform float stem_tint : hint_range(0.0, 1.0) = 0.0;
uniform vec4 stem_swatch = vec4(0.5, 0.25, 0.625, 0.375);

group_uniforms lighting;
// Difusa envolvente y translucidez a contraluz, como el césped (las hojas son finas).
uniform float light_wrap : hint_range(0.0, 1.0) = 0.3;
uniform vec3 translucency_color : source_color = vec3(0.90, 1.0, 0.45);
uniform float translucency_strength : hint_range(0.0, 2.0) = 0.25;
uniform float translucency_power : hint_range(1.0, 16.0) = 4.0;

group_uniforms wind;
// Los mismos valores que `grass.tres` / `grass.gdshader` (si se cambian allí, cambiarlos aquí).
uniform sampler2D wind_noise : hint_default_black, filter_linear, repeat_enable;
uniform vec2 wind_direction = vec2(1.0, 0.35);
uniform float wind_scale = 0.025;
uniform float wind_speed = 0.05;
uniform float gust_threshold : hint_range(0.0, 1.0) = 0.4;
// Metros que se mueve un punto a `bend_height` de altura en una planta flexible (rigidez 0).
uniform float gust_strength = 0.28;
uniform float sway_strength = 0.05;
uniform float sway_speed = 1.3;
uniform float sway_frequency = 0.35;
// Cabeceo rápido (las flores tiemblan con la brisa).
uniform float flutter_strength = 0.03;
uniform float flutter_speed = 5.0;
// Altura (m) a la que se dobla «del todo»; por encima, algo más. La raíz no se mueve.
uniform float bend_height = 1.0;
// Lo que quita la rigidez al viento (1 = un arbusto firme casi no se mueve).
uniform float stiffness_damping : hint_range(0.0, 1.0) = 0.8;

group_uniforms interaction;
uniform float push_radius = 1.0;
uniform float push_strength = 0.4;
// Altura (m) desde la que el empuje se nota entero (las flores bajas también se apartan).
uniform float push_height = 0.3;

group_uniforms ground_masks;
// Los mismos valores que `grass.gdshader` (si se cambian allí, cambiarlos aquí).
uniform bool use_ground_masks = false;
uniform float ground_stiffness : hint_range(0.0, 1.0) = 0.4;
uniform float clearing_threshold = 0.53;
uniform float flat_dirt_amount = 1.0;
uniform float slope_rock_up = 0.74;
uniform float wall_rock_up = 0.8;
uniform float rock_edge = 0.03;
uniform sampler2D block_mask : hint_default_black, filter_linear, repeat_disable;
uniform vec4 block_rect = vec4(0.0);

group_uniforms distance;
// Se encogen entre estas distancias a la cámara (las del césped; los arbustos, más lejos con INSTANCE_CUSTOM.b).
uniform float fade_start = 25.0;
uniform float fade_end = 33.0;

varying float v_tint;
varying float v_height;
varying float v_glow;

#include "res://entities/nature/toy_noise.gdshaderinc"

// Copias de `grass.gdshader` (que las copia de `terrain.gdshader`): mismas coordenadas y mismos ruidos.
vec2 ground_p(vec3 pos) {
	return mat2(vec2(0.866, 0.5), vec2(-0.5, 0.866)) * pos.xz;
}

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

float rock_at(vec3 pos, float up, float wall) {
	vec2 p = ground_p(pos);
	float mid = fbm(p * 0.35 + 17.0);
	float fine = value_noise(p * 2.3 + 41.0);
	float wall_zone = smoothstep(0.12, 0.25, wall + (mid - 0.5) * 0.15);
	float rock_mid = mix(slope_rock_up, wall_rock_up, wall_zone);
	return 1.0 - smoothstep(rock_mid - rock_edge, rock_mid + rock_edge, up + (mid - 0.5) * 0.22 + (fine - 0.5) * 0.05);
}


void vertex() {
	// Con MultiMesh, MODEL_MATRIX incluye la instancia: su origen es la raíz de la planta.
	vec3 root = MODEL_MATRIX[3].xyz;
	float plant_scale = length(MODEL_MATRIX[1].xyz);
	float height = max(VERTEX.y - root.y, 0.0);
	float stiffness = use_ground_masks ? ground_stiffness : clamp(INSTANCE_CUSTOM.g, 0.0, 1.0);

	// 0) Encoger con la distancia a la cámara (sin cortes bruscos) y, en el césped, donde él se encoge.
	float reach = use_ground_masks ? 1.0 : 1.0 + clamp(INSTANCE_CUSTOM.b, 0.0, 1.0);
	float shrink = 1.0 - smoothstep(fade_start * reach, fade_end * reach, distance(root, CAMERA_POSITION_WORLD));
	if (use_ground_masks) {
		shrink *= 1.0 - smoothstep(0.42, 0.65, clearing_at(root, INSTANCE_CUSTOM.g));
		shrink *= 1.0 - smoothstep(0.3, 0.7, rock_at(root, INSTANCE_CUSTOM.b, INSTANCE_CUSTOM.a));
		if (block_rect.z > 0.0) {
			vec2 block_uv = (root.xz - block_rect.xy) / block_rect.zw;
			if (all(greaterThanEqual(block_uv, vec2(0.0))) && all(lessThanEqual(block_uv, vec2(1.0)))) {
				shrink *= 1.0 - smoothstep(0.35, 0.6, textureLod(block_mask, block_uv, 0.0).r);
			}
		}
	}
	VERTEX = root + (VERTEX - root) * shrink;
	height *= shrink;

	// 1) Viento, muestreado en la raíz para que la planta se doble entera.
	vec2 dir = normalize(wind_direction);
	vec3 wind_dir = vec3(dir.x, 0.0, dir.y);
	vec3 side_dir = vec3(-dir.y, 0.0, dir.x);
	vec2 wind_uv = root.xz * wind_scale - dir * (TIME * wind_speed);
	float gust = smoothstep(gust_threshold, 1.0, textureLod(wind_noise, wind_uv, 0.0).r);
	float sway = sin(dot(root.xz, dir) * sway_frequency - TIME * sway_speed);
	float phase = INSTANCE_CUSTOM.r * TAU;
	float flutter = sin(TIME * flutter_speed + phase + height * 6.0) * (0.35 + gust);
	float bend = pow(clamp(height / bend_height, 0.0, 1.6), 1.5);
	float give = 1.0 - stiffness * stiffness_damping;
	vec3 offset = (wind_dir * (gust * gust_strength + sway * sway_strength) + side_dir * flutter * flutter_strength)
			* bend * give;

	// 2) El jugador la aparta hacia fuera (solo si está a su altura). Las bajas también: su curva llega antes.
	vec3 away = root - player_position;
	float height_gap = abs(away.y);
	away.y = 0.0;
	float dist = length(away);
	float push = (1.0 - smoothstep(push_radius * 0.3, push_radius * max(plant_scale, 1.0), dist))
			* (1.0 - smoothstep(1.0, 2.0, height_gap));
	vec3 away_dir = dist > 0.001 ? away / dist : wind_dir;
	float push_bend = clamp(height / max(push_height, 0.01), 0.0, 1.0);
	offset += away_dir * push * push_strength * push_bend * mix(1.0, 0.45, stiffness);

	// Aplicar: lo de arriba se aparta y baja un poco para que la planta no se estire.
	VERTEX.xz += offset.xz;
	VERTEX.y -= length(offset.xz) * 0.35 * clamp(height / bend_height, 0.0, 1.0);

	v_tint = INSTANCE_CUSTOM.r;
	v_height = height;
}


void fragment() {
	vec3 color = texture(palette_texture, UV).rgb;
	bool tinted_stem = stem_tint > 0.0 && UV.x > stem_swatch.x && UV.x < stem_swatch.z && UV.y > stem_swatch.y
			&& UV.y < stem_swatch.w;
	if (tinted_stem) {
		// Sin la sombra de la base: en un trébol, el tallo es casi todo base y se veía oscuro entre las briznas.
		color = mix(color, stem_tint_color, stem_tint);
	} else {
		color *= mix(base_shade, 1.0, smoothstep(0.0, base_shade_height, v_height));
	}
	color *= 1.0 + (v_tint - 0.5) * 2.0 * tint_variation;
	ALBEDO = color;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	v_glow = smoothstep(0.0, base_shade_height, v_height);
}


void light() {
	// Difusa envolvente (Godot multiplica luego por ALBEDO).
	vec3 light_in = LIGHT_COLOR * ATTENUATION / PI;
	float wrapped = clamp((dot(NORMAL, LIGHT) + light_wrap) / (1.0 + light_wrap), 0.0, 1.0);
	DIFFUSE_LIGHT += light_in * wrapped;
	// Translucidez: las hojas brillan cuando miras hacia el sol a través de ellas.
	float behind = pow(clamp(dot(LIGHT, -VIEW), 0.0, 1.0), translucency_power);
	DIFFUSE_LIGHT += light_in * translucency_color * behind * translucency_strength * v_glow;
}
