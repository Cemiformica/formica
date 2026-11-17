extends Node3D
## Escena de pruebas de B2 (solo desarrollo). Da materiales de prueba, muestra la barra de construcción
## en una línea de texto, la red eléctrica de lo que miras en otra, e imprime en Salida lo que pasa.
## (Los textos de esta escena son de desarrollo y no se traducen, salvo los nombres.)

## Materiales iniciales (trituradora: 6 madera + 4 piedra; cinta: 1 + 1).
const START_WOOD: int = 100
const START_STONE: int = 100
## Para probar el horno (B3): mineral y carbón; con E se meten en él (2 mineral + 1 carbón cada 8 s).
const START_ORE: int = 40
const START_CHARCOAL: int = 20
## Materiales del Nexo (D-089: Mira trae 7 células y 7 de hierro) y cobre para los postes. En el sandbox,
## el doble, para poder probar más de una placa, horno o poste.
const START_IRON: int = 14
const START_CELLS: int = 14
const START_COPPER_INGOTS: int = 10
## Bobinas de cobre para el talador (2 cada uno, D-092). En el juego se harán en el banco de trabajo.
const START_COILS: int = 10
## Arboleda de 3×3 ya plantada (B2.7b), desde esta esquina noroeste: casillas x 3–5, y −9…−7.
## Para probar el talador (3×1): colócalo en x 3–5, y −6, justo al sur de la arboleda, mirando al norte.
const GROVE_ORIGIN: Vector2i = Vector2i(3, -9)
## Esquina noroeste de la veta de malaquita de prueba (B3.7).
const VEIN_ORIGIN: Vector2i = Vector2i(6, -4)
## Canal de agua de prueba (D-094): una columna de casillas en x = −12, de norte a sur, que corre al sur.
## Para probar la rueda hidráulica (2×3, tecla 5): con la rueda sobre el canal y la dinamo en x = −11.
const CANAL_X: int = -12
## Estanque de agua quieta (D-094): 3×3 casillas desde esta esquina noroeste (x −18…−16, y 6…8).
const POND_ORIGIN: Vector2i = Vector2i(-18, 6)
## Música de prueba (B5.4): bucle de 8 s generado por art/tools/make_sounds.py, por el bus «Music».
const TEST_MUSIC: AudioStreamWAV = preload("res://assets/audio/music_test.wav")

@onready var player: Player = $Player
@onready var test_box: Interactable = $TestBox
@onready var build_bar_label: Label = $HUD/BuildBarLabel
@onready var network_label: Label = $HUD/NetworkLabel
@onready var toast_label: Label = $HUD/ToastLabel

## Animación del aviso de arriba («Partida guardada»…), para cortarla si llega otro aviso.
var _toast_tween: Tween = null


func _ready() -> void:
	WorldState.reset()
	var inventory: Inventory = WorldState.player_inventory
	inventory.add_item(Content.find_item(&"wood"), START_WOOD)
	inventory.add_item(Content.find_item(&"stone"), START_STONE)
	inventory.add_item(Content.find_item(&"copper_ore"), START_ORE)
	inventory.add_item(Content.find_item(&"charcoal"), START_CHARCOAL)
	inventory.add_item(Content.find_item(&"iron_ingot"), START_IRON)
	inventory.add_item(Content.find_item(&"solar_cell"), START_CELLS)
	inventory.add_item(Content.find_item(&"copper_ingot"), START_COPPER_INGOTS)
	inventory.add_item(Content.find_item(&"copper_coil"), START_COILS)
	print("Inventario inicial: ", inventory.debug_string())
	# Naturaleza de prueba: una arboleda de 3×3 madura y unos árboles sueltos en distintas fases.
	var island: IslandState = WorldState.get_island(player.build_controller.island_id)
	# El suelo (TerrainView) sale de los límites de la isla: 40×40 m, como el suelo plano de antes.
	island.bounds = Rect2i(-20, -20, 40, 40)
	# Canal y estanque (D-094): primero, porque son terreno. El canal va de punta a punta y se vadea.
	var canal: Array[Vector2i] = []
	for y: int in range(-20, 20):
		canal.append(Vector2i(CANAL_X, y))
	island.add_water(canal, Vector2i(0, 1))
	var pond: Array[Vector2i] = []
	for x: int in 3:
		for y: int in 3:
			pond.append(POND_ORIGIN + Vector2i(x, y))
	island.add_water(pond, Vector2i.ZERO)
	for x: int in 3:
		for y: int in 3:
			island.add_tree(GROVE_ORIGIN + Vector2i(x, y))
	island.add_tree(Vector2i(-4, -3))
	island.add_tree(Vector2i(-6, -3), NatureState.Stage.YOUNG)
	island.add_tree(Vector2i(-8, -3), NatureState.Stage.SPROUT)
	island.add_tree(Vector2i(-10, -3), NatureState.Stage.STUMP)
	# Rocas (B2.8, D-090): aparecen solas cada 20 s dentro del suelo de 40×40 m; ponemos once para empezar.
	island.add_rock(Vector2i(-3, 1))
	island.add_rock(Vector2i(-5, 2))
	island.add_rock(Vector2i(6, 2))
	for rock_cell: Vector2i in [Vector2i(-2, 4), Vector2i(1, 5), Vector2i(4, 4), Vector2i(-7, 5), Vector2i(-9, 1),
			Vector2i(9, 4), Vector2i(-1, 8), Vector2i(3, 9)]:
		island.add_rock(rock_cell)
	# Veta de malaquita de 3×3 (B3.7): casillas x 6–8, y −4…−2, al este del inicio. E sobre los cristales
	# del centro: un golpe por segundo; 4 golpes = 1 mineral.
	island.add_vein(Content.find_vein(&"malachite_vein"), VEIN_ORIGIN)

	var builder: BuildController = player.build_controller
	player.focus_changed.connect(_on_player_focus_changed)
	test_box.interacted.connect(_on_test_box_interacted)
	builder.placed.connect(_on_building_placed)
	builder.place_failed.connect(_on_place_failed)
	builder.cable_changed.connect(_on_cable_changed)
	builder.mode_changed.connect(_update_label.unbind(1))
	builder.selection_changed.connect(_update_label)
	inventory.changed.connect(_update_label)
	SaveSystem.notification_requested.connect(_show_toast)
	add_child(SettingsPanel.new()) # F10: opciones gráficas y volúmenes (B5.3, B5.4)
	_start_music()
	toast_label.modulate.a = 0.0
	_update_label()


