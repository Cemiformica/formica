shader_type spatial;
// Haz de luz que entra por un hueco (C5.5: la trampilla del refugio). Se dibuja sobre un cono abierto (`LightShaft`):
// suma luz (no tapa nada), se desvanece hacia los bordes del cono, arriba y abajo, y lleva unas franjas suaves que
// se mueven despacio, como polvo en el aire. `strength` lo enciende y lo apaga (lo anima `LightShaft`).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://entities/nature/toy_noise.gdshaderinc"

uniform vec3 color : source_color = vec3(1.0, 0.9, 0.7);
uniform float intensity = 0.22;
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float height = 8.0;          // alto del cono (m), para saber a qué altura está cada punto
uniform float fade_top = 0.12;       // parte de arriba que se desvanece (en tanto por uno del alto)
uniform float fade_bottom = 0.18;    // y la de abajo, para que no se vea el corte contra el suelo

varying float along;   // 1 arriba, 0 abajo
varying vec2 ring;     // dirección alrededor del eje (sin costura, a diferencia de un ángulo)

void vertex() {
	along = VERTEX.y / height + 0.5;
	ring = normalize(VERTEX.xz + vec2(0.0001));
}

void fragment() {
	// Bordes: donde el cono se ve de canto, casi nada; de frente, el máximo.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = facing * facing;
	float ends = smoothstep(0.0, fade_bottom, along) * smoothstep(1.0, 1.0 - fade_top, along);
	// Franjas a lo largo del haz que se deslizan despacio, y algo de ruido que baja.
	float streaks = value_noise(ring * 2.5 + vec2(along * 0.4, TIME * 0.03));
	float drift = fbm(ring * 1.2 + vec2(along * 3.0 - TIME * 0.06, TIME * 0.02));
	float shade = mix(0.55, 1.15, streaks) * mix(0.75, 1.15, drift);
	ALBEDO = color * intensity * strength * edge * ends * shade;
}
