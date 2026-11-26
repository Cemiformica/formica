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

## Parámetro global del shader del césped (Project Settings → Shader Globals, C5.6): la hierba se aparta de Mira.
const GRASS_PLAYER_PARAM: StringName = &"player_position"

@export_group("Movimiento")
@export var walk_speed: float = 4.5 ## Velocidad al caminar (m/s; César: 5 se sentía rápido).
@export var sprint_speed: float = 7.0 ## Velocidad al correr con Mayús (m/s; César: 8,5 se sentía rápido).
@export var crouch_speed: float = 2.5 ## Velocidad agachada, con Ctrl (m/s).
@export var acceleration: float = 40.0 ## Rapidez para alcanzar la velocidad (m/s²).
@export var jump_velocity: float = 6.3 ## Impulso vertical del salto (m/s). Con gravedad ×2 al subir da ~1 m de altura.
@export var gravity_multiplier: float = 2.0 ## Gravedad al subir respecto a la del mundo: ×2 = salto más firme, menos flotante.
@export var fall_gravity_multiplier: float = 3.2 ## Gravedad al caer (César: caía lento): baja antes y cada vez más deprisa.
@export var max_fall_speed: float = 30.0 ## Velocidad máxima de caída (m/s).
@export var jump_cut: float = 0.5 ## Al soltar el salto mientras sube, se queda con esta parte de la velocidad: salto corto.
@export var coyote_time: float = 0.1 ## Segundos tras salir de un borde en los que aún se puede saltar.
@export var jump_buffer_time: float = 0.12 ## Segundos que se recuerda el salto pulsado justo antes de tocar el suelo.
@export var step_height: float = 0.3 ## Bordes que sube solo al caminar, sin saltar (cintas, losas bajas) (B3.7).
@export var climb_speed: float = 1.6 ## Velocidad por una escala (m/s a lo largo de ella; C5.6b).
@export var climb_top_entry: float = 0.8 ## Al agarrarse arriba, se empieza esto por debajo del final (m; César: si no, salía).
@export var climb_turn_time: float = 0.25 ## Al agarrarse, lo que tarda en girarse hacia la escala (s; César).
@export var climb_exit_time: float = 0.45 ## Lo que tarda en subir al borde al salir por arriba (s; César: daba un salto).

@export_group("Cámara")
@export var mouse_sensitivity: float = 0.002 ## Radianes girados por cada píxel de ratón.
@export var max_pitch_degrees: float = 89.0 ## Límite para mirar arriba y abajo.
@export var crouch_head_drop: float = 0.5 ## Lo que baja la cabeza al agacharse (m).
@export var sprint_fov_boost: float = 8.0 ## Grados que se abre el campo de visión al correr.
@export var landing_dip_max: float = 0.18 ## Lo que baja la cámara, como mucho, al aterrizar de una caída alta (m).
@export var landing_dust_speed: float = 7.0 ## Velocidad de caída (m/s) desde la que sale polvo al aterrizar.

@export_group("Herramientas")
@export var tool_reach: float = 2.5 ## Alcance para talar y picar con una herramienta (m); la E sigue llegando a 3 m (C3).

@export_group("Seguridad")
@export var fall_limit_y: float = -10.0 ## Por debajo de esta altura, reaparece (en la cama, si la hay).

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interact_ray: RayCast3D = $Head/InteractRay
@onready var build_controller: BuildController = $BuildController
@onready var mira: Mira = $Mira
@onready var arm: FirstPersonArm = $Head/Camera3D/FirstPersonArm   # lo que lleva en la mano, en primera persona

