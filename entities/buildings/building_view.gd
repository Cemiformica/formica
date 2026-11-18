class_name BuildingView
extends Interactable
## Pieza visible de una construcción colocada (B2.4c). Solo MUESTRA los datos de su `PlacedBuilding`
## (D-046): la crea y la borra `IslandView`. Si el `BuildingData` tiene `scene`, la usa girada y
## reflejada; si no, una caja provisional con un cubito por puerto (azul = entrada, naranja = salida).
## Encima, un texto flotante con el contenido y el progreso de la máquina, leído en cada fotograma. Solo se
## ve en la construcción que miras a alcance de E (B5, César); es provisional hasta las ventanas de B6.
## Las cintas son una losa baja con una flecha, y sus ítems se ven como cubitos del color de cada ítem.
## Los postes son un palo alto; los generadores, una losa azulada (B2.6b). E sobre un generador
## rearma el fusible de su red; sobre una máquina, hace el intercambio rápido provisional.
## Con modelo real (B3): pone el puerto estándar en cada `PortData` (D-079), con su lengüeta de cinta
## visible solo si está conectado; ilumina el borne si tiene cable; y el cable se engancha en el nodo
## «cable_anchor» del modelo. Las máquinas con modelo muestran su estado (B3): mientras trabajan, la brasa
## («ember_window…») brilla y parpadea, sale humo de cada «smoke_origin…» (del color `smoke_color` de su
## construcción) y el fuelle («bellows_pivot») bombea;
## al parar, todo se apaga poco a poco. Dónde tocar: colores y ritmos en las constantes EMBER_… y BELLOWS_….

const BODY_HEIGHT: float = 1.0
const BODY_COLOR: Color = Color(0.55, 0.5, 0.45)
const GENERATOR_COLOR: Color = Color(0.15, 0.25, 0.5)
const POLE_COLOR: Color = Color(0.45, 0.32, 0.2)
const POLE_HEIGHT: float = 2.0
const GENERATOR_HEIGHT: float = 0.5
const COLOR_INPUT: Color = Color(0.2, 0.5, 1.0)
const COLOR_OUTPUT: Color = Color(1.0, 0.55, 0.1)
## Altura de la superficie de la cinta (la banda del modelo está a 0,125 m, D-079).
const BELT_HEIGHT: float = 0.125
const BELT_COLOR: Color = Color(0.25, 0.25, 0.27)
const ARROW_COLOR: Color = Color(0.85, 0.85, 0.8)
## Puertos estándar (D-079): se modelan en el lado norte de su casilla, con el origen en su centro.
const PORT_INPUT_SCENE: PackedScene = preload("res://assets/models/buildings/port_input.glb")
const PORT_OUTPUT_SCENE: PackedScene = preload("res://assets/models/buildings/port_output.glb")
## Color del borne con un cable conectado (verde brillante, petición de César: se entiende mejor).
const CABLE_LIGHT_COLOR: Color = Color(0.6, 0.95, 0.3)
## Brasa: color encendido, color apagado, brillo máximo y velocidad de encendido y apagado (por segundo).
const EMBER_COLOR: Color = Color(1.0, 0.5, 0.15)
const EMBER_DARK: Color = Color(0.18, 0.08, 0.05)
const EMBER_ENERGY: float = 1.2
const EMBER_FADE_IN: float = 1.5
const EMBER_FADE_OUT: float = 0.5
## Segundos que se sigue considerando «trabajando» tras el último avance (Simulation da 10 pasos/s).
const WORKING_HOLD: float = 0.3
## Fuelle: veces por segundo y cuánto se aplasta (0,35 = hasta el 65 % de su altura).
const BELLOWS_RATE: float = 0.9
const BELLOWS_SQUEEZE: float = 0.35
## Luz de estado de los generadores («status_light…», B3.7, colores de César): ámbar sin cable; verde
## con cable y el fusible armado; si salta, parpadea en rojo (STATUS_BLINK_RATE veces por segundo) para
## que se vea dónde rearmarlo.
const STATUS_COLOR: Color = Color(1.0, 0.72, 0.23)
const STATUS_OK_COLOR: Color = CABLE_LIGHT_COLOR
const STATUS_TRIPPED_COLOR: Color = Color(1.0, 0.18, 0.12)
const STATUS_DARK: Color = Color(0.12, 0.1, 0.08)
const STATUS_ENERGY: float = 1.5
const STATUS_BLINK_RATE: float = 1.5
## Taladro del extractor (B3.7): vueltas por segundo en radianes, cuánto baja (m) y cuántas veces por
## segundo; y cada cuánto sale una nubecita de polvo de la broca (César) mientras trabaja.
const DRILL_SPIN: float = 9.0
const DRILL_BOB: float = 0.05
const DRILL_BOB_RATE: float = 1.5
const DUST_INTERVAL: float = 0.6
## Talador (B3.7, D-092): mordiscos por segundo de la mandíbula y cuánto se cierra cada hoja (radianes);
## cuánto tantean las antenas (radianes); madera por tronco de las bandejas (lo que da un árbol) y color
## de las virutas que saltan en cada mordisco.
const JAW_RATE: float = 2.0
const JAW_BITE: float = 0.6
const ANTENNA_SWAY: float = 0.22
const LOG_WOOD: int = 4
const CHIPS_COLOR: Color = Color(0.85, 0.68, 0.45)
## Rueda hidráulica (D-094): vueltas por segundo de la rueda (radianes/s), cada cuánto salpica y de qué color.
const WHEEL_SPIN: float = 0.8
const SPLASH_INTERVAL: float = 0.45
const SPLASH_COLOR: Color = Color(0.78, 0.92, 1.0)
# Banco de trabajo (D-095): la manivela y el carrete giran mientras fabrica, la bobina crece con el
# progreso y el flexo del Nexo se enciende (bombilla y un foco cálido de verdad, sin sombras: es barato).
const CRANK_SPIN: float = 5.0
const SPOOL_SPIN: float = 7.0
const COIL_MIN_SCALE: float = 0.47 ## grosor del hilo con el carrete vacío (el núcleo de madera se ve)
const LAMP_COLOR: Color = Color(1.0, 0.8, 0.52)
const LAMP_DARK: Color = Color(0.3, 0.3, 0.28)
const LAMP_BULB_ENERGY: float = 2.5
const LAMP_LIGHT_ENERGY: float = 1.6
## Efecto al colocar (B5.4): color del polvo, tiempo que tarda en crecer (igual que el zumbido del sonido,
## hasta el golpe: art/tools/make_sounds.py, materialize_m1), tamaño inicial, duración del rebote y aplastamiento.
const PLACE_DUST_COLOR: Color = Color(0.56, 0.47, 0.34)
const PLACE_GROW_TIME: float = 0.2
const PLACE_GROW_START: float = 0.15
const PLACE_POP_TIME: float = 0.35
const PLACE_POP_SQUASH: float = 0.2
## Capas de colisión de las cintas: la 1 (sólidas, B3.7, César: el jugador ya no las atraviesa; las
## sube andando gracias al escalón automático de `Player`) y la 2 (la de siempre de las cintas, por si
## algún rayo las busca solo a ellas).
const BELT_COLLISION_LAYER: int = 1 | 2
## Alto del choque de la cinta: el borde de arriba de sus paredes (conveyor_blockout.py, WALL_TOP_Z).
const BELT_COLLISION_HEIGHT: float = 0.23

