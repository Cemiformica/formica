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
const BAR_SIZE: int = 10 # teclas 1–9 y 0 (la décima, como en Satisfactory)
## Número de barras de construcción (C2.3, César): Mayús + rueda cambia de una a otra.
const BAR_COUNT: int = 5

## Barra de construcción en uso (10 casillas): `BuildingData`, `CableTool` o null (vacía). La primera de serie
## se pone en el Inspector; el catálogo (Q, C2.3) las cambia y se guardan en `WorldState.build_bars_ids`.
@export var build_bar: Array[Resource] = []
## Las 5 barras (C2.3); `build_bar` es siempre `bars[bar_index]`.
var bars: Array = []
var bar_index: int = 0
## Isla de `WorldState` donde se construye.
@export var island_id: StringName = &"dev_sandbox"
## Alcance del rayo para apuntar (m).
@export var reach: float = 10.0

const COLOR_OK: Color = Color(0.2, 0.9, 0.3, 0.35)
const COLOR_BAD: Color = Color(0.95, 0.2, 0.2, 0.35)
const COLOR_INPUT: Color = Color(0.2, 0.5, 1.0)
const COLOR_OUTPUT: Color = Color(1.0, 0.55, 0.1)
## Altura del fantasma de caja (para construcciones sin modelo).
const GHOST_HEIGHT: float = 1.0
const CABLE_PREVIEW_THICKNESS: float = 0.04
## Sonido al colocar (B5.4, de prueba: art/tools/make_sounds.py). Suena en 3D donde cae, por el bus «SFX».
const PLACE_SOUND: AudioStream = preload("res://assets/audio/build_place.wav")
## Acoples (B5.4): clic neumático cuando un puerto de lo colocado queda conectado (suena tras el golpe) y
## «blip» eléctrico al tender un cable.
const LINK_SOUND: AudioStream = preload("res://assets/audio/link_pneumatic.wav")
const CABLE_SOUND: AudioStream = preload("res://assets/audio/link_electric.wav")
const LINK_SOUND_DELAY: float = 0.3

## ¿Estamos en el modo construcción?
var active: bool = false
## Casilla elegida de la barra (0–8).
var selected_slot: int = 0
## Cuartos de vuelta, sentido horario visto desde arriba.
var rotation_steps: int = 0
## Reflejo norte-sur (D-061).
var flipped: bool = false
## Solo cajas logísticas (D-093): lado de la salida. 0 = recta, 1 = derecha, 2 = izquierda. F lo cambia.
var output_turn: int = 0

## Construcción cogida con el cuentagotas que no está en la barra (tiene prioridad sobre la casilla).
var _picked: BuildingData = null
## Mover (C2.5, César): construcción levantada con el clic derecho, la MISMA (con su contenido), sus cables
## y dónde estaba, para devolverla con otro clic derecho, al salir del modo o al guardar.
var _carried: PlacedBuilding = null
var _carried_cables: Array[Vector2i] = []
var _carried_origin: Vector2i = Vector2i.ZERO
var _carried_rotation: int = 0
var _carried_flipped: bool = false
var _carried_turn: int = 0
var _ghost: MeshInstance3D
var _ghost_box: BoxMesh
var _ghost_material: StandardMaterial3D
var _input_material: StandardMaterial3D
var _output_material: StandardMaterial3D
var _port_markers: Array[MeshInstance3D] = []
## Losas translúcidas que marcan el área de un talador en el fantasma (B2.7b).
var _area_markers: Array[MeshInstance3D] = []
var _area_material: StandardMaterial3D
var _has_target: bool = false
var _target_origin: Vector2i = Vector2i.ZERO
## Cable: id de la construcción donde empieza el cable que estamos tendiendo (0 = ninguno).
var _cable_from: int = 0
var _cable_preview: MeshInstance3D
var _cable_ok_material: StandardMaterial3D
var _cable_bad_material: StandardMaterial3D
## Fantasma con la forma del modelo (B3): la construcción y sus puertos, translúcidos en verde o rojo.
## `_ghost_model` va en el centro de la huella; dentro, `_ghost_body` (el modelo, girado y reflejado) y
## un puerto estándar por cada `PortData`. Se rehace solo al cambiar de construcción.
var _ghost_model: Node3D = null
var _ghost_body: Node3D = null
var _ghost_ports: Array[Node3D] = []
var _ghost_data: BuildingData = null