## Posición y orientación iniciales, para reaparecer si caemos.
var spawn_transform: Transform3D
## Objeto interactuable que estamos mirando (null si ninguno).
var focused_interactable: Interactable = null
## Casilla de la barra elegida (C1.6): lo que hay en ella es lo que Mira lleva en la mano.
var held_slot: int = 0
## Plantar semillas con el clic izquierdo, con la semilla en la mano (C1.9).
var planter: PlantController
## Modo desmontar con X (C2.2).
var dismantler: DismantleController
## Pisadas (sesión 28): pasos según lo que se pisa, golpe al aterrizar y crujido de cuerda al trepar.
var footsteps: Footsteps
## El clic izquierdo de trabajar (talar, picar…) empezó con el ratón ya capturado. Así, el clic que solo
## recaptura el ratón no da un golpe.
var _using: bool = false
## Movimiento (sesión 25, D-190): tiempo desde que dejó el suelo, salto pulsado que espera al suelo, si se agacha y
## cuánto (0–1, suavizado), si corre, la velocidad de caída del paso anterior y lo que baja la cámara al aterrizar.
var _air_time: float = 0.0
var _jump_buffer: float = 0.0
var _crouching: bool = false
var _crouch_t: float = 0.0
var _sprinting: bool = false
var _last_fall_speed: float = 0.0
var _landing_dip: float = 0.0
var _head_height: float = 1.6
var _base_fov: float = 75.0
## Escala (C5.6b): por dónde se sube (puntos del mundo a la altura de los pies, de abajo arriba; vacío = no se está en
## ninguna), dónde se sale arriba, cuánto mide y por dónde se va.
var _climb_path: PackedVector3Array = PackedVector3Array()
var _climb_exit: Vector3 = Vector3.ZERO
var _climb_length: float = 0.0
var _climb_s: float = 0.0
## Al agarrarse, hacia dónde se gira (hacia la escala) y cuánto le queda de giro; al salir por arriba, de dónde a dónde
## sube al borde y cuánto lleva (0–1; -1 = no está saliendo).
var _climb_yaw: float = 0.0
var _climb_turn: float = 0.0
var _exit_from: Vector3 = Vector3.ZERO
var _exit_to: Vector3 = Vector3.ZERO
var _exit_t: float = -1.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	interact_ray.add_exception(self) # el rayo no debe tocar nuestra propia cápsula
	# Zonas de trabajo (capa 4): la losa de las vetas, para picar en cualquiera de sus 9 casillas (C3).
	interact_ray.collide_with_areas = true
	interact_ray.collision_mask |= VeinView.WORK_AREA_LAYER
	add_to_group(&"player")
	# Pegada al suelo al bajar una pendiente (sin esto, bota ladera abajo, C5.3d).
	floor_snap_length = maxf(floor_snap_length, step_height)
	spawn_transform = global_transform
	# Interpolación de la física (B3): la cámara va suelta y se coloca en cada fotograma (ver _process).
	camera.top_level = true
	_head_height = head.position.y
	_base_fov = camera.fov
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Primera persona: Mira oculta (sin sombra). Sigue animándose por dentro, lista para la tercera persona.
	mira.visible = false
	WorldState.player_inventory.changed.connect(_update_held_item)
	WorldState.player_inventory.changed.connect(_update_backpack)
	_update_backpack()
	planter = PlantController.new()
	planter.player = self
	add_child(planter)
	dismantler = DismantleController.new()
	dismantler.player = self
	add_child(dismantler)
	footsteps = Footsteps.new()
	footsteps.player = self
	add_child(footsteps)
	# El plano da un golpecito al colocar o desmontar algo (D-223).
	build_controller.placed.connect(func(_building: PlacedBuilding) -> void: arm.plan_tap())
	dismantler.dismantled.connect(arm.plan_tap)


