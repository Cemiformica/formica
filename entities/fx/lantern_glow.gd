class_name LanternGlow
extends Node3D
## Luz de una llama (C5.5, D-188 y D-191): el candil y el fogón del refugio. Hace brillar sus llamas (mallas del
## modelo) y pone una luz cálida que parpadea. Hay dos estilos:
## - **farol** (el candil): una llama quieta que se queda a la vista, oscura, cuando está apagado;
## - **hoguera** (`fire`, el fogón): llamas que bailan y se esconden al apagarse, brasas que laten, chispas que suben,
##   crepitar mientras arde y un hilo de humo un rato después de apagarlo.
## `set_lit()` lo enciende (con un fundido) o lo apaga. Lo monta `RepairSiteView` con lo que dice `RepairLightData`.
## Uso: `var glow := LanternGlow.new(); glow.setup(llamas, es_hoguera, brasas); vacío.add_child(glow); glow.set_lit(true)`.

const LANTERN_COLOR: Color = Color(1.0, 0.68, 0.36)
const FIRE_COLOR: Color = Color(1.0, 0.56, 0.26)
const LANTERN_ENERGY: float = 1.6
const FIRE_ENERGY: float = 2.8
const LANTERN_RANGE: float = 5.5
const FIRE_RANGE: float = 7.0
## Llama: apagada, mecha oscura; encendida, ámbar que brilla.
const FLAME_DARK: Color = Color(0.25, 0.17, 0.1)
const FLAME_COLOR: Color = Color(1.0, 0.62, 0.22)
const FLAME_GLOW: float = 3.0
## Brasas: apagadas, ceniza; encendidas, rojo que late.
const EMBER_DARK: Color = Color(0.22, 0.2, 0.19)
const EMBER_COLOR: Color = Color(1.0, 0.3, 0.08)
const EMBER_GLOW: float = 2.2
## Lo que tarda en prender (s) y cuánto parpadea cada estilo.
const LIGHT_UP_TIME: float = 1.2
const LANTERN_FLICKER: float = 0.12
const FIRE_FLICKER: float = 0.22
## Sonidos de la hoguera (`make_sounds.py`, `write_fire_sounds`).
const LIGHT_SOUND: AudioStream = preload("res://assets/audio/fire_light.wav")
const OUT_SOUND: AudioStream = preload("res://assets/audio/fire_out.wav")
const CRACKLE_SOUND: AudioStreamWAV = preload("res://assets/audio/fire_crackle_loop.wav")
const CRACKLE_DB: float = -14.0   # suave, que se oiga de cerca (César: sonaba a soplete; después, aún algo fuerte)
## Humo después de apagar la hoguera (s).
const SMOKE_AFTER: float = 25.0

var _fire: bool = false
var _flames: Array[MeshInstance3D] = []
var _flame_scales: Array[Vector3] = []
var _embers: MeshInstance3D = null
var _flame_material: StandardMaterial3D
var _ember_material: StandardMaterial3D
var _light: OmniLight3D
var _sparks: GPUParticles3D = null
var _smoke: GPUParticles3D = null
var _crackle: LoopSound = null
var _level: float = 0.0   # 0 apagado, 1 encendido del todo (sin el parpadeo)
var _lit: bool = false
var _time: float = 0.0
var _smoke_until_ms: int = 0
var _tween: Tween = null


## `flames` puede estar vacío (luz sin llama visible); `embers`, null. Se llama ANTES de añadirlo al árbol.
func setup(flames: Array[MeshInstance3D], fire: bool = false, embers: MeshInstance3D = null) -> void:
	name = "FireGlow" if fire else "LanternGlow"
	_fire = fire
	_flames = flames
	_embers = embers
	_flame_material = StandardMaterial3D.new()
	_flame_material.albedo_color = FLAME_DARK
	_flame_material.emission_enabled = true
	_flame_material.emission = FLAME_COLOR
	_flame_material.emission_energy_multiplier = 0.0
	for flame: MeshInstance3D in _flames:
		flame.material_override = _flame_material
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # la llama no tapa su propia luz
		_flame_scales.append(flame.scale)
	if _embers != null:
		_ember_material = StandardMaterial3D.new()
		_ember_material.albedo_color = EMBER_DARK
		_ember_material.emission_enabled = true
		_ember_material.emission = EMBER_COLOR
		_ember_material.emission_energy_multiplier = 0.0
		_embers.material_override = _ember_material
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = FIRE_COLOR if fire else LANTERN_COLOR
	_light.omni_range = FIRE_RANGE if fire else LANTERN_RANGE
	_light.omni_attenuation = 1.3
	# Con sombras: si no, la luz atravesaría las paredes del refugio y alumbraría el suelo de fuera.
	_light.shadow_enabled = true
	_light.shadow_bias = 0.05
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 35.0
	_light.distance_fade_length = 10.0
	add_child(_light)
	if fire:
		_sparks = _make_sparks()
		add_child(_sparks)
		_smoke = _make_smoke()
		add_child(_smoke)
	_time = randf() * 100.0
	_apply()


