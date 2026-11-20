class_name LightShaft
extends Node3D
## Haz de luz que entra por un hueco (C5.5: la trampilla del refugio, D-180). Va de `top` a `bottom`: un cono abierto
## que suma luz (`light_shaft.gdshader`), un foco que deja un círculo claro donde cae y motas de polvo que flotan
## dentro. `set_on()` lo enciende o lo apaga con un fundido. Lo monta `RepairSiteView` con los vacíos
## «light_shaft_top» y «light_shaft_bottom» del modelo.
## Uso: `var shaft := LightShaft.new(); shaft.setup(arriba, abajo); padre.add_child(shaft); shaft.set_on(true)`.

const SHADER: Shader = preload("res://entities/fx/light_shaft.gdshader")
## Radio del haz arriba (la boca) y abajo (el círculo del suelo), en metros.
const TOP_RADIUS: float = 0.5
const BOTTOM_RADIUS: float = 1.0
## Luz cálida de mediodía y lo fuerte que es el foco encendido del todo.
const LIGHT_COLOR: Color = Color(1.0, 0.93, 0.78)
const LIGHT_ENERGY: float = 6.0
## Lo que tarda en encenderse o apagarse (s): lo mismo que gira la trampilla.
const FADE_TIME: float = 0.7
## Motas de polvo.
const MOTES: int = 48
const MOTE_SIZE: float = 0.018
const MOTE_COLOR: Color = Color(1.0, 0.9, 0.7, 0.55)

var _top: Vector3
var _bottom: Vector3
var _material: ShaderMaterial
var _light: SpotLight3D
var _motes: GPUParticles3D
var _mote_material: StandardMaterial3D
var _strength: float = 0.0
var _tween: Tween = null


## Extremos del haz en el espacio del padre. Se llama ANTES de añadirlo al árbol.
func setup(top: Vector3, bottom: Vector3) -> void:
	_top = top
	_bottom = bottom
	name = "LightShaft"
	var axis: Vector3 = top - bottom
	var length: float = axis.length()
	# El eje Y del nodo va de abajo arriba; el centro, a medio camino.
	var up: Vector3 = axis / length
	var side: Vector3 = up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	transform = Transform3D(Basis(side, up, side.cross(up)), (top + bottom) * 0.5)
	_add_cone(length)
	_add_light(length)
	_add_motes(length)
	_apply(0.0)


## Enciende o apaga el haz; sin `animated`, de golpe (al cargar la partida).
func set_on(on: bool, animated: bool = true) -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	var goal: float = 1.0 if on else 0.0
	if not animated or not is_inside_tree():
		_apply(goal)
		return
	_tween = create_tween()
	_tween.tween_method(_apply, _strength, goal, FADE_TIME).set_trans(Tween.TRANS_SINE)


func _apply(value: float) -> void:
	_strength = value
	visible = value > 0.001
	_material.set_shader_parameter("strength", value)
	_light.light_energy = LIGHT_ENERGY * value
	_mote_material.albedo_color.a = MOTE_COLOR.a * value
	_motes.emitting = value > 0.001


## Cono abierto (sin tapas) con el shader del haz.
func _add_cone(length: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = TOP_RADIUS
	mesh.bottom_radius = BOTTOM_RADIUS
	mesh.height = length
	mesh.radial_segments = 20
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("height", length)
	var cone := MeshInstance3D.new()
	cone.name = "Cone"
	cone.mesh = mesh
	cone.material_override = _material
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cone)


## Foco desde la boca hacia abajo: deja un círculo de luz en el suelo, del ancho del haz.
func _add_light(length: float) -> void:
	_light = SpotLight3D.new()
	_light.name = "Light"
	_light.position = Vector3(0.0, length * 0.5, 0.0)
	_light.rotation = Vector3(-PI * 0.5, 0.0, 0.0)   # el foco mira a su −Z: girado, mira hacia abajo (−Y)
	_light.light_color = LIGHT_COLOR
	_light.spot_range = length + 1.0
	_light.spot_angle = rad_to_deg(atan(BOTTOM_RADIUS * 1.15 / length))
	_light.spot_angle_attenuation = 0.6
	_light.spot_attenuation = 0.2   # casi sin perder fuerza con la distancia: es el sol
	_light.shadow_enabled = false
	add_child(_light)


## Motas de polvo que flotan despacio por la mitad de abajo del haz y se encienden y apagan.
func _add_motes(length: float) -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(BOTTOM_RADIUS * 0.6, length * 0.3, BOTTOM_RADIUS * 0.6)
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = 0.02
	process.initial_velocity_max = 0.08
	process.gravity = Vector3(0.0, -0.015, 0.0)
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.3
	process.turbulence_noise_speed_random = 0.2
	process.turbulence_influence_min = 0.02
	process.turbulence_influence_max = 0.05
	process.scale_min = 0.5
	process.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.25, Color(1, 1, 1, 1))
	fade.add_point(0.75, Color(1, 1, 1, 1))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	_mote_material = StandardMaterial3D.new()
	_mote_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mote_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mote_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mote_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_mote_material.vertex_color_use_as_albedo = true
	_mote_material.albedo_color = MOTE_COLOR
	var quad := QuadMesh.new()
	quad.size = Vector2(MOTE_SIZE, MOTE_SIZE)
	quad.material = _mote_material
	_motes = GPUParticles3D.new()
	_motes.name = "Motes"
	_motes.position = Vector3(0.0, -length * 0.15, 0.0)   # más en la parte de abajo, donde se ven
	_motes.process_material = process
	_motes.draw_pass_1 = quad
	_motes.amount = MOTES
	_motes.lifetime = 9.0
	_motes.preprocess = 9.0   # al encender ya están flotando
	_motes.local_coords = true
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_motes.visibility_aabb = AABB(Vector3(-1.5, -length * 0.5, -1.5), Vector3(3.0, length, 3.0))
	add_child(_motes)