func _ready() -> void:
	top_level = true # el fantasma se coloca en coordenadas del mundo, no relativo al jugador
	# El fantasma y el cable provisional se mueven en cada fotograma: sin interpolación de la física
	# (si no, irían con retraso detrás del puntero).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_ghost_box = BoxMesh.new()
	_ghost_material = _make_material(COLOR_OK, true)
	_input_material = _make_material(COLOR_INPUT, false)
	_output_material = _make_material(COLOR_OUTPUT, false)
	_ghost = MeshInstance3D.new()
	_ghost.mesh = _ghost_box
	_ghost.material_override = _ghost_material
	add_child(_ghost)
	_area_material = _make_material(Color(1.0, 0.85, 0.2, 0.3), true)
	_cable_ok_material = _make_material(COLOR_OK, false)
	_cable_bad_material = _make_material(COLOR_BAD, false)
	_cable_preview = MeshInstance3D.new()
	_cable_preview.visible = false
	add_child(_cable_preview)
	# Al cargar una partida, un cable a medias apuntaría a una construcción que ya no es la misma (B5.2).
	WorldState.state_replaced.connect(func() -> void: _cable_from = 0)
	# Al cargar una partida, lo que se estaba moviendo ya no existe en el estado nuevo (C2.5).
	WorldState.state_replaced.connect(func() -> void:
		_carried = null
		_carried_cables.clear())
	WorldState.state_replaced.connect(_load_bar)
	build_bar.resize(BAR_SIZE)
	bars.append(build_bar)
	for i: int in BAR_COUNT - 1:
		var empty: Array[Resource] = []
		empty.resize(BAR_SIZE)
		bars.append(empty)
	_load_bar()
	visible = false


## Construcción que se lleva en la mano (null si ninguna o fuera del modo).
func get_held() -> BuildingData:
	if not active:
		return null
	if _carried != null:
		return _carried.data
	if _picked != null:
		return _picked
	if selected_slot < build_bar.size():
		return build_bar[selected_slot] as BuildingData # null si es el cable
	return null


## ¿Construcción cogida con el cuentagotas que no está en la barra? (la ayuda de teclas dice su nombre)
func is_held_picked() -> bool:
	return active and _picked != null


## ¿Hay un cable a medio tender (primer clic dado)?
func cable_started() -> bool:
	return holding_cable() and _cable_from != 0


## ¿Llevamos una construcción levantada para moverla?
func is_carrying() -> bool:
	return _carried != null


## Devuelve a su sitio lo que se está moviendo (al salir del modo, cambiar de casilla o guardar).
func cancel_carry() -> void:
	if _carried == null:
		return
	var island: IslandState = WorldState.get_island(island_id)
	var placed_back: PlacedBuilding = _carried
	_carried = null
	if island.drop(placed_back, _carried_origin, _carried_rotation, _carried_flipped, _carried_turn):
		for cable: Vector2i in _carried_cables:
			island.add_cable(cable.x, cable.y)
	else:
		# Muy raro: algo ocupó su sitio mientras se movía (una roca). Se devuelve como al desmontar.
		var refund: Dictionary[ItemData, int] = placed_back.get_refund()
		for item: ItemData in refund:
			WorldState.player_inventory.add_item(item, refund[item])
		push_warning("BuildController: no se pudo devolver %s a su sitio; se ha reembolsado" % placed_back.data.id)
	_carried_cables.clear()
	selection_changed.emit()


## ¿Llevamos el cable en la mano?
func holding_cable() -> bool:
	return active and _carried == null and _picked == null and selected_slot < build_bar.size() and build_bar[selected_slot] is CableTool