## Enciende o apaga; sin `animated`, de golpe y sin sonido (al cargar la partida).
func set_lit(lit: bool, animated: bool = true) -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	var was_lit: bool = _lit
	_lit = lit
	var goal: float = 1.0 if lit else 0.0
	if not animated or not is_inside_tree():
		_level = goal
		_apply()
		return
	if _fire and lit != was_lit:
		_play(LIGHT_SOUND if lit else OUT_SOUND)
		if not lit:
			_smoke_until_ms = Time.get_ticks_msec() + int(SMOKE_AFTER * 1000.0)
	_tween = create_tween()
	if lit:
		# Prende como una mecha: un chispazo corto, baja un poco y sube hasta su brillo.
		_tween.tween_property(self, "_level", 0.7, LIGHT_UP_TIME * 0.25).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "_level", 0.4, LIGHT_UP_TIME * 0.2)
		_tween.tween_property(self, "_level", 1.0, LIGHT_UP_TIME * 0.55).set_trans(Tween.TRANS_SINE)
	else:
		_tween.tween_property(self, "_level", 0.0, LIGHT_UP_TIME * 0.6).set_trans(Tween.TRANS_SINE)


## ¿Está encendido (o encendiéndose)?
func is_lit() -> bool:
	return _lit


func _ready() -> void:
	if _fire:
		_crackle = LoopSound.create(self, CRACKLE_SOUND, CRACKLE_DB)


func _process(delta: float) -> void:
	_time += delta
	_apply()
	if _crackle != null and _level > 0.3:
		_crackle.keep()


## Brillo de ahora: el nivel por un parpadeo suave (tres ondas que no se repiten igual).
func _apply() -> void:
	var amount: float = FIRE_FLICKER if _fire else LANTERN_FLICKER
	var flicker: float = 1.0 + amount * (0.5 * sin(_time * 7.3) + 0.3 * sin(_time * 13.1 + 1.7) + 0.2 * sin(_time * 23.7 + 0.4))
	var value: float = _level * flicker
	_light.visible = _level > 0.001
	_light.light_energy = (FIRE_ENERGY if _fire else LANTERN_ENERGY) * value
	_flame_material.emission_energy_multiplier = FLAME_GLOW * value
	_flame_material.albedo_color = FLAME_DARK.lerp(FLAME_COLOR, clampf(_level, 0.0, 1.0))
	if _fire:
		# Cada llama baila a su ritmo (su origen está en su base) y se encoge hasta desaparecer al apagarse.
		var grow: float = clampf(_level, 0.0, 1.0)
		for i: int in _flames.size():
			var dance: float = 0.5 * sin(_time * (8.0 + i * 1.7) + i * 2.1) + 0.5 * sin(_time * (13.0 + i * 2.3) + i)
			_flames[i].scale = _flame_scales[i] * Vector3(1.0 - 0.1 * dance, (0.8 + 0.3 * dance) * grow, 1.0 - 0.1 * dance)
			_flames[i].visible = grow > 0.02
		if _embers != null:
			var pulse: float = 0.75 + 0.25 * sin(_time * 2.1)
			_ember_material.emission_energy_multiplier = EMBER_GLOW * pulse * _level
			_ember_material.albedo_color = EMBER_DARK.lerp(EMBER_COLOR * 0.6, grow)
		_sparks.emitting = _level > 0.5
		_smoke.emitting = _level < 0.1 and Time.get_ticks_msec() < _smoke_until_ms


func _play(stream: AudioStream) -> void:
	var sound := AudioStreamPlayer3D.new()
	sound.stream = stream
	sound.bus = &"SFX"
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()


## Chispas: puntitos naranjas que suben deprisa, tiemblan y se apagan.
func _make_sparks() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.12
	process.direction = Vector3.UP
	process.spread = 18.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 1.1
	process.gravity = Vector3(0.0, 0.2, 0.0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.6
	process.turbulence_influence_min = 0.05
	process.turbulence_influence_max = 0.12
	process.scale_min = 0.6
	process.scale_max = 1.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.8, 0.4, 1.0))
	fade.set_color(1, Color(1.0, 0.3, 0.1, 0.0))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.025, 0.025)
	quad.material = material
	var sparks := GPUParticles3D.new()
	sparks.name = "Sparks"
	sparks.process_material = process
	sparks.draw_pass_1 = quad
	sparks.amount = 10
	sparks.lifetime = 1.1
	sparks.randomness = 0.5
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sparks.emitting = false
	return sparks


## Humo: unas bolitas grises que suben despacio y se abren (como el humo de las máquinas, más fino).
func _make_smoke() -> GPUParticles3D:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.06
	process.direction = Vector3.UP
	process.spread = 8.0
	process.initial_velocity_min = 0.15
	process.initial_velocity_max = 0.3
	process.gravity = Vector3(0.0, 0.05, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	process.scale_curve = grow_texture
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	fade.add_point(0.2, Color(1, 1, 1, 0.35))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.53, 0.5)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	quad.material = material
	var smoke := GPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.process_material = process
	smoke.draw_pass_1 = quad
	smoke.amount = 8
	smoke.lifetime = 3.0
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.emitting = false
	return smoke
