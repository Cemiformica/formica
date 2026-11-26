class_name ItemModels
extends RefCounted
## Mallas de los ítems para enseñarlos en el mundo (sesión 28, César: las cintas llevan los objetos y no cubos).
## Salen de `assets/models/items/items.glb` (art/tools/export_items.py, desde items.blend): una malla
## «item_<id>» por ítem, de unos 25 cm, con el origen en su centro y el material compartido `palette`.
## Se cargan la primera vez que se piden y se comparten entre todas las cintas.

const SCENE_PATH: String = "res://assets/models/items/items.glb"
const PREFIX: String = "item_"

static var _meshes: Dictionary[StringName, Mesh] = {}
static var _lifts: Dictionary[StringName, float] = {}
static var _halves: Dictionary[StringName, float] = {}
static var _loaded: bool = false


## Malla del ítem, o null si no tiene modelo (entonces se enseña un cubo de su color).
static func mesh_for(item: ItemData) -> Mesh:
	if not _loaded:
		_load()
	return _meshes.get(item.id) as Mesh


## Cuánto hay que subir el ítem para que apoye en el suelo (su origen está en el centro).
static func lift_for(item: ItemData) -> float:
	if not _loaded:
		_load()
	return _lifts.get(item.id, 0.0)


## Media longitud del ítem a lo largo de la cinta (su eje X, que se pone en la dirección de avance).
static func half_length_for(item: ItemData) -> float:
	if not _loaded:
		_load()
	return _halves.get(item.id, 0.125)


static func _load() -> void:
	_loaded = true
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("ItemModels: no se pudo cargar %s; los ítems se verán como cubos" % SCENE_PATH)
		return
	var root: Node = scene.instantiate()
	for node: Node in root.find_children(PREFIX + "*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var item_id := StringName(String(mesh_node.name).trim_prefix(PREFIX))
		_meshes[item_id] = mesh_node.mesh
		_lifts[item_id] = -mesh_node.mesh.get_aabb().position.y
		_halves[item_id] = maxf(absf(mesh_node.mesh.get_aabb().position.x), absf(mesh_node.mesh.get_aabb().end.x))
	root.free()