func _unhandled_input(event: InputEvent) -> void:
	if WindowManager.is_open():
		return

	# Si el ratón estaba suelto, este clic solo lo recaptura: no debe dar un golpe (se mira antes de recapturar).
	var pointer_was_ready: bool = Aim.pointer_ready()
	# Esc libera el ratón; un clic lo vuelve a capturar.
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# En una escala, E suelta (C5.6b, opción B de César): no interactúa con nada más.
	if is_climbing() and event.is_action_pressed("interact"):
		stop_climb()
		return
	# E interactúa con lo que miramos, salvo en el modo construcción: construir es un modo aparte (C1.6, César).
	if event.is_action_pressed("interact") and is_instance_valid(focused_interactable) and not in_tool_mode():
		focused_interactable.interact(self)
	# Clic izquierdo: usar lo que se lleva en la mano (César). Con una semilla, plantar (C1.9); si no,
	# trabajar lo que miramos (C1.8), y mantenerlo sigue golpeando (ver `_physics_process`).
	if event.is_action_pressed("use_tool"):
		var ready_to_use: bool = pointer_was_ready and not in_tool_mode()
		if ready_to_use and planter.held_seed() != null:
			planter.try_plant()
			_using = false
		else:
			_using = ready_to_use
	elif event.is_action_released("use_tool"):
		_using = false

	# Mirar con el ratón (solo con el ratón capturado).
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity) # horizontal: gira todo el cuerpo
		head.rotate_x(-motion.relative.y * mouse_sensitivity) # vertical: solo la cabeza
		var max_pitch: float = deg_to_rad(max_pitch_degrees)
		head.rotation.x = clampf(head.rotation.x, -max_pitch, max_pitch)


## Cámara en cada fotograma: en la posición suavizada de la cabeza (interpolación de la física) y con su
## giro actual, sin esperar al siguiente paso de física, para que el ratón responda al instante.
## Encima, lo del movimiento (sesión 25): la cámara baja un poco al aterrizar y vuelve, y el campo de visión se
## abre al correr.
func _process(delta: float) -> void:
	_landing_dip = move_toward(_landing_dip, 0.0, landing_dip_max * 3.0 * delta)
	var origin: Vector3 = head.get_global_transform_interpolated().origin - Vector3.UP * _landing_dip
	camera.global_transform = Transform3D(head.global_transform.basis, origin)
	var moving: bool = Vector2(velocity.x, velocity.z).length() > walk_speed + 0.5
	var target_fov: float = _base_fov + (sprint_fov_boost if _sprinting and moving else 0.0)
	camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-8.0 * delta))
	# Césped (C5.6): los pies de Mira, con la posición suavizada para que la hierba no dé tirones.
	RenderingServer.global_shader_parameter_set(GRASS_PLAYER_PARAM, get_global_transform_interpolated().origin)