func _unhandled_input(event: InputEvent) -> void:
	if WindowManager.is_open():
		return
	if event.is_action_pressed("pick_building"):
		_pick_building()
		return
	if event.is_action_pressed("toggle_build"):
		_set_active(not active)
		if active:
			_face_player()
		return
	if not active:
		return
	# Clic derecho: levantar la construcción que miras para moverla, o devolverla si ya la llevas (C2.5).
	if event.is_action_pressed("build_move") and Aim.pointer_ready():
		if _carried != null:
			cancel_carry()
		else:
			_lift_aimed()
		return
	for i: int in BAR_SIZE:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			_select_slot(i)
			_face_player()
			return
	# Mayús + rueda: otra barra (C2.3, César).
	if Input.is_action_pressed("select_area") and (event.is_action_pressed("hotbar_next") or event.is_action_pressed("hotbar_prev")):
		switch_bar(1 if event.is_action_pressed("hotbar_next") else -1)
		return
	if event.is_action_pressed("hotbar_next"):
		_select_slot((selected_slot + 1) % BAR_SIZE)
		_face_player()
	elif event.is_action_pressed("hotbar_prev"):
		_select_slot(posmod(selected_slot - 1, BAR_SIZE))
		_face_player()
	elif holding_cable():
		if event.is_action_pressed("build_place") and Aim.pointer_ready():
			_cable_click()
		elif event.is_action_pressed("ui_cancel"):
			_cable_from = 0
	elif event.is_action_pressed("build_rotate"):
		rotation_steps = (rotation_steps + 1) % 4
	elif event.is_action_pressed("build_flip") and get_held() != null and get_held().output_turns:
		output_turn = (output_turn + 1) % 3 # recta → derecha → izquierda → recta (César)
	elif event.is_action_pressed("build_flip") and get_held() != null and get_held().can_flip():
		flipped = not flipped
	elif event.is_action_pressed("build_place") and Aim.pointer_ready():
		_try_place()


func _process(_delta: float) -> void:
	if holding_cable():
		_update_cable_preview()
		return
	_cable_preview.visible = false
	var building: BuildingData = get_held()
	if building == null:
		visible = false
		_has_target = false
		return

	# Rayo desde el centro de la pantalla; solo vale una superficie poco inclinada (las rampas de las
	# orillas del agua, unos 39°, también valen: así se puede apuntar al agua, D-094).
	var hit: Dictionary = _aim_hit()
	if hit.is_empty() or hit["normal"].y < 0.7:
		visible = false
		_has_target = false
		return

	# Casilla apuntada → origen de la huella, centrada en el puntero.
	var hit_pos: Vector3 = hit["position"]
	var s: Vector2i = OccupancyGrid.rotated_size(building.size, rotation_steps)
	_target_origin = GridMath.world_to_cell(hit_pos) - Vector2i(int((s.x - 1) / 2.0), int((s.y - 1) / 2.0))
	if not building.water_cells.is_empty():
		# Rueda hidráulica: la casilla apuntada es la del CENTRO de la rueda (la que va sobre el agua). Así,
		# apuntando al agua, R cambia la orilla de la dinamo sin tener que mover la mira (César).
		var anchor: Vector2i = building.water_cells[floori(building.water_cells.size() * 0.5)]
		_target_origin = GridMath.world_to_cell(hit_pos) - OccupancyGrid.local_to_cell(Vector2i.ZERO, building.size, rotation_steps, anchor)
	elif building.extract_time > 0.0:
		# Extractor: la casilla apuntada es la de la CABEZA (la que va sobre la veta).
		var head_offset: Vector2i = PlacedBuilding.head_cell_for(building, Vector2i.ZERO, rotation_steps)
		_target_origin = GridMath.world_to_cell(hit_pos) - head_offset
	_has_target = true

	# Fantasma: el modelo si lo tiene; si no, una caja del tamaño de la huella girada. Verde o rojo.
	if building.scene != null:
		_ghost.visible = false
		_update_ghost_model(building, hit_pos.y)
	else:
		if _ghost_model != null:
			_ghost_model.visible = false
		_ghost.visible = true
		_ghost_box.size = Vector3(s.x - 0.05, GHOST_HEIGHT, s.y - 0.05)
		_ghost.global_position = GridMath.footprint_center(_target_origin, building.size, rotation_steps, hit_pos.y + GHOST_HEIGHT * 0.5)
	if _can_place_here(building):
		_ghost_material.albedo_color = COLOR_OK
	else:
		_ghost_material.albedo_color = COLOR_BAD
	_update_port_markers(building, hit_pos.y)
	_update_area_markers(building, hit_pos.y)
	visible = true


## Fija `entry` (construcción o cable) en la casilla `slot` de la barra (catálogo, C2.3). Si ya estaba en otra
## casilla, esa queda vacía: cada cosa una sola vez en la barra.
func pin(slot: int, entry: Resource) -> void:
	if slot < 0 or slot >= BAR_SIZE or entry == null:
		return
	var old: int = build_bar.find(entry)
	if old >= 0:
		build_bar[old] = null
	build_bar[slot] = entry
	_store_bar()
	if _picked == entry:
		_picked = null
	selection_changed.emit()


