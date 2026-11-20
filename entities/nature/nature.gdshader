shader_type spatial;
// Naturaleza (César, sesión 23): igual que el material paleta (`palette.tres`: color de la paleta, y brillo y
// rugosidad del mapa de superficie, D-105), pero
// - cada árbol tiñe un poco su madera y sus hojas para que no salgan todos del mismo color exacto. El tono lo pone
//   `TreeView` por casilla, con parámetros por instancia: todos comparten este material y se dibujan juntos;
// - una textura de juguete sin imágenes, como la de los acantilados (`toy_noise.gdshaderinc`): vetas de corteza en
//   la madera (nudos de juguete con el borde marcado), manchas y motas en las hojas, motas en la piedra, y la copa más oscura por abajo que por arriba.
// El dibujo va en coordenadas del modelo: se mueve con él (el árbol que cae se lleva su corteza).
// En la paleta (art/tools/make_palette.py), la fila 0 es la madera, la 1 la piedra y la 2 los verdes.
// Dónde tocar: las constantes de abajo (fuerza de cada efecto; 0 = sin él).

#include "res://entities/nature/toy_noise.gdshaderinc"

uniform sampler2D palette_texture : source_color, filter_nearest;
uniform sampler2D surface_texture : filter_nearest;

// Multiplicadores de color (1, 1, 1 = como en la paleta).
instance uniform vec3 wood_tint = vec3(1.0);
instance uniform vec3 leaf_tint = vec3(1.0);

