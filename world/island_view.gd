class_name IslandView
extends Node3D
## Dibuja una isla de `WorldState` (B2.4c): una `BuildingView` por construcción colocada.
## Solo muestra (D-046): los datos los cambian el modo construcción y `Simulation`.
## Escucha a su `IslandState` para crear y borrar piezas, y lo rehace todo si se carga una partida.
## También dibuja los cables de energía como líneas finas entre sus dos construcciones (B2.6b)
## y la naturaleza: un `TreeView` por árbol o tocón (B2.7b). Y las estructuras por reparar: una
## `RepairSiteView` por cada una (C4.3).

const CABLE_COLOR: Color = Color(0.1, 0.1, 0.11)
## Grosor de los cables (B3: más gruesos para que se vean bien, petición de César).
const CABLE_THICKNESS: float = 0.04
## Comba de los cables normales: cuánto baja el centro, en proporción a su largo (un cable de 12 m baja 0,48 m).
const CABLE_SAG_RATIO: float = 0.04
## Comba mínima, para que también se note en los cables cortos.
const CABLE_SAG_MIN: float = 0.06
## Tramos del cable que cuelga y caras del tubo (hexagonal, como todo en Formica).
const CABLE_SEGMENTS: int = 12
const CABLE_SIDES: int = 6
## Material de la banda de las cintas, compartido por todas: se desplaza una sola vez por fotograma
## para que todas las bandas avancen (B3.7). Su textura se repite BELT_TEXTURE_PER_M veces por metro.
## Si la banda avanzara hacia atrás, cambiar el signo de BELT_SCROLL_SIGN.
const BELT_TEXTURE_PER_M: float = 2.0
const BELT_SCROLL_SIGN: float = 1.0

## Isla de `WorldState` que dibuja.
@export var island_id: StringName = &"dev_sandbox"

var _island: IslandState = null
## Id de la construcción → su vista.
var _views: Dictionary[int, BuildingView] = {}
## Casilla → vista de su árbol o tocón.
var _tree_views: Dictionary[Vector2i, TreeView] = {}
## Esquina → vista de su veta.
var _vein_views: Dictionary[Vector2i, VeinView] = {}
## Esquina → vista de su estructura por reparar (C4.3).
var _repair_views: Dictionary[Vector2i, RepairSiteView] = {}
## Suelo de la isla con su agua: una sola vista (D-094).
var _terrain_view: TerrainView = null
## Líneas de los cables dibujados.
var _cable_meshes: Array[MeshInstance3D] = []
var _cable_material: StandardMaterial3D
## true mientras `_rebuild` crea todas las vistas: las conexiones se repasan una sola vez al final.
var _rebuilding: bool = false
## Velocidad de las cintas (casillas por segundo) y desplazamiento actual de su banda.
var _belt_speed: float = 0.75
var _belt_scroll: float = 0.0
## Material compartido de la banda: es una variable porque GDScript no deja modificar propiedades de una constante.
var _belt_material: StandardMaterial3D = preload("res://assets/materials/belt_band.tres")


func _ready() -> void:
	add_to_group(&"island_view") # el desmontaje busca aquí las vistas para marcarlas (C2.2)
	var conveyor: BuildingData = Content.find_building(&"conveyor")
	if conveyor != null:
		_belt_speed = conveyor.belt_speed
	_cable_material = StandardMaterial3D.new()
	_cable_material.albedo_color = CABLE_COLOR
	WorldState.state_replaced.connect(_rebuild)
	_rebuild()


## Vista de una construcción por su id (null si no hay).
func get_view(id: int) -> BuildingView:
	return _views.get(id, null)


## Hace avanzar la banda de todas las cintas a la vez (cuesta lo mismo con 1 cinta que con 1.000).
func _process(delta: float) -> void:
	_belt_scroll = fposmod(_belt_scroll + BELT_SCROLL_SIGN * delta * _belt_speed * BELT_TEXTURE_PER_M, 1.0)
	_belt_material.uv1_offset = Vector3(0.0, _belt_scroll, 0.0)


