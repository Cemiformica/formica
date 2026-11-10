class_name Inventory
extends RefCounted
## Inventario por casillas, como DATOS (D-046): no es un nodo. Lo pueden tener el jugador, una caja o
## la entrada/salida de una máquina, y `Simulation` puede usarlo aunque no haya nada en pantalla.
## Guarda referencias a ItemData (contenido) y cantidades (estado). Las ventanas y los nodos
## solo lo muestran y escuchan su señal `changed`.

## Se emite cada vez que cambia el contenido.
signal changed

## Ítems que se pueden meter. Vacío = cualquiera (p. ej., la entrada de una máquina solo admite su receta).
var accepted_items: Array[ItemData] = []
## Si es false, solo se puede sacar (p. ej., la salida de una máquina).
var allow_insert: bool = true
## Casillas: null = vacía; ItemStack = ocupada.
var slots: Array[ItemStack] = []


## `slot_count`: número de casillas. Ejemplo: `Inventory.new(12)`.
func _init(slot_count: int = 12, p_accepted_items: Array[ItemData] = [], p_allow_insert: bool = true) -> void:
	slots.resize(maxi(slot_count, 1))
	accepted_items = p_accepted_items
	allow_insert = p_allow_insert


## Número de casillas.
func get_slot_count() -> int:
	return slots.size()


## Añade `amount` unidades de `item`. Devuelve las que NO cupieron (0 si cupo todo).
func add_item(item: ItemData, amount: int) -> int:
	var remaining: int = amount

	# 1) Rellenar pilas existentes del mismo ítem.
	for stack: ItemStack in slots:
		if remaining == 0:
			break
		if stack != null and stack.item == item and stack.space_left() > 0:
			var moved: int = mini(remaining, stack.space_left())
			stack.amount += moved
			remaining -= moved

	# 2) Ocupar casillas vacías.
	for i: int in slots.size():
		if remaining == 0:
			break
		if slots[i] == null:
			var moved: int = mini(remaining, item.max_stack)
			slots[i] = ItemStack.new(item, moved)
			remaining -= moved

	if remaining != amount:
		changed.emit()
	return remaining


## Quita `amount` unidades de `item`, empezando por las últimas casillas.
## Devuelve true si había suficientes (y las quita); false si no (y no toca nada).
func remove_item(item: ItemData, amount: int) -> bool:
	if get_total(item) < amount:
		return false
	var remaining: int = amount
	for i: int in range(slots.size() - 1, -1, -1):
		if remaining == 0:
			break
		var stack: ItemStack = slots[i]
		if stack == null or stack.item != item:
			continue
		var taken: int = mini(remaining, stack.amount)
		stack.amount -= taken
		remaining -= taken
		if stack.amount == 0:
			slots[i] = null # La casilla queda vacía.
	changed.emit()
	return true


## ¿Hay al menos lo indicado de cada ítem? `costs` relaciona ItemData con cantidad.
func has_items(costs: Dictionary[ItemData, int]) -> bool:
	for item: ItemData in costs:
		if get_total(item) < costs[item]:
			return false
	return true


## ¿Cabrían todos estos ítems a la vez? Lo simula sobre una copia: no cambia el inventario.
func can_add_all(items: Dictionary[ItemData, int]) -> bool:
	# Copia ligera: por casilla, [ítem, cantidad] o null.
	var sim: Array = []
	for stack: ItemStack in slots:
		sim.append(null if stack == null else [stack.item, stack.amount])
	for item: ItemData in items:
		var remaining: int = items[item]
		for entry: Variant in sim:
			if remaining == 0:
				break
			if entry != null and entry[0] == item:
				var moved: int = mini(remaining, item.max_stack - int(entry[1]))
				entry[1] = int(entry[1]) + moved
				remaining -= moved
		for i: int in sim.size():
			if remaining == 0:
				break
			if sim[i] == null:
				var moved: int = mini(remaining, item.max_stack)
				sim[i] = [item, moved]
				remaining -= moved
		if remaining > 0:
			return false
	return true


## ¿Se puede meter `item` en la casilla `index` desde la interfaz?
func can_insert(index: int, item: ItemData) -> bool:
	if not allow_insert or index < 0 or index >= slots.size():
		return false
	return accepted_items.is_empty() or item in accepted_items


## Mueve la pila de la casilla `from_index` a la casilla `to_index` de `target` (puede ser este mismo
## inventario). Si el destino está vacío, la mueve; si tiene el mismo ítem, junta lo que quepa;
## si tiene otro ítem, las intercambia (solo si ambos lados lo admiten).
func transfer_to(from_index: int, target: Inventory, to_index: int) -> void:
	var stack: ItemStack = slots[from_index]
	if stack == null or (target == self and from_index == to_index):
		return
	if not target.can_insert(to_index, stack.item):
		return
	var dest: ItemStack = target.slots[to_index]
	if dest == null:
		target.slots[to_index] = stack
		slots[from_index] = null
	elif dest.item == stack.item:
		var moved: int = mini(stack.amount, dest.space_left())
		if moved == 0:
			return
		dest.amount += moved
		stack.amount -= moved
		if stack.amount == 0:
			slots[from_index] = null
	else:
		# Intercambio: el ítem del destino tiene que poder volver a nuestra casilla.
		if not can_insert(from_index, dest.item) and target != self:
			return
		target.slots[to_index] = stack
		slots[from_index] = dest
	changed.emit()
	if target != self:
		target.changed.emit()


## Total de unidades de `item` sumando todas las casillas.
func get_total(item: ItemData) -> int:
	var total: int = 0
	for stack: ItemStack in slots:
		if stack != null and stack.item == item:
			total += stack.amount
	return total


## Texto de depuración con el contenido (solo consola, no se traduce).
func debug_string() -> String:
	var parts: PackedStringArray = []
	for stack: ItemStack in slots:
		if stack != null:
			parts.append("%s×%d" % [stack.item.id, stack.amount])
	return "[" + ", ".join(parts) + "]"
