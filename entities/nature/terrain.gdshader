// Suelo de las islas con plano (C5.4a). La malla trae en cada esquina lo que la rodea (ver
// `TerrainView._build_layout_ground()`): COLOR.r arena, COLOR.g mojado, COLOR.b sendero, COLOR.a altura (0 abajo,
// 1 arriba); UV2.x superficie del agua cercana (m), UV2.y explanada; UV.x borde de hierba de las paredes y UV.y lo que
// es pared. La roca sale de la pendiente, antes en las paredes. Las manchas, de un ruido
// en coordenadas del mundo (sin texturas). Dónde tocar: los colores y los umbrales de abajo.
shader_type spatial;
render_mode cull_disabled;

// Colores con Solarpunk como referencia (César): hierba más viva, tierra beis clara y roca rojiza.
// Hierba: la de abajo, la de arriba (algo más cálida, para distinguirla desde abajo) y la seca de las manchas.
uniform vec3 grass_low : source_color = vec3(0.32, 0.52, 0.23);
uniform vec3 grass_high : source_color = vec3(0.39, 0.55, 0.23);
uniform vec3 grass_dry : source_color = vec3(0.55, 0.58, 0.30);
uniform vec3 sand : source_color = vec3(0.88, 0.81, 0.64);
uniform vec3 wet_sand : source_color = vec3(0.60, 0.50, 0.37);
// Hasta cuántos metros sobre el agua llega la arena mojada.
uniform float wet_height = 0.45;
// Arena mojada que va y viene (sesión 23, César): solo sobre la arena, oscurece su color. Cada `swash_period` segundos
// el agua sube por la orilla hasta `wet_height` (deprisa) y baja (despacio); lo de abajo se queda húmedo y lo de arriba
// se va secando. Cada tramo de playa va a su ritmo.
uniform float swash_period = 7.0;
uniform float wet_darken = 0.68;   // lo oscura que queda la arena empapada (1 = nada)
uniform vec3 dirt : source_color = vec3(0.71, 0.62, 0.49);
uniform vec3 rock : source_color = vec3(0.66, 0.44, 0.32);
// Estratos de la roca (C5.4c): tonos de las capas, alto de cada una (m) y la línea oscura entre ellas.
uniform vec3 rock_light : source_color = vec3(0.76, 0.54, 0.38);
uniform vec3 rock_dark : source_color = vec3(0.52, 0.33, 0.25);
uniform float strata_height = 1.1;
uniform float strata_line = 0.07;
uniform vec3 bed_deep : source_color = vec3(0.10, 0.38, 0.50);
// Fondo del mar lejos de la costa: se pierde en la oscuridad, del color del fondo del cielo (`isla_alba.tscn`).
uniform vec3 abyss : source_color = vec3(0.04, 0.14, 0.22);
// Pendiente (componente vertical de la normal) en la que la hierba pasa a roca.
uniform float rock_from = 0.55;
uniform float rock_to = 0.75;
// Ancho del paso de hierba a roca: corto, para que sea una cosa u otra con el borde roto por el ruido (con un paso
// largo, las cuestas medianas salían a medias, mezcladas y a triángulos: captura de César).
uniform float rock_edge = 0.03;
// Pendiente desde la que es roca en el terreno con plano (C5.6, César: las cuestas fuertes, peladas y claras, mejor de
// roca que de hierba): en las lomas y cuestas, `slope_rock_up` (unos 42°); en las paredes del plano (UV.y), antes,
// `wall_rock_up` (unos 37°). Los modelos del terreno (refugio) siguen con rock_from y rock_to.
uniform float slope_rock_up = 0.74;
uniform float wall_rock_up = 0.8;
// Cuánto manchan los ruidos (en las explanadas, la mitad: ahí se construye y se tiene que leer bien).
uniform float patch_strength = 1.0;
// Claros de tierra pisada sueltos por las explanadas, como en Solarpunk (0 = ninguno) y cuánta explanada cubren
// (más bajo = más claros).
uniform float flat_dirt_amount = 1.0;
uniform float clearing_threshold = 0.53;
// Piedrecitas y motas oscuras en la tierra, para que se lea como suelo pisado.
uniform float pebble_amount = 1.0;
// Para modelos que son parte del terreno, como el hormiguero del refugio (C5.5, `assets/materials/terrain_rock.tres`):
// no se lee el color de vértice (sin arena, mojado ni sendero; la altura sale de la posición), así se ven con los
// mismos estratos y la misma hierba que los acantilados.
uniform bool object_mode = false;
uniform float object_level_height = 6.0;

