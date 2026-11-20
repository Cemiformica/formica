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
## Mover (C2b, César): sonidos propios para levantar y soltar (art/tools/make_sounds.py) y la construcción en
## la mano con sus colores, levantada y balanceándose; teñida de rojo si ahí no cabe.
const LIFT_SOUND: AudioStream = preload("res://assets/audio/move_lift.wav")
const DROP_SOUND: AudioStream = preload("res://assets/audio/move_drop.wav")
const CARRY_HEIGHT: float = 0.2
const CARRY_BOB: float = 0.03
## Construir cintas arrastrando (C2b, como en Alchemy Factory): tope de casillas por tramo.
const DRAG_MAX_CELLS: int = 64
enum DragCell { OK, EXISTING_BELT, BLOCKED, NO_MATERIALS }

## ¿Estamos en el modo construcción?
var active: bool = false
## Casilla elegida de la barra (0–8).
var selected_slot: int = 0
## Cuartos de vuelta, sentido horario visto desde arriba.
var rotation_steps: int = 0
## Último giro de cada construcción (César, 2026-11-19): al volver a elegirla sale con él. La primera vez, mirando
## hacia el jugador (`_face_player()`).
var _rotation_by_building: Dictionary[BuildingData, int] = {}
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
## Cuáles de esos cables eran tensos, para devolverlos igual.
var _carried_taut_cables: Array[Vector2i] = []
var _carried_origin: Vector2i = Vector2i.ZERO
var _carried_rotation: int = 0
var _carried_flipped: bool = false
var _carried_turn: int = 0
var _ghost: MeshInstance3D
var _ghost_box: BoxMesh
var _ghost_material: StandardMaterial3D
var _input_material: StandardMaterial3D
## Flecha de los puertos del fantasma (una malla para todas, apunta hacia −Z).
var _arrow_mesh: ArrayMesh = null
const ARROW_DISTANCE: float = 0.78
const ARROW_HEIGHT: float = 0.06
const ARROW_SLIDE: float = 0.14
const ARROW_SLIDE_TIME: float = 0.9
var _output_material: StandardMaterial3D
var _port_markers: Array[MeshInstance3D] = []
## Losas translúcidas que marcan el área de un talador en el fantasma (B2.7b).
var _area_markers: Array[MeshInstance3D] = []
var _area_material: StandardMaterial3D
var _has_target: bool = false
var _target_origin: Vector2i = Vector2i.ZERO
## Cable: id de la construcción donde empieza el cable que estamos tendiendo (0 = ninguno).
var _cable_from: int = 0
## Modo del cable que se tiende (César): normal, con su comba, o tenso (recto). F lo cambia y se recuerda,
## como el giro de cada construcción (D-164).
var cable_taut: bool = false
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
## ¿Es el fantasma de algo que se mueve? (entonces lleva sus colores, no el material translúcido)
var _ghost_carried: bool = false
var _ghost_meshes: Array[MeshInstance3D] = []
var _carry_blocked_material: StandardMaterial3D
## Arrastrar cintas (C2b; revisado en C3 con lo que César averiguó de Alchemy Factory): pulsar fija el
## principio (`_drag_start`) y soltar construye. El tramo va del principio a la casilla apuntada en **L**:
## primero por el eje en que más se ha movido el ratón y después un solo giro (R invierte el orden de la L),
## así que es siempre una línea seguida, sin zigzags ni tramos pegados. Se puede cruzar en recto una cinta
## que ya está (su fantasma enseña el cruce); un giro sobre una cinta, una cinta en sentido contrario o un
## obstáculo cortan el tramo: desde ahí todo sale en rojo y no se construye. Un fantasma por casilla.
var _drag_active: bool = false
var _drag_start: Vector2i = Vector2i.ZERO
var _drag_cells: Array[Vector2i] = []
var _drag_rotations: Array[int] = []
var _drag_states: Array[DragCell] = []
var _drag_flip: bool = false   # R mientras se arrastra: la L empieza por el otro eje
## Si el tramo acaba apuntando a una construcción o a una cinta (C3, César): la última cinta mira hacia
## ella para conectarse justo ahí (un puerto concreto, o una cinta para hacer una T).
var _drag_into: bool = false
var _drag_into_step: Vector2i = Vector2i.ZERO
var _drag_ground_y: float = 0.0
## Fantasmas del tramo: vistas de cinta de verdad (sin colisión y translúcidas) sobre una isla de prueba
## con el tramo y lo que lo rodea, para que cada una enseñe su forma real (recta, curva o cruce). Se
## rehacen solo cuando cambia el tramo; las que no cambian de casilla ni de giro se reutilizan.
var _drag_views: Dictionary[String, BuildingView] = {}
var _drag_view_at: Array = []
var _drag_preview_key: String = ""
## Fantasma de las bocas de un cruce sobre una cinta que ya existe (C5.3d, César): solo la parte de fuera de las
## paredes de esa cinta (desde CROSS_KEEP_FROM del centro de la casilla hasta su borde), para no pintar encima.
## Las paredes y los remaches de la cinta llegan a 0,387 m del centro (`conveyor.blend`).
const CROSS_KEEP_FROM: float = 0.39
const CROSS_SHADER_CODE: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;
uniform vec4 color : source_color;
uniform vec3 cell_center;
uniform vec2 axis;
uniform float keep_from;
varying vec3 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	if (abs(dot(world_pos.xz - cell_center.xz, axis)) < keep_from) {
		discard;
	}
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
"""
var _cross_shader: Shader = null
var _drag_ok_material: StandardMaterial3D
var _drag_bad_material: StandardMaterial3D


func _ready() -> void:
	top_level = true # el fantasma se coloca en coordenadas del mundo, no relativo al jugador
	# El fantasma y el cable provisional se mueven en cada fotograma: sin interpolación de la física
	# (si no, irían con retraso detrás del puntero).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_ghost_box = BoxMesh.new()
	_ghost_material = _make_material(COLOR_OK, true)
	_input_material = _make_material(COLOR_INPUT, false)
	_output_material = _make_material(COLOR_OUTPUT, false)
	_input_material.cull_mode = BaseMaterial3D.CULL_DISABLED # las flechas se ven por las dos caras
	_output_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost = MeshInstance3D.new()
	_ghost.mesh = _ghost_box
	_ghost.material_override = _ghost_material
	add_child(_ghost)
	_area_material = _make_material(Color(1.0, 0.85, 0.2, 0.3), true)
	_carry_blocked_material = _make_material(COLOR_BAD, true)
	_drag_ok_material = _make_material(COLOR_OK, true)
	_drag_bad_material = _make_material(COLOR_BAD, true)
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
	# Un tramo de cintas a medias también se cancela (al salir, cambiar de casilla, cuentagotas…).
	if _drag_active:
		_cancel_drag()
	if _carried == null:
		return
	var island: IslandState = WorldState.get_island(island_id)
	var placed_back: PlacedBuilding = _carried
	_carried = null
	if island.drop(placed_back, _carried_origin, _carried_rotation, _carried_flipped, _carried_turn):
		for cable: Vector2i in _carried_cables:
			island.add_cable(cable.x, cable.y, _carried_taut_cables.has(cable))
	else:
		# Muy raro: algo ocupó su sitio mientras se movía (una roca). Se devuelve como al desmontar.
		var refund: Dictionary[ItemData, int] = placed_back.get_refund()
		for item: ItemData in refund:
			WorldState.player_inventory.add_item(item, refund[item])
		push_warning("BuildController: no se pudo devolver %s a su sitio; se ha reembolsado" % placed_back.data.id)
	_carried_cables.clear()
	_carried_taut_cables.clear()
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
			_restore_rotation()
		return
	if not active:
		return
	# Arrastrando cintas: soltar construye; clic derecho o Esc cancelan.
	if _drag_active:
		if event.is_action_released("build_place"):
			_finish_drag()
		elif event.is_action_pressed("build_move") or event.is_action_pressed("ui_cancel"):
			_cancel_drag()
		elif event.is_action_pressed("build_rotate"):
			_drag_flip = not _drag_flip
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
			_restore_rotation()
			return
	# Ctrl + rueda: otra barra (C2.3; antes Mayús + rueda, cambiado a petición de César).
	if Input.is_action_pressed("bar_switch") and (event.is_action_pressed("hotbar_next") or event.is_action_pressed("hotbar_prev")):
		switch_bar(1 if event.is_action_pressed("hotbar_next") else -1)
		return
	if event.is_action_pressed("hotbar_next"):
		_select_slot((selected_slot + 1) % BAR_SIZE)
		_restore_rotation()
	elif event.is_action_pressed("hotbar_prev"):
		_select_slot(posmod(selected_slot - 1, BAR_SIZE))
		_restore_rotation()
	elif holding_cable():
		if event.is_action_pressed("build_place") and Aim.pointer_ready():
			_cable_click()
		elif event.is_action_pressed("build_flip"):
			_toggle_cable_taut()
		elif event.is_action_pressed("ui_cancel"):
			_cable_from = 0
	elif event.is_action_pressed("build_rotate"):
		rotation_steps = (rotation_steps + 1) % 4
	elif event.is_action_pressed("build_flip") and get_held() != null and get_held().output_turns:
		output_turn = (output_turn + 1) % BuildingData.TURN_COUNT # las 9 combinaciones de entrada y salida (C2b, César)
	elif event.is_action_pressed("build_flip") and get_held() != null and get_held().can_flip():
		flipped = not flipped
	elif event.is_action_pressed("build_place") and Aim.pointer_ready():
		var held: BuildingData = get_held()
		if _carried == null and held != null and held.belt_speed > 0.0 and _has_target:
			_start_drag()
		else:
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
	if _carried == null:
		_rotation_by_building[building] = rotation_steps # R y el cuentagotas también cuentan

	# Rayo desde el centro de la pantalla; solo vale una superficie poco inclinada (las rampas de las
	# orillas del agua, unos 39°, también valen: así se puede apuntar al agua, D-094).
	var hit: Dictionary = _aim_hit()
	# Arrastrando una cinta, apuntar a una construcción o a una cinta (también a su costado) elige a qué se
	# conecta el final del tramo: la casilla apuntada es la de dentro de lo que se mira (C3, César).
	if _drag_active and not hit.is_empty() and hit["collider"] is BuildingView:
		var inside: Vector3 = hit["position"] - hit["normal"] * 0.1
		_target_origin = GridMath.world_to_cell(inside)
		_has_target = true
		_update_drag(building, _drag_ground_y)
		_ghost.visible = false
		if _ghost_model != null:
			_ghost_model.visible = false
		for marker: MeshInstance3D in _port_markers:
			marker.visible = false
		visible = true
		return
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
	# Altura: la de la casilla donde quedará la construcción, no la del punto apuntado (C5.3d, César: el fantasma
	# salía hundido o levantado según dónde apuntaras, en la orilla o sobre otra construcción).
	var ground_y: float = WorldState.get_island(island_id).ground_y_for(building, _target_origin, rotation_steps)
	if _drag_active:
		_drag_ground_y = ground_y
		_update_drag(building, ground_y)
		_ghost.visible = false
		if _ghost_model != null:
			_ghost_model.visible = false
		for marker: MeshInstance3D in _port_markers:
			marker.visible = false
		visible = true
		return

	# Fantasma: el modelo si lo tiene; si no, una caja del tamaño de la huella girada. Verde o rojo.
	if building.scene != null:
		_ghost.visible = false
		_update_ghost_model(building, ground_y)
	else:
		if _ghost_model != null:
			_ghost_model.visible = false
		_ghost.visible = true
		_ghost_box.size = Vector3(s.x - 0.05, GHOST_HEIGHT, s.y - 0.05)
		_ghost.global_position = GridMath.footprint_center(_target_origin, building.size, rotation_steps, ground_y + GHOST_HEIGHT * 0.5)
	var can_place: bool = _can_place_here(building)
	if can_place:
		_ghost_material.albedo_color = COLOR_OK
	else:
		_ghost_material.albedo_color = COLOR_BAD
	if _ghost_carried:
		for mesh: MeshInstance3D in _ghost_meshes:
			mesh.material_overlay = null if can_place else _carry_blocked_material
	_update_port_markers(building, ground_y)
	_update_area_markers(building, ground_y)
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
	_restore_rotation()


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
	_carried_taut_cables.clear()
	for cable: Vector2i in _carried_cables:
		if island.taut_cables.has(cable):
			_carried_taut_cables.append(cable)
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
	_play_sound(LIFT_SOUND, view.global_position)
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
		if not island.add_cable(cable.x, cable.y, _carried_taut_cables.has(cable)):
			lost += 1
	_carried_cables.clear()
	_carried_taut_cables.clear()
	if lost > 0:
		place_failed.emit("BUILD_CABLES_LOST")
	_play_sound(DROP_SOUND, BuildingView.cable_anchor(moving))
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
## Al elegir una construcción: su último giro si ya se usó; si no, mirando hacia el jugador.
func _restore_rotation() -> void:
	var held: BuildingData = get_held()
	if held != null and _rotation_by_building.has(held):
		rotation_steps = _rotation_by_building[held]
	else:
		_face_player()


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
	var carrying: bool = _carried != null
	if _ghost_data != building or _ghost_carried != carrying:
		_build_ghost_model(building, carrying)
	_ghost_model.visible = true
	# La rueda del fantasma, hundida como la de verdad (`BuildingView.WHEEL_DIP`), una sola vez por modelo.
	if not building.water_cells.is_empty():
		var wheel := _ghost_model.find_child("wheel_pivot", true, false) as Node3D
		if wheel != null and not wheel.has_meta(&"dipped"):
			wheel.position.y -= BuildingView.WHEEL_DIP
			wheel.set_meta(&"dipped", true)
	var lift: float = 0.0
	if carrying:
		lift = CARRY_HEIGHT + sin(Time.get_ticks_msec() * 0.004) * CARRY_BOB
	_ghost_model.global_position = GridMath.footprint_center(_target_origin, building.size, rotation_steps, ground_y + lift)
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
		_ghost_ports[i].global_position = GridMath.cell_center(cell, ground_y + lift)
		_ghost_ports[i].rotation.y = GridMath.rotation_to_yaw(port.get_grid_side(rotation_steps, flipped))


## Crea el fantasma de una construcción: su modelo y sus puertos, todo con el material translúcido
## del fantasma, sin sombra y sin la lengüeta de cinta. Si se está moviendo (`carried`, C2b), con sus
## colores y su sombra.
func _build_ghost_model(building: BuildingData, carried: bool = false) -> void:
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
	_ghost_meshes.clear()
	for node: Node in _ghost_model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		_ghost_meshes.append(mesh)
		if not carried:
			mesh.material_override = _ghost_material
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mesh.name.begins_with("belt_tongue") or mesh.name.begins_with("belt_join"):
			mesh.visible = false
		# Cinta (C2b): en el fantasma, siempre recta (sin curvas ni cruce).
		if mesh.name.begins_with("belt_corner") or mesh.name.begins_with("belt_hub"):
			mesh.visible = false
	_ghost_data = building
	_ghost_carried = carried


## Una flecha plana por puerto, justo fuera de su lado (César, 2026-11-19: en lugar de cubitos): hacia dentro en las
## entradas y hacia fuera en las salidas, y se desliza un poco en su sentido. Sale de los datos: así se ve si R y F
## van bien.
func _update_port_markers(building: BuildingData, ground_y: float) -> void:
	if _arrow_mesh == null:
		_arrow_mesh = _make_arrow_mesh()
	while _port_markers.size() < building.ports.size():
		var marker := MeshInstance3D.new()
		marker.mesh = _arrow_mesh
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(marker)
		_port_markers.append(marker)
	var slide: float = fmod(Time.get_ticks_msec() / 1000.0, ARROW_SLIDE_TIME) / ARROW_SLIDE_TIME * ARROW_SLIDE
	for i: int in _port_markers.size():
		var marker: MeshInstance3D = _port_markers[i]
		if i >= building.ports.size():
			marker.visible = false
			continue
		var port: PortData = building.ports_for(output_turn)[i]
		var port_cell: Vector2i = port.get_grid_cell(_target_origin, building.size, rotation_steps, flipped)
		var out: Vector2i = PortData.side_offset(port.get_grid_side(rotation_steps, flipped))
		var outward := Vector3(out.x, 0.0, out.y)
		var pointing: Vector3 = outward if port.kind == PortData.Kind.OUTPUT else -outward
		# El centro de la flecha, a ARROW_DISTANCE del centro de la casilla del puerto (justo fuera de su lado).
		var center: Vector3 = GridMath.cell_center(port_cell, ground_y + ARROW_HEIGHT) + outward * ARROW_DISTANCE
		marker.global_transform = Transform3D(Basis.looking_at(pointing), center + pointing * (slide - ARROW_SLIDE * 0.5))
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
		var at := GridMath.cell_center(cell, placed_building.ground_y + 0.3)
		get_tree().create_timer(LINK_SOUND_DELAY).timeout.connect(_play_sound.bind(LINK_SOUND, at))


# --- Construir cintas arrastrando (C2b) ---

## ¿Se está arrastrando un tramo de cintas? Y cuántas se pondrían al soltar (para la ayuda de teclas).
func is_dragging() -> bool:
	return _drag_active


func drag_count() -> int:
	return _drag_states.count(DragCell.OK)


func _start_drag() -> void:
	_drag_active = true
	_drag_start = _target_origin
	_drag_cells = [_drag_start]
	_drag_rotations = [rotation_steps]
	_drag_states = []
	_drag_flip = false
	_drag_into = false


func _cancel_drag() -> void:
	_drag_active = false
	for view: BuildingView in _drag_views.values():
		view.queue_free()
	_drag_views.clear()
	_drag_view_at.clear()
	_drag_preview_key = ""


## Tramo en L del principio a `to`: por el eje dominante (o el otro, con R) y un solo giro. Se recalcula
## entero en cada movimiento. Cada cinta mira hacia la siguiente; la última, en la dirección del último
## paso. Sin moverse, una sola cinta con el giro elegido con R.
func _drag_path(to: Vector2i) -> void:
	_drag_cells = [_drag_start]
	var delta: Vector2i = to - _drag_start
	var x_first: bool = absi(delta.x) >= absi(delta.y)
	if _drag_flip:
		x_first = not x_first
	var legs: Array[Vector2i] = [Vector2i(delta.x, 0), Vector2i(0, delta.y)]
	if not x_first:
		legs.reverse()
	var last: Vector2i = _drag_start
	for leg: Vector2i in legs:
		var step := Vector2i(signi(leg.x), signi(leg.y))
		for _k: int in absi(leg.x) + absi(leg.y):
			if _drag_cells.size() >= DRAG_MAX_CELLS:
				break
			last += step
			_drag_cells.append(last)
	# Si la casilla final está ocupada (una máquina o una cinta), no se construye ahí: la cinta anterior
	# mira hacia ella y se conecta justo con eso.
	_drag_into = false
	if _drag_cells.size() >= 2 and WorldState.get_island(island_id).get_at(_drag_cells[_drag_cells.size() - 1]) != null:
		var target: Vector2i = _drag_cells.pop_back()
		_drag_into = true
		_drag_into_step = target - _drag_cells[_drag_cells.size() - 1]
	_drag_rotations.clear()
	if _drag_cells.size() == 1:
		_drag_rotations.append(_rotation_for_step(_drag_into_step) if _drag_into else rotation_steps)
		return
	for i: int in _drag_cells.size():
		var step: Vector2i
		if i + 1 < _drag_cells.size():
			step = _drag_cells[i + 1] - _drag_cells[i]
		elif _drag_into:
			step = _drag_into_step
		else:
			step = _drag_cells[i] - _drag_cells[i - 1]
		_drag_rotations.append(_rotation_for_step(step))


## Giro de la cuadrícula para mirar hacia `step`: norte 0, este 1, sur 2, oeste 3.
static func _rotation_for_step(step: Vector2i) -> int:
	if step.y < 0:
		return 0
	if step.x > 0:
		return 1
	if step.y > 0:
		return 2
	return 3


## Rehace el tramo y sus fantasmas: verde si se puede poner; rojo si está ocupado o ya no llegan los
## materiales; sin fantasma si ahí ya hay una cinta (se respeta y la nueva se empalma con ella).
func _update_drag(building: BuildingData, _ground_y: float) -> void:   # cada cinta toma la altura de su casilla
	_drag_path(_target_origin)
	var island: IslandState = WorldState.get_island(island_id)
	var inventory: Inventory = WorldState.player_inventory
	var affordable: int = DRAG_MAX_CELLS
	for item: ItemData in building.cost:
		affordable = mini(affordable, floori(float(inventory.get_total(item)) / building.cost[item]))
	_drag_states.clear()
	var used: int = 0
	var cut: bool = false   # tras el primer obstáculo, todo lo que sigue sale en rojo y no se construye
	for i: int in _drag_cells.size():
		var cell: Vector2i = _drag_cells[i]
		var existing: PlacedBuilding = island.get_at(cell)
		var state: DragCell = DragCell.OK
		if cut:
			state = DragCell.BLOCKED
		elif existing != null and existing.is_belt():
			state = DragCell.EXISTING_BELT if _can_cross(existing, i) else DragCell.BLOCKED
		elif not island.can_place(building, cell, _drag_rotations[i]):
			state = DragCell.BLOCKED
		elif used >= affordable:
			state = DragCell.NO_MATERIALS
		else:
			used += 1
		if state == DragCell.BLOCKED and i > 0:
			cut = true
		_drag_states.append(state)
	var key: String = "%s|%s|%s" % [str(_drag_cells), str(_drag_rotations), str(_drag_states)]
	if key != _drag_preview_key:
		_drag_preview_key = key
		_rebuild_drag_preview(building, island)
	for i: int in _drag_view_at.size():
		var view: BuildingView = _drag_view_at[i]
		if view == null:
			continue
		# En coordenadas del mundo y sin heredar giro: este nodo es `top_level`, pero conserva el sitio y el giro
		# que tenía el jugador al empezar, y la vista se coloca relativa a su padre.
		# Cada cinta del tramo, a la altura de su casilla (el tramo es del mismo nivel: si cambia, se corta).
		var cell_y: float = WorldState.get_island(island_id).ground_height(_drag_cells[i])
		view.global_transform = Transform3D(Basis.IDENTITY, GridMath.cell_center(_drag_cells[i], cell_y))
		var ok: bool = _drag_states[i] == DragCell.OK or _drag_states[i] == DragCell.EXISTING_BELT
		var material: Material = _drag_ok_material if ok else _drag_bad_material
		if _drag_states[i] == DragCell.EXISTING_BELT:
			material = _crossing_material(view, _drag_rotations[i])
		for node: Node in view.find_children("*", "MeshInstance3D", true, false):
			(node as MeshInstance3D).material_override = material


## ¿Puede el tramo pasar por la cinta `existing` (casilla `i` del tramo)? Al principio o al final del tramo,
## sí (se empalma con ella). En medio, solo en recto (sin girar encima) y sin ir en sentido contrario a ella:
## así una cinta nunca recibe dos entradas raras del mismo arrastre (César).
func _can_cross(existing: PlacedBuilding, i: int) -> bool:
	if i == 0 or i == _drag_cells.size() - 1:
		return true
	var step_in: Vector2i = _drag_cells[i] - _drag_cells[i - 1]
	var step_out: Vector2i = _drag_cells[i + 1] - _drag_cells[i]
	if step_in != step_out:
		return false
	return existing.rotation != (_rotation_for_step(step_in) + 2) % 4


## Isla de prueba con lo que rodea el tramo y las cintas que se pondrían (también las rojas por falta de
## materiales, para que la forma sea la que tendrá), y una vista por cinta que calcula su forma con ella.
func _rebuild_drag_preview(building: BuildingData, island: IslandState) -> void:
	var preview := IslandState.new()
	var planned: Dictionary[Vector2i, bool] = {}
	for i: int in _drag_cells.size():
		if _drag_states[i] == DragCell.OK or _drag_states[i] == DragCell.NO_MATERIALS:
			planned[_drag_cells[i]] = true
	var copied: Dictionary[int, PlacedBuilding] = {}
	for cell: Vector2i in _drag_cells:
		for offset: Vector2i in [Vector2i.ZERO, Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var neighbor: PlacedBuilding = island.get_at(cell + offset)
			if neighbor != null and not copied.has(neighbor.id):
				copied[neighbor.id] = preview.add_for_preview(neighbor.data, neighbor.origin, neighbor.rotation,
						neighbor.flipped, neighbor.output_turn)
	var preview_belts: Array = []
	preview_belts.resize(_drag_cells.size())
	for i: int in _drag_cells.size():
		if planned.has(_drag_cells[i]):
			preview_belts[i] = preview.add_for_preview(building, _drag_cells[i], _drag_rotations[i])
		elif _drag_states[i] == DragCell.EXISTING_BELT:
			# Cinta que ya está y que el tramo cruza: su fantasma enseña cómo quedará (el cruce) (César).
			var existing: PlacedBuilding = island.get_at(_drag_cells[i])
			if existing != null:
				preview_belts[i] = copied.get(existing.id)
	preview.get_links()
	var views: Dictionary[String, BuildingView] = {}
	_drag_view_at.clear()
	_drag_view_at.resize(_drag_cells.size())
	for i: int in _drag_cells.size():
		if preview_belts[i] == null:
			continue
		var view_key: String = "%d,%d,%d,%s" % [_drag_cells[i].x, _drag_cells[i].y, _drag_rotations[i],
				"e" if _drag_states[i] == DragCell.EXISTING_BELT else "n"]
		var view: BuildingView = _drag_views.get(view_key)
		if view == null:
			view = BuildingView.new()
			view.setup(preview_belts[i], preview)
			view.collision_layer = 0
			view.collision_mask = 0
			add_child(view)
			for node: Node in view.find_children("*", "MeshInstance3D", true, false):
				(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			_drag_views.erase(view_key)
			view.placed = preview_belts[i]
			view.island = preview
		view.set_linked_ports([])
		# Sobre una cinta que ya existe (un cruce), el fantasma solo enseña las bocas nuevas, las del tramo, para no
		# taparla (C5.3d, César).
		if _drag_states[i] == DragCell.EXISTING_BELT:
			view.show_only_hub_arms([_drag_rotations[i], (_drag_rotations[i] + 2) % 4])
		views[view_key] = view
		_drag_view_at[i] = view
	for old: BuildingView in _drag_views.values():
		old.queue_free()
	_drag_views = views


## Soltar: pone las cintas verdes del tramo (cobrando cada una) y suena una vez. Un clic sin arrastrar
## pone una sola, como siempre.
func _finish_drag() -> void:
	_cancel_drag()
	if (_drag_cells.size() <= 1 and not _drag_into) or _drag_states.size() != _drag_cells.size():
		_try_place()
		return
	var building: BuildingData = get_held()
	if building == null:
		return
	var island: IslandState = WorldState.get_island(island_id)
	var inventory: Inventory = WorldState.player_inventory
	var built: Array[PlacedBuilding] = []
	var short_of_materials: bool = false
	for i: int in _drag_cells.size():
		if _drag_states[i] == DragCell.NO_MATERIALS:
			short_of_materials = true
		if _drag_states[i] != DragCell.OK:
			continue
		if not inventory.has_items(building.cost):
			short_of_materials = true
			break
		var result: PlacedBuilding = island.place(building, _drag_cells[i], _drag_rotations[i])
		if result == null:
			continue
		for item: ItemData in building.cost:
			inventory.remove_item(item, building.cost[item])
		built.append(result)
		placed.emit(result)
	if short_of_materials:
		place_failed.emit("BUILD_NO_MATERIALS")
	if built.is_empty():
		return
	_play_sound(PLACE_SOUND, BuildingView.cable_anchor(built[floori(built.size() * 0.5)]))
	_play_link_sounds(island, built[0])
	if built.size() > 1:
		_play_link_sounds(island, built[built.size() - 1])


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
	island.add_cable(_cable_from, target.id, cable_taut)
	_play_sound(CABLE_SOUND, BuildingView.cable_anchor(target))
	cable_changed.emit(true)
	_cable_from = 0


## F con el cable: cambia entre normal y tenso. Si hay un cable empezado y se apunta a una construcción ya
## unida a él, cambia ese cable (así se arreglan los que ya están tendidos) y el modo pasa a ser el suyo.
func _toggle_cable_taut() -> void:
	var island: IslandState = WorldState.get_island(island_id)
	if _cable_from != 0 and island.buildings.has(_cable_from):
		var target: PlacedBuilding = _aimed_building()
		if target != null and target.id != _cable_from and island.cables.has(Vector2i(mini(_cable_from, target.id), maxi(_cable_from, target.id))):
			cable_taut = not island.is_cable_taut(_cable_from, target.id)
			island.set_cable_taut(_cable_from, target.id, cable_taut)
			_play_sound(CABLE_SOUND, BuildingView.cable_anchor(target))
			_cable_from = 0
			return
	cable_taut = not cable_taut


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
	IslandView.place_cable(_cable_preview, from, to, CABLE_PREVIEW_THICKNESS, cable_taut)
	if ok:
		_cable_preview.material_override = _cable_ok_material
	else:
		_cable_preview.material_override = _cable_bad_material


## Material del fantasma de un cruce: el verde del tramo, recortado para que solo se vea fuera de las paredes de la
## cinta que ya existe. Uno por vista (cada una tiene su casilla), guardado en la propia vista.
func _crossing_material(view: BuildingView, turn: int) -> ShaderMaterial:
	if _cross_shader == null:
		_cross_shader = Shader.new()
		_cross_shader.code = CROSS_SHADER_CODE
	var material: ShaderMaterial = view.get_meta(&"cross_material", null)
	if material == null:
		material = ShaderMaterial.new()
		material.shader = _cross_shader
		material.set_shader_parameter("color", COLOR_OK)
		material.set_shader_parameter("keep_from", CROSS_KEEP_FROM)
		view.set_meta(&"cross_material", material)
	var forward: Vector2i = GridMath.rotate_offset(Vector2i(0, -1), turn)
	material.set_shader_parameter("cell_center", view.global_position)
	material.set_shader_parameter("axis", Vector2(forward.x, forward.y))
	return material


## Flecha plana de 0,5 m de largo y 4 cm de grueso que apunta hacia −Z: punta ancha y cola estrecha.
func _make_arrow_mesh() -> ArrayMesh:
	var outline: PackedVector2Array = [ # (x, z) en el sentido de las agujas del reloj visto desde arriba
		Vector2(0.0, -0.25), Vector2(0.2, -0.02), Vector2(0.075, -0.02), Vector2(0.075, 0.25),
		Vector2(-0.075, 0.25), Vector2(-0.075, -0.02), Vector2(-0.2, -0.02),
	]
	var thickness: float = 0.04
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
	for i: int in range(0, triangles.size(), 3):
		for k: int in [0, 2, 1]: # cara de arriba
			var p: Vector2 = outline[triangles[i + k]]
			tool.add_vertex(Vector3(p.x, thickness, p.y))
		for k: int in [0, 1, 2]: # cara de abajo
			var p: Vector2 = outline[triangles[i + k]]
			tool.add_vertex(Vector3(p.x, 0.0, p.y))
	for i: int in outline.size(): # costados
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i + 1) % outline.size()]
		var a_low := Vector3(a.x, 0.0, a.y)
		var b_low := Vector3(b.x, 0.0, b.y)
		var a_high := Vector3(a.x, thickness, a.y)
		var b_high := Vector3(b.x, thickness, b.y)
		for v: Vector3 in [a_low, a_high, b_high, a_low, b_high, b_low]:
			tool.add_vertex(v)
	return tool.commit()


func _make_material(color: Color, transparent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
