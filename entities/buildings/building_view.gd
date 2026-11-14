class_name BuildingView
extends Interactable
## Pieza visible de una construcción colocada (B2.4c). Solo MUESTRA los datos de su `PlacedBuilding`
## (D-046): la crea y la borra `IslandView`. Si el `BuildingData` tiene `scene`, la usa girada y
## reflejada; si no, una caja provisional con un cubito por puerto (azul = entrada, naranja = salida).
## Encima, un texto flotante con el contenido y el progreso de la máquina, leído en cada fotograma.

const BODY_HEIGHT: float = 1.0
const BODY_COLOR: Color = Color(0.55, 0.5, 0.45)
const COLOR_INPUT: Color = Color(0.2, 0.5, 1.0)
const COLOR_OUTPUT: Color = Color(1.0, 0.55, 0.1)

## Construcción que muestra.
var placed: PlacedBuilding

var _label: Label3D


## Prepara la vista. Se llama ANTES de añadirla al árbol.
func setup(p_placed: PlacedBuilding) -> void:
	placed = p_placed
	name = "%s_%d" % [placed.data.id, placed.id]
	display_name_key = placed.data.name_key
	position = GridMath.footprint_center(placed.origin, placed.data.size, placed.rotation)
	var s: Vector2i = OccupancyGrid.rotated_size(placed.data.size, placed.rotation)

	# Colisión del tamaño de la huella girada: bloquea el paso y el rayo de interacción la encuentra.
	var shape := BoxShape3D.new()
	shape.size = Vector3(s.x, BODY_HEIGHT, s.y)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = BODY_HEIGHT * 0.5
	add_child(collision)

	if placed.data.scene != null:
		# Modelo real: primero se refleja (escala −1 en Z, norte ↔ sur) y luego se gira.
		var model := placed.data.scene.instantiate() as Node3D
		model.rotation.y = GridMath.rotation_to_yaw(placed.rotation)
		if placed.flipped:
			model.scale.z = -1.0
		add_child(model)
	else:
		_add_box(Vector3(s.x - 0.1, BODY_HEIGHT, s.y - 0.1), Vector3(0.0, BODY_HEIGHT * 0.5, 0.0), BODY_COLOR)
		_add_port_markers()

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # el texto ya va traducido
	_label.font_size = 40
	_label.outline_size = 8
	_label.position.y = BODY_HEIGHT + 0.5
	add_child(_label)


func _process(_delta: float) -> void:
	if placed == null:
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
	return " → ".join(parts)


## E: avisa (señal `interacted`) y hace el intercambio rápido provisional con el inventario del jugador.
func interact(by: Node) -> void:
	super(by)
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
