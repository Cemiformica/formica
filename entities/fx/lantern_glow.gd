class_name LanternGlow
extends Node3D
## Luz de un candil o farol (C5.5: el candil del refugio, D-180). Hace brillar su llama (una malla del modelo) y pone
## una luz cálida que parpadea suave. `set_lit()` lo enciende (con un fundido) o lo apaga. Lo monta `RepairSiteView`
## con la malla «lantern_flame» y el vacío «lantern_light» del modelo.
## Uso: `var glow := LanternGlow.new(); glow.setup(llama); vacío.add_child(glow); glow.set_lit(true)`.

const LIGHT_COLOR: Color = Color(1.0, 0.68, 0.36)
const LIGHT_ENERGY: float = 1.6
const LIGHT_RANGE: float = 5.5
## Llama: apagada, mecha oscura; encendida, ámbar que brilla.
const FLAME_DARK: Color = Color(0.25, 0.17, 0.1)
const FLAME_COLOR: Color = Color(1.0, 0.62, 0.22)
const FLAME_GLOW: float = 3.0
## Lo que tarda en prender (s) y cuánto y con qué ritmo parpadea.
const LIGHT_UP_TIME: float = 1.2
const FLICKER: float = 0.12

var _flame: MeshInstance3D = null
var _flame_material: StandardMaterial3D
var _light: OmniLight3D
var _level: float = 0.0   # 0 apagado, 1 encendido del todo (sin el parpadeo)
var _lit: bool = false
var _time: float = 0.0
var _tween: Tween = null


## `flame` puede ser null (luz sin llama visible). Se llama ANTES de añadirlo al árbol.
func setup(flame: MeshInstance3D) -> void:
	name = "LanternGlow"
	_flame = flame
	_flame_material = StandardMaterial3D.new()
	_flame_material.albedo_color = FLAME_DARK
	_flame_material.emission_enabled = true
	_flame_material.emission = FLAME_COLOR
	_flame_material.emission_energy_multiplier = 0.0
	if _flame != null:
		_flame.material_override = _flame_material
		_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # la llama no tapa su propia luz
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = LIGHT_COLOR
	_light.omni_range = LIGHT_RANGE
	_light.omni_attenuation = 1.3
	# Con sombras: si no, la luz atravesaría las paredes del refugio y alumbraría el suelo de fuera.
	_light.shadow_enabled = true
	_light.shadow_bias = 0.05
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 35.0
	_light.distance_fade_length = 10.0
	add_child(_light)
	_time = randf() * 100.0
	_apply()


## Enciende o apaga; sin `animated`, de golpe (al cargar la partida).
func set_lit(lit: bool, animated: bool = true) -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	_lit = lit
	var goal: float = 1.0 if lit else 0.0
	if not animated or not is_inside_tree():
		_level = goal
		_apply()
		return
	_tween = create_tween()
	# Prende como una mecha: un chispazo corto, baja un poco y sube hasta su brillo.
	_tween.tween_property(self, "_level", 0.7 * goal, LIGHT_UP_TIME * 0.25).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "_level", 0.4 * goal, LIGHT_UP_TIME * 0.2)
	_tween.tween_property(self, "_level", goal, LIGHT_UP_TIME * 0.55).set_trans(Tween.TRANS_SINE)


## ¿Está encendido (o encendiéndose)?
func is_lit() -> bool:
	return _lit


func _process(delta: float) -> void:
	_time += delta
	_apply()


## Brillo de ahora: el nivel por un parpadeo suave (tres ondas que no se repiten igual).
func _apply() -> void:
	var flicker: float = 1.0 + FLICKER * (0.5 * sin(_time * 7.3) + 0.3 * sin(_time * 13.1 + 1.7) + 0.2 * sin(_time * 23.7 + 0.4))
	var value: float = _level * flicker
	_light.visible = _level > 0.001
	_light.light_energy = LIGHT_ENERGY * value
	_flame_material.emission_energy_multiplier = FLAME_GLOW * value
	_flame_material.albedo_color = FLAME_DARK.lerp(FLAME_COLOR, clampf(_level, 0.0, 1.0))
