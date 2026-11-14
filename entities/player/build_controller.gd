class_name BuildController
extends Node3D
## Modo construcción (B2.4b, B2.5b; D-067), al estilo Satisfactory. Hijo del jugador.
## B entra y sale. Dentro, la barra de construcción (1–9 o rueda) elige qué colocar; al volver a
## entrar se recuerda lo último. R gira; F refleja (solo si cambia algo: `BuildingData.can_flip()`);
## clic izquierdo coloca en los DATOS de la isla y cobra el coste del inventario de `WorldState`.
## Botón central (cuentagotas): coge la construcción que miras y entra en el modo si no estabas.
## El fantasma es verde (cabe y hay materiales) o rojo, con un cubito por puerto (azul = entrada,
## naranja = salida). La construcción visible la crea la vista de la isla (`IslandView`).
## Con el **cable** (`CableTool`) en la mano (B2.6b, D-068): clic en una construcción eléctrica y clic en
## otra tiende un cable; si ya estaban unidas, lo quita. Un cable provisional verde o rojo sigue a la mira.

## Se emite al entrar o salir del modo construcción.
signal mode_changed(active: bool)
## Se emite al cambiar lo que se lleva en la mano (casilla de la barra o cuentagotas).
signal selection_changed
## Se emite al colocar una construcción.
signal placed(building: PlacedBuilding)
## Se emite si no se pudo colocar. `reason_key` es una clave de traducción ("BUILD_NO_ROOM"...).
signal place_failed(reason_key: String)
## Se emite al tender (true) o quitar (false) un cable.
signal cable_changed(added: bool)

## Número de casillas de la barra de construcción.
const BAR_SIZE: int = 9

## Barra de construcción (hasta 9): `BuildingData` o `CableTool`. Por ahora fija en el Inspector;
## el catálogo con Q llegará en la fase C.
@export var build_bar: Array[Resource] = []
## Isla de `WorldState` donde se construye.
@export var island_id: StringName = &"dev_sandbox"
## Alcance del rayo para apuntar (m).
@export var reach: float = 10.0

const COLOR_OK: Color = Color(0.2, 0.9, 0.3, 0.35)
const COLOR_BAD: Color = Color(0.95, 0.2, 0.2, 0.35)
const COLOR_INPUT: Color = Color(0.2, 0.5, 1.0)
const COLOR_OUTPUT: Color = Color(1.0, 0.55, 0.1)
## Altura del fantasma (provisional: aún no hay modelos).
const GHOST_HEIGHT: float = 1.0
const CABLE_PREVIEW_THICKNESS: float = 0.05

## ¿Estamos en el modo construcción?
var active: bool = false
## Casilla elegida de la barra (0–8).
var selected_slot: int = 0
## Cuartos de vuelta, sentido horario visto desde arriba.
var rotation_steps: int = 0
## Reflejo norte-sur (D-061).
var flipped: bool = false

## Construcción cogida con el cuentagotas que no está en la barra (tiene prioridad sobre la casilla).
var _picked: BuildingData = null
var _ghost: MeshInstance3D
var _ghost_box: BoxMesh
var _ghost_material: StandardMaterial3D
var _input_material: StandardMaterial3D
var _output_material: StandardMaterial3D
var _port_markers: Array[MeshInstance3D] = []
var _has_target: bool = false
var _target_origin: Vector2i = Vector2i.ZERO
## Cable: id de la construcción donde empieza el cable que estamos tendiendo (0 = ninguno).
var _cable_from: int = 0
var _cable_preview: MeshInstance3D
var _cable_ok_material: StandardMaterial3D
var _cable_bad_material: StandardMaterial3D


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
	_cable_ok_material = _make_material(COLOR_OK, false)
	_cable_bad_material = _make_material(COLOR_BAD, false)
	_cable_preview = MeshInstance3D.new()
	_cable_preview.visible = false
	add_child(_cable_preview)
	visible = false


## Construcción que se lleva en la mano (null si ninguna o fuera del modo).
func get_held() -> BuildingData:
	if not active:
		return null
	if _picked != null:
		return _picked
	if selected_slot < build_bar.size():
		return build_bar[selected_slot] as BuildingData # null si es el cable
	return null


## ¿Llevamos el cable en la mano?
func holding_cable() -> bool:
	return active and _picked == null and selected_slot < build_bar.size() and build_bar[selected_slot] is CableTool


func _unhandled_input(event: InputEvent) -> void:
	if Aim.ui_open:
		return
	if event.is_action_pressed("pick_building"):
		_pick_building()
		return
	if event.is_action_pressed("toggle_build"):
		_set_active(not active)
		return
	if not active:
		return
	for i: int in BAR_SIZE:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			_select_slot(i)
			return
	if event.is_action_pressed("hotbar_next"):
		_select_slot((selected_slot + 1) % BAR_SIZE)
	elif event.is_action_pressed("hotbar_prev"):
		_select_slot(posmod(selected_slot - 1, BAR_SIZE))
	elif holding_cable():
		if event.is_action_pressed("build_place") and Aim.pointer_ready():
			_cable_click()
		elif event.is_action_pressed("ui_cancel"):
			_cable_from = 0
	elif event.is_action_pressed("build_rotate"):
		rotation_steps = (rotation_steps + 1) % 4
	elif event.is_action_pressed("build_flip") and get_held() != null and get_held().can_flip():
		flipped = not flipped
	elif event.is_action_pressed("build_place") and Aim.pointer_ready():
		_try_place()


