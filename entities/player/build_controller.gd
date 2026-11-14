class_name BuildController
extends Node3D
## Modo construcción sobre `IslandState` (B2.4b). Hijo del jugador.
## B entra y sale; R gira; F refleja (solo si cambia algo: `BuildingData.can_flip()`); clic izquierdo
## coloca en los DATOS de la isla y cobra del inventario de `WorldState`. Muestra un fantasma verde
## (cabe y hay materiales) o rojo, y un cubito por puerto en la casilla a la que apunta:
## azul = entrada, naranja = salida.
## No crea la construcción visible: eso lo hará la vista de la isla (B2.4c), escuchando a `IslandState`.

## Se emite al entrar o salir del modo construcción.
signal mode_changed(active: bool)
## Se emite al colocar una construcción.
signal placed(building: PlacedBuilding)
## Se emite si no se pudo colocar. `reason_key` es una clave de traducción ("BUILD_NO_ROOM"...).
signal place_failed(reason_key: String)

## Qué se construye (más adelante habrá una lista para elegir).
@export var building: BuildingData
## Isla de `WorldState` donde se construye.
@export var island_id: StringName = &"dev_sandbox"
## Alcance del rayo para apuntar al suelo (m).
@export var reach: float = 10.0

const COLOR_OK: Color = Color(0.2, 0.9, 0.3, 0.35)
const COLOR_BAD: Color = Color(0.95, 0.2, 0.2, 0.35)
const COLOR_INPUT: Color = Color(0.2, 0.5, 1.0)
const COLOR_OUTPUT: Color = Color(1.0, 0.55, 0.1)
## Altura del fantasma (provisional: aún no hay modelos).
const GHOST_HEIGHT: float = 1.0

var active: bool = false
## Cuartos de vuelta, sentido horario visto desde arriba.
var rotation_steps: int = 0
## Reflejo norte-sur (D-061).
var flipped: bool = false

var _ghost: MeshInstance3D
var _ghost_box: BoxMesh
var _ghost_material: StandardMaterial3D
var _input_material: StandardMaterial3D
var _output_material: StandardMaterial3D
var _port_markers: Array[MeshInstance3D] = []
var _has_target: bool = false
var _target_origin: Vector2i = Vector2i.ZERO


func _ready() -> void:
	top_level = true # el fantasma se coloca en coordenadas del mundo, no relativo al jugador
	_ghost_box = BoxMesh.new()
	_ghost_material = _make_material(COLOR_OK, true)
	_input_material = _make_material(COLOR_INPUT, false)
	_output_material = _make_material(COLOR_OUTPUT, false)
	_ghost = MeshInstance3D.new()
	_ghost.mesh = _ghost_box
	_ghost.material_override = _ghost_material
	add_child(_ghost)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if Aim.ui_open:
		return
	if event.is_action_pressed("toggle_build"):
		active = not active
		if not active:
			visible = false
		mode_changed.emit(active)
		return
	if not active:
		return
	if event.is_action_pressed("build_rotate"):
		rotation_steps = (rotation_steps + 1) % 4
	elif event.is_action_pressed("build_flip") and building != null and building.can_flip():
		flipped = not flipped
	elif event.is_action_pressed("build_place") and Aim.pointer_ready():
		_try_place()


func _process(_delta: float) -> void:
	if not active or building == null:
		visible = false
		_has_target = false
		return

	# Rayo desde el centro de la pantalla; solo vale suelo casi plano.
	var exclude: Array[RID] = []
	var body := get_parent() as CollisionObject3D
	if body != null:
		exclude.append(body.get_rid())
	var hit: Dictionary = Aim.from_screen_center(get_viewport(), reach, exclude)
	if hit.is_empty() or hit["normal"].y < 0.9:
		visible = false
		_has_target = false
		return

	# Casilla apuntada → origen de la huella, centrada en el puntero.
	var hit_pos: Vector3 = hit["position"]
	var s: Vector2i = OccupancyGrid.rotated_size(building.size, rotation_steps)
	_target_origin = GridMath.world_to_cell(hit_pos) - Vector2i(int((s.x - 1) / 2.0), int((s.y - 1) / 2.0))
	_has_target = true

	# Fantasma del tamaño de la huella girada, verde o rojo.
	_ghost_box.size = Vector3(s.x - 0.05, GHOST_HEIGHT, s.y - 0.05)
	_ghost.global_position = GridMath.footprint_center(_target_origin, building.size, rotation_steps, hit_pos.y + GHOST_HEIGHT * 0.5)
	if _can_place_here():
		_ghost_material.albedo_color = COLOR_OK
	else:
		_ghost_material.albedo_color = COLOR_BAD
	_update_port_markers(hit_pos.y)
	visible = true


## ¿Cabe aquí y tenemos los materiales?
func _can_place_here() -> bool:
	var island: IslandState = WorldState.get_island(island_id)
	return island.can_place(building, _target_origin, rotation_steps) and WorldState.player_inventory.has_items(building.cost)


## Un cubito por puerto en la casilla a la que apunta (sale de los datos: así se ve si R y F van bien).
func _update_port_markers(ground_y: float) -> void:
	while _port_markers.size() < building.ports.size():
		var marker := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = Vector3(0.3, 0.3, 0.3)
		marker.mesh = cube
		add_child(marker)
		_port_markers.append(marker)
	for i: int in _port_markers.size():
		var marker: MeshInstance3D = _port_markers[i]
		if i >= building.ports.size():
			marker.visible = false
			continue
		var port: PortData = building.ports[i]
		var cell: Vector2i = port.get_target_cell(_target_origin, building.size, rotation_steps, flipped)
		marker.global_position = GridMath.cell_center(cell, ground_y + 0.15)
		if port.kind == PortData.Kind.INPUT:
			marker.material_override = _input_material
		else:
			marker.material_override = _output_material
		marker.visible = true


## Coloca en los datos de la isla y cobra. Avisa con señales de lo que pasó.
func _try_place() -> void:
	if not _has_target:
		return
	var inventory: Inventory = WorldState.player_inventory
	if not inventory.has_items(building.cost):
		place_failed.emit("BUILD_NO_MATERIALS")
		return
	var result: PlacedBuilding = WorldState.get_island(island_id).place(building, _target_origin, rotation_steps, flipped and building.can_flip())
	if result == null:
		place_failed.emit("BUILD_NO_ROOM")
		return
	for item: ItemData in building.cost:
		inventory.remove_item(item, building.cost[item])
	placed.emit(result)


func _make_material(color: Color, transparent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
