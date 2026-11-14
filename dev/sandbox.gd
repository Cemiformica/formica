extends Node3D
## Escena de pruebas de B2 (solo desarrollo). Imprime en Salida lo que pasa: qué mira el jugador,
## interacciones y construcción. Al empezar da materiales de prueba al jugador.

## Materiales iniciales para probar (la trituradora cuesta 6 de madera y 4 de piedra).
const START_WOOD: int = 30
const START_STONE: int = 30

@onready var player: Player = $Player
@onready var test_box: Interactable = $TestBox


func _ready() -> void:
	WorldState.reset()
	WorldState.player_inventory.add_item(Content.find_item(&"wood"), START_WOOD)
	WorldState.player_inventory.add_item(Content.find_item(&"stone"), START_STONE)
	print("Inventario inicial: ", WorldState.player_inventory.debug_string())

	player.focus_changed.connect(_on_player_focus_changed)
	test_box.interacted.connect(_on_test_box_interacted)
	player.build_controller.mode_changed.connect(_on_build_mode_changed)
	player.build_controller.placed.connect(_on_building_placed)
	player.build_controller.place_failed.connect(_on_place_failed)


func _on_player_focus_changed(target: Interactable) -> void:
	if target != null:
		print("Mirando: ", target.name)
	else:
		print("Mirando: nada")


func _on_test_box_interacted(by: Node) -> void:
	print("Interacción con la caja de prueba (por ", by.name, ")")


func _on_build_mode_changed(active: bool) -> void:
	print("Modo construcción: ", "sí" if active else "no")


func _on_building_placed(placed: PlacedBuilding) -> void:
	var island: IslandState = WorldState.get_island(player.build_controller.island_id)
	print("Colocada %s #%d en %s, giro %d, reflejo %s · construcciones en la isla: %d" % [
		placed.data.id, placed.id, placed.origin, placed.rotation, placed.flipped, island.buildings.size()])
	print("Inventario: ", WorldState.player_inventory.debug_string())


func _on_place_failed(reason_key: String) -> void:
	print("No se pudo colocar: ", reason_key)