varying vec3 world_pos;
varying vec3 world_normal;

#include "res://entities/nature/toy_noise.gdshaderinc"

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 ground = object_mode ? vec4(0.0, 0.0, 0.0, clamp(world_pos.y / object_level_height, 0.0, 1.0)) : COLOR;
	vec2 ground_uv2 = object_mode ? vec2(-100.0, 0.0) : UV2;   // sin agua cerca y sin explanada
	float lip_from = object_mode ? 0.0 : UV.x;                 // sin borde de hierba
	// Coordenadas giradas 30°: así las manchas no siguen la cuadrícula de construcción.
	vec2 p = mat2(vec2(0.866, 0.5), vec2(-0.5, 0.866)) * world_pos.xz;
	float big = fbm(p * 0.07);
	float mid = fbm(p * 0.35 + 17.0);
	float fine = value_noise(p * 2.3 + 41.0);
	float flat_area = ground_uv2.y;
	float patches = patch_strength * mix(1.0, 0.5, flat_area);

	// Hierba: más cálida arriba, con manchas secas grandes y motas finas.
	vec3 color = mix(grass_low, grass_high, smoothstep(0.35, 0.75, ground.a));
	color = mix(color, grass_dry, smoothstep(0.55, 0.85, big) * 0.45 * patches);
	color *= 1.0 + ((big - 0.5) * 0.35 + (fine - 0.5) * 0.08) * patches;
	color *= mix(1.0, 1.05, flat_area);

	// Roca donde es empinado (acantilados y bordes de las alturas). Se mira la cara del triángulo, no la normal
	// suavizada de las esquinas: con esa, la hierba subía en vetas por el acantilado. Se calcula antes para que la
	// tierra no la pise.
	// Sobre todo la normal suave (con la cara del triángulo, la roca salía en triángulos, captura de César) y un poco de
	// la cara, para que la hierba no suba por las paredes. El ruido rompe el borde entre las dos.
	vec3 face_normal = normalize(cross(dFdy(world_pos), dFdx(world_pos)));
	// La cara del triángulo solo cuenta donde es mucho más empinada que la normal suave (las paredes).
	float steepness = min(world_normal.y, abs(face_normal.y) + 0.2);
	float rock_mid = (rock_from + rock_to) * 0.5;
	float wall_zone = smoothstep(0.12, 0.25, UV.y + (mid - 0.5) * 0.15);
	rock_mid = object_mode ? rock_mid : mix(slope_rock_up, wall_rock_up, wall_zone);
	float cliff = 1.0 - smoothstep(rock_mid - rock_edge, rock_mid + rock_edge,
			steepness + (mid - 0.5) * 0.22 + (fine - 0.5) * 0.05);

	// Tierra pisada: el sendero y sus extremos, más claros sueltos por las explanadas, con el borde irregular.
	float worn = ground.b + (mid - 0.5) * 0.3 + (fine - 0.5) * 0.15;
	// Claros sueltos: manchas redondeadas, con el borde roto por el ruido medio y el fino.
	vec2 warp = vec2(fbm(p * 0.05 + 3.1), fbm(p * 0.05 + 9.7)) - 0.5;
	float clearing_noise = fbm(p * 0.06 + warp * 0.8 + 73.0) + (mid - 0.5) * 0.12;
	float clearing = smoothstep(clearing_threshold, clearing_threshold + 0.1, clearing_noise) * flat_area * flat_dirt_amount;
	// Sin claros cerca del agua: junto a la orilla quedaba una franja de hierba suelta entre el claro y el agua.
	clearing *= 1.0 - step(-50.0, ground_uv2.x);
	float path = smoothstep(0.3, 0.6, max(worn, clearing + (fine - 0.5) * 0.15)) * smoothstep(rock_to, rock_to + 0.1, steepness);
	vec3 soil = dirt * (0.9 + 0.12 * fine + 0.08 * mid);
	// Piedrecitas: motas pequeñas y redondeadas, algo más oscuras o algo más claras.
	vec2 speck_p = mat2(vec2(0.6, 0.8), vec2(-0.8, 0.6)) * p * 6.0;
	float pebble = smoothstep(0.78, 0.84, value_noise(speck_p + 29.0)) * pebble_amount;
	float pebble_tone = step(0.5, value_noise(speck_p * 0.5 + 91.0)); // unas más oscuras y otras más claras
	soil = mix(soil, dirt * mix(0.7, 1.1, pebble_tone), pebble * 0.8);
	color = mix(color, soil, path);

	// Hondura bajo el agua en este punto y altura sobre ella.
	float depth = ground_uv2.x - world_pos.y;
	// Arena de la playa y franja de arena mojada pegada al agua (solo hasta medio metro sobre ella: si no, subía por
	// los acantilados del mar). Ninguna de las dos pisa la roca.
	float flat_ground = 1.0 - cliff;
	float beach = smoothstep(0.3, 0.6, ground.r + (mid - 0.5) * 0.35) * flat_ground;
	color = mix(color, sand * (0.95 + 0.1 * mid), beach);
	// La marca la altura sobre el agua (antes caía casi toda bajo el mar y no se veía). Solo donde hay agua cerca.
	// Y solo en la casilla pegada al agua (si no, en las explanadas a ras del río se mojaba una franja ancha).
	float near_water = step(-50.0, ground_uv2.x) * smoothstep(0.05, 0.4, ground.g);
	float above = -depth + (fine - 0.5) * 0.06;   // altura sobre el agua, con el borde algo irregular
	float t = fract(TIME / swash_period + mid * 1.7 + big * 0.9);
	float reach = wet_height * (t < 0.2 ? smoothstep(0.0, 0.2, t) : 1.0 - smoothstep(0.2, 1.0, t));
	float front = 1.0 - smoothstep(reach - 0.03, reach + 0.02, above);        // donde llega el agua ahora
	float damp = (1.0 - smoothstep(0.0, wet_height, above)) * 0.55;            // abajo siempre algo húmeda
	float wet = max(front, damp) * near_water * beach;                         // solo sobre la arena (no en la hierba)
	color *= mix(1.0, wet_darken, wet);

	// Capas horizontales con el borde ondulado; cada capa toma uno de tres tonos y entre ellas, una línea más oscura.
	float strata_y = world_pos.y / strata_height + (mid - 0.5) * 0.9 + (big - 0.5) * 0.6;
	float layer = floor(strata_y);
	float pick = hash(vec2(layer, 7.0));
	vec3 rock_color = pick < 0.33 ? rock_dark : (pick < 0.66 ? rock : rock_light);
	float in_layer = strata_y - layer;
	rock_color *= 1.0 - (1.0 - smoothstep(0.0, strata_line, in_layer)) * 0.28;
	rock_color *= 0.92 + 0.12 * fine + 0.08 * (in_layer - 0.5);
	// Borde de hierba que asoma por lo alto de la pared, con el borde roto (lip_from lo trae de `IslandLayout.wall_lip()`).
	float lip = smoothstep(0.25, 0.6, lip_from + (mid - 0.5) * 0.5 + (fine - 0.5) * 0.25);
	// Solo bajo la hierba: bajo el sendero, el rellano o la arena el borde enseñaba su color y colgaban triángulos de
	// tierra y arena por la pared (C5.6, captura de César junto a la futura barandilla). Ahí, roca hasta el filo.
	// (Sin la pendiente: `path` y `beach` ya valen 0 en la pared.)
	lip *= 1.0 - max(smoothstep(0.25, 0.5, worn), smoothstep(0.3, 0.6, ground.r + (mid - 0.5) * 0.35));
	color = mix(color, rock_color, cliff * (1.0 - lip));

	// Bajo el agua: arena mojada en la orilla y cada vez más oscuro con la hondura.
	color = mix(color, wet_sand, smoothstep(0.0, 0.12, depth));
	color = mix(color, bed_deep, smoothstep(0.1, 1.2, depth));
	color = mix(color, abyss, smoothstep(2.0, 10.0, depth));

	ALBEDO = color;
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
}