## Un material por ítem, compartido por todos los cubitos de todas las cintas.
static var _item_materials: Dictionary[ItemData, StandardMaterial3D] = {}
## Punto de enganche del cable de cada modelo, en su espacio local sin girar (null si no tiene).
## Se calcula una vez por tipo de construcción.
static var _anchor_cache: Dictionary = {}
## Material del borne encendido, compartido por todos.
static var _cable_light: StandardMaterial3D = null
## Humo de juguete: material de partículas y bolita, compartidos por todas las chimeneas.
## Un material de partículas por color de humo, compartido por todas las chimeneas de ese color.
static var _smoke_processes: Dictionary[Color, ParticleProcessMaterial] = {}
static var _smoke_mesh: ArrayMesh = null

## Rojo translúcido encima de lo marcado para desmontar (C2.2), compartido por todas.
static var _marked_material: StandardMaterial3D = null

## Construcción que muestra.
var placed: PlacedBuilding
## Isla a la que pertenece (para preguntar por su red eléctrica).
var island: IslandState

## Solo cintas: dirección de avance (hacia la salida) y cubitos de los ítems.
var _belt_forward: Vector3 = Vector3.ZERO
var _belt_cubes: Array[MeshInstance3D] = []
## Solo cintas con modelo: en cada extremo, la vuelta de banda (si está libre) o el tramo de unión
## (si está conectado). Índices de sus puertos de entrada (atrás) y salida (delante).
var _belt_end_back: Node3D = null
var _belt_end_front: Node3D = null
var _belt_join_back: Node3D = null
var _belt_join_front: Node3D = null
var _belt_in_port: int = -1
var _belt_out_port: int = -1
## ¿Está conectada la salida de la cinta? (el ítem de delante puede asomar por ella al dibujarlo)
var _belt_out_linked: bool = false
## Solo con modelo: lengüeta de cada puerto (mismo orden que `placed.get_ports()`; null si no tiene) y aislante del borne.
var _port_tongues: Array[Node3D] = []
var _insulator: MeshInstance3D = null
## Solo máquinas con modelo: material propio de la brasa, humo, pivote del fuelle y estado del calor.
var _ember_material: StandardMaterial3D = null
## Humo de cada «smoke_origin…» del modelo (una o varias columnas).
var _smokes: Array[GPUParticles3D] = []
var _bellows: Node3D = null
## Solo extractores con modelo: taladro (gira y sube y baja) y punto de donde sale el polvo.
var _drill: Node3D = null
var _drill_rest: Vector3 = Vector3.ZERO
var _dust_origin: Node3D = null
var _dust_timer: float = 0.0
## Solo extractores con modelo: mineral de las mirillas, que sube según lo lleno que esté el almacén.
var _store_fill: Node3D = null
var _store_fill_painted: bool = false
## Solo almacenes: ítem del que están pintadas las mirillas ahora.
var _store_fill_item: ItemData = null
## Solo taladores con modelo: hojas de la mandíbula (giran en Y; el signo dice hacia dónde cierran),
## antenas que tantean, punto de donde saltan las virutas y troncos de las bandejas, en orden.
var _jaws: Array[Node3D] = []
var _jaw_signs: Array[float] = []
var _antennas: Array[Node3D] = []
var _chips_origin: Node3D = null
var _bite_closed: bool = false
var _store_logs: Array[Node3D] = []
## Solo rueda hidráulica: la rueda que gira, su sentido (las paletas de abajo van con la corriente),
## dónde salpica (local al modelo, ya del lado por el que salen del agua) y el modelo.
var _wheel: Node3D = null
var _wheel_sign: float = 1.0
var _splash_local: Vector3 = Vector3.ZERO
var _splash_timer: float = 0.0
var _crank: Node3D = null
var _spool: Node3D = null
var _coil_fill: Node3D = null
var _lamp_material: StandardMaterial3D = null
var _lamp_light: SpotLight3D = null
var _model_root: Node3D = null
var _heat: float = 0.0 ## 0 = apagado, 1 = a pleno
var _working_hold: float = 0.0
var _last_progress: float = 0.0
var _time: float = 0.0
var _phase: float = 0.0 ## desfase al azar, para que no parpadeen todos los hornos a la vez
## Solo generadores con modelo: material propio de sus luces de estado (null si no tienen) y su reloj.
var _status_material: StandardMaterial3D = null
var _status_time: float = 0.0
## ¿Tiene algún cable? (lo dice `set_cabled`; también decide el color de la luz de estado)
var _cabled: bool = false
## ¿Tiene el jugador abierta la ventana de esta construcción? (C1.5) El banco se anima y el arcón abre la tapa.
var window_open: bool = false
var _lid: Node3D = null
var _lid_tween: Tween = null
## Piezas que rebotan al colocar y su escala original (B5.4).
var _pop_nodes: Array[Node3D] = []
var _pop_scales: Array[Vector3] = []