## F5 guarda y F9 carga (B5.2, D-040). Van aquí, en el sandbox, porque en el juego irán en el menú de pausa.
## La partida está en %APPDATA%\Godot\app_userdata\formica\savegame.json (la misma desde el editor y el .exe).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("save_game"):
		player.store_to_world()
		SaveSystem.save_game()
	elif event.is_action_pressed("load_game"):
		var result: String = SaveSystem.load_game()
		if result == "LOAD_DONE" or result == "LOAD_BACKUP":
			player.restore_from_world()
			_update_label()


## Música en bucle: el bucle se marca aquí (de la muestra 0 al final) en vez de en la importación.
func _start_music() -> void:
	var music: AudioStreamWAV = TEST_MUSIC.duplicate()
	music.loop_mode = AudioStreamWAV.LOOP_FORWARD
	music.loop_begin = 0
	music.loop_end = roundi(music.get_length() * music.mix_rate)
	var player_node := AudioStreamPlayer.new()
	player_node.stream = music
	player_node.bus = &"Music"
	add_child(player_node)
	player_node.play()


## Muestra un aviso traducido arriba durante 1,5 s y lo desvanece en 0,5 s.
func _show_toast(text_key: String) -> void:
	toast_label.text = tr(text_key)
	if _toast_tween != null:
		_toast_tween.kill()
	toast_label.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.5)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.5)


## Fuera del modo: "B: construir · Madera 100 · Piedra 100".
## Dentro: "[1 Trituradora]   2 Cinta   3 —  …" (la casilla elegida entre corchetes).
func _update_label() -> void:
	var builder: BuildController = player.build_controller
	var inventory: Inventory = WorldState.player_inventory
	var wood: ItemData = Content.find_item(&"wood")
	var stone: ItemData = Content.find_item(&"stone")
	var seed_item: ItemData = Content.find_item(&"seed")
	var materials: String = "%s %d · %s %d · %s %d" % [tr(wood.name_key), inventory.get_total(wood), tr(stone.name_key), inventory.get_total(stone), tr(seed_item.name_key), inventory.get_total(seed_item)]
	for id: StringName in [&"copper_ore", &"charcoal", &"copper_ingot", &"slag", &"iron_ingot", &"solar_cell", &"copper_coil"]:
		var item: ItemData = Content.find_item(id)
		if inventory.get_total(item) > 0:
			materials += " · %s %d" % [tr(item.name_key), inventory.get_total(item)]
	if not builder.active:
		build_bar_label.text = "B: construir · " + materials
		return
	var parts: PackedStringArray = []
	for i: int in BuildController.BAR_SIZE:
		var key: int = (i + 1) % 10 # la décima casilla va con el 0
		var text: String = "%d —" % key
		if i < builder.build_bar.size() and builder.build_bar[i] != null:
			text = "%d %s" % [key, tr(str(builder.build_bar[i].get("name_key")))]
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