func _physics_process(delta: float) -> void:
	if _exit_t >= 0.0:
		_exit_step(delta)
		_update_focus()
		return
	if is_climbing():
		var climbed_from: float = _climb_s
		_climb_step(delta)
		footsteps.climb(absf(_climb_s - climbed_from))
		_update_focus()
		return
	var playing: bool = not WindowManager.is_open()
	# Gravedad (sesión 25, César: caía lento): normal al subir, más fuerte al caer, con un tope.
	if is_on_floor():
		_air_time = 0.0
	else:
		_air_time += delta
		var falling: bool = velocity.y < 0.0
		velocity += get_gravity() * (fall_gravity_multiplier if falling else gravity_multiplier) * delta
		velocity.y = maxf(velocity.y, -max_fall_speed)

	# Salto con margen: vale pulsarlo un poco antes de tocar el suelo (se recuerda) y un poco después de salir de
	# un borde. Soltarlo mientras sube lo corta: salto corto o largo según lo que se mantenga. Con la tecla
	# mantenida, vuelve a saltar cada vez que toca el suelo (César, sesión 28).
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	if playing and (Input.is_action_just_pressed("jump") or (Input.is_action_pressed("jump") and is_on_floor())):
		_jump_buffer = jump_buffer_time
	if _jump_buffer > 0.0 and _air_time <= coyote_time and velocity.y <= 0.5:
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_air_time = coyote_time + 1.0   # el margen ya se ha usado: no se encadena otro salto en el aire
		_crouching = false
	if Input.is_action_just_released("jump") and velocity.y > 0.0:
		velocity.y *= jump_cut

	# Correr (Mayús) y agacharse (Ctrl). En construir y desmontar, Ctrl + rueda cambia de barra y Mayús elige un
	# recuadro: ahí no se agacha, y en desmontar no corre.
	_sprinting = playing and Input.is_action_pressed("sprint") and not (dismantler != null and dismantler.active)
	_crouching = playing and Input.is_action_pressed("crouch") and not in_tool_mode() and is_on_floor()
	if _crouching:
		_sprinting = false
	_crouch_t = move_toward(_crouch_t, 1.0 if _crouching else 0.0, 6.0 * delta)
	head.position.y = _head_height - crouch_head_drop * smoothstep(0.0, 1.0, _crouch_t)

	# Dirección según WASD, relativa a hacia dónde mira el cuerpo.
	var input_dir: Vector2 = Vector2.ZERO
	if not WindowManager.is_open():
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed: float = crouch_speed if _crouching else (sprint_speed if _sprinting else walk_speed)
	var target_velocity: Vector3 = direction * speed
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)
	_step_up(delta)
	var was_on_floor: bool = is_on_floor()
	_last_fall_speed = -velocity.y
	move_and_slide()
	if not was_on_floor and is_on_floor():
		_land(_last_fall_speed)
		footsteps.land(_last_fall_speed)
	footsteps.walk(delta, is_on_floor(), Vector2(velocity.x, velocity.z).length(), _sprinting, _crouching)

	if global_position.y < fall_limit_y:
		respawn()
		velocity = Vector3.ZERO
		reset_physics_interpolation() # salto instantáneo: sin «volar» desde donde caía

	_update_focus()
	if _using and (WindowManager.is_open() or in_tool_mode()):
		_using = false
	if _using and is_instance_valid(focused_interactable):
		# Con una herramienta, talar y picar piden acercarse un poco (tool_reach) (C3).
		var workable: bool = focused_interactable.get_required_tool() != &""
		if can_use_on(focused_interactable) and not (workable and work_distance() > tool_reach):
			focused_interactable.use(self)
	# En el modo construcción o desmontar, Mira saca el plano en lugar de lo que lleva (D-223, César).
	if dismantler != null and dismantler.active:
		arm.plan_mode = FirstPersonArm.PlanMode.DISMANTLE
	elif build_controller.active:
		arm.plan_mode = FirstPersonArm.PlanMode.BUILD
	else:
		arm.plan_mode = FirstPersonArm.PlanMode.NONE
	# La herramienta se enciende con el clic aunque no haya nada delante; solo da materiales si trabaja algo
	# (César).
	arm.set_working(_using and holding_tool())


## Al tocar el suelo tras caer a `fall_speed` m/s (sesión 25): la cámara baja un poco, más cuanto más fuerte la
## caída, y en las caídas altas sale una nubecita de polvo a los pies.
func _land(fall_speed: float) -> void:
	if fall_speed <= 4.0:
		return
	_landing_dip = maxf(_landing_dip, landing_dip_max * clampf((fall_speed - 4.0) / 12.0, 0.15, 1.0))
	if fall_speed >= landing_dust_speed and get_parent() != null:
		DustPuff.spawn(get_parent(), global_position + Vector3.UP * 0.05)


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
	if arm.held_item != item:
		arm.hold_item(item)


## ¿Lleva Mira una herramienta en la mano (algo que se coge en puño, C3)?
func holding_tool() -> bool:
	return mira.held_item != null and mira.held_item.held_grip == ItemData.HeldGrip.FIST


## Id de la herramienta que lleva en la mano (vacío si no lleva ninguna).
func held_tool_id() -> StringName:
	return mira.held_item.id if holding_tool() else &""


## ¿Puede hacer el clic izquierdo sobre `target`? Si pide una herramienta, tiene que llevar esa (C3).
func can_use_on(target: Interactable) -> bool:
	var required: StringName = target.get_required_tool()
	return required == &"" or required == held_tool_id()


## Punto del mundo donde está trabajando (donde toca la mira); si no toca nada, delante de la cámara.
func work_point() -> Vector3:
	if interact_ray.is_colliding():
		return interact_ray.get_collision_point()
	return interact_ray.to_global(interact_ray.target_position)


## Distancia de los ojos a lo que miramos (m).
func work_distance() -> float:
	return interact_ray.global_position.distance_to(work_point())