## Altura de la construcción: la de `BuildingData.height` si la tiene (modelos reales); si no, la de la
## pieza provisional: palo alto para los postes, losa para los generadores, caja para el resto.
static func body_height(data: BuildingData) -> float:
	if data.height > 0:
		return float(data.height)
	if is_pole(data):
		return POLE_HEIGHT
	if data.power > 0.0:
		return GENERATOR_HEIGHT
	return BODY_HEIGHT


## ¿Es un poste? (admite varios cables y ni genera, ni consume, ni trabaja)
static func is_pole(data: BuildingData) -> bool:
	return data.power_connections > 1 and data.power == 0.0 and data.recipe == null and data.belt_speed <= 0.0


## Punto del mundo donde se engancha un cable a esta construcción: el nodo «cable_anchor» del modelo
## (reflejado y girado como la construcción) o, si no lo tiene, arriba del todo, en su centro.
static func cable_anchor(p_placed: PlacedBuilding) -> Vector3:
	var center: Vector3 = GridMath.footprint_center(p_placed.origin, p_placed.data.size, p_placed.rotation)
	var local: Variant = _model_anchor(p_placed.data)
	if local != null:
		var offset: Vector3 = local
		if p_placed.flipped:
			offset.z = -offset.z # primero se refleja (como el modelo, escala −1 en Z) y luego se gira
		return center + offset.rotated(Vector3.UP, GridMath.rotation_to_yaw(p_placed.rotation))
	return center + Vector3(0.0, body_height(p_placed.data) - 0.1, 0.0)


## Caja logística (D-093): el modelo trae tres versiones del túnel de salida; enseña solo la del lado
## elegido (0 = recta, 1 = derecha, 2 = izquierda). En otros modelos no hace nada. La usa también el fantasma.
const OUTPUT_TUNNELS: Array[String] = ["tunnel_straight", "tunnel_right", "tunnel_left"]


static func show_output_tunnel(model: Node3D, turn: int) -> void:
	for i: int in OUTPUT_TUNNELS.size():
		var tunnel := model.find_child(OUTPUT_TUNNELS[i], true, false) as Node3D
		if tunnel != null:
			tunnel.visible = i == posmod(turn, 3)


## Posición de «cable_anchor» dentro del modelo (sin girar), o null. Instancia el modelo una sola vez.
static func _model_anchor(data: BuildingData) -> Variant:
	if data.scene == null:
		return null
	if not _anchor_cache.has(data):
		var result: Variant = null
		var model := data.scene.instantiate() as Node3D
		var anchor := model.find_child("cable_anchor", true, false) as Node3D
		if anchor != null:
			# Fuera del árbol no hay posiciones globales: se suman a mano las de sus padres.
			var xform: Transform3D = anchor.transform
			var node: Node = anchor.get_parent()
			while node != model and node is Node3D:
				xform = (node as Node3D).transform * xform
				node = node.get_parent()
			result = xform.origin
		model.free()
		_anchor_cache[data] = result
	return _anchor_cache[data]


## Prepara la vista. Se llama ANTES de añadirla al árbol.
func setup(p_placed: PlacedBuilding, p_island: IslandState) -> void:
	placed = p_placed
	island = p_island
	# Las construcciones no se mueven con la física; lo que anima esta vista (fuelle, ítems de las cintas)
	# cambia en cada fotograma, así que no debe suavizarse con la interpolación de la física.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	name = "%s_%d" % [placed.data.id, placed.id]
	display_name_key = placed.data.name_key
	position = GridMath.footprint_center(placed.origin, placed.data.size, placed.rotation)
	var s: Vector2i = OccupancyGrid.rotated_size(placed.data.size, placed.rotation)
	if placed.is_belt():
		_setup_belt()
		return

	# Colisión del tamaño de la huella girada: bloquea el paso y el rayo de interacción la encuentra.
	var height: float = body_height(placed.data)
	var shape := BoxShape3D.new()
	shape.size = Vector3(s.x, height, s.y)
	if is_pole(placed.data):
		# Más estrecha que la casilla, pero lo bastante ancha y alta (altura 3: cruceta y aislante
		# incluidos) para apuntarle sin afinar al empezar o acabar un cable (César).
		shape.size = Vector3(0.6, height, 0.6)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = height * 0.5
	add_child(collision)

	if placed.data.scene != null:
		# Modelo real: primero se refleja (escala −1 en Z, norte ↔ sur) y luego se gira.
		var model := placed.data.scene.instantiate() as Node3D
		model.rotation.y = GridMath.rotation_to_yaw(placed.rotation)
		if placed.flipped:
			model.scale.z = -1.0
		add_child(model)
		_insulator = model.find_child("cable_insulator", true, false) as MeshInstance3D
		_add_port_models()
		show_output_tunnel(model, placed.output_turn)
		_setup_machine_visuals(model)
		_setup_status_lights(model)
	elif is_pole(placed.data):
		_add_box(Vector3(0.2, height, 0.2), Vector3(0.0, height * 0.5, 0.0), POLE_COLOR)
	else:
		var color: Color = BODY_COLOR
		if placed.data.power > 0.0:
			color = GENERATOR_COLOR
		_add_box(Vector3(s.x - 0.1, height, s.y - 0.1), Vector3(0.0, height * 0.5, 0.0), color)
		_add_port_markers()


