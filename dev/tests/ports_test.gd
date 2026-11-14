extends Node
## Prueba de `PortData`: puertos que giran y se reflejan con la construcción (solo desarrollo).
## Ejecuta con F6 y mira la pestaña Salida: cada comprobación imprime OK o FALLO.
## Usa un horno de prueba de 2×2 creado en código: entradas al oeste, salidas al este.

var _failures: int = 0


func _ready() -> void:
	# Horno de prueba (en código, sin .tres). Piedra y grava hacen de lingote y escoria.
	var furnace := BuildingData.new()
	furnace.id = &"test_furnace"
	furnace.size = Vector2i(2, 2)
	var in_a := _port(PortData.Kind.INPUT, Vector2i(0, 0), PortData.PortSide.WEST, null)
	var in_b := _port(PortData.Kind.INPUT, Vector2i(0, 1), PortData.PortSide.WEST, null)
	var out_a := _port(PortData.Kind.OUTPUT, Vector2i(1, 0), PortData.PortSide.EAST, Content.find_item(&"stone"))
	var out_b := _port(PortData.Kind.OUTPUT, Vector2i(1, 1), PortData.PortSide.EAST, Content.find_item(&"gravel"))
	furnace.ports = [in_a, in_b, out_a, out_b]
	var size: Vector2i = furnace.size
	var o := Vector2i.ZERO # origen de la construcción en la cuadrícula

	# 1) Sin girar: entradas al oeste, salidas al este.
	_check("0°: entrada mira al oeste", in_a.get_grid_side(0, false) == PortData.PortSide.WEST)
	_check("0°: entrada apunta a (-1,0)", in_a.get_target_cell(o, size, 0, false) == Vector2i(-1, 0))
	_check("0°: salida apunta a (2,0)", out_a.get_target_cell(o, size, 0, false) == Vector2i(2, 0))

	# 2) A 90°: entradas al norte y salidas al sur.
	_check("90°: entradas miran al norte", in_a.get_grid_side(1, false) == PortData.PortSide.NORTH and in_b.get_grid_side(1, false) == PortData.PortSide.NORTH)
	_check("90°: salidas miran al sur", out_a.get_grid_side(1, false) == PortData.PortSide.SOUTH and out_b.get_grid_side(1, false) == PortData.PortSide.SOUTH)
	_check("90°: entrada A apunta a (1,-1)", in_a.get_target_cell(o, size, 1, false) == Vector2i(1, -1))
	_check("90°: salida A apunta a (1,2)", out_a.get_target_cell(o, size, 1, false) == Vector2i(1, 2))

	# 3) A 180° y 270°.
	_check("180°: entrada A apunta a (2,1)", in_a.get_target_cell(o, size, 2, false) == Vector2i(2, 1))
	_check("180°: salida A apunta a (-1,1)", out_a.get_target_cell(o, size, 2, false) == Vector2i(-1, 1))
	_check("270°: entrada A apunta a (0,2)", in_a.get_target_cell(o, size, 3, false) == Vector2i(0, 2))
	_check("270°: salida A apunta a (0,-1)", out_a.get_target_cell(o, size, 3, false) == Vector2i(0, -1))

	# 4) Reflejar intercambia las salidas (sin girar y girado 90°).
	_check("reflejo 0°: salidas intercambiadas", out_a.get_target_cell(o, size, 0, true) == out_b.get_target_cell(o, size, 0, false)
			and out_b.get_target_cell(o, size, 0, true) == out_a.get_target_cell(o, size, 0, false))
	_check("reflejo 90°: salidas intercambiadas", out_a.get_target_cell(o, size, 1, true) == out_b.get_target_cell(o, size, 1, false))
	_check("reflejo: norte pasa a sur", PortData.transform_side(PortData.PortSide.NORTH, 0, true) == PortData.PortSide.SOUTH)
	_check("reflejo: este se queda", PortData.transform_side(PortData.PortSide.EAST, 0, true) == PortData.PortSide.EAST)

	# 5) En cualquier giro y reflejo, cada puerto está DENTRO de la huella y apunta FUERA de ella.
	var all_ok: bool = true
	for rotation: int in 4:
		for flipped: bool in [false, true]:
			var cells: Array[Vector2i] = OccupancyGrid.footprint_cells(o, size, rotation)
			for port: PortData in furnace.ports:
				if not cells.has(port.get_grid_cell(o, size, rotation, flipped)):
					all_ok = false
				if cells.has(port.get_target_cell(o, size, rotation, flipped)):
					all_ok = false
	_check("todos los giros: dentro y apuntando fuera", all_ok)

	# 6) Los filtros se conservan.
	_check("salida A saca piedra", out_a.item_filter == Content.find_item(&"stone"))
	_check("entradas sin filtro", in_a.item_filter == null and in_b.item_filter == null)

	# 7) Reflejar solo cuando cambia algo: el horno sí (salidas con filtros distintos), la trituradora no.
	_check("horno: se puede reflejar", furnace.can_flip())
	_check("trituradora: reflejar no cambia nada", not Content.find_building(&"crusher").can_flip())

	if _failures == 0:
		print("--- PortData: TODO OK ---")
	else:
		print("--- PortData: %d FALLOS ---" % _failures)


func _port(kind: PortData.Kind, cell: Vector2i, side: PortData.PortSide, filter: ItemData) -> PortData:
	var port := PortData.new()
	port.kind = kind
	port.cell = cell
	port.side = side
	port.item_filter = filter
	return port


func _check(label: String, condition: bool) -> void:
	if condition:
		print("OK    ", label)
	else:
		_failures += 1
		push_error("FALLO " + label)