## Coge `entry` para colocarla (clic en el catálogo, C2.3): si está en la barra, elige su casilla; si no, la
## lleva en la mano como el cuentagotas (el cable, que no puede ir así, se fija en la casilla elegida).
## Entra en el modo construcción si no estaba.
func pick(entry: Resource) -> void:
	cancel_carry()
	var index: int = build_bar.find(entry)
	if index >= 0:
		_select_slot(index)
	elif entry is BuildingData:
		_picked = entry
		_cable_from = 0
		selection_changed.emit()
	else:
		pin(selected_slot, entry)
		_select_slot(selected_slot)
	if not active:
		_set_active(true)
	_face_player()


## Vacía una casilla de la barra en uso (clic derecho sobre ella con el catálogo abierto).
func clear_slot(slot: int) -> void:
	if slot < 0 or slot >= BAR_SIZE:
		return
	build_bar[slot] = null
	_store_bar()
	selection_changed.emit()


## Pasa a la barra siguiente (+1) o anterior (−1), dando la vuelta (Mayús + rueda).
func switch_bar(step: int) -> void:
	cancel_carry()
	bar_index = posmod(bar_index + step, BAR_COUNT)
	build_bar = bars[bar_index]
	WorldState.build_bar_index = bar_index
	_picked = null
	_cable_from = 0
	selection_changed.emit()


func _store_bar() -> void:
	var all_ids: Array = []
	for bar: Array in bars:
		var ids: Array[String] = []
		for entry: Resource in bar:
			ids.append(String(entry.get("id")) if entry != null else "")
		all_ids.append(ids)
	WorldState.build_bars_ids = all_ids
	WorldState.build_bar_index = bar_index


## Pone las barras guardadas en la partida (si las hay; si no, se quedan las de serie).
func _load_bar() -> void:
	if WorldState.build_bars_ids.is_empty():
		return
	for b: int in BAR_COUNT:
		var ids: Array = WorldState.build_bars_ids[b] if b < WorldState.build_bars_ids.size() else []
		for i: int in BAR_SIZE:
			var id: String = str(ids[i]) if i < ids.size() else ""
			bars[b][i] = Content.find_buildable(StringName(id)) if id != "" else null
	bar_index = clampi(WorldState.build_bar_index, 0, BAR_COUNT - 1)
	build_bar = bars[bar_index]
	selection_changed.emit()


## Sale del modo construcción (lo usa el modo desmontar: los dos no pueden estar a la vez, C2.2).
func leave() -> void:
	if active:
		_set_active(false)


## Levanta la construcción que se mira: sale de la isla con su contenido, sin reembolso, y se lleva como
## fantasma con su giro. Se recuerdan sus cables y su sitio.
func _lift_aimed() -> void:
	var hit: Dictionary = _aim_hit()
	if hit.is_empty():
		return
	var view := hit["collider"] as BuildingView
	if view == null or view.placed == null:
		return
	var island: IslandState = WorldState.get_island(island_id)
	var target: PlacedBuilding = view.placed
	_carried_cables = island.cables_of(target.id)
	_carried_origin = target.origin
	_carried_rotation = target.rotation
	_carried_flipped = target.flipped
	_carried_turn = target.output_turn
	_picked = null
	_cable_from = 0
	_carried = island.remove(target.id)
	rotation_steps = _carried_rotation
	flipped = _carried_flipped
	output_turn = _carried_turn
	_play_sound(PLACE_SOUND, view.global_position)
	selection_changed.emit()


## Suelta lo que se está moviendo en el sitio apuntado: sin coste; recupera los cables que sigan llegando.
func _drop_carried() -> void:
	if not _has_target:
		return
	var island: IslandState = WorldState.get_island(island_id)
	var problem: String = island.placement_problem(_carried.data, _target_origin, rotation_steps)
	if problem != "":
		place_failed.emit(problem)
		return
	var moving: PlacedBuilding = _carried
	if not island.drop(moving, _target_origin, rotation_steps, flipped, output_turn):
		place_failed.emit("BUILD_NO_ROOM")
		return
	_carried = null
	var lost: int = 0
	for cable: Vector2i in _carried_cables:
		if not island.add_cable(cable.x, cable.y):
			lost += 1
	_carried_cables.clear()
	if lost > 0:
		place_failed.emit("BUILD_CABLES_LOST")
	_play_sound(PLACE_SOUND, BuildingView.cable_anchor(moving))
	_play_link_sounds(island, moving)
	selection_changed.emit()


func _set_active(value: bool) -> void:
	if not value:
		cancel_carry()
	active = value
	_cable_from = 0
	if not active:
		visible = false
	mode_changed.emit(active)