func _process(delta: float) -> void:
	if placed == null:
		return
	if placed.is_belt():
		_update_belt_items()
		return
	if _status_material != null:
		_update_status_lights(delta)
	if placed.is_machine() or placed.is_extractor() or placed.is_harvester() or placed.is_workbench():
		_update_machine_visuals(delta)
	if _wheel != null:
		_update_water_wheel(delta)
	if placed.is_storage():
		_update_storage_visuals()


## Marca (o desmarca) la construcción para desmontarla: se tiñe de rojo (C2.2).
func set_marked(marked: bool) -> void:
	if _marked_material == null:
		_marked_material = StandardMaterial3D.new()
		_marked_material.albedo_color = Color(1.0, 0.2, 0.15, 0.4)
		_marked_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_marked_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_overlay = _marked_material if marked else null


## Efecto al colocar (B5.4, César), a juego con el sonido: mientras suena el zumbido la construcción crece
## desde pequeña; en el golpe se aplasta, rebota como un juguete (se pasa un ~5 % y se asienta) y suelta polvo
## alrededor de la base. Solo al construir: al cargar una partida aparece quieta (lo llama `IslandView`).
## Crecen y rebotan las piezas visibles, no la colisión.
func play_place_effect() -> void:
	_pop_nodes.clear()
	_pop_scales.clear()
	for child: Node in get_children():
		var visual := child as Node3D
		if visual == null or visual is CollisionShape3D or visual is Label3D or visual is GPUParticles3D:
			continue
		_pop_nodes.append(visual)
		_pop_scales.append(visual.scale)
	_set_grow(0.0)
	var tween: Tween = create_tween()
	tween.tween_method(_set_grow, 0.0, 1.0, PLACE_GROW_TIME)
	tween.tween_callback(_land)
	tween.tween_method(_set_pop, 0.0, 1.0, PLACE_POP_TIME)


## Crecer: de PLACE_GROW_START a casi su tamaño, acelerando (como si cayera en su sitio).
func _set_grow(t: float) -> void:
	var size: float = lerpf(PLACE_GROW_START, 1.0, t * t)
	for i: int in _pop_nodes.size():
		if is_instance_valid(_pop_nodes[i]):
			_pop_nodes[i].scale = _pop_scales[i] * size


## El golpe: polvo alrededor de la base (esquinas y mitad de cada lado).
func _land() -> void:
	var s: Vector2i = OccupancyGrid.rotated_size(placed.data.size, placed.rotation)
	for side_x: float in [-0.5, 0.0, 0.5]:
		for side_z: float in [-0.5, 0.0, 0.5]:
			if side_x == 0.0 and side_z == 0.0:
				continue
			var spot := Vector3(side_x * s.x, 0.05, side_z * s.y)
			DustPuff.spawn(get_parent(), global_position + spot, PLACE_DUST_COLOR)


## Rebote amortiguado: `t` de 0 a 1. La altura oscila alrededor de 1 y lo ancho compensa (como goma).
func _set_pop(t: float) -> void:
	var stretch: float = 1.0 - PLACE_POP_SQUASH * exp(-4.0 * t) * cos(t * TAU * 1.5)
	if t >= 1.0:
		stretch = 1.0
	var wide: float = 1.0 / sqrt(stretch)
	for i: int in _pop_nodes.size():
		if is_instance_valid(_pop_nodes[i]):
			_pop_nodes[i].scale = _pop_scales[i] * Vector3(wide, stretch, wide)


## La ventana de esta construcción se abre o se cierra (C1.5): el arcón levanta o baja la tapa (unos 80°,
## desde la bisagra de atrás); el banco se anima mientras está abierta (ver `_update_machine_visuals`).
func set_window_open(open: bool) -> void:
	window_open = open
	if _lid != null:
		if _lid_tween != null:
			_lid_tween.kill()
		_lid_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_lid_tween.tween_property(_lid, "rotation:x", deg_to_rad(-80.0) if open else 0.0, 0.35)


## Rueda hidráulica: busca la rueda y decide hacia dónde gira. Girando en +X (local), las paletas de abajo
## van hacia el norte del modelo; si el agua corre al revés, gira al revés. Salpica del lado por el que
## las paletas salen del agua (el de aguas abajo).
func _setup_water_wheel(model: Node3D) -> void:
	_wheel = model.find_child("wheel_pivot", true, false) as Node3D
	if _wheel == null or placed.data.water_cells.is_empty() or island == null:
		return
	var cell: Vector2i = OccupancyGrid.local_to_cell(placed.origin, placed.data.size, placed.rotation, placed.data.water_cells[0])
	var model_north: Vector2i = GridMath.rotate_offset(Vector2i(0, -1), placed.rotation)
	_wheel_sign = 1.0 if island.water.get(cell, model_north) == model_north else -1.0
	var splash := model.find_child("splash_origin", true, false) as Node3D
	if splash != null:
		_splash_local = splash.position
		_splash_local.z = absf(_splash_local.z) * -_wheel_sign # aguas abajo: norte (−Z) si gira en +X


## La rueda gira siempre (el agua siempre corre) y salpica cada poco.
func _update_water_wheel(delta: float) -> void:
	_wheel.rotation.x += WHEEL_SPIN * _wheel_sign * delta
	_splash_timer -= delta
	if _splash_timer <= 0.0 and _model_root != null:
		_splash_timer = SPLASH_INTERVAL
		DustPuff.spawn(self, _model_root.to_global(_splash_local), SPLASH_COLOR)


## ¿Le cabe algo más? (alguna casilla vacía o alguna pila sin llenar)
func _storage_has_space() -> bool:
	for stack: ItemStack in placed.output.slots:
		if stack == null or stack.space_left() > 0:
			return true
	return false


## Almacén con modelo: las mirillas se llenan según las casillas ocupadas, del color de lo primero que
## guarda (cambia si cambia lo que guarda).
func _update_storage_visuals() -> void:
	if _store_fill == null:
		return
	var used: int = 0
	var first: ItemData = null
	for stack: ItemStack in placed.output.slots:
		if stack != null:
			used += 1
			if first == null:
				first = stack.item
	var ratio: float = float(used) / maxf(placed.output.slots.size(), 1)
	_store_fill.visible = ratio > 0.0
	_store_fill.scale.y = maxf(ratio, 0.01)
	if first != null and first != _store_fill_item:
		_store_fill_item = first
		for mesh: Node in _store_fill.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).material_override = _material_for(first)