func _process(_delta: float) -> void:
	if holding_cable():
		_update_cable_preview()
		return
	_cable_preview.visible = false
	_ghost.visible = true
	var building: BuildingData = get_held()
	if building == null:
		visible = false
		_has_target = false
		return

	# Rayo desde el centro de la pantalla; solo vale una superficie casi plana.
	var hit: Dictionary = _aim_hit()
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
	if _can_place_here(building):
		_ghost_material.albedo_color = COLOR_OK
	else:
		_ghost_material.albedo_color = COLOR_BAD
	_update_port_markers(building, hit_pos.y)
	visible = true


func _set_active(value: bool) -> void:
	active = value
	_cable_from = 0
	if not active:
		visible = false
	mode_changed.emit(active)


func _select_slot(index: int) -> void:
	selected_slot = index
	_picked = null
	_cable_from = 0
	selection_changed.emit()


## Cuentagotas: coge la construcción que miras. Si está en la barra, elige su casilla; si no, la lleva
## en la mano igualmente. Si no estabas en el modo construcción, entra.
func _pick_building() -> void:
	var hit: Dictionary = _aim_hit()
	if hit.is_empty():
		return
	var view := hit["collider"] as BuildingView
	if view == null:
		return
	var data: BuildingData = view.placed.data
	var index: int = build_bar.find(data)
	if index >= 0:
		_select_slot(index)
	else:
		_picked = data
		_cable_from = 0
		selection_changed.emit()
	rotation_steps = view.placed.rotation # copia también el giro, como el cuentagotas de Satisfactory
	if not active:
		_set_active(true)


## ¿Cabe aquí y tenemos los materiales?
func _can_place_here(building: BuildingData) -> bool:
	var island: IslandState = WorldState.get_island(island_id)
	return island.can_place(building, _target_origin, rotation_steps) and WorldState.player_inventory.has_items(building.cost)


## Rayo desde el centro de la pantalla, sin tocar al propio jugador.
func _aim_hit() -> Dictionary:
	var exclude: Array[RID] = []
	var body := get_parent() as CollisionObject3D
	if body != null:
		exclude.append(body.get_rid())
	return Aim.from_screen_center(get_viewport(), reach, exclude)


## Un cubito por puerto en la casilla a la que apunta (sale de los datos: así se ve si R y F van bien).
func _update_port_markers(building: BuildingData, ground_y: float) -> void:
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
	var building: BuildingData = get_held()
	if building == null or not _has_target:
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


# --- Cable (B2.6b) ---

## Construcción que miramos, o null.
func _aimed_building() -> PlacedBuilding:
	var hit: Dictionary = _aim_hit()
	if hit.is_empty():
		return null
	var view := hit["collider"] as BuildingView
	if view == null:
		return null
	return view.placed


## Primer clic: elige dónde empieza el cable. Segundo clic: lo tiende (o lo quita si ya estaban unidas).
func _cable_click() -> void:
	var island: IslandState = WorldState.get_island(island_id)
	var target: PlacedBuilding = _aimed_building()
	if target == null:
		return
	if _cable_from == 0 or not island.buildings.has(_cable_from):
		if target.data.power_connections <= 0:
			place_failed.emit("CABLE_NO_CONNECTOR")
			return
		_cable_from = target.id
		return
	if target.id == _cable_from:
		_cable_from = 0 # clic en la misma: cancelar
		return
	if island.remove_cable(_cable_from, target.id):
		cable_changed.emit(false)
		_cable_from = 0
		return
	var problem: String = island.cable_problem(_cable_from, target.id)
	if problem != "":
		place_failed.emit(problem)
		return
	island.add_cable(_cable_from, target.id)
	cable_changed.emit(true)
	_cable_from = 0


## Cable provisional desde el inicio hasta lo que miramos: verde si se puede tender (o quitar), rojo si no.
func _update_cable_preview() -> void:
	_ghost.visible = false
	for marker: MeshInstance3D in _port_markers:
		marker.visible = false
	var island: IslandState = WorldState.get_island(island_id)
	if _cable_from == 0 or not island.buildings.has(_cable_from):
		_cable_preview.visible = false
		visible = true
		return
	var from: Vector3 = BuildingView.cable_anchor(island.buildings[_cable_from])
	var to: Vector3
	var ok: bool = false
	var target: PlacedBuilding = _aimed_building()
	if target != null and target.id != _cable_from:
		to = BuildingView.cable_anchor(target)
		ok = island.cable_problem(_cable_from, target.id) == "" or island.cables.has(Vector2i(mini(_cable_from, target.id), maxi(_cable_from, target.id)))
	else:
		var hit: Dictionary = _aim_hit()
		if hit.is_empty():
			to = from + (-get_viewport().get_camera_3d().global_basis.z) * 3.0
		else:
			to = hit["position"]
		ok = from.distance_to(to) <= IslandState.MAX_CABLE_LENGTH
	visible = true
	_cable_preview.visible = true
	IslandView.place_line(_cable_preview, from, to, CABLE_PREVIEW_THICKNESS)
	if ok:
		_cable_preview.material_override = _cable_ok_material
	else:
		_cable_preview.material_override = _cable_bad_material


func _make_material(color: Color, transparent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
