class_name BuildingView
extends Interactable
## Pieza visible de una construcción colocada (B2.4c). Solo MUESTRA los datos de su `PlacedBuilding`
## (D-046): la crea y la borra `IslandView`. Si el `BuildingData` tiene `scene`, la usa girada y
## reflejada; si no, una caja provisional con un cubito por puerto (azul = entrada, naranja = salida).
## Encima, un texto flotante con el contenido y el progreso de la máquina, leído en cada fotograma.
## Las cintas son una losa baja con una flecha, y sus ítems se ven como cubitos del color de cada ítem.
## Los postes son un palo alto; los generadores, una losa azulada (B2.6b). E sobre un generador
## rearma el fusible de su red; sobre una máquina, hace el intercambio rápido provisional.

const BODY_HEIGHT: float = 1.0
const BODY_COLOR: Color = Color(0.55, 0.5, 0.45)
const GENERATOR_COLOR: Color = Color(0.15, 0.25, 0.5)
const POLE_COLOR: Color = Color(0.45, 0.32, 0.2)
const POLE_HEIGHT: float = 2.0
const GENERATOR_HEIGHT: float = 0.5
const COLOR_INPUT: Color = Color(0.2, 0.5, 1.0)
const COLOR_OUTPUT: Color = Color(1.0, 0.55, 0.1)
const BELT_HEIGHT: float = 0.1
const BELT_COLOR: Color = Color(0.25, 0.25, 0.27)
const ARROW_COLOR: Color = Color(0.85, 0.85, 0.8)
## Capa de colisión de las cintas: el jugador camina por encima (no choca), pero los rayos de
## construir y del cuentagotas sí las encuentran.
const BELT_COLLISION_LAYER: int = 2

## Un material por ítem, compartido por todos los cubitos de todas las cintas.
static var _item_materials: Dictionary[ItemData, StandardMaterial3D] = {}

## Construcción que muestra.
var placed: PlacedBuilding
## Isla a la que pertenece (para preguntar por su red eléctrica).
var island: IslandState

var _label: Label3D = null
## Solo cintas: dirección de avance (hacia la salida) y cubitos de los ítems.
var _belt_forward: Vector3 = Vector3.ZERO
var _belt_cubes: Array[MeshInstance3D] = []


## Altura de la pieza provisional: palo alto para los postes, losa para los generadores, caja para el resto.
static func body_height(data: BuildingData) -> float:
	if is_pole(data):
		return POLE_HEIGHT
	if data.power > 0.0:
		return GENERATOR_HEIGHT
	return BODY_HEIGHT


## ¿Es un poste? (admite varios cables y ni genera, ni consume, ni trabaja)
static func is_pole(data: BuildingData) -> bool:
	return data.power_connections > 1 and data.power == 0.0 and data.recipe == null and data.belt_speed <= 0.0


## Punto del mundo donde se engancha un cable a esta construcción: arriba del todo, en su centro.
static func cable_anchor(p_placed: PlacedBuilding) -> Vector3:
	var center: Vector3 = GridMath.footprint_center(p_placed.origin, p_placed.data.size, p_placed.rotation)
	return center + Vector3(0.0, body_height(p_placed.data) - 0.1, 0.0)


## Prepara la vista. Se llama ANTES de añadirla al árbol.
func setup(p_placed: PlacedBuilding, p_island: IslandState) -> void:
	placed = p_placed
	island = p_island
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
		shape.size = Vector3(0.4, height, 0.4)
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
	elif is_pole(placed.data):
		_add_box(Vector3(0.2, height, 0.2), Vector3(0.0, height * 0.5, 0.0), POLE_COLOR)
	else:
		var color: Color = BODY_COLOR
		if placed.data.power > 0.0:
			color = GENERATOR_COLOR
		_add_box(Vector3(s.x - 0.1, height, s.y - 0.1), Vector3(0.0, height * 0.5, 0.0), color)
		_add_port_markers()

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # el texto ya va traducido
	_label.font_size = 40
	_label.outline_size = 8
	_label.position.y = height + 0.5
	add_child(_label)


func _process(_delta: float) -> void:
	if placed == null:
		return
	if placed.is_belt():
		_update_belt_items()
		return
	if placed.is_machine():
		_label.text = _machine_text()
	else:
		_label.text = tr(placed.data.name_key)


## "Piedra 5 → 40 % → Grava 3"
func _machine_text() -> String:
	var recipe: RecipeData = placed.data.recipe
	var parts: PackedStringArray = []
	for item: ItemData in recipe.inputs:
		parts.append("%s %d" % [tr(item.name_key), placed.input.get_total(item)])
	parts.append("%d %%" % int(placed.progress / recipe.duration * 100.0))
	for item: ItemData in recipe.outputs:
		parts.append("%s %d" % [tr(item.name_key), placed.output.get_total(item)])
	var text: String = " → ".join(parts)
	if placed.data.power < 0.0 and island != null and not island.is_powered(placed.id):
		text += "  · " + tr("POWER_NO_POWER")
	return text


## Cinta: losa baja, flecha hacia la salida y un cubito por cada hueco de ítem.
func _setup_belt() -> void:
	collision_layer = BELT_COLLISION_LAYER
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, BELT_HEIGHT, 1.0)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = BELT_HEIGHT * 0.5
	add_child(collision)
	_add_box(Vector3(0.9, BELT_HEIGHT, 0.9), Vector3(0.0, BELT_HEIGHT * 0.5, 0.0), BELT_COLOR)

	# Dirección: hacia donde mira su puerto de salida.
	for port: PortData in placed.data.ports:
		if port.kind == PortData.Kind.OUTPUT:
			var offset: Vector2i = PortData.side_offset(port.get_grid_side(placed.rotation, placed.flipped))
			_belt_forward = Vector3(offset.x, 0.0, offset.y)
			break
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


## Coloca los cubitos según el avance de cada ítem en los datos (0 = detrás, 1 = delante).
func _update_belt_items() -> void:
	for i: int in _belt_cubes.size():
		var cube: MeshInstance3D = _belt_cubes[i]
		if i >= placed.belt_items.size():
			cube.visible = false
			continue
		var item: ItemData = placed.belt_items[i]
		cube.position = _belt_forward * (placed.belt_progress[i] - 0.5) + Vector3(0.0, BELT_HEIGHT + 0.125, 0.0)
		cube.material_override = _material_for(item)
		cube.visible = true


static func _material_for(item: ItemData) -> StandardMaterial3D:
	if not _item_materials.has(item):
		var material := StandardMaterial3D.new()
		material.albedo_color = item.color
		_item_materials[item] = material
	return _item_materials[item]


## E: avisa (señal `interacted`). Sobre un generador rearma el fusible de su red; sobre una máquina,
## hace el intercambio rápido provisional con el inventario del jugador.
func interact(by: Node) -> void:
	super(by)
	if placed.data.power > 0.0 and island != null:
		var network: PowerNetwork = island.get_network(placed.id)
		if network != null:
			network.reset_fuse() # si sigue sobrecargada, volverá a saltar en el siguiente paso
		return
	placed.quick_exchange(WorldState.player_inventory)


## Un cubito por puerto, pegado al borde de su casilla por el lado del puerto.
func _add_port_markers() -> void:
	for port: PortData in placed.data.ports:
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