## Ítems que guarda en su salida, de cualquier tipo.
func _stored_total() -> int:
	var total: int = 0
	for stack: ItemStack in placed.output.slots:
		if stack != null:
			total += stack.amount
	return total


## Cinta: losa baja, flecha hacia la salida y un cubito por cada hueco de ítem.
func _setup_belt() -> void:
	collision_layer = BELT_COLLISION_LAYER
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, BELT_COLLISION_HEIGHT, 1.0)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = BELT_COLLISION_HEIGHT * 0.5
	add_child(collision)

	# Dirección: hacia donde mira su puerto de salida.
	for i: int in placed.data.ports.size():
		var port: PortData = placed.data.ports[i]
		if port.kind == PortData.Kind.OUTPUT:
			_belt_out_port = i
			var offset: Vector2i = PortData.side_offset(port.get_grid_side(placed.rotation, placed.flipped))
			_belt_forward = Vector3(offset.x, 0.0, offset.y)
		else:
			_belt_in_port = i
	if placed.data.scene != null:
		# Modelo real (B3.7): sin puertos estándar (la cinta encaja en los de las máquinas). Su banda avanza
		# con el material compartido belt_band, que mueve IslandView. En cada extremo se ve la vuelta de
		# banda mientras esté libre (ver set_linked_ports).
		var model := placed.data.scene.instantiate() as Node3D
		model.rotation.y = GridMath.rotation_to_yaw(placed.rotation)
		add_child(model)
		_belt_end_back = model.find_child("belt_end_back", true, false) as Node3D
		_belt_end_front = model.find_child("belt_end_front", true, false) as Node3D
		_belt_join_back = model.find_child("belt_join_back", true, false) as Node3D
		_belt_join_front = model.find_child("belt_join_front", true, false) as Node3D
		_show_belt_ends(false, false)
	else:
		_add_box(Vector3(0.9, BELT_HEIGHT, 0.9), Vector3(0.0, BELT_HEIGHT * 0.5, 0.0), BELT_COLOR)
		# Flecha: un palo y una punta, sobre la losa.
		_add_box(_arrow_size(0.08, 0.5), _belt_forward * -0.05 + Vector3(0.0, BELT_HEIGHT + 0.01, 0.0), ARROW_COLOR)
		_add_box(_arrow_size(0.3, 0.08), _belt_forward * 0.22 + Vector3(0.0, BELT_HEIGHT + 0.01, 0.0), ARROW_COLOR)

	for i: int in placed.data.belt_capacity:
		var cube := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.25, 0.25, 0.25)
		cube.mesh = mesh
		cube.visible = false
		add_child(cube)
		_belt_cubes.append(cube)


## Caja plana alineada con la dirección de la cinta: `across` de ancho y `along` de largo.
func _arrow_size(across: float, along: float) -> Vector3:
	if absf(_belt_forward.x) > 0.5:
		return Vector3(along, 0.02, across)
	return Vector3(across, 0.02, along)


## Coloca los cubitos según el avance de cada ítem (0 = detrás, 1 = delante). La simulación avanza a
## 10 pasos por segundo: entre paso y paso se predice el avance para que se deslicen sin saltitos.
func _update_belt_items() -> void:
	# Si la salida está conectada, el de delante puede asomar un poco por ella mientras llega el paso que
	# lo pasa a la siguiente (allí empieza justo donde iba): así no se para en cada unión.
	var front_limit: float = 1.0
	if _belt_out_linked and not placed.belt_progress.is_empty() and placed.belt_progress[0] < 1.0:
		front_limit = 1.0 + placed.data.belt_speed * Simulation.TICK
	var shown: Array[float] = placed.predict_belt_progress(Simulation.time_since_step(), front_limit)
	for i: int in _belt_cubes.size():
		var cube: MeshInstance3D = _belt_cubes[i]
		if i >= placed.belt_items.size():
			cube.visible = false
			continue
		var item: ItemData = placed.belt_items[i]
		cube.position = _belt_forward * (shown[i] - 0.5) + Vector3(0.0, BELT_HEIGHT + 0.125, 0.0)
		cube.material_override = _material_for(item)
		cube.visible = true


static func _material_for(item: ItemData) -> StandardMaterial3D:
	if not _item_materials.has(item):
		var material := StandardMaterial3D.new()
		material.albedo_color = item.color
		_item_materials[item] = material
	return _item_materials[item]


## E: abre la ventana de la construcción (C1.3). El nombre y el estado los enseña el letrero de arriba
## (`FocusPanel`, C1.8), que sustituye a los textos flotantes; el detalle está en la ventana.
func interact(by: Node) -> void:
	super(by)
	# E abre la ventana de la construcción (C1.3); el fusible se rearma desde ella.
	if by.has_method("open_building"):
		by.open_building(self)


## Qué hace la E aquí, para el letrero de arriba. Las cintas no tienen ventana.
func get_interact_hint_key() -> String:
	if placed == null or placed.is_belt():
		return ""
	return "HINT_OPEN"


