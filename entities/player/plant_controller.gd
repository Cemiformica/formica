class_name PlantController
extends Node3D
## Plantar con la mano (C1.9, César). Con una semilla elegida en la barra (bellota o piña), clic izquierdo
## sobre una casilla libre de suelo planta un brote de su especie y gasta una semilla. Mientras se lleva la
## semilla, su fantasma (el brote, verde si se puede y rojo si no) marca dónde caería. No se planta sobre
## agua, vetas, construcciones, rocas ni otros árboles (`IslandState.can_plant`).
## Hijo del jugador: lo crea `Player`, que le pasa el clic izquierdo si se lleva una semilla (`try_plant`).

## Alcance de la mano para plantar (m).
const REACH: float = 4.0
const COLOR_OK: Color = Color(0.2, 0.9, 0.3, 0.45)
const COLOR_BAD: Color = Color(0.95, 0.2, 0.2, 0.45)

var player: Player

var _ghost: MeshInstance3D
var _ghost_species: StringName = &""
var _ok_material: StandardMaterial3D
var _bad_material: StandardMaterial3D
var _target_cell: Vector2i
var _can_plant: bool = false


func _ready() -> void:
	top_level = true # el fantasma se coloca en coordenadas del mundo
	_ghost = MeshInstance3D.new()
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)
	_ok_material = _make_material(COLOR_OK)
	_bad_material = _make_material(COLOR_BAD)


## Semilla que se lleva en la mano (casilla elegida de la barra), o null.
func held_seed() -> ItemData:
	if player == null:
		return null
	var stack: ItemStack = WorldState.player_inventory.slots[player.held_slot]
	if stack == null or stack.item.plants_tree == &"":
		return null
	return stack.item


func _process(_delta: float) -> void:
	_can_plant = false
	var seed_item: ItemData = null
	if not player.in_tool_mode() and not WindowManager.is_open():
		seed_item = held_seed()
	if seed_item == null:
		_ghost.visible = false
		return
	var exclude: Array[RID] = [player.get_rid()] # el rayo no toca al propio jugador
	var hit: Dictionary = Aim.from_screen_center(get_viewport(), REACH, exclude)
	if hit.is_empty():
		_ghost.visible = false
		return
	var position_hit: Vector3 = hit["position"]
	_target_cell = GridMath.world_to_cell(position_hit)
	var island: IslandState = WorldState.get_island(player.build_controller.island_id)
	var on_ground: bool = (hit["normal"] as Vector3).y > 0.7 # apuntando al suelo, no a una pared
	_can_plant = on_ground and island.can_plant(_target_cell)
	_show_ghost(seed_item.plants_tree, GridMath.cell_center(_target_cell, position_hit.y if on_ground else 0.0))


## Clic izquierdo: planta un brote de la semilla en la casilla apuntada. Devuelve true si ha plantado.
func try_plant() -> bool:
	var seed_item: ItemData = held_seed()
	if seed_item == null or not _can_plant:
		return false
	var island: IslandState = WorldState.get_island(player.build_controller.island_id)
	if not island.add_tree(_target_cell, NatureState.Stage.SPROUT, seed_item.plants_tree):
		return false
	WorldState.player_inventory.remove_item(seed_item, 1)
	DustPuff.spawn(get_parent(), _ghost.global_position + Vector3(0.0, 0.05, 0.0))
	return true


func _show_ghost(species: StringName, at: Vector3) -> void:
	if species != _ghost_species:
		_ghost_species = species
		_ghost.mesh = TreeView.get_model_mesh(species, "sprout")
	_ghost.material_override = _ok_material if _can_plant else _bad_material
	_ghost.global_position = at
	_ghost.visible = _ghost.mesh != null


func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