// Madera: lisa, como un juguete, con nudos sueltos de borde marcado (César: las vetas difuminadas parecían buscar
// realismo). La superficie se divide en casillas (cuántas alrededor del tronco y cuántas por metro de alto) y en
// algunas hay una marca, de uno de tres tipos (César: que no fueran todas iguales ni tan geométricas), con el borde
// abollado y un giro al azar:
//   0 nudo: mancha oscura con un aro fino más claro;
//   1 ojo: almendra con el borde oscuro y una pupila oscura en el centro;
//   2 rama cortada: disco claro con un aro oscuro.
const float KNOT_CELLS_AROUND = 5.0;
const float KNOT_CELLS_PER_M = 2.6;
const float KNOT_CHANCE = 0.38;       // parte de las casillas con nudo
const float KNOT_RADIUS = 0.15;       // en casillas (el nudo nunca sale de la suya)
const float KNOT_DARK = 0.55;         // centro del nudo
const float KNOT_RING = 1.18;         // aro de alrededor
const float KNOT_RING_WIDTH = 0.05;
const float KNOT_WOBBLE = 0.25;       // cuánto se abolla el borde (0 = formas perfectas)
const float KNOT_TILT = 0.45;         // giro máximo de cada marca (radianes)
const float CUT_LIGHT = 1.22;         // centro claro de la rama cortada
const float BARK_SPECKS = 0.04;       // motas casi imperceptibles
// Hojas: manchas grandes, motas finas y sombra de juguete (abajo más oscuro, arriba más claro).
const float LEAF_PATCHES = 0.22;
const float LEAF_SPECKS = 0.10;
const float LEAF_SHADE_LOW = 0.72;
const float LEAF_SHADE_HIGH = 1.08;
// Piedra: motas.
const float STONE_SPECKS = 0.16;

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 color = texture(palette_texture, UV).rgb;
	vec4 surface = texture(surface_texture, UV);
	float row = floor(UV.y * 8.0);
	float is_wood = 1.0 - step(0.5, row);                        // fila 0
	float is_stone = step(0.5, row) * (1.0 - step(1.5, row));    // fila 1
	float is_leaf = step(1.5, row) * (1.0 - step(2.5, row));     // fila 2
	vec3 tint = mix(vec3(1.0), wood_tint, is_wood);
	tint = mix(tint, leaf_tint, is_leaf);

	// Nudos: casillas en (ángulo alrededor del tronco, altura). La de cada vuelta se repite (mod), así no hay costura
	// donde el ángulo pasa de 1 a 0.
	vec2 knot_p = vec2((atan(local_pos.z, local_pos.x) / 6.2832 + 0.5) * KNOT_CELLS_AROUND, local_pos.y * KNOT_CELLS_PER_M);
	vec2 knot_cell = floor(knot_p);
	vec2 knot_key = vec2(mod(knot_cell.x, KNOT_CELLS_AROUND), knot_cell.y);
	float has_knot = step(hash(knot_key + 3.7), KNOT_CHANCE);
	// Centro al azar dentro de la casilla, sin acercarse al borde; tamaño, giro y tipo distintos en cada una.
	vec2 knot_center = vec2(0.36, 0.36) + vec2(hash(knot_key + 11.0), hash(knot_key + 23.0)) * 0.28;
	float knot_size = KNOT_RADIUS * mix(0.7, 1.15, hash(knot_key + 41.0));
	float tilt = (hash(knot_key + 53.0) - 0.5) * 2.0 * KNOT_TILT;
	float knot_type = floor(hash(knot_key + 67.0) * 3.0);
	vec2 q = (fract(knot_p) - knot_center) / knot_size;
	q = mat2(vec2(cos(tilt), sin(tilt)), vec2(-sin(tilt), cos(tilt))) * q;
	// Borde abollado: ruido según la dirección desde el centro (sobre un círculo, así no hay costura).
	float knot_a = atan(q.y, q.x);
	float wobble = (value_noise(vec2(cos(knot_a), sin(knot_a)) * 1.7 + knot_key * 7.3) - 0.5) * 2.0 * KNOT_WOBBLE;
	float ring_w = KNOT_RING_WIDTH / knot_size;
	float mark = 1.0;
	if (knot_type < 0.5) {
		// Nudo: óvalo algo más alto que ancho.
		float d = length(q * vec2(1.0, 0.75)) * (1.0 + wobble);
		float core = 1.0 - smoothstep(0.9, 1.0, d);
		float ring = (1.0 - smoothstep(1.0, 1.0 + ring_w, d)) * (1.0 - core);
		mark = mix(1.0, KNOT_DARK, core) * mix(1.0, KNOT_RING, ring);
	} else if (knot_type < 1.5) {
		// Ojo: almendra con las puntas arriba y abajo; ancho que se cierra hacia las puntas.
		float half_height = 1.45;
		float width = 0.62 * (1.0 - pow(clamp(abs(q.y) / half_height, 0.0, 1.0), 2.0));
		float d = (abs(q.y) < half_height ? abs(q.x) / max(width, 0.001) : 2.0) * (1.0 + wobble * 0.6);
		float outline = smoothstep(0.62, 0.72, d) * (1.0 - smoothstep(0.95, 1.05, d));
		float pupil = 1.0 - smoothstep(0.26, 0.34, length(q * vec2(1.0, 0.8)) * (1.0 + wobble));
		mark = mix(1.0, KNOT_DARK, max(outline, pupil));
	} else {
		// Rama cortada: disco claro con el aro oscuro.
		float d = length(q) * (1.0 + wobble);
		float disc = 1.0 - smoothstep(0.62, 0.7, d);
		float ring = (1.0 - smoothstep(0.92, 1.0, d)) * (1.0 - disc);
		mark = mix(1.0, CUT_LIGHT, disc) * mix(1.0, KNOT_DARK, ring);
	}
	float wood_fine = value_noise(local_pos.xy * 22.0 + local_pos.zy * 17.0);
	float bark = 1.0 + (wood_fine - 0.5) * 2.0 * BARK_SPECKS;
	bark *= mix(1.0, mark, has_knot);

	// Hojas: dos planos de ruido cruzados para que se vea bien desde todos los lados.
	float patches = fbm(local_pos.xy * 1.8 + 5.0) * 0.5 + fbm(local_pos.zy * 1.8 + 31.0) * 0.5;
	float leaf_fine = value_noise(local_pos.xz * 14.0 + local_pos.y * 9.0);
	float shade = mix(LEAF_SHADE_LOW, LEAF_SHADE_HIGH, normalize(local_normal).y * 0.5 + 0.5);
	float leaf = (1.0 + (patches - 0.5) * 2.0 * LEAF_PATCHES + (leaf_fine - 0.5) * 2.0 * LEAF_SPECKS) * shade;

	float stone = 1.0 + (value_noise(local_pos.xz * 18.0 + local_pos.y * 11.0) - 0.5) * 2.0 * STONE_SPECKS;

	float toy = mix(1.0, bark, is_wood);
	toy = mix(toy, leaf, is_leaf);
	toy = mix(toy, stone, is_stone);

	ALBEDO = clamp(color * tint * toy, 0.0, 1.0);
	METALLIC = surface.r;
	ROUGHNESS = surface.g;
}