## Busca en el modelo las piezas que muestran el estado de la máquina y las prepara (todas son opcionales).
func _setup_machine_visuals(model: Node3D) -> void:
	_model_root = model
	_setup_water_wheel(model)
	_last_progress = placed.progress
	_phase = randf() * TAU
	var embers: Array[Node] = model.find_children("ember_window*", "MeshInstance3D", true, false)
	if not embers.is_empty():
		_ember_material = StandardMaterial3D.new()
		_ember_material.albedo_color = EMBER_DARK
		_ember_material.emission_enabled = true
		_ember_material.emission = EMBER_COLOR
		_ember_material.emission_energy_multiplier = 0.0
		for ember: Node in embers:
			(ember as MeshInstance3D).material_override = _ember_material
	for smoke_origin: Node in model.find_children("smoke_origin*", "Node3D", true, false):
		var smoke: GPUParticles3D = _make_smoke(placed.data.smoke_color)
		smoke_origin.add_child(smoke)
		_smokes.append(smoke)
	_bellows = model.find_child("bellows_pivot", true, false) as Node3D
	_drill = model.find_child("drill_pivot", true, false) as Node3D
	if _drill != null:
		_drill_rest = _drill.position
	_dust_origin = model.find_child("dust_origin", true, false) as Node3D
	_store_fill = model.find_child("store_fill_pivot", true, false) as Node3D
	if _store_fill != null:
		_store_fill.visible = false # vacío hasta que saque algo
	for side: String in ["east", "west"]:
		var jaw := model.find_child("jaw_pivot_" + side, true, false) as Node3D
		if jaw != null:
			_jaws.append(jaw)
			_jaw_signs.append(1.0 if side == "east" else -1.0) # las dos hojas cierran hacia delante
		var antenna := model.find_child("antenna_pivot_" + side, true, false) as Node3D
		if antenna != null:
			_antennas.append(antenna)
	_chips_origin = model.find_child("chips_origin", true, false) as Node3D
	var log_index: int = 0
	while true:
		var log_node := model.find_child("store_log_%d" % log_index, true, false) as Node3D
		if log_node == null:
			break
		log_node.visible = false # bandejas vacías hasta que tale algo
		_store_logs.append(log_node)
		log_index += 1
	_setup_workbench(model)


## Banco de trabajo: manivela, carrete, bobina que crece y flexo con luz propia (todo opcional).
func _setup_workbench(model: Node3D) -> void:
	_lid = model.find_child("lid_pivot", true, false) as Node3D # arcón
	_crank = model.find_child("crank_pivot", true, false) as Node3D
	_spool = model.find_child("spool_pivot", true, false) as Node3D
	_coil_fill = model.find_child("coil_fill_pivot", true, false) as Node3D
	var bulb := model.find_child("work_lamp", true, false) as MeshInstance3D
	if bulb != null:
		_lamp_material = StandardMaterial3D.new()
		_lamp_material.albedo_color = LAMP_DARK
		_lamp_material.emission_enabled = true
		_lamp_material.emission = LAMP_COLOR
		_lamp_material.emission_energy_multiplier = 0.0
		bulb.material_override = _lamp_material
	var anchor := model.find_child("lamp_light", true, false) as Node3D
	if anchor != null:
		_lamp_light = SpotLight3D.new()
		# Apunta hacia abajo pase lo que pase con el vacío (girar o reflejar la construcción no cambia «abajo»).
		_lamp_light.transform.basis = anchor.transform.basis.inverse() * Basis(Vector3.RIGHT, -PI * 0.5)
		_lamp_light.light_color = LAMP_COLOR
		_lamp_light.light_energy = 0.0
		_lamp_light.spot_range = 1.8
		_lamp_light.spot_angle = 50.0
		_lamp_light.shadow_enabled = false
		_lamp_light.distance_fade_enabled = true # de lejos no se calcula
		_lamp_light.distance_fade_begin = 30.0
		_lamp_light.distance_fade_length = 10.0
		_lamp_light.visible = false
		anchor.add_child(_lamp_light)