## La mochila de Mira enseña un módulo por cada 10 casillas que haya después de la barra (C3).
func _update_backpack() -> void:
	var slots: int = WorldState.player_inventory.get_slot_count() - WorldState.HOTBAR_SLOTS
	@warning_ignore("integer_division")
	mira.set_backpack_modules(slots / WorldState.BACKPACK_MODULE_SLOTS)


## ¿Estamos construyendo o desmontando? En esos modos el clic y la E son del modo, no de la mano.
func in_tool_mode() -> bool:
	return build_controller.active or (dismantler != null and dismantler.active)


## Lo llama una construcción al pulsar E sobre ella (C1.3).
func open_building(view: BuildingView) -> void:
	building_opened.emit(view)


## Anota en `WorldState` dónde está el jugador, justo antes de guardar la partida (B5.2).
func store_to_world() -> void:
	build_controller.cancel_carry() # nunca se guarda una construcción a medio mover (C2.5)
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
## interpolación de la física suaviza la subida en pantalla. Paredes más altas no se suben, y las pendientes que
## se pueden andar tampoco cuentan como escalón (C5.3d).
func _step_up(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if not is_on_floor() or horizontal.length_squared() < 0.01:
		return
	var motion: Vector3 = horizontal * delta
	var hit := KinematicCollision3D.new()
	if not test_move(global_transform, motion, hit):
		return # nada delante
	# Una pendiente que se puede andar (la ladera de Isla Alba, C5.3d) no es un escalón: si no, sube a saltitos.
	if hit.get_normal().angle_to(Vector3.UP) <= floor_max_angle:
		return
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
		var collider: Object = interact_ray.get_collider()
		new_focus = collider as Interactable # null si no es Interactable
		if new_focus == null and collider is Area3D:   # zona de trabajo: cuenta como su dueño
			new_focus = (collider as Node).get_parent() as Interactable
	if new_focus != focused_interactable:
		if is_instance_valid(focused_interactable):
			focused_interactable.set_focused(false)
		focused_interactable = new_focus
		if focused_interactable != null:
			focused_interactable.set_focused(true)
		focus_changed.emit(focused_interactable)


## Agarrarse a una escala (C5.6b, D-187; opción B de César: E se agarra y E se suelta). Se sube con W y se baja con S
## por `path` (puntos del mundo a la altura de los pies, de abajo arriba), sin gravedad y mirando a donde se quiera.
## Arriba se sale a `top_exit`; abajo, al llegar al suelo, se suelta sola. Empieza en el punto más cercano.
func start_climb(path: PackedVector3Array, top_exit: Vector3) -> void:
	if path.size() < 2:
		return
	_climb_path = path
	_climb_exit = top_exit
	footsteps.start_climb()
	_climb_length = 0.0
	for i: int in path.size() - 1:
		_climb_length += path[i].distance_to(path[i + 1])
	# Agarrándose desde arriba, el punto más cercano es el final: se empieza un poco más abajo (César: te volvía a sacar).
	_climb_s = minf(_closest_on_climb(global_position), maxf(0.0, _climb_length - climb_top_entry))
	# Mirando a la escala (César: que no se baje de espaldas; así W siempre sube y S siempre baja): la escala sube hacia
	# la pared, así que su primer punto y el último dicen hacia dónde queda.
	var facing: Vector3 = path[path.size() - 1] - path[0]
	facing.y = 0.0
	_climb_yaw = atan2(-facing.x, -facing.z) if facing.length_squared() > 0.0001 else rotation.y
	_climb_turn = climb_turn_time
	velocity = Vector3.ZERO
	_crouching = false
	_sprinting = false
	global_position = _climb_point(_climb_s)


## Suelta la escala (con E, al salir por arriba o al llegar abajo). Si es en el aire, cae.
func stop_climb() -> void:
	_climb_path = PackedVector3Array()
	velocity = Vector3.ZERO


func is_climbing() -> bool:
	return not _climb_path.is_empty()


## Un paso en la escala: W sube y S baja a `climb_speed`. Al principio, se gira hacia la escala.
func _climb_step(delta: float) -> void:
	if _climb_turn > 0.0:
		_climb_turn -= delta
		rotation.y = _climb_yaw if _climb_turn <= 0.0 else lerp_angle(rotation.y, _climb_yaw, 1.0 - exp(-14.0 * delta))
	var climb_input: float = 0.0
	if not WindowManager.is_open():
		climb_input = Input.get_axis("move_back", "move_forward")
	_climb_s += climb_input * climb_speed * delta
	if _climb_s >= _climb_length and climb_input > 0.0:
		# Arriba, solo subiendo: sube al borde, pasadas las estacas (sin saltar de golpe, César).
		_exit_from = global_position
		_exit_to = _climb_exit
		_exit_t = 0.0
		stop_climb()
		return
	_climb_s = minf(_climb_s, _climb_length)
	if _climb_s <= 0.0 and climb_input < 0.0:
		global_position = _climb_point(0.0)   # abajo: ya en el suelo
		stop_climb()
		return
	_climb_s = maxf(_climb_s, 0.0)
	global_position = _climb_point(_climb_s)


## Subir al borde al salir por arriba: primero sube y luego avanza, con un pequeño arco, en `climb_exit_time`.
func _exit_step(delta: float) -> void:
	_exit_t = minf(_exit_t + delta / climb_exit_time, 1.0)
	var spot: Vector3 = _exit_from.lerp(_exit_to, smoothstep(0.0, 1.0, _exit_t))
	spot.y = lerpf(_exit_from.y, _exit_to.y, sqrt(_exit_t)) + sin(PI * _exit_t) * 0.25
	global_position = spot
	if _exit_t >= 1.0:
		_exit_t = -1.0
		velocity = Vector3.ZERO


## El punto de la escala a `along` metros de su principio.
func _climb_point(along: float) -> Vector3:
	var walked: float = 0.0
	for i: int in _climb_path.size() - 1:
		var length: float = _climb_path[i].distance_to(_climb_path[i + 1])
		if along <= walked + length and length > 0.0:
			return _climb_path[i].lerp(_climb_path[i + 1], (along - walked) / length)
		walked += length
	return _climb_path[_climb_path.size() - 1]


## Cuántos metros de escala hay hasta su punto más cercano a `point`.
func _closest_on_climb(point: Vector3) -> float:
	var best_along: float = 0.0
	var best_distance: float = INF
	var walked: float = 0.0
	for i: int in _climb_path.size() - 1:
		var a: Vector3 = _climb_path[i]
		var b: Vector3 = _climb_path[i + 1]
		var length: float = a.distance_to(b)
		var t: float = clampf((point - a).dot(b - a) / maxf(length * length, 0.0001), 0.0, 1.0)
		var distance: float = point.distance_to(a.lerp(b, t))
		if distance < best_distance:
			best_distance = distance
			best_along = walked + t * length
		walked += length
	return best_along


## Vuelve al punto de reaparición: la cama del refugio si se ha descansado en ella en esta isla (C4) o, si
## no, el sitio donde empezó la escena.
func respawn() -> void:
	stop_climb()
	_exit_t = -1.0
	if WorldState.has_respawn(build_controller.island_id):
		global_position = WorldState.respawn_position
		rotation.y = WorldState.respawn_rotation_y
	else:
		global_transform = spawn_transform
	velocity = Vector3.ZERO
	reset_physics_interpolation() # salto instantáneo: sin «volar» desde donde caía


## Descansar en una cama (C4, César): ahí reaparecerás y se guarda la partida. Devuelve lo que dijo el
## guardado ("SAVE_DONE" o "SAVE_ERROR").
func rest_at(spot: Transform3D) -> String:
	WorldState.set_respawn(build_controller.island_id, spot.origin, spot.basis.get_euler().y)
	store_to_world()
	var result: String = SaveSystem.save_game()
	if result == "SAVE_DONE":
		SaveSystem.notification_requested.emit("REST_DONE")
	return result
