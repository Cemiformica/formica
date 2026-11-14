class_name PowerNetwork
extends RefCounted
## Una red eléctrica: construcciones unidas por cables (D-068). La crea `IslandState` y se rehace
## cuando cambian las construcciones o los cables, así que no se guarda: lo que se guarda son los
## cables y el fusible de cada generador.
## Regla: si lo que consume la red supera lo que genera, salta el fusible y nada de la red trabaja
## hasta quitar carga y rearmarlo (E sobre un generador, B2.6b).

const EPSILON: float = 0.0001

## Construcciones de la red.
var members: Array[PlacedBuilding] = []
## Puntos que generan sus generadores.
var supply: float = 0.0
## Puntos que piden sus consumidores conectados (cuentan siempre enteros, trabajen o no).
var demand: float = 0.0


## Añade una construcción a la red (lo usa `IslandState` al rehacer las redes).
func add(placed: PlacedBuilding) -> void:
	members.append(placed)
	if placed.data.power > 0.0:
		supply += placed.data.power
	elif placed.data.power < 0.0:
		demand -= placed.data.power


## ¿Pide más de lo que genera?
func is_overloaded() -> bool:
	return demand > supply + EPSILON


## ¿Ha saltado el fusible? (algún generador de la red lo tiene saltado)
func is_tripped() -> bool:
	for placed: PlacedBuilding in members:
		if placed.data.power > 0.0 and placed.fuse_tripped:
			return true
	return false


## ¿Funciona? Tiene generadores, no está sobrecargada y el fusible está armado.
func is_powered() -> bool:
	return supply > 0.0 and not is_overloaded() and not is_tripped()


## Salta el fusible: se marca en todos sus generadores (así se guarda y sobrevive al rehacer la red).
func trip() -> void:
	for placed: PlacedBuilding in members:
		if placed.data.power > 0.0:
			placed.fuse_tripped = true


## Rearma el fusible. Si la red sigue sobrecargada, volverá a saltar en el siguiente paso.
func reset_fuse() -> void:
	for placed: PlacedBuilding in members:
		placed.fuse_tripped = false
