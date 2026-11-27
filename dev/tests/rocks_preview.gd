extends Node3D
## Vista previa de las rocas nuevas (C5.6, sesión 30; solo desarrollo). Abre la escena y pulsa F6: enseña las 11 piezas
## de `rocks.glb` como están en `rocks.blend` (guijarros delante, medianas en medio, peñascos detrás) sobre un suelo de
## hierba, con Mira al lado para ver el tamaño. Sirve para comprobar que la roca lleva el shader de los acantilados.
## Ratón: botón derecho y arrastrar gira la cámara alrededor; la rueda acerca y aleja.

const ROCKS: String = "res://assets/models/props/rocks.glb"
const MIRA: String = "res://entities/mira/mira.tscn"
const TARGET: Vector3 = Vector3(7.5, 0.6, -5.0)

var _yaw: float = 0.0
var _pitch: float = -0.45
var _distance: float = 16.0
var _camera: Camera3D


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
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
	plane.size = Vector2(40.0, 40.0)
	ground.mesh = plane
	var grass := StandardMaterial3D.new()
	grass.albedo_color = Color(0.3, 0.45, 0.2)
	ground.material_override = grass
	ground.position = TARGET * Vector3(1.0, 0.0, 1.0)
	add_child(ground)
	var rocks: Node3D = (load(ROCKS) as PackedScene).instantiate() as Node3D
	add_child(rocks)
	if ResourceLoader.exists(MIRA):
		var mira: Node3D = (load(MIRA) as PackedScene).instantiate() as Node3D
		mira.position = Vector3(2.5, 0.0, -2.2)
		add_child(mira)
	_camera = Camera3D.new()
	add_child(_camera)
	_place_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_yaw -= motion.relative.x * 0.008
		_pitch = clampf(_pitch - motion.relative.y * 0.006, -1.4, -0.05)
		_place_camera()
	elif event is InputEventMouseButton and event.pressed:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(3.0, _distance * 0.9)
			_place_camera()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(40.0, _distance * 1.1)
			_place_camera()


func _place_camera() -> void:
	var offset := Vector3(0.0, 0.0, _distance).rotated(Vector3.RIGHT, _pitch).rotated(Vector3.UP, _yaw)
	_camera.look_at_from_position(TARGET + offset, TARGET)
