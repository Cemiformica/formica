extends Node3D
## Escena de pruebas de B2 (solo desarrollo). Da materiales de prueba, muestra la barra de construcción
## en una línea de texto, la red eléctrica de lo que miras en otra, e imprime en Salida lo que pasa.
## (Los textos de esta escena son de desarrollo y no se traducen, salvo los nombres.)

## Materiales iniciales (trituradora: 6 madera + 4 piedra; cinta: 1 + 1).
const START_WOOD: int = 100
const START_STONE: int = 100
## Arboleda de 3×3 ya plantada (B2.7b), desde esta esquina noroeste: casillas x 3–5, y −9…−7.
## Para probar el talador: colócalo en (4, −6), justo al sur de la arboleda, sin girar (mira al norte).
const GROVE_ORIGIN: Vector2i = Vector2i(3, -9)

@onready var player: Player = $Player
@onready var test_box: Interactable = $TestBox
@onready var build_bar_label: Label = $HUD/BuildBarLabel
@onready var network_label: Label = $HUD/NetworkLabel


func _ready() -> void:
	WorldState.reset()
	var inventory: Inventory = WorldState.player_inventory
	inventory.add_item(Content.find_item(&"wood"), START_WOOD)
	inventory.add_item(Content.find_item(&"stone"), START_STONE)
	print("Inventario inicial: ", inventory.debug_string())
	# Naturaleza de prueba: una arboleda de 3×3 madura y unos árboles sueltos en distintas fases.
	var island: IslandState = WorldState.get_island(player.build_controller.island_id)
	for x: int in 3:
		for y: int in 3:
			island.add_tree(GROVE_ORIGIN + Vector2i(x, y))
	island.add_tree(Vector2i(-4, -3))
	island.add_tree(Vector2i(-6, -3), NatureState.Stage.YOUNG)
	island.add_tree(Vector2i(-8, -3), NatureState.Stage.SPROUT)
	island.add_tree(Vector2i(-10, -3), NatureState.Stage.STUMP)
	# Rocas (B2.8): aparecen solas cada 45 s dentro del suelo de 40×40 m; ponemos tres para empezar.
	island.bounds = Rect2i(-20, -20, 40, 40)
	island.add_rock(Vector2i(-3, 1))
	island.add_rock(Vector2i(-5, 2))
	island.add_rock(Vector2i(6, 2))

	var builder: BuildController = player.build_controller
	player.focus_changed.connect(_on_player_focus_changed)
	test_box.interacted.connect(_on_test_box_interacted)
	builder.placed.connect(_on_building_placed)
	builder.place_failed.connect(_on_place_failed)
	builder.cable_changed.connect(_on_cable_changed)
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
	var seed_item: ItemData = Content.find_item(&"seed")
	var materials: String = "%s %d · %s %d · %s %d" % [tr(wood.name_key), inventory.get_total(wood), tr(stone.name_key), inventory.get_total(stone), tr(seed_item.name_key), inventory.get_total(seed_item)]
	if not builder.active:
		build_bar_label.text = "B: construir · " + materials
		return
	var parts: PackedStringArray = []
	for i: int in BuildController.BAR_SIZE:
		var text: String = "%d —" % (i + 1)
		if i < builder.build_bar.size() and builder.build_bar[i] != null:
			text = "%d %s" % [i + 1, tr(str(builder.build_bar[i].get("name_key")))]
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
	print("No se pudo: ", tr(reason_key))


func _on_cable_changed(added: bool) -> void:
	var island: IslandState = WorldState.get_island(player.build_controller.island_id)
	print("%s · cables: %d · redes: %d" % ["Cable tendido" if added else "Cable quitado", island.cables.size(), island.get_networks().size()])


## Red eléctrica de lo que miras (con E a 3 m): "Red · genera 4 · consume 6 · ¡FUSIBLE SALTADO! …".
func _process(_delta: float) -> void:
	if not is_instance_valid(player.focused_interactable):
		network_label.text = ""
		return
	var view := player.focused_interactable as BuildingView
	if view == null or view.island == null:
		network_label.text = ""
		return
	var network: PowerNetwork = view.island.get_network(view.placed.id)
	if network == null:
		network_label.text = ""
		return
	var state: String = "funciona"
	if network.is_tripped():
		state = "¡FUSIBLE SALTADO! Quita carga y pulsa E en un generador"
	elif network.supply <= 0.0:
		state = "sin generación"
	elif network.is_overloaded():
		state = "sobrecarga"
	network_label.text = "Red · genera %d · consume %d · %s" % [int(network.supply), int(network.demand), state]
