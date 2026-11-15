class_name DustPuff
extends GPUParticles3D
## Nubecita de polvo de un golpe (B3.7): unas pocas «piedrecitas» facetadas color piedra que salen hacia
## arriba y a los lados, encogen y desaparecen. Se borra sola al terminar. Mismo estilo de juguete que el
## humo del horno (D-082). Uso: `DustPuff.spawn(padre, posición_global)`.

const DUST_COLOR: Color = Color(0.62, 0.57, 0.48)

static var _process: ParticleProcessMaterial = null
static var _mesh: ArrayMesh = null


## Crea una nube en `global_pos`, colgada de `parent` (que debe estar en el árbol).
static func spawn(parent: Node, global_pos: Vector3) -> void:
	var puff := DustPuff.new()
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
		var material := StandardMaterial3D.new()
		material.albedo_color = DUST_COLOR
		material.roughness = 1.0
		material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		_mesh = BuildingView._make_puff_mesh() # la misma bolita facetada que el humo
		_mesh.surface_set_material(0, material)
	process_material = _process
	draw_pass_1 = _mesh
	amount = 5
	lifetime = 0.7
	one_shot = true
	explosiveness = 0.9
	local_coords = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	finished.connect(queue_free)
	emitting = true