## Borra todas las vistas y las vuelve a crear desde los datos (al empezar o al cargar una partida).
func _rebuild() -> void:
	if _island != null and _island.building_placed.is_connected(_on_building_placed):
		_island.building_placed.disconnect(_on_building_placed)
		_island.building_removed.disconnect(_on_building_removed)
		_island.cables_changed.disconnect(_redraw_cables)
		_island.nature_changed.disconnect(_on_nature_changed)
		_island.vein_added.disconnect(_on_vein_added)
		_island.water_changed.disconnect(_on_water_changed)
		_island.repair_site_added.disconnect(_on_repair_site_added)
		_island.repair_changed.disconnect(_on_repair_changed)
		_island.repair_completed.disconnect(_on_repair_completed)
		_island.repair_toggled.disconnect(_on_repair_toggled)
	for view: BuildingView in _views.values():
		view.queue_free()
	_views.clear()
	for tree: TreeView in _tree_views.values():
		tree.queue_free()
	_tree_views.clear()
	for vein: VeinView in _vein_views.values():
		vein.queue_free()
	_vein_views.clear()
	for repair: RepairSiteView in _repair_views.values():
		repair.queue_free()
	_repair_views.clear()

	_island = WorldState.get_island(island_id)
	_island.building_placed.connect(_on_building_placed)
	_island.building_removed.connect(_on_building_removed)
	_island.cables_changed.connect(_redraw_cables)
	_island.nature_changed.connect(_on_nature_changed)
	_island.vein_added.connect(_on_vein_added)
	_island.water_changed.connect(_on_water_changed)
	_island.repair_site_added.connect(_on_repair_site_added)
	_island.repair_changed.connect(_on_repair_changed)
	_island.repair_completed.connect(_on_repair_completed)
	_island.repair_toggled.connect(_on_repair_toggled)
	_on_water_changed()
	for vein_origin: Vector2i in _island.veins:
		_on_vein_added(vein_origin)
	for site_origin: Vector2i in _island.repair_sites:
		_on_repair_site_added(site_origin)
	_rebuilding = true
	for placed: PlacedBuilding in _island.buildings.values():
		_on_building_placed(placed)
	_rebuilding = false
	_refresh_connections()
	_redraw_cables()
	for cell: Vector2i in _island.nature:
		_on_nature_changed(cell)


func _on_building_placed(placed: PlacedBuilding) -> void:
	var view := BuildingView.new()
	view.setup(placed, _island)
	add_child(view)
	_views[placed.id] = view
	if not _rebuilding:
		_refresh_connections()
		if _island.is_dropping():
			view.play_drop_effect() # soltar tras moverla (C2b): cae y rebota, sin crecer
		else:
			view.play_place_effect() # rebote y polvo (B5.4); al cargar una partida, no


func _on_building_removed(placed: PlacedBuilding) -> void:
	if _views.has(placed.id):
		_views[placed.id].queue_free()
		_views.erase(placed.id)
	_refresh_connections()


## Hay una veta nueva: crea su vista.
func _on_vein_added(vein_origin: Vector2i) -> void:
	if _vein_views.has(vein_origin):
		return
	var view := VeinView.new()
	view.setup(vein_origin, _island.veins[vein_origin], _island)
	add_child(view)
	_vein_views[vein_origin] = view


## Hay una estructura por reparar nueva: crea su vista (C4.3).
func _on_repair_site_added(site_origin: Vector2i) -> void:
	if _repair_views.has(site_origin):
		return
	var view := RepairSiteView.new()
	view.setup(_island.repair_sites[site_origin], _island)
	add_child(view)
	_repair_views[site_origin] = view


## Se entregó algo a una pieza: la vista la pone al día (y la hace crecer si se completó).
func _on_repair_changed(site_origin: Vector2i, piece_index: int) -> void:
	if _repair_views.has(site_origin):
		_repair_views[site_origin].on_piece_changed(piece_index)


func _on_repair_completed(site_origin: Vector2i) -> void:
	if _repair_views.has(site_origin):
		_repair_views[site_origin].on_completed()


func _on_repair_toggled(site_origin: Vector2i, piece_index: int) -> void:
	if _repair_views.has(site_origin):
		_repair_views[site_origin].on_piece_toggled(piece_index)


## El agua cambió: el suelo y el agua se rehacen enteros (pasa al empezar o al cargar, no en cada
## fotograma). Se espera al final del fotograma, porque al empezar la isla aún puede estar poniendo
## sus límites (`bounds`) y su agua.
func _on_water_changed() -> void:
	if _terrain_view == null:
		_terrain_view = TerrainView.new()
		add_child(_terrain_view)
	_refresh_terrain.call_deferred()


func _refresh_terrain() -> void:
	if _terrain_view != null and _island != null:
		_terrain_view.rebuild(_island)


## Algo natural cambió en `cell`: crea, actualiza o borra su vista.
func _on_nature_changed(cell: Vector2i) -> void:
	if not _island.nature.has(cell):
		if _tree_views.has(cell):
			_tree_views[cell].queue_free()
			_tree_views.erase(cell)
		return
	if not _tree_views.has(cell):
		var view := TreeView.new()
		view.setup(cell, _island)
		add_child(view)
		_tree_views[cell] = view
	_tree_views[cell].refresh()


