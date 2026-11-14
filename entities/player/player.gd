class_name Player
extends CharacterBody3D
## Jugador de la fase B (D-064): solo primera persona. Andar, saltar, mirar con el ratón e interactuar.
## No guarda el inventario: el del jugador es `WorldState.player_inventory` (D-046).
## Construir llegará en B2.4b como un nodo hijo aparte, igual que en el prototipo.

## Se emite cuando cambia el objeto interactuable al que miramos (null si ya no miramos ninguno).
signal focus_changed(interactable: Interactable)

@export_group("Movimiento")
@export var walk_speed: float = 5.0 ## Velocidad al caminar (m/s).
@export var acceleration: float = 40.0 ## Rapidez para alcanzar la velocidad (m/s²).
@export var jump_velocity: float = 4.5 ## Impulso vertical del salto (m/s).

@export_group("Cámara")
@export var mouse_sensitivity: float = 0.002 ## Radianes girados por cada píxel de ratón.
@export var max_pitch_degrees: float = 89.0 ## Límite para mirar arriba y abajo.

@export_group("Seguridad")
@export var fall_limit_y: float = -10.0 ## Por debajo de esta altura, vuelve al punto de inicio.

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interact_ray: RayCast3D = $Head/InteractRay

## Posición y orientación iniciales, para reaparecer si caemos.
var spawn_transform: Transform3D
## Objeto interactuable que estamos mirando (null si ninguno).
var focused_interactable: Interactable = null


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	interact_ray.add_exception(self) # el rayo no debe tocar nuestra propia cápsula
	add_to_group(&"player")
	spawn_transform = global_transform


func _unhandled_input(event: InputEvent) -> void:
	if Aim.ui_open:
		return

	# Esc libera el ratón; un clic lo vuelve a capturar.
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# E interactúa con lo que miramos.
	if event.is_action_pressed("interact") and focused_interactable != null:
		focused_interactable.interact(self)

	# Mirar con el ratón (solo con el ratón capturado).
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity) # horizontal: gira todo el cuerpo
		head.rotate_x(-motion.relative.y * mouse_sensitivity) # vertical: solo la cabeza
		var max_pitch: float = deg_to_rad(max_pitch_degrees)
		head.rotation.x = clampf(head.rotation.x, -max_pitch, max_pitch)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor() and not Aim.ui_open:
		velocity.y = jump_velocity

	# Dirección según WASD, relativa a hacia dónde mira el cuerpo.
	var input_dir: Vector2 = Vector2.ZERO
	if not Aim.ui_open:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var target_velocity: Vector3 = direction * walk_speed
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)
	move_and_slide()

	if global_position.y < fall_limit_y:
		global_transform = spawn_transform
		velocity = Vector3.ZERO

	_update_focus()


## Avisa (solo cuando cambia) de qué objeto interactuable tenemos delante.
func _update_focus() -> void:
	var new_focus: Interactable = null
	if interact_ray.is_colliding():
		new_focus = interact_ray.get_collider() as Interactable # null si no es Interactable
	if new_focus != focused_interactable:
		focused_interactable = new_focus
		focus_changed.emit(focused_interactable)
