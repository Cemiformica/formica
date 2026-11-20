shader_type spatial;
// Interior del refugio (C5.5, César): tierra de hormiguero con textura de juguete, como el terreno y los árboles
// (`toy_noise.gdshaderinc`). El color de base sale de la paleta, como lo pintó `shelter_blockout.py` (paredes, y lo
// alto de la cúpula más oscuro); encima:
// - capas de tierra suaves, con el borde ondulado y una línea algo más oscura entre ellas;
// - motas y piedrecitas, como las de la tierra pisada;
// - surcos de las hormigas: grupos de dos o tres marcas cortas y curvas, como raspadas por mandíbulas, solo en las
//   paredes (`Refugio.md` §5).
// Las coordenadas van alrededor del centro de la sala (lo que se recorre por la pared y la altura), en el espacio del
// modelo: el dibujo no depende de dónde esté el refugio. La costura del ángulo cae en la esquina del fondo (norte).
// Dónde tocar: las constantes de abajo (0 = sin ese efecto).

#include "res://entities/nature/toy_noise.gdshaderinc"

uniform sampler2D palette_texture : source_color, filter_nearest;
uniform sampler2D surface_texture : filter_nearest;

// Centro de la sala en el modelo (z de Godot = −y de Blender; ROOM_CENTER = (0, 0,2) en `shelter_blockout.py`).
const vec2 ROOM_CENTER_XZ = vec2(0.0, -0.2);
const float ROOM_RADIUS = 2.95;

// Capas.
const float BAND_HEIGHT = 0.42;
const float BAND_WAVE = 0.9;
const float BAND_CONTRAST = 0.13;
const float BAND_LINE = 0.07;
const float BAND_LINE_DARK = 0.22;
// Motas.
const float SPECKS = 0.10;
const float PEBBLES = 0.8;
// Surcos: tamaño de cada casilla (por la pared y en alto, m), cuántas tienen, lo oscuros, largos y finos que son.
const vec2 GROOVE_CELL = vec2(0.85, 0.6);
const float GROOVE_CHANCE = 0.4;
const float GROOVE_DARK = 0.6;
const float GROOVE_LENGTH = 0.22;
const float GROOVE_WIDTH = 0.022;
const float GROOVE_SPACING = 0.065;

varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}

// Marca de surcos en la casilla `cell`, en el punto `q` (metros desde su centro). 0 = nada, 1 = surco.
float grooves(vec2 cell, vec2 q) {
	if (hash(cell + 5.1) > GROOVE_CHANCE) {
		return 0.0;
	}
	// Centro algo desplazado, un giro y una curva distintos en cada grupo, y dos o tres surcos.
	q -= (vec2(hash(cell + 13.0), hash(cell + 17.0)) - 0.5) * GROOVE_CELL * 0.35;
	float tilt = (hash(cell + 23.0) - 0.5) * 1.1;
	q = mat2(vec2(cos(tilt), sin(tilt)), vec2(-sin(tilt), cos(tilt))) * q;
	float bend = (hash(cell + 29.0) - 0.5) * 6.0;
	float count = hash(cell + 31.0) < 0.5 ? 2.0 : 3.0;
	float length_m = GROOVE_LENGTH * mix(0.75, 1.25, hash(cell + 37.0));
	float mark = 0.0;
	for (int k = 0; k < 3; k++) {
		float fk = float(k);
		if (fk >= count) {
			break;
		}
		float offset = (fk - (count - 1.0) * 0.5) * GROOVE_SPACING;
		float x = q.x - offset * 0.4;                         // cada surco algo corrido, como un zarpazo
		float along = abs(x) / (length_m * mix(0.8, 1.0, hash(cell + 41.0 + fk)));
		float width = GROOVE_WIDTH * (1.0 - along * along);   // afilado en las puntas
		float d = abs(q.y - offset - bend * x * x);
		mark = max(mark, (1.0 - smoothstep(width * 0.55, width, d)) * step(along, 1.0));
	}
	return mark;
}

void fragment() {
	vec3 color = texture(palette_texture, UV).rgb;
	vec4 surface = texture(surface_texture, UV);
	vec2 from_center = local_pos.xz - ROOM_CENTER_XZ;
	float around = atan(from_center.x, from_center.y) * ROOM_RADIUS;   // metros recorridos por la pared
	vec2 wall_p = vec2(around, local_pos.y);

	// Capas de tierra.
	float band_y = local_pos.y / BAND_HEIGHT + (fbm(wall_p * vec2(0.5, 0.3) + 7.0) - 0.5) * BAND_WAVE;
	float layer = floor(band_y);
	float tone = mix(1.0 - BAND_CONTRAST, 1.0 + BAND_CONTRAST, hash(vec2(layer, 3.0)));
	tone *= 1.0 - (1.0 - smoothstep(0.0, BAND_LINE, fract(band_y))) * BAND_LINE_DARK;

	// Motas y piedrecitas.
	vec2 speck_p = wall_p * 7.0;
	tone *= 1.0 + (value_noise(speck_p * 3.1 + 5.0) - 0.5) * 2.0 * SPECKS;
	float pebble = smoothstep(0.78, 0.84, value_noise(speck_p + 29.0)) * PEBBLES;
	float pebble_tone = step(0.5, value_noise(speck_p * 0.5 + 91.0));
	tone *= mix(1.0, mix(0.72, 1.15, pebble_tone), pebble);

	// Surcos, solo en lo que es pared (no en techos ni suelos).
	float wallness = 1.0 - smoothstep(0.45, 0.75, abs(normalize(local_normal).y));
	vec2 gp = wall_p / GROOVE_CELL;
	vec2 cell = floor(gp);
	float mark = grooves(cell, (fract(gp) - 0.5) * GROOVE_CELL);
	tone *= mix(1.0, GROOVE_DARK, mark * wallness);

	ALBEDO = clamp(color * tone, 0.0, 1.0);
	METALLIC = surface.r;
	ROUGHNESS = surface.g;
}
