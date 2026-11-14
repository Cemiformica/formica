extends Node
## Prueba de `IslandState` y `PlacedBuilding`: construcciones colocadas en datos (solo desarrollo).
## Ejecuta con F6 y mira la pestaña Salida: cada comprobación imprime OK o FALLO.
## En Depurador salen 3 avisos amarillos esperados (bloque 5: datos dañados a propósito).

var _failures: int = 0


func _ready() -> void:
	var crusher: BuildingData = Content.find_building(&"crusher")
	var stone: ItemData = Content.find_item(&"stone")
	var gravel: ItemData = Content.find_item(&"gravel")

	# 1) La trituradora está en el catálogo, con su receta y sus puertos.
	_check("trituradora en el catálogo", crusher != null and crusher.recipe != null)
	_check("trituradora con 2 puertos", crusher != null and crusher.ports.size() == 2)

	# 2) Colocar.
	var island := IslandState.new()
	var m1: PlacedBuilding = island.place(crusher, Vector2i(0, 0))
	var m2: PlacedBuilding = island.place(crusher, Vector2i(2, 0), 1, true)
	_check("coloca dos máquinas", m1 != null and m2 != null and m1.id == 1 and m2.id == 2)
	_check("no se monta encima", island.place(crusher, Vector2i(0, 0)) == null)
	_check("busca por casilla", island.get_at(Vector2i(2, 0)) == m2 and island.get_at(Vector2i(1, 0)) == null)
	_check("es máquina con entrada y salida", m1.is_machine() and m1.input != null and m1.output != null)
	_check("la entrada solo admite piedra", m1.input.can_insert(0, stone) and not m1.input.can_insert(0, gravel))
	_check("en la salida no se mete nada", not m1.output.can_insert(0, gravel))

	# 3) Guardar y cargar con contenido y progreso.
	m1.input.add_item(stone, 5)
	m1.output.add_item(gravel, 3)
	m1.progress = 1.5
	var json_text: String = JSON.stringify(island.to_data())
	var restored := IslandState.new()
	restored.load_data(JSON.parse_string(json_text))
	var r1: PlacedBuilding = restored.get_at(Vector2i(0, 0))
	var r2: PlacedBuilding = restored.get_at(Vector2i(2, 0))
	_check("cargada: 2 construcciones", restored.buildings.size() == 2)
	_check("cargada: contenido y progreso", r1 != null and r1.input.get_total(stone) == 5 and r1.output.get_total(gravel) == 3 and is_equal_approx(r1.progress, 1.5))
	_check("cargada: giro y reflejo", r2 != null and r2.rotation == 1 and r2.flipped)

	# 4) Quitar libera la casilla y los ids no se reutilizan.
	var removed: PlacedBuilding = restored.remove(1)
	_check("quitar devuelve la máquina", removed != null and removed.input.get_total(stone) == 5)
	_check("casilla libre tras quitar", restored.get_at(Vector2i(0, 0)) == null and restored.can_place(crusher, Vector2i(0, 0)))
	var m3: PlacedBuilding = restored.place(crusher, Vector2i(0, 0))
	_check("id nuevo, no reutilizado", m3 != null and m3.id == 3)

	# 5) Datos dañados: tipo desconocido, entrada basura y solape se ignoran sin romper nada.
	var damaged := IslandState.new()
	damaged.load_data({"next_id": 1, "buildings": [ # next_id desfasado a propósito
		{"id": 1, "type": "crusher", "x": 0, "y": 0, "r": 0},
		{"id": 2, "type": "unobtainium", "x": 5, "y": 5},
		"basura",
		{"id": 3, "type": "crusher", "x": 0, "y": 0},
	]})
	_check("dañados: solo queda la válida", damaged.buildings.size() == 1 and damaged.get_at(Vector2i(0, 0)) != null)
	_check("dañados: el siguiente id salta los usados", damaged.place(crusher, Vector2i(1, 0)).id == 2)

	if _failures == 0:
		print("--- IslandState: TODO OK ---")
	else:
		print("--- IslandState: %d FALLOS ---" % _failures)


func _check(label: String, condition: bool) -> void:
	if condition:
		print("OK    ", label)
	else:
		_failures += 1
		push_error("FALLO " + label)
