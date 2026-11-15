class_name TreeView
extends Interactable
## Árbol, tocón o roca visible (B2.7b, B2.8). El nombre de la clase es de antes de las rocas. Solo MUESTRA su `NatureState` (D-046): la crea, actualiza y borra
## `IslandView` cuando la isla avisa con `nature_changed`. La forma cambia con la fase:
## tocón bajo, brote pequeño, árbol joven y árbol maduro. Formas provisionales hasta B3.
## E sobre un árbol maduro: un golpe; a los `NatureState.CHOP_HITS` golpes (uno por segundo como mucho)
## se tala a mano (4 de madera + 1 semilla, queda un tocón) (D-090). Cada golpe levanta polvo y lo agita.
## E sobre un tocón: arrancarlo (1 de madera, libera la casilla). Brotes y jóvenes no se tocan.
## E sobre una roca: recogerla de una vez (1 de piedra, libera la casilla).

const TRUNK_COLOR: Color = Color(0.45, 0.3, 0.17)
const LEAVES_COLOR: Color = Color(0.2, 0.55, 0.22)
const SPROUT_COLOR: Color = Color(0.45, 0.75, 0.3)
const ROCK_COLOR: Color = Color(0.5, 0.5, 0.53)

## Casilla que ocupa.
var cell: Vector2i
## Isla a la que pertenece.
var island: IslandState

var _shape: CylinderShape3D
var _visual: Node3D = null
## Golpes dados al árbol y momento del último (no se guardan: si te vas, se pierden).
var _hits: int = 0
var _last_hit_ms: int = -100000
var _shake: float = 0.0


## Prepara la vista. Se llama ANTES de añadirla al árbol.
func setup(p_cell: Vector2i, p_island: IslandState) -> void:
	cell = p_cell
	island = p_island
	name = "tree_%d_%d" % [cell.x, cell.y]
	position = GridMath.cell_center(cell)
	_shape = CylinderShape3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = _shape
	add_child(collision)


## Vuelve a dibujar según la fase actual (la llama `IslandView` cuando cambia).
func refresh() -> void:
	var state: NatureState = island.nature.get(cell, null)
	if state == null:
		return
	if _visual != null:
		_visual.queue_free()
	_visual = Node3D.new()
	add_child(_visual)
	var collision_height: float = 0.4
	if state.is_rock():
		display_name_key = "PROP_ROCK"
		_add_sphere(0.45, 0.25, ROCK_COLOR)
		(_visual.get_child(0) as Node3D).scale = Vector3(1.0, 0.6, 0.85) # aplastada para que parezca una roca
		_shape.radius = 0.45
		_shape.height = 0.55
		(get_child(0) as CollisionShape3D).position.y = 0.275
		return
	match state.stage:
		NatureState.Stage.STUMP:
			display_name_key = "PROP_STUMP"
			_add_cylinder(0.25, 0.3, 0.15, TRUNK_COLOR)
			collision_height = 0.3
		NatureState.Stage.SPROUT:
			display_name_key = "PROP_SPROUT"
			_add_cylinder(0.04, 0.3, 0.15, SPROUT_COLOR)
			_add_sphere(0.15, 0.35, SPROUT_COLOR)
		NatureState.Stage.YOUNG:
			display_name_key = "PROP_YOUNG_TREE"
			_add_cylinder(0.1, 0.9, 0.45, TRUNK_COLOR)
			_add_sphere(0.45, 1.1, LEAVES_COLOR)
			collision_height = 1.4
		_:
			display_name_key = "PROP_TREE"
			_add_cylinder(0.2, 1.6, 0.8, TRUNK_COLOR)
			_add_sphere(0.85, 2.1, LEAVES_COLOR)
			collision_height = 2.8
	_shape.radius = 0.3
	_shape.height = collision_height
	(get_child(0) as CollisionShape3D).position.y = collision_height * 0.5


## E: talar si está maduro, arrancar si es un tocón. Lo obtenido va al inventario del jugador;
## si no cabe entero, no se hace nada (para no perder materiales).
func interact(by: Node) -> void:
	super(by)
	var state: NatureState = island.nature.get(cell, null)
	if state == null:
		return
	var inventory: Inventory = WorldState.player_inventory
	var preview: Dictionary[ItemData, int] = {}
	if state.is_rock():
		preview = {Content.find_item(&"stone"): IslandState.ROCK_STONE}
	elif state.is_mature_tree():
		preview = {Content.find_item(&"wood"): IslandState.TREE_WOOD, Content.find_item(&"seed"): 1}
	elif state.is_stump():
		preview = {Content.find_item(&"wood"): IslandState.STUMP_WOOD}
	if preview.is_empty() or not inventory.can_add_all(preview):
		return
	if state.is_mature_tree():
		var now: int = Time.get_ticks_msec()
		if now - _last_hit_ms < int(NatureState.HIT_COOLDOWN * 1000.0):
			return
		_last_hit_ms = now
		_hits += 1
		_shake = 1.0
		DustPuff.spawn(self, global_position + Vector3(0.0, 0.6, 0.0))
		if _hits < NatureState.CHOP_HITS:
			return
		_hits = 0
	var gained: Dictionary[ItemData, int] = {}
	if state.is_rock():
		gained = island.mine_rock(cell)
	elif state.is_mature_tree():
		gained = island.chop_tree(cell, true)
	else:
		gained = island.uproot_stump(cell)
	for item: ItemData in gained:
		inventory.add_item(item, gained[item])


## Sacudida corta del árbol tras un golpe.
func _process(delta: float) -> void:
	if _shake <= 0.0 or _visual == null:
		return
	_shake = maxf(_shake - delta * 5.0, 0.0)
	_visual.rotation.z = 0.06 * sin(_shake * PI * 3.0) * _shake


func _add_cylinder(radius: float, height: float, center_y: float, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	_add_mesh(mesh, center_y, color)


func _add_sphere(radius: float, center_y: float, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	_add_mesh(mesh, center_y, color)


func _add_mesh(mesh: Mesh, center_y: float, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position.y = center_y
	_visual.add_child(instance)
