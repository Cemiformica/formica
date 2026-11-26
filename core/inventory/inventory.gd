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
## Casillas reservadas (sesión 28, César): si no está vacío, la casilla i solo admite `slot_items[i]`. Lo usa la
## entrada de las máquinas, una casilla por ingrediente: así un ingrediente que llega en abundancia no ocupa la casilla
## del otro y la máquina no se atasca.
var slot_items: Array[ItemData] = []
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
		if slots[i] == null and _slot_allows(i, item):
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
		if stack == null:
			sim.append(null)
		else:
			sim.append([stack.item, stack.amount])
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
			if sim[i] == null and _slot_allows(i, item):
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
	if not _slot_allows(index, item):
		return false
	return accepted_items.is_empty() or item in accepted_items


## ¿Admite la casilla `index` este ítem según `slot_items`? (sin reservas, cualquiera)
func _slot_allows(index: int, item: ItemData) -> bool:
	return slot_items.is_empty() or index >= slot_items.size() or slot_items[index] == item


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


## Primera casilla vacía (y que admita `item`, si se da) entre `from` y `to` (sin incluir `to`; -1 = hasta el
## final). Devuelve -1 si no hay ninguna.
func find_empty(from: int = 0, to: int = -1, item: ItemData = null) -> int:
	var end: int = slots.size() if to < 0 else mini(to, slots.size())
	for i: int in range(maxi(from, 0), end):
		if slots[i] == null and (item == null or can_insert(i, item)):
			return i
	return -1


## Parte la pila de `index` (C1.2): la mitad, redondeando hacia abajo, pasa a la primera casilla vacía entre
## `from` y `to`. Devuelve false si la pila tiene menos de 2 o no hay hueco.
func split_half(index: int, from: int = 0, to: int = -1) -> bool:
	var stack: ItemStack = slots[index]
	if stack == null or stack.amount < 2:
		return false
	var empty: int = find_empty(from, to, stack.item)
	if empty < 0:
		return false
	@warning_ignore("integer_division")
	var half: int = stack.amount / 2 # se redondea hacia abajo a propósito
	stack.amount -= half
	slots[empty] = ItemStack.new(stack.item, half)
	changed.emit()
	return true


## Mueve rápido la pila de `index` a `target`, entre las casillas `from` y `to` (C1.2, Mayús + clic):
## primero junta con pilas del mismo ítem y después ocupa casillas vacías. Lo que no quepa se queda donde
## estaba. `target` puede ser este mismo inventario (p. ej., de la barra a la mochila).
func quick_move(index: int, target: Inventory, from: int = 0, to: int = -1) -> void:
	var stack: ItemStack = slots[index]
	if stack == null:
		return
	var end: int = target.slots.size() if to < 0 else mini(to, target.slots.size())
	# 1) Juntar con pilas del mismo ítem.
	for i: int in range(maxi(from, 0), end):
		if stack.amount == 0:
			break
		var dest: ItemStack = target.slots[i]
		if (target == self and i == index) or dest == null or dest.item != stack.item:
			continue
		var moved: int = mini(stack.amount, dest.space_left())
		dest.amount += moved
		stack.amount -= moved
	# 2) Ocupar casillas vacías (la pila entera de golpe, si cabe en una).
	if stack.amount > 0:
		var empty: int = target.find_empty(from, to, stack.item)
		if empty >= 0:
			target.slots[empty] = stack
			slots[index] = null
	if stack.amount == 0:
		slots[index] = null
	changed.emit()
	if target != self:
		target.changed.emit()


## Coge la pila de `index` para llevarla en la mano (C1.2): entera, o con `half` la mitad redondeando hacia
## arriba (clic derecho). Devuelve null si la casilla estaba vacía.
func take_stack(index: int, half: bool = false) -> ItemStack:
	var stack: ItemStack = slots[index]
	if stack == null:
		return null
	if not half or stack.amount == 1:
		slots[index] = null
		changed.emit()
		return stack
	var taken: int = ceili(stack.amount / 2.0)
	stack.amount -= taken
	changed.emit()
	return ItemStack.new(stack.item, taken)


## Deja en la casilla `index` la pila que se lleva en la mano (C1.2). Si está vacía, la pone; si tiene el
## mismo ítem, junta lo que quepa; si tiene otro ítem y `allow_swap`, las intercambia. Con `max_amount` (1 con
## clic derecho) deja como mucho esa cantidad y nunca intercambia. Devuelve lo que queda en la mano (null si
## nada): el resto, la pila intercambiada o la misma pila si la casilla no la admite.
func put_stack(index: int, stack: ItemStack, max_amount: int = -1, allow_swap: bool = true) -> ItemStack:
	if stack == null:
		return null
	if not can_insert(index, stack.item):
		return stack
	var dest: ItemStack = slots[index]
	var amount: int = stack.amount if max_amount < 0 else mini(max_amount, stack.amount)
	if dest == null:
		var placed: int = mini(amount, stack.item.max_stack)
		slots[index] = ItemStack.new(stack.item, placed)
		stack.amount -= placed
	elif dest.item == stack.item:
		var moved: int = mini(amount, dest.space_left())
		dest.amount += moved
		stack.amount -= moved
	elif allow_swap and max_amount < 0:
		slots[index] = stack
		changed.emit()
		return dest
	else:
		return stack
	changed.emit()
	return null if stack.amount == 0 else stack


## Total de unidades de `item` sumando todas las casillas.
func get_total(item: ItemData) -> int:
	var total: int = 0
	for stack: ItemStack in slots:
		if stack != null and stack.item == item:
			total += stack.amount
	return total


## Inventario → datos simples para el guardado (JSON): una entrada por casilla,
## null si está vacía o {"id": "wood", "amount": 4} si está ocupada.
## Solo se guarda el contenido; las reglas (`accepted_items`, `allow_insert`) son de quien lo crea.
func to_data() -> Array:
	var data: Array = []
	for stack: ItemStack in slots:
		if stack == null:
			data.append(null)
		else:
			data.append({"id": String(stack.item.id), "amount": stack.amount})
	return data


## Datos del guardado → contenido de este inventario (sustituye lo que hubiera).
## Es tolerante: ignora con aviso ids desconocidos y entradas raras, recorta cantidades a
## `max_stack` y descarta las casillas que sobren. Un guardado dañado nunca rompe la partida.
func load_data(data: Array) -> void:
	for i: int in slots.size():
		slots[i] = null
		if i >= data.size() or data[i] == null:
			continue
		if not data[i] is Dictionary:
			push_warning("Inventario: casilla %d con datos no válidos en el guardado" % i)
			continue
		var entry: Dictionary = data[i]
		var item: ItemData = Content.find_item(StringName(str(entry.get("id", ""))))
		if item == null:
			push_warning("Inventario: ítem desconocido en el guardado: '%s'" % entry.get("id", ""))
			continue
		var amount: int = clampi(int(entry.get("amount", 0)), 0, item.max_stack)
		if amount > 0:
			slots[i] = ItemStack.new(item, amount)
	changed.emit()


## Texto de depuración con el contenido (solo consola, no se traduce).
func debug_string() -> String:
	var parts: PackedStringArray = []
	for stack: ItemStack in slots:
		if stack != null:
			parts.append("%s×%d" % [stack.item.id, stack.amount])
	return "[" + ", ".join(parts) + "]"
