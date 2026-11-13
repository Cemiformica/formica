extends Node
## Prueba de `Content` y del guardado de inventarios (solo desarrollo).
## Ejecuta con F6 y mira la pestaña Salida: cada comprobación imprime OK o FALLO.
## Los avisos amarillos de «Ítem desconocido» son esperados: forman parte de la prueba.

var _failures: int = 0


func _ready() -> void:
	# 1) Búsqueda por id en el catálogo.
	var wood: ItemData = Content.find_item(&"wood")
	var stone: ItemData = Content.find_item(&"stone")
	_check("encuentra madera", wood != null and wood.id == &"wood")
	_check("encuentra receta", Content.find_recipe(&"crush_stone") != null)
	_check("id inexistente = null", Content.find_item(&"unobtainium") == null)

	# 2) Ida y vuelta: inventario → datos → JSON → datos → inventario.
	var original := Inventory.new(4)
	original.add_item(wood, 70) # 50 + 20
	original.add_item(stone, 3)
	var json_text: String = JSON.stringify(original.to_data())
	var restored := Inventory.new(4)
	restored.load_data(JSON.parse_string(json_text))
	_check("madera igual", restored.get_total(wood) == 70)
	_check("piedra igual", restored.get_total(stone) == 3)
	_check("mismas casillas", restored.debug_string() == original.debug_string())

	# 3) Datos dañados o antiguos: se ignora lo que no se entiende, sin romper nada.
	var damaged: Array = [{"id": "unobtainium", "amount": 5}, "basura", {"id": "wood", "amount": 999}, null, {"id": "stone"}]
	var safe := Inventory.new(3)
	safe.load_data(damaged)
	_check("ignora id desconocido", safe.slots[0] == null)
	_check("ignora entrada rara", safe.slots[1] == null)
	_check("recorta a max_stack", safe.get_total(wood) == wood.max_stack)
	_check("sobran casillas: no peta", safe.get_slot_count() == 3)

	print("--- Content y guardado: %s ---" % ("TODO OK" if _failures == 0 else "%d FALLOS" % _failures))


func _check(label: String, condition: bool) -> void:
	if condition:
		print("OK    ", label)
	else:
		_failures += 1
		push_error("FALLO " + label)