## Trabaja si su progreso cambió hace poco. El calor sube y baja suave, y de él dependen la brasa
## (con parpadeo), el humo y el fuelle.
func _update_machine_visuals(delta: float) -> void:
	if placed.is_workbench() and window_open:
		_working_hold = WORKING_HOLD # el banco trabaja mientras su ventana está abierta (César)
	elif placed.progress != _last_progress:
		_last_progress = placed.progress
		_working_hold = WORKING_HOLD
	else:
		_working_hold = maxf(_working_hold - delta, 0.0)
	var target: float = 0.0
	if _working_hold > 0.0:
		target = 1.0
	var rate: float = EMBER_FADE_OUT
	if target > _heat:
		rate = EMBER_FADE_IN
	_heat = move_toward(_heat, target, rate * delta)
	_time += delta
	if _ember_material != null:
		var flicker: float = 0.85 + 0.1 * sin(_time * 7.3 + _phase) + 0.05 * sin(_time * 17.9 + _phase * 2.0)
		_ember_material.emission_energy_multiplier = EMBER_ENERGY * _heat * flicker
		_ember_material.albedo_color = EMBER_DARK.lerp(EMBER_COLOR, _heat * 0.6)
	for smoke: GPUParticles3D in _smokes:
		smoke.emitting = _heat > 0.5
	if _bellows != null:
		var squeeze: float = 0.5 + 0.5 * sin(_time * TAU * BELLOWS_RATE + _phase)
		_bellows.scale.y = 1.0 - BELLOWS_SQUEEZE * squeeze * _heat
	if _drill != null:
		# Gira (más rápido cuanto más «caliente») y sube y baja un poco, como si picara.
		_drill.rotation.y += DRILL_SPIN * _heat * delta
		_drill.position = _drill_rest + Vector3(0.0, -DRILL_BOB * _heat * (0.5 + 0.5 * sin(_time * TAU * DRILL_BOB_RATE + _phase)), 0.0)
	if _store_fill != null and placed.vein_item != null and placed.data.output_capacity > 0:
		var ratio: float = clampf(float(placed.output.get_total(placed.vein_item)) / placed.data.output_capacity, 0.0, 1.0)
		_store_fill.visible = ratio > 0.0
		_store_fill.scale.y = maxf(ratio, 0.01)
		if not _store_fill_painted:
			# Del color del mineral que saca (el mismo material que sus cubitos en las cintas).
			_store_fill_painted = true
			for mesh: Node in _store_fill.find_children("*", "MeshInstance3D", true, false):
				(mesh as MeshInstance3D).material_override = _material_for(placed.vein_item)
	if not _jaws.is_empty():
		# Muerde JAW_RATE veces por segundo; con el «calor» la mordida crece o se apaga y se queda abierta.
		var bite: float = 0.5 - 0.5 * cos(_time * TAU * JAW_RATE + _phase)
		for i: int in _jaws.size():
			_jaws[i].rotation.y = _jaw_signs[i] * JAW_BITE * bite * _heat
		# Virutas justo cuando las hojas se cierran del todo.
		var closed: bool = bite > 0.9
		if closed and not _bite_closed and _heat > 0.5 and _chips_origin != null:
			DustPuff.spawn(self, _chips_origin.global_position, CHIPS_COLOR)
		_bite_closed = closed
	for i: int in _antennas.size():
		# Cada antena tantea a su ritmo (adelante y atrás, y a los lados), como una hormiga (César).
		var p: float = _phase + i * 1.7
		_antennas[i].rotation.x = ANTENNA_SWAY * _heat * sin(_time * 2.3 + p)
		_antennas[i].rotation.z = ANTENNA_SWAY * 0.7 * _heat * sin(_time * 1.4 + p * 1.3)
	if not _store_logs.is_empty():
		# Un tronco por cada LOG_WOOD de madera guardada (lo que da un árbol).
		var shown: int = mini(ceili(float(_stored_total()) / LOG_WOOD), _store_logs.size())
		for i: int in _store_logs.size():
			_store_logs[i].visible = i < shown
	if _crank != null:
		_crank.rotation.x += CRANK_SPIN * _heat * delta
	if _spool != null:
		_spool.rotation.x += SPOOL_SPIN * _heat * delta
	if _coil_fill != null and (placed.is_machine() or placed.is_workbench()):
		var done: float = 0.5 + 0.5 * sin(_time * 1.3) # el banco devana sin parar mientras está abierto
		if placed.is_machine():
			done = clampf(placed.progress / placed.data.recipe.duration, 0.0, 1.0)
		var thick: float = lerpf(COIL_MIN_SCALE, 1.0, done)
		_coil_fill.scale = Vector3(1.0, thick, thick)
	if _lamp_material != null:
		_lamp_material.emission_energy_multiplier = LAMP_BULB_ENERGY * _heat
		_lamp_material.albedo_color = LAMP_DARK.lerp(LAMP_COLOR, _heat)
	if _lamp_light != null:
		_lamp_light.visible = _heat > 0.01
		_lamp_light.light_energy = LAMP_LIGHT_ENERGY * _heat
	if _dust_origin != null and _heat > 0.5:
		_dust_timer -= delta
		if _dust_timer <= 0.0:
			_dust_timer = DUST_INTERVAL
			DustPuff.spawn(self, _dust_origin.global_position)


## Humo de juguete: pocas «piedrecitas» de humo facetadas (icosaedro achatado, como el resto del arte
## low-poly), de gris carbón, con sombreado de dibujo animado y sin reflejos. Suben separadas, girando
## un poco y con algo de deriva (brisa), crecen y se desvanecen al final. Barato: 5 partículas por chimenea y no se dibuja
## a más de 60 m. Dónde tocar: cantidad y duración abajo (amount, lifetime); color en `fade`.
static func _make_smoke(color: Color) -> GPUParticles3D:
	if not _smoke_processes.has(color):
		var process := ParticleProcessMaterial.new()
		_smoke_processes[color] = process
		process.direction = Vector3.UP
		process.spread = 15.0
		process.initial_velocity_min = 0.5
		process.initial_velocity_max = 0.7
		process.gravity = Vector3(0.12, 0.05, 0.04) # brisa suave: la columna se tuerce un poco
		process.scale_min = 0.8
		process.scale_max = 1.3
		process.particle_flag_rotate_y = true # cada bolita con su giro: no salen todas iguales
		process.angle_min = 0.0
		process.angle_max = 360.0
		process.angular_velocity_min = -45.0
		process.angular_velocity_max = 45.0
		var grow := Curve.new()
		grow.max_value = 2.0
		grow.add_point(Vector2(0.0, 0.5))
		grow.add_point(Vector2(1.0, 1.8))
		var grow_texture := CurveTexture.new()
		grow_texture.curve = grow
		process.scale_curve = grow_texture
		var fade := Gradient.new()
		# Del color de la construcción (casi negro en el horno, César) y casi opaco hasta el 65 % de su vida;
		# luego se aclara un poco y se desvanece.
		var mid: Color = color.lightened(0.08)
		var end: Color = color.lightened(0.2)
		fade.offsets = PackedFloat32Array([0.0, 0.65, 1.0])
		fade.colors = PackedColorArray([Color(color, 0.95), Color(mid, 0.85), Color(end, 0.0)])
		var fade_texture := GradientTexture1D.new()
		fade_texture.gradient = fade
		process.color_ramp = fade_texture
		var puff_material := StandardMaterial3D.new()
		puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff_material.vertex_color_use_as_albedo = true
		puff_material.roughness = 1.0
		puff_material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON # dos tonos: luz y sombra, de juguete
		puff_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED # sin reflejos del cielo (no burbujas)
		if _smoke_mesh == null:
			_smoke_mesh = _make_puff_mesh()
			_smoke_mesh.surface_set_material(0, puff_material)
	var particles := GPUParticles3D.new()
	particles.amount = 5
	particles.lifetime = 3.0
	particles.randomness = 0.3
	particles.process_material = _smoke_processes[color]
	particles.draw_pass_1 = _smoke_mesh
	particles.emitting = false
	particles.local_coords = false
	particles.visibility_range_end = 60.0
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles


