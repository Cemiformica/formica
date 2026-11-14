extends Node
## Prueba de `OccupancyGrid` (solo desarrollo).
## Ejecuta con F6 y mira la pestaña Salida: cada comprobación imprime OK o FALLO.
## Los avisos amarillos de «OccupancyGrid» son esperados (salen en Depurador): forman parte de la prueba.

var _failures: int = 0


func _ready() -> void:
	var grid := OccupancyGrid.new()
	var size := Vector2i(2, 3) # 2 de ancho (X) × 3 de fondo (Z)

	# 1) Giro de la huella.
	_check("sin girar: 2×3", OccupancyGrid.rotated_size(size, 0) == Vector2i(2, 3))
	_check("girada 90°: 3×2", OccupancyGrid.rotated_size(size, 1) == Vector2i(3, 2))
	# La esquina noroeste local (0,0) gira en sentido horario: NE a 90°, SE a 180°, SO a 270°.
	_check("esquina local a 90°", OccupancyGrid.local_to_cell(Vector2i.ZERO, size, 1, Vector2i(0, 0)) == Vector2i(2, 0))
	_check("esquina local a 180°", OccupancyGrid.local_to_cell(Vector2i.ZERO, size, 2, Vector2i(0, 0)) == Vector2i(1, 2))
	_check("esquina local a 270°", OccupancyGrid.local_to_cell(Vector2i.ZERO, size, 3, Vector2i(0, 0)) == Vector2i(0, 1))

	# 2) Colocar una construcción de 2×3 girada 90° en (10, 10): ocupa x 10–12, y 10–11.
	_check("coloca la primera", grid.place(1, Vector2i(10, 10), size, 1))
	_check("casilla interior ocupada", grid.get_occupant(Vector2i(12, 11)) == 1)
	_check("casilla de fuera libre", grid.get_occupant(Vector2i(10, 12)) == 0)

	# 3) Solapes y ids no válidos.
	_check("no se monta encima", not grid.place(2, Vector2i(11, 11), Vector2i.ONE, 0))
	_check("id repetido rechazado", not grid.place(1, Vector2i(0, 0), Vector2i.ONE, 0))
	_check("id 0 rechazado", not grid.place(0, Vector2i(0, 0), Vector2i.ONE, 0))
	_check("pegada al lado sí cabe", grid.place(2, Vector2i(13, 10), Vector2i.ONE, 0))

	# 4) Guardar y cargar (ida y vuelta por JSON).
	var json_text: String = JSON.stringify(grid.to_data())
	var restored := OccupancyGrid.new()
	restored.load_data(JSON.parse_string(json_text))
	_check("cargada: 2 construcciones", restored.get_occupant_count() == 2)
	_check("cargada: giro conservado", restored.get_occupant(Vector2i(12, 11)) == 1 and restored.get_occupant(Vector2i(10, 12)) == 0)

	# 5) Quitar libera todas sus casillas.
	_check("quita la primera", restored.remove(1))
	_check("casillas liberadas", restored.can_place(Vector2i(10, 10), size, 1))
	_check("quitar dos veces = false", not restored.remove(1))

	# 6) Datos dañados: se ignoran sin romper nada.
	var damaged := OccupancyGrid.new()
	damaged.load_data([{"id": 5, "x": 0, "y": 0, "w": 2, "h": 2, "r": 0}, "basura", {"id": 6, "x": 1, "y": 1, "w": 1, "h": 1, "r": 0}, {"id": 7}])
	_check("dañados: solo queda la válida", damaged.get_occupant_count() == 1 and damaged.get_occupant(Vector2i(1, 1)) == 5)

	if _failures == 0:
		print("--- OccupancyGrid: TODO OK ---")
	else:
		print("--- OccupancyGrid: %d FALLOS ---" % _failures)


func _check(label: String, condition: bool) -> void:
	if condition:
		print("OK    ", label)
	else:
		_failures += 1
		push_error("FALLO " + label)
