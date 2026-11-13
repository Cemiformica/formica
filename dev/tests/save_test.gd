extends Node
## Prueba de `WorldState` + `SaveSystem` (solo desarrollo). Ejecuta con F6 y mira la pestaña Salida.
## Usa un archivo de prueba propio, así que nunca toca la partida real. Los avisos amarillos son
## esperados: la prueba estropea el guardado a propósito.

const TEST_PATH: String = "user://test_save.json"

var _failures: int = 0


func _ready() -> void:
	_delete_test_files()
	var wood: ItemData = Content.find_item(&"wood")
	var inventory_ref: Inventory = WorldState.player_inventory

	# 1) Sin partida.
	_check("sin partida → SAVE_NONE", SaveSystem.load_game(TEST_PATH) == "SAVE_NONE")

	# 2) Guardar dos veces: la segunda deja la primera como copia.
	WorldState.reset()
	WorldState.player_inventory.add_item(wood, 30)
	WorldState.current_island = &"alba"
	WorldState.player_position = Vector3(1.5, 2.0, -3.0)
	WorldState.islands[&"alba"] = {"note": "prueba"}
	_check("guardar 1", SaveSystem.save_game(TEST_PATH) == "SAVE_DONE")
	WorldState.player_inventory.remove_item(wood, 20) # quedan 10
	_check("guardar 2", SaveSystem.save_game(TEST_PATH) == "SAVE_DONE")
	_check("hay copia .bak", FileAccess.file_exists("user://test_save.bak.json"))

	# 3) Cargar sobre un estado distinto: vuelve lo guardado.
	WorldState.reset()
	_check("cargar → LOAD_DONE", SaveSystem.load_game(TEST_PATH) == "LOAD_DONE")
	_check("madera = 10", WorldState.player_inventory.get_total(wood) == 10)
	_check("isla", WorldState.current_island == &"alba")
	_check("posición", WorldState.player_position.is_equal_approx(Vector3(1.5, 2.0, -3.0)))
	_check("datos de isla", WorldState.islands.get(&"alba", {}).get("note", "") == "prueba")
	_check("mismo objeto de inventario", WorldState.player_inventory == inventory_ref)

	# 4) Principal dañada: se carga la copia (la de 30 de madera).
	_write(TEST_PATH, "{esto no es json")
	_check("dañada → LOAD_BACKUP", SaveSystem.load_game(TEST_PATH) == "LOAD_BACKUP")
	_check("madera de la copia = 30", WorldState.player_inventory.get_total(wood) == 30)

	# 5) Partida de una versión futura: no se carga y no toca el estado.
	_write(TEST_PATH, '{"version": 99, "world": {}}')
	DirAccess.remove_absolute("user://test_save.bak.json")
	_check("versión futura → LOAD_TOO_NEW", SaveSystem.load_game(TEST_PATH) == "LOAD_TOO_NEW")
	_check("estado intacto", WorldState.player_inventory.get_total(wood) == 30)

	_delete_test_files()
	WorldState.reset()
	print("--- WorldState y SaveSystem: %s ---" % ("TODO OK" if _failures == 0 else "%d FALLOS" % _failures))


func _check(label: String, condition: bool) -> void:
	if condition:
		print("OK    ", label)
	else:
		_failures += 1
		push_error("FALLO " + label)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _delete_test_files() -> void:
	for path: String in ["user://test_save.json", "user://test_save.bak.json", "user://test_save.json.tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