func _select_slot(index: int) -> void:
	cancel_carry()
	selected_slot = index
	_picked = null
	_cable_from = 0
	selection_changed.emit()


## Gira el fantasma para que su frente (la cara sur del modelo, la de la vista frontal de Blender) mire
## hacia el jugador. Así una cinta sale avanzando hacia donde miras y una placa solar te enseña el panel.
## Se usa al entrar en el modo y al elegir en la barra; el cuentagotas, en cambio, copia el giro.
func _face_player() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var toward_player: Vector3 = camera.global_basis.z # la cámara mira hacia −Z: +Z apunta al jugador
	var best: float = -INF
	for steps: int in 4:
		var yaw: float = GridMath.rotation_to_yaw(steps)
		var front := Vector3(sin(yaw), 0.0, cos(yaw)) # la cara sur (+Z) del modelo, girada
		var score: float = front.dot(toward_player)
		if score > best:
			best = score
			rotation_steps = steps
	var held: BuildingData = get_held()
	if held != null and held.extract_time > 0.0:
		# Extractor: al revés, la cola (con el almacén y la salida) hacia ti y la cabeza hacia la veta.
		rotation_steps = (rotation_steps + 2) % 4


## Cuentagotas: coge la construcción que miras. Si está en la barra, elige su casilla; si no, la lleva
## en la mano igualmente. Si no estabas en el modo construcción, entra.
func _pick_building() -> void:
	cancel_carry()
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
	output_turn = view.placed.output_turn # y el lado de la salida de una caja logística
	if not active:
		_set_active(true)


## ¿Cabe aquí y tenemos los materiales?
func _can_place_here(building: BuildingData) -> bool:
	var island: IslandState = WorldState.get_island(island_id)
	if _carried != null:
		return island.can_place(building, _target_origin, rotation_steps) # mover no cuesta nada
	return island.can_place(building, _target_origin, rotation_steps) and WorldState.player_inventory.has_items(building.cost)


## Rayo desde el centro de la pantalla, sin tocar al propio jugador.
func _aim_hit() -> Dictionary:
	var exclude: Array[RID] = []
	var body := get_parent() as CollisionObject3D
	if body != null:
		exclude.append(body.get_rid())
	return Aim.from_screen_center(get_viewport(), reach, exclude)


## Coloca el fantasma con forma de modelo en la huella apuntada, con el giro y el reflejo actuales.
func _update_ghost_model(building: BuildingData, ground_y: float) -> void:
	if _ghost_data != building:
		_build_ghost_model(building)
	_ghost_model.visible = true
	_ghost_model.global_position = GridMath.footprint_center(_target_origin, building.size, rotation_steps, ground_y)
	_ghost_body.rotation.y = GridMath.rotation_to_yaw(rotation_steps)
	if flipped:
		_ghost_body.scale.z = -1.0
	else:
		_ghost_body.scale.z = 1.0
	BuildingView.show_output_tunnel(_ghost_body, output_turn) # caja logística: el túnel del lado elegido
	var ghost_ports: Array[PortData] = building.ports_for(output_turn)
	for i: int in _ghost_ports.size():
		var port: PortData = ghost_ports[i]
		var cell: Vector2i = port.get_grid_cell(_target_origin, building.size, rotation_steps, flipped)
		_ghost_ports[i].global_position = GridMath.cell_center(cell, ground_y)
		_ghost_ports[i].rotation.y = GridMath.rotation_to_yaw(port.get_grid_side(rotation_steps, flipped))


## Crea el fantasma de una construcción: su modelo y sus puertos, todo con el material translúcido
## del fantasma, sin sombra y sin la lengüeta de cinta.
func _build_ghost_model(building: BuildingData) -> void:
	if _ghost_model != null:
		_ghost_model.queue_free()
	_ghost_model = Node3D.new()
	add_child(_ghost_model)
	_ghost_body = building.scene.instantiate() as Node3D
	_ghost_model.add_child(_ghost_body)
	_ghost_ports.clear()
	# Las cintas no llevan puertos estándar: encajan en los de las máquinas (B3.7).
	var port_list: Array[PortData] = building.ports
	if building.belt_speed > 0.0:
		port_list = []
	for port: PortData in port_list:
		var scene: PackedScene = BuildingView.PORT_INPUT_SCENE
		if port.kind == PortData.Kind.OUTPUT:
			scene = BuildingView.PORT_OUTPUT_SCENE
		var port_node := scene.instantiate() as Node3D
		_ghost_model.add_child(port_node)
		_ghost_ports.append(port_node)
	for node: Node in _ghost_model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.material_override = _ghost_material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mesh.name.begins_with("belt_tongue") or mesh.name.begins_with("belt_join"):
			mesh.visible = false
	_ghost_data = building


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
		var port: PortData = building.ports_for(output_turn)[i]
		var cell: Vector2i = port.get_target_cell(_target_origin, building.size, rotation_steps, flipped)
		marker.global_position = GridMath.cell_center(cell, ground_y + 0.15)
		if port.kind == PortData.Kind.INPUT:
			marker.material_override = _input_material
		else:
			marker.material_override = _output_material
		marker.visible = true


