extends Node3D
## Isla Alba (C5.3d, D-154): la isla del vertical slice, construida a partir de su plano de texto
## (`content/islands/isla_alba.txt`, D-155). Al empezar, pone el plano en la isla, la puebla (árboles y la
## veta de malaquita) y deja a Mira delante del portal.
## Provisional hasta C6 y C8: empieza siempre una partida nueva y, mientras no llegue el laboratorio, da a Mira
## un equipo de pruebas (`DEV_KIT`) para poder construir. El terreno es el provisional de bloques a dos
## alturas de `TerrainView` hasta C5.4.

const ISLAND_ID: StringName = &"isla_alba"
const LAYOUT_PATH: String = "res://content/islands/isla_alba.txt"
## Equipo de pruebas hasta C6 (en el juego, Mira trae 7 células y 9 hierros del laboratorio). Ponlo en
## false para empezar con las manos vacías.
const DEV_KIT: bool = true
## Rocas y palos que ya hay al llegar: se dejan aparecer los que saldrían en unos minutos.
const START_SPAWN_STEPS: int = 12
## Distancia (m) del borde norte del portal a la que aparece Mira.
const SPAWN_GAP: float = 1.5

@onready var player: Player = $Player


func _ready() -> void:
	WorldState.reset()
	player.build_controller.island_id = ISLAND_ID
	var island: IslandState = WorldState.get_island(ISLAND_ID)
	var layout: IslandLayout = IslandLayout.load_file(LAYOUT_PATH)
	island.apply_layout(layout)
	var trees: int = island.populate_from_layout()
	for i: int in START_SPAWN_STEPS:
		island.step_nature(IslandState.ROCK_SPAWN_TIME)
	print("Isla Alba: %d × %d casillas, %d árboles, %d rocas y %d palos" % [
		layout.size.x, layout.size.y, trees, island.rock_count(), island.sticks_count()])
	_place_player_at_portal(layout)
	if DEV_KIT:
		_give_dev_kit()
	var hud := GameHud.new()
	hud.player = player
	add_child(hud)


## Mira aparece delante del portal, por su lado norte, de espaldas a él y mirando al norte: con la boca del
## refugio de frente, a unos 6 m (el portal está al sur del refugio desde la sesión 25).
func _place_player_at_portal(layout: IslandLayout) -> void:
	var portal: Array[Vector2i] = layout.cells_of("P")
	if portal.is_empty():
		return
	var center := Vector2(0.0, 0.0)
	var top: int = 1000
	for cell: Vector2i in portal:
		center += Vector2(cell.x + 0.5, cell.y + 0.5)
		top = mini(top, cell.y)
	center /= portal.size()
	player.global_position = Vector3(center.x, 0.2, top - SPAWN_GAP)
	player.rotation.y = 0.0
	player.spawn_transform = player.global_transform
	player.reset_physics_interpolation()


func _give_dev_kit() -> void:
	var inventory: Inventory = WorldState.player_inventory
	for entry: Array in [[&"wood", 100], [&"stone", 100], [&"iron_ingot", 14], [&"solar_cell", 14],
			[&"copper_ingot", 10], [&"copper_coil", 10], [&"timber", 17], [&"stone_tile", 10],
			[&"fiber", 63]]:   # fibra de esparto para hacer cuerda en el banco (C5.5), hasta que haya esparto en C5.6;
			# 63 = 21 cuerdas: el refugio, los tramos de la barandilla del mirador, las 4 de la escala y las 2 del pasamanos
			# de la pasarela (C5.6b); 17 maderos: 4 más para la pasarela (los tablones se hacen con madera en el banco)
		inventory.add_item(Content.find_item(entry[0]), entry[1])
