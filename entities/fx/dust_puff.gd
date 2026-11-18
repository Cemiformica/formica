class_name DustPuff
extends GPUParticles3D
## Nubecita de polvo de un golpe (B3.7): unas pocas «piedrecitas» facetadas color piedra que salen hacia
## arriba y a los lados, encogen y desaparecen. Se borra sola al terminar. Mismo estilo de juguete que el
## humo del horno (D-082). Uso: `DustPuff.spawn(padre, posición_global)`, o con un color propio
## (`DustPuff.spawn(padre, posición, color)`: virutas de madera del talador). Con `soft`, más pequeña,
## con menos piedrecitas y medio transparente: la que sale seguida mientras trabaja una herramienta (C3).

const DUST_COLOR: Color = Color(0.62, 0.57, 0.48)

static var _process: ParticleProcessMaterial = null
static var _soft_process: ParticleProcessMaterial = null   # igual, con piedrecitas más pequeñas
## Una bolita (con su material) por color, compartida por todas las nubes de ese color (las suaves, aparte).
static var _meshes: Dictionary[Color, ArrayMesh] = {}
static var _soft_meshes: Dictionary[Color, ArrayMesh] = {}
const SOFT_ALPHA: float = 0.45

var _color: Color = DUST_COLOR
var _soft: bool = false


## Crea una nube en `global_pos`, colgada de `parent` (que debe estar en el árbol).
static func spawn(parent: Node, global_pos: Vector3, color: Color = DUST_COLOR, soft: bool = false) -> void:
	var puff := DustPuff.new()
	puff._color = color
	puff._soft = soft
	parent.add_child(puff)
	puff.global_position = global_pos


func _ready() -> void:
	if _process == null:
		_process = ParticleProcessMaterial.new()
		_process.direction = Vector3.UP
		_process.spread = 60.0
		_process.initial_velocity_min = 0.6
		_process.initial_velocity_max = 1.1
		_process.gravity = Vector3(0.0, -1.5, 0.0)
		_process.scale_min = 0.5
		_process.scale_max = 0.9
		_process.angle_min = 0.0
		_process.angle_max = 360.0
		_process.particle_flag_rotate_y = true
		var shrink := Curve.new()
		shrink.add_point(Vector2(0.0, 1.0))
		shrink.add_point(Vector2(1.0, 0.0))
		var shrink_texture := CurveTexture.new()
		shrink_texture.curve = shrink
		_process.scale_curve = shrink_texture
	var cache: Dictionary[Color, ArrayMesh] = _soft_meshes if _soft else _meshes
	if not cache.has(_color):
		var material := StandardMaterial3D.new()
		material.albedo_color = _color
		material.roughness = 1.0
		material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		if _soft:
			material.albedo_color.a = SOFT_ALPHA
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var mesh: ArrayMesh = BuildingView._make_puff_mesh() # la misma bolita facetada que el humo
		mesh.surface_set_material(0, material)
		cache[_color] = mesh
	if _soft_process == null:
		_soft_process = _process.duplicate() as ParticleProcessMaterial
		_soft_process.scale_min = 0.3
		_soft_process.scale_max = 0.55
		_soft_process.initial_velocity_min = 0.4
		_soft_process.initial_velocity_max = 0.8
	process_material = _soft_process if _soft else _process
	draw_pass_1 = cache[_color]
	amount = 3 if _soft else 5
	lifetime = 0.7
	one_shot = true
	explosiveness = 0.9
	local_coords = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	finished.connect(queue_free)
	emitting = true
