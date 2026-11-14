extends Node3D
## Escena de pruebas de B2 (solo desarrollo). Da materiales de prueba, muestra la barra de construcción
## en una línea de texto e imprime en Salida lo que pasa (qué mira, interacciones y construcción).

## Materiales iniciales (trituradora: 6 madera + 4 piedra; cinta: 1 + 1).
const START_WOOD: int = 100
const START_STONE: int = 100

@onready var player: Player = $Player
@onready var test_box: Interactable = $TestBox
@onready var build_bar_label: Label = $HUD/BuildBarLabel


func _ready() -> void:
	WorldState.reset()
	var inventory: Inventory = WorldState.player_inventory
	inventory.add_item(Content.find_item(&"wood"), START_WOOD)
	inventory.add_item(Content.find_item(&"stone"), START_STONE)
	print("Inventario inicial: ", inventory.debug_string())

	var builder: BuildController = player.build_controller
	player.focus_changed.connect(_on_player_focus_changed)
	test_box.interacted.connect(_on_test_box_interacted)
	builder.placed.connect(_on_building_placed)
	builder.place_failed.connect(_on_place_failed)
	builder.mode_changed.connect(_update_label.unbind(1))
	builder.selection_changed.connect(_update_label)
	inventory.changed.connect(_update_label)
	_update_label()


## Fuera del modo: "B: construir · Madera 100 · Piedra 100".
## Dentro: "[1 Trituradora]   2 Cinta   3 —  …" (la casilla elegida entre corchetes).
func _update_label() -> void:
	var builder: BuildController = player.build_controller
	var inventory: Inventory = WorldState.player_inventory
	var wood: ItemData = Content.find_item(&"wood")
	var stone: ItemData = Content.find_item(&"stone")
	var materials: String = "%s %d · %s %d" % [tr(wood.name_key), inventory.get_total(wood), tr(stone.name_key), inventory.get_total(stone)]
	if not builder.active:
		build_bar_label.text = "B: construir · " + materials
		return
	var parts: PackedStringArray = []
	for i: int in BuildController.BAR_SIZE:
		var text: String = "%d —" % (i + 1)
		if i < builder.build_bar.size() and builder.build_bar[i] != null:
			text = "%d %s" % [i + 1, tr(builder.build_bar[i].name_key)]
		if i == builder.selected_slot:
			text = "[" + text + "]"
		parts.append(text)
	var held: BuildingData = builder.get_held()
	var held_text: String = ""
	if held != null and not builder.build_bar.has(held):
		held_text = "    · En la mano: " + tr(held.name_key) # cogido con el cuentagotas, fuera de la barra
	build_bar_label.text = "   ".join(parts) + held_text + "    · " + materials


func _on_player_focus_changed(target: Interactable) -> void:
	if target != null:
		print("Mirando: ", target.name)
	else:
		print("Mirando: nada")


func _on_test_box_interacted(by: Node) -> void:
	print("Interacción con la caja de prueba (por ", by.name, ")")


func _on_building_placed(placed: PlacedBuilding) -> void:
	var island: IslandState = WorldState.get_island(player.build_controller.island_id)
	print("Colocada %s #%d en %s, giro %d · construcciones: %d · conexiones: %d" % [
		placed.data.id, placed.id, placed.origin, placed.rotation, island.buildings.size(), island.get_links().size()])


func _on_place_failed(reason_key: String) -> void:
	print("No se pudo colocar: ", tr(reason_key))