## Borra las líneas y las vuelve a crear desde `IslandState.cables` (son pocas: no merece la pena más).
func _redraw_cables() -> void:
	for mesh: MeshInstance3D in _cable_meshes:
		mesh.queue_free()
	_cable_meshes.clear()
	for cable: Vector2i in _island.cables:
		if not _island.buildings.has(cable.x) or not _island.buildings.has(cable.y):
			continue
		var line := MeshInstance3D.new()
		add_child(line)
		place_cable(line, BuildingView.cable_anchor(_island.buildings[cable.x]), BuildingView.cable_anchor(_island.buildings[cable.y]),
				CABLE_THICKNESS, _island.taut_cables.has(cable))
		line.material_override = _cable_material
		_cable_meshes.append(line)
	_refresh_cabled()


## Dice a cada vista qué puertos suyos están conectados (para la lengüeta de cinta, B3). Se llama al
## colocar o quitar algo, no en cada fotograma: recorre las conexiones una vez y reparte el resultado.
func _refresh_connections() -> void:
	var linked: Dictionary[int, Array] = {}
	for link: Dictionary in _island.get_links():
		_mark_port(linked, link["from"], link["out"])
		_mark_port(linked, link["to"], link["in"])
	for id: int in _views:
		var ports: Array[int] = []
		if linked.has(id):
			ports.assign(linked[id])
		_views[id].set_linked_ports(ports)


func _mark_port(linked: Dictionary[int, Array], building: PlacedBuilding, port: PortData) -> void:
	if not linked.has(building.id):
		linked[building.id] = []
	linked[building.id].append(building.get_ports().find(port))


## Enciende el borne de las construcciones que tienen algún cable.
func _refresh_cabled() -> void:
	var cabled: Dictionary[int, bool] = {}
	for cable: Vector2i in _island.cables:
		cabled[cable.x] = true
		cabled[cable.y] = true
	for id: int in _views:
		_views[id].set_cabled(cabled.has(id))


## Convierte `line` en una barra fina de `from` a `to` (también la usa el cable provisional del modo construcción).
static func place_line(line: MeshInstance3D, from: Vector3, to: Vector3, thickness: float) -> void:
	var length: float = from.distance_to(to)
	var box := line.mesh as BoxMesh
	if box == null:
		box = BoxMesh.new()
		line.mesh = box
	box.size = Vector3(thickness, thickness, maxf(length, 0.01))
	line.global_position = (from + to) * 0.5
	if length > 0.001:
		var up: Vector3 = Vector3.UP
		if absf((to - from).normalized().dot(Vector3.UP)) > 0.99:
			up = Vector3.FORWARD # casi vertical: otro «arriba» para que look_at no falle
		line.look_at(to, up)


## Convierte `line` en un cable de `from` a `to`: un tubo fino que cuelga un poco en el centro o, si es
## `taut`, recto. El cable provisional del modo construcción usa la misma función.
static func place_cable(line: MeshInstance3D, from: Vector3, to: Vector3, thickness: float, taut: bool) -> void:
	var span: Vector3 = to - from
	var length: float = span.length()
	var sag: float = 0.0 if taut else maxf(length * CABLE_SAG_RATIO, CABLE_SAG_MIN)
	var segments: int = 1 if taut else CABLE_SEGMENTS
	var radius: float = thickness * 0.5
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for i: int in segments + 1:
		var t: float = float(i) / segments
		# Parábola: baja `sag` en el centro y nada en los extremos (parecida a la catenaria si cuelga poco).
		var point: Vector3 = span * t + Vector3.DOWN * (4.0 * sag * t * (1.0 - t))
		var tangent: Vector3 = span + Vector3.DOWN * (4.0 * sag * (1.0 - 2.0 * t))
		if tangent.length_squared() < 0.000001:
			tangent = Vector3.FORWARD
		tangent = tangent.normalized()
		var side: Vector3 = tangent.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = tangent.cross(Vector3.FORWARD) # cable casi vertical
		side = side.normalized()
		var up: Vector3 = side.cross(tangent)
		for k: int in CABLE_SIDES:
			var angle: float = TAU * k / CABLE_SIDES
			var normal: Vector3 = side * cos(angle) + up * sin(angle)
			vertices.append(point + normal * radius)
			normals.append(normal)
	for i: int in segments:
		for k: int in CABLE_SIDES:
			var a: int = i * CABLE_SIDES + k
			var b: int = i * CABLE_SIDES + (k + 1) % CABLE_SIDES
			var c: int = a + CABLE_SIDES
			var d: int = b + CABLE_SIDES
			indices.append_array(PackedInt32Array([a, b, c, b, d, c])) # en el sentido de las agujas del reloj, visto desde fuera (cara delantera en Godot)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := line.mesh as ArrayMesh
	if mesh == null:
		mesh = ArrayMesh.new()
		line.mesh = mesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Los vértices van relativos a `from`, sin giro: la malla ya tiene la forma en el mundo.
	line.global_transform = Transform3D(Basis.IDENTITY, from)
