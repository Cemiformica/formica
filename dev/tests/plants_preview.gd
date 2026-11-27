extends Node3D
## Vista previa de las plantas con su shader (C5.6, sesión 31; solo desarrollo). Abre la escena y pulsa F6: cada pieza
## de `plants.glb` sale en un corro de 3 × 3 en un MultiMesh (como irán en la isla), con el material `plants.tres`, y
## Mira pasea entre ellas para ver cómo se apartan. El viento es el del césped.
## Ratón: botón derecho y arrastrar gira la cámara; la rueda acerca y aleja. Espacio: Mira para o sigue.

const PLANTS: String = "res://assets/models/props/plants.glb"
const MATERIAL: String = "res://assets/materials/plants.tres"
const MIRA: String = "res://entities/mira/mira.tscn"
const TARGET: Vector3 = Vector3(9.0, 0.4, -3.0)
## Cada pieza: rigidez (0 = se dobla mucho, 1 = firme), alcance a lo lejos (0 a 1) y separación del corro (m).
## Los mismos valores que usará la isla.
const KINDS: Dictionary[String, Vector3] = {
	"clover_3": Vector3(0.6, 0.0, 0.25), "clover_4": Vector3(0.6, 0.0, 0.25),
	"flowers_0": Vector3(0.35, 0.0, 0.5), "flowers_1": Vector3(0.35, 0.0, 0.5), "flowers_2": Vector3(0.35, 0.0, 0.5),
	"fern_0": Vector3(0.45, 0.3, 1.0), "fern_1": Vector3(0.45, 0.3, 1.2),
	"reeds_0": Vector3(0.05, 0.6, 0.6), "reeds_1": Vector3(0.05, 0.6, 0.6),
	"bush_0": Vector3(0.8, 1.0, 0.9), "bush_1": Vector3(0.8, 1.0, 1.3), "bush_2": Vector3(0.8, 1.0, 1.7),
}
## Recorrido de Mira (ida y vuelta por las dos filas) y su paso (m/s, el de andar).
const PATH: Array[Vector3] = [Vector3(-2.0, 0.0, 0.0), Vector3(21.0, 0.0, 0.0), Vector3(21.0, 0.0, -6.0),
		Vector3(-2.0, 0.0, -6.0)]
const WALK_SPEED: float = 1.6

var _yaw: float = 0.3
var _pitch: float = -0.4
var _distance: float = 14.0
var _camera: Camera3D
var _mira: Node3D
var _walker: Vector3 = PATH[0]
var _next: int = 1
var _walking: bool = true


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
	sun.shadow_enabled = true
	sun.light_color = Color(1.0, 0.95, 0.85)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.65, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.65)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(50.0, 50.0)
	ground.mesh = plane
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.32, 0.5, 0.22)
	ground.material_override = grass
	ground.position = TARGET * Vector3(1.0, 0.0, 1.0)
	add_child(ground)
	_build_patches()
	if ResourceLoader.exists(MIRA):
		_mira = (load(MIRA) as PackedScene).instantiate() as Node3D
		add_child(_mira)
	_camera = Camera3D.new()
	add_child(_camera)
	_place_camera()


## Un corro de 3 × 3 de cada pieza: las de la primera mitad en la fila de delante (z = 0) y el resto en la de atrás
## (z = −6), así Mira pasa por encima de todas.
func _build_patches() -> void:
	var meshes: Dictionary[String, Mesh] = {}
	var scene: Node = (load(PLANTS) as PackedScene).instantiate()
	for node: Node in scene.find_children("*", "MeshInstance3D", true, false):
		meshes[String(node.name).trim_suffix("_mesh")] = (node as MeshInstance3D).mesh
	scene.free()
	var material: Material = load(MATERIAL) as Material
	var random := RandomNumberGenerator.new()
	random.seed = 31
	var names: Array[String] = KINDS.keys()
	var half: int = (names.size() + 1) / 2
	for i: int in names.size():
		var piece: String = names[i]
		if not meshes.has(piece):
			push_warning("plants_preview: falta la pieza %s en plants.glb" % piece)
			continue
		var data: Vector3 = KINDS[piece]
		var center := Vector3(float(i % half) * 3.8, 0.0, 0.0 if i < half else -6.0)
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_custom_data = true
		multi.mesh = meshes[piece]
		multi.instance_count = 9
		for k: int in 9:
			var at: Vector3 = center + Vector3(float(k % 3 - 1), 0.0, float(k / 3 - 1)) * data.z \
					+ Vector3(random.randf_range(-0.15, 0.15), 0.0, random.randf_range(-0.15, 0.15)) * data.z
			var turn := Basis(Vector3.UP, random.randf() * TAU).scaled(Vector3.ONE * random.randf_range(0.85, 1.15))
			multi.set_instance_transform(k, Transform3D(turn, at))
			multi.set_instance_custom_data(k, Color(random.randf(), data.x, data.y, 0.0))
		var instance := MultiMeshInstance3D.new()
		instance.name = "Plants_" + piece
		instance.multimesh = multi
		instance.material_override = material
		add_child(instance)
		var label := Label3D.new()
		label.text = piece
		label.font_size = 48
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = center + Vector3(0.0, 0.2, 1.1 * data.z + 0.6)   # delante del corro, casi en el suelo
		add_child(label)


func _process(delta: float) -> void:
	if _walking:
		var goal: Vector3 = PATH[_next]
		var to_goal: Vector3 = goal - _walker
		var step: float = WALK_SPEED * delta
		if to_goal.length() <= step:
			_walker = goal
			_next = (_next + 1) % PATH.size()
		else:
			_walker += to_goal.normalized() * step
	if _mira != null:
		var heading: Vector3 = PATH[_next] - _walker
		_mira.position = _walker
		if heading.length() > 0.01:
			_mira.rotation.y = atan2(heading.x, heading.z)
	# Lo mismo que hace player.gd en el juego: las plantas y el césped se apartan de aquí.
	RenderingServer.global_shader_parameter_set(&"player_position", _walker)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_yaw -= motion.relative.x * 0.008
		_pitch = clampf(_pitch - motion.relative.y * 0.006, -1.4, -0.05)
		_place_camera()
	elif event is InputEventMouseButton and event.pressed:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(2.0, _distance * 0.9)
			_place_camera()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(40.0, _distance * 1.1)
			_place_camera()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_SPACE:
		_walking = not _walking


func _place_camera() -> void:
	var offset := Vector3(0.0, 0.0, _distance).rotated(Vector3.RIGHT, _pitch).rotated(Vector3.UP, _yaw)
	_camera.look_at_from_position(TARGET + offset, TARGET)
