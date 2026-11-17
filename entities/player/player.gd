class_name Player
extends CharacterBody3D
## Jugador de la fase B (D-064): solo primera persona. Andar, saltar, mirar con el ratón e interactuar.
## No guarda el inventario: el del jugador es `WorldState.player_inventory` (D-046).
## Construir lo hace su hijo `BuildController` (B2.4b).
## El cuerpo es Mira (B4.6), girada 180° porque su frente es +Z y el del jugador −Z. En primera persona está
## oculta del todo, también su sombra: una sombra sin cuerpo despista (César). Con la tercera persona se
## volverá a ver; y en la fase C se valorará el cuerpo visible en primera persona (mira.set_shadow_only).

## Se emite cuando cambia el objeto interactuable al que miramos (null si ya no miramos ninguno).
signal focus_changed(interactable: Interactable)
## Se emite al pulsar E sobre una construcción: la interfaz abre su ventana (C1.3).
signal building_opened(view: BuildingView)

@export_group("Movimiento")
@export var walk_speed: float = 5.0 ## Velocidad al caminar (m/s).
@export var acceleration: float = 40.0 ## Rapidez para alcanzar la velocidad (m/s²).
@export var jump_velocity: float = 6.3 ## Impulso vertical del salto (m/s). Con gravedad ×2 da ~1 m de altura.
@export var gravity_multiplier: float = 2.0 ## Gravedad del personaje respecto a la del mundo: ×2 = salto más firme, menos flotante.
@export var step_height: float = 0.3 ## Bordes que sube solo al caminar, sin saltar (cintas, losas bajas) (B3.7).

@export_group("Cámara")
@export var mouse_sensitivity: float = 0.002 ## Radianes girados por cada píxel de ratón.
@export var max_pitch_degrees: float = 89.0 ## Límite para mirar arriba y abajo.

@export_group("Seguridad")
@export var fall_limit_y: float = -10.0 ## Por debajo de esta altura, vuelve al punto de inicio.

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interact_ray: RayCast3D = $Head/InteractRay
@onready var build_controller: BuildController = $BuildController
@onready var mira: Mira = $Mira

## Posición y orientación iniciales, para reaparecer si caemos.
var spawn_transform: Transform3D
## Objeto interactuable que estamos mirando (null si ninguno).
var focused_interactable: Interactable = null
## Casilla de la barra elegida (C1.6): lo que hay en ella es lo que Mira lleva en la mano.
var held_slot: int = 0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	interact_ray.add_exception(self) # el rayo no debe tocar nuestra propia cápsula
	add_to_group(&"player")
	spawn_transform = global_transform
	# Interpolación de la física (B3): la cámara va suelta y se coloca en cada fotograma (ver _process).
	camera.top_level = true
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Primera persona: Mira oculta (sin sombra). Sigue animándose por dentro, lista para la tercera persona.
	mira.visible = false
	WorldState.player_inventory.changed.connect(_update_held_item)


func _unhandled_input(event: InputEvent) -> void:
	if WindowManager.is_open():
		return

	# Esc libera el ratón; un clic lo vuelve a capturar.
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# E interactúa con lo que miramos, salvo en el modo construcción: construir es un modo aparte (C1.6, César).
	if event.is_action_pressed("interact") and is_instance_valid(focused_interactable) and not build_controller.active:
		focused_interactable.interact(self)

	# Mirar con el ratón (solo con el ratón capturado).
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity) # horizontal: gira todo el cuerpo
		head.rotate_x(-motion.relative.y * mouse_sensitivity) # vertical: solo la cabeza
		var max_pitch: float = deg_to_rad(max_pitch_degrees)
		head.rotation.x = clampf(head.rotation.x, -max_pitch, max_pitch)


## Cámara en cada fotograma: en la posición suavizada de la cabeza (interpolación de la física) y con su
## giro actual, sin esperar al siguiente paso de física, para que el ratón responda al instante.
func _process(_delta: float) -> void:
	camera.global_transform = Transform3D(head.global_transform.basis, head.get_global_transform_interpolated().origin)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * gravity_multiplier * delta

	if Input.is_action_just_pressed("jump") and is_on_floor() and not WindowManager.is_open():
		velocity.y = jump_velocity

	# Dirección según WASD, relativa a hacia dónde mira el cuerpo.
	var input_dir: Vector2 = Vector2.ZERO
	if not WindowManager.is_open():
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var target_velocity: Vector3 = direction * walk_speed
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)
	_step_up(delta)
	move_and_slide()

	if global_position.y < fall_limit_y:
		global_transform = spawn_transform
		velocity = Vector3.ZERO
		reset_physics_interpolation() # salto instantáneo: sin «volar» desde donde caía

	_update_focus()


## Elige la casilla de la barra (C1.6; lo llama la barra de abajo). Mira lleva en la mano lo que haya en ella.
func set_held_slot(index: int) -> void:
	held_slot = index
	_update_held_item()


## Pone en la mano de Mira lo de la casilla elegida (o nada). Se repite cuando cambia el inventario.
func _update_held_item() -> void:
	var stack: ItemStack = WorldState.player_inventory.slots[held_slot]
	var item: ItemData = stack.item if stack != null else null
	if mira.held_item != item:
		mira.hold_item(item)


## Lo llama una construcción al pulsar E sobre ella (C1.3).
func open_building(view: BuildingView) -> void:
	building_opened.emit(view)


## Anota en `WorldState` dónde está el jugador, justo antes de guardar la partida (B5.2).
func store_to_world() -> void:
	WorldState.current_island = build_controller.island_id
	WorldState.player_position = global_position
	WorldState.player_rotation_y = rotation.y


## Coloca al jugador donde dice `WorldState`, justo después de cargar una partida (B5.2).
func restore_from_world() -> void:
	global_position = WorldState.player_position
	rotation.y = WorldState.player_rotation_y
	velocity = Vector3.ZERO
	reset_physics_interpolation() # salto instantáneo: sin «volar» desde donde estaba


## Escalón automático (B3.7, César): si al andar chocamos con un borde de hasta `step_height` (una cinta,
## una losa) y por encima hay sitio, subimos de golpe esa altura y la gravedad nos posa encima. La
## interpolación de la física suaviza la subida en pantalla. Paredes más altas no se suben.
func _step_up(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if not is_on_floor() or horizontal.length_squared() < 0.01:
		return
	var motion: Vector3 = horizontal * delta
	if not test_move(global_transform, motion):
		return # nada delante
	var up: Vector3 = Vector3.UP * step_height
	if test_move(global_transform, up):
		return # no hay sitio encima (techo)
	if test_move(global_transform.translated(up), motion):
		return # también choca más arriba: es una pared, no un escalón
	global_position += up


## Avisa (solo cuando cambia) de qué objeto interactuable tenemos delante.
func _update_focus() -> void:
	# Si lo que mirábamos ha desaparecido (p. ej., un tocón arrancado), lo soltamos.
	if focused_interactable != null and not is_instance_valid(focused_interactable):
		focused_interactable = null
		focus_changed.emit(null)
	var new_focus: Interactable = null
	if interact_ray.is_colliding():
		new_focus = interact_ray.get_collider() as Interactable # null si no es Interactable
	if new_focus != focused_interactable:
		if is_instance_valid(focused_interactable):
			focused_interactable.set_focused(false)
		focused_interactable = new_focus
		if focused_interactable != null:
			focused_interactable.set_focused(true)
		focus_changed.emit(focused_interactable)