## Bolita de humo facetada: un icosaedro (20 caras planas) de 0,14 m de radio, achatado en vertical.
## Cada cara lleva su propia normal, para que se vea en facetas como el resto del arte.
static func _make_puff_mesh() -> ArrayMesh:
	var t: float = (1.0 + sqrt(5.0)) * 0.5
	var corners: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces: Array[Vector3i] = [
		Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10), Vector3i(0, 10, 11),
		Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6), Vector3i(7, 1, 8),
		Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9),
		Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1)]
	var radius: float = corners[0].length()
	var puff_scale: Vector3 = Vector3(0.14, 0.11, 0.14) / radius
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face: Vector3i in faces:
		var a: Vector3 = corners[face.x] * puff_scale
		var b: Vector3 = corners[face.y] * puff_scale
		var c: Vector3 = corners[face.z] * puff_scale
		var cross: Vector3 = (b - a).cross(c - a)
		if cross.dot(a + b + c) > 0.0:
			# Godot dibuja la cara de delante con los vértices en sentido horario visto desde fuera.
			var swap: Vector3 = b
			b = c
			c = swap
			cross = -cross
		st.set_normal(-cross.normalized()) # normal hacia fuera, la misma para toda la cara (facetas)
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
	return st.commit()


## Puerto estándar en cada `PortData`: en el centro de su casilla, girado hacia su lado. Su lengüeta de
## cinta empieza oculta (la enseña `set_linked_ports`).
func _add_port_models() -> void:
	for port: PortData in placed.get_ports():
		var scene: PackedScene = PORT_INPUT_SCENE
		if port.kind == PortData.Kind.OUTPUT:
			scene = PORT_OUTPUT_SCENE
		var port_model := scene.instantiate() as Node3D
		var cell: Vector2i = port.get_grid_cell(placed.origin, placed.data.size, placed.rotation, placed.flipped)
		port_model.position = GridMath.cell_center(cell) - position
		port_model.rotation.y = GridMath.rotation_to_yaw(port.get_grid_side(placed.rotation, placed.flipped))
		add_child(port_model)
		var tongue := port_model.find_child("belt_tongue*", true, false) as Node3D
		if tongue != null:
			tongue.visible = false
		_port_tongues.append(tongue)


## Enseña la lengüeta de los puertos conectados. `linked`: índices de `placed.get_ports()` con conexión.
## En una cinta con modelo, decide en cada extremo si se ve la vuelta de banda o el tramo de unión.
func set_linked_ports(linked: Array[int]) -> void:
	if placed.is_belt():
		_belt_out_linked = linked.has(_belt_out_port)
		_show_belt_ends(linked.has(_belt_in_port), _belt_out_linked)
		return
	for i: int in _port_tongues.size():
		if _port_tongues[i] != null:
			_port_tongues[i].visible = linked.has(i)


## Extremo conectado → tramo recto de unión (la banda sigue en la cinta de al lado); libre → vuelta de banda.
func _show_belt_ends(back_linked: bool, front_linked: bool) -> void:
	if _belt_end_back != null:
		_belt_end_back.visible = not back_linked
	if _belt_join_back != null:
		_belt_join_back.visible = back_linked
	if _belt_end_front != null:
		_belt_end_front.visible = not front_linked
	if _belt_join_front != null:
		_belt_join_front.visible = front_linked


## Luces de estado (generadores): todas comparten un material propio de esta construcción.
func _setup_status_lights(model: Node3D) -> void:
	var lights: Array[Node] = model.find_children("status_light*", "MeshInstance3D", true, false)
	if lights.is_empty():
		return
	_status_material = StandardMaterial3D.new()
	_status_material.emission_enabled = true
	for light: Node in lights:
		(light as MeshInstance3D).material_override = _status_material
	_update_status_lights(0.0)


## Ámbar sin cable, verde con cable, rojo parpadeando con el fusible saltado (dato del propio generador).
func _update_status_lights(delta: float) -> void:
	var color: Color = STATUS_COLOR
	var lit: bool = true
	if placed.is_storage():
		# Almacén (caja logística): verde si le cabe algo más, ámbar si está llena.
		color = STATUS_OK_COLOR if _storage_has_space() else STATUS_COLOR
	elif placed.fuse_tripped:
		color = STATUS_TRIPPED_COLOR
		_status_time += delta
		lit = fposmod(_status_time * STATUS_BLINK_RATE, 1.0) < 0.5
	else:
		_status_time = 0.0
		if _cabled:
			color = STATUS_OK_COLOR
	_status_material.albedo_color = color if lit else STATUS_DARK
	_status_material.emission = color
	_status_material.emission_energy_multiplier = STATUS_ENERGY if lit else 0.0


## Ilumina el borne si la construcción tiene algún cable, llegue o no la energía (decisión de César:
## sirve para ver de un vistazo qué está bien montado).
func set_cabled(cabled: bool) -> void:
	_cabled = cabled
	if _insulator == null:
		return
	if cabled:
		if _cable_light == null:
			_cable_light = StandardMaterial3D.new()
			_cable_light.albedo_color = CABLE_LIGHT_COLOR
			_cable_light.emission_enabled = true
			_cable_light.emission = CABLE_LIGHT_COLOR
			_cable_light.emission_energy_multiplier = 1.0
		_insulator.material_override = _cable_light
	else:
		_insulator.material_override = null


## Un cubito por puerto, pegado al borde de su casilla por el lado del puerto.
func _add_port_markers() -> void:
	for port: PortData in placed.get_ports():
		var cell: Vector2i = port.get_grid_cell(placed.origin, placed.data.size, placed.rotation, placed.flipped)
		var offset: Vector2i = PortData.side_offset(port.get_grid_side(placed.rotation, placed.flipped))
		var world: Vector3 = GridMath.cell_center(cell, 0.2) + Vector3(offset.x, 0.0, offset.y) * 0.5
		var color: Color = COLOR_INPUT
		if port.kind == PortData.Kind.OUTPUT:
			color = COLOR_OUTPUT
		_add_box(Vector3(0.25, 0.25, 0.25), world - position, color)


func _add_box(size: Vector3, local_position: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = local_position
	add_child(mesh)