## Talador: una losa amarilla translúcida en cada casilla del área que talará (sale de los datos).
func _update_area_markers(building: BuildingData, ground_y: float) -> void:
	var cells: Array[Vector2i] = []
	if building.harvest_area.x > 0 and building.harvest_area.y > 0:
		cells = PlacedBuilding.harvest_cells_for(building, _target_origin, rotation_steps)
	while _area_markers.size() < cells.size():
		var marker := MeshInstance3D.new()
		var slab := BoxMesh.new()
		slab.size = Vector3(0.9, 0.04, 0.9)
		marker.mesh = slab
		marker.material_override = _area_material
		add_child(marker)
		_area_markers.append(marker)
	for i: int in _area_markers.size():
		var marker: MeshInstance3D = _area_markers[i]
		marker.visible = i < cells.size()
		if marker.visible:
			marker.global_position = GridMath.cell_center(cells[i], ground_y + 0.03)


## Coloca en los datos de la isla y cobra. Avisa con señales de lo que pasó.
func _try_place() -> void:
	if _carried != null:
		_drop_carried()
		return
	var building: BuildingData = get_held()
	if building == null or not _has_target:
		return
	var inventory: Inventory = WorldState.player_inventory
	if not inventory.has_items(building.cost):
		place_failed.emit("BUILD_NO_MATERIALS")
		return
	var island: IslandState = WorldState.get_island(island_id)
	var problem: String = island.placement_problem(building, _target_origin, rotation_steps)
	if problem != "":
		place_failed.emit(problem)
		return
	var result: PlacedBuilding = island.place(building, _target_origin, rotation_steps, flipped and building.can_flip(), output_turn)
	if result == null:
		place_failed.emit("BUILD_NO_ROOM")
		return
	for item: ItemData in building.cost:
		inventory.remove_item(item, building.cost[item])
	_play_sound(PLACE_SOUND, BuildingView.cable_anchor(result))
	_play_link_sounds(island, result)
	placed.emit(result)


## Un clic por cada puerto de `placed` que ha quedado conectado, en esa casilla, tras el golpe de colocar.
func _play_link_sounds(island: IslandState, placed_building: PlacedBuilding) -> void:
	for link: Dictionary in island.get_links():
		var port: PortData = null
		if link["from"] == placed_building:
			port = link["out"]
		elif link["to"] == placed_building:
			port = link["in"]
		if port == null:
			continue
		var cell: Vector2i = port.get_grid_cell(placed_building.origin, placed_building.data.size, placed_building.rotation, placed_building.flipped)
		var at := GridMath.cell_center(cell, 0.3)
		get_tree().create_timer(LINK_SOUND_DELAY).timeout.connect(_play_sound.bind(LINK_SOUND, at))


## Sonido de una sola vez en un punto del mundo, con un poco de variación de tono para que no canse.
func _play_sound(stream: AudioStream, at: Vector3) -> void:
	var sound := AudioStreamPlayer3D.new()
	sound.stream = stream
	sound.bus = &"SFX"
	sound.pitch_scale = randf_range(0.92, 1.08)
	get_tree().current_scene.add_child(sound)
	sound.global_position = at
	sound.finished.connect(sound.queue_free)
	sound.play()


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
	_play_sound(CABLE_SOUND, BuildingView.cable_anchor(target))
	cable_changed.emit(true)
	_cable_from = 0


## Cable provisional desde el inicio hasta lo que miramos: verde si se puede tender (o quitar), rojo si no.
func _update_cable_preview() -> void:
	_ghost.visible = false
	if _ghost_model != null:
		_ghost_model.visible = false
	for marker: MeshInstance3D in _port_markers:
		marker.visible = false
	for marker: MeshInstance3D in _area_markers:
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
