class_name NatureState
extends RefCounted
## Algo natural que ocupa una casilla de la isla (B2.7, B2.8; D-057, D-069): un árbol, una roca o unos palos
## caídos (C3, César: se recogen con la E como las rocas y dan madera para empezar sin herramientas).
## Bloquea construir en su casilla (ver `IslandState`).
##
## Ciclo del árbol: TOCÓN → BROTE → JOVEN → MADURO, 30 s por fase (90 s en total).
## Talar un árbol maduro deja un TOCÓN que, si no se arranca, rebrota solo (monte bajo).
## Solo el tocón se puede arrancar (libera la casilla).

enum Kind { TREE, ROCK, STICKS }   # al final, para que las partidas guardadas sigan valiendo
## Especies de árbol (C1.9, César): cada una da su semilla y se dibuja con su modelo.
const OAK: StringName = &"oak"
const PINE: StringName = &"pine"
## Semilla que da cada especie al talarla a mano (y que la planta).
const SEED_ITEMS: Dictionary[StringName, StringName] = {OAK: &"acorn", PINE: &"pine_cone"}
## Árboles salvajes: uno de cada PINE_EVERY es pino, según su casilla (la misma regla que antes, así las
## partidas antiguas, que no guardaban la especie, conservan sus árboles).
const PINE_EVERY: int = 4
## El orden importa: cada fase pasa a la siguiente.
enum Stage { STUMP, SPROUT, YOUNG, MATURE }

## Segundos que dura cada fase hasta pasar a la siguiente.
const STAGE_TIME: float = 30.0
## Talar a mano (D-090, César): golpes de E que hacen falta y segundos mínimos entre golpe y golpe.
## La herramienta necesaria llegará con las herramientas (fase C).
const CHOP_HITS: int = 4
const HIT_COOLDOWN: float = 1.0

var kind: Kind = Kind.TREE
## Especie del árbol (`OAK` o `PINE`); vacía en las rocas.
var species: StringName = &""
var stage: Stage = Stage.MATURE
## Segundos que lleva en la fase actual.
var timer: float = 0.0


func _init(p_kind: Kind = Kind.TREE, p_stage: Stage = Stage.MATURE, p_species: StringName = OAK) -> void:
	kind = p_kind
	stage = p_stage
	species = p_species if p_kind == Kind.TREE else &""


## Número fijo y bien repartido para una casilla (no cambia entre partidas). Lo usan la especie de los
## árboles salvajes y la vista (variante, giro y tamaño).
static func cell_hash(cell: Vector2i) -> int:
	var h: int = (cell.x * 73856093) ^ (cell.y * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	return (h ^ (h >> 16)) & 0x7fffffff


## Especie de un árbol salvaje en esta casilla.
static func wild_species(cell: Vector2i) -> StringName:
	return PINE if (cell_hash(cell) >> 3) % PINE_EVERY == 0 else OAK


## ¿Es un árbol maduro (se puede talar)?
func is_mature_tree() -> bool:
	return kind == Kind.TREE and stage == Stage.MATURE


## ¿Es una roca (se puede picar)?
func is_rock() -> bool:
	return kind == Kind.ROCK


## ¿Son unos palos caídos (se recogen con la E)?
func is_sticks() -> bool:
	return kind == Kind.STICKS


## ¿Es un tocón (se puede arrancar)?
func is_stump() -> bool:
	return kind == Kind.TREE and stage == Stage.STUMP


## Avanza `dt` segundos. Devuelve true si ha cambiado de fase (la vista se redibuja).
func grow(dt: float) -> bool:
	if kind != Kind.TREE or stage == Stage.MATURE:
		return false
	timer += dt
	if timer + 0.0001 < STAGE_TIME:
		return false
	timer = 0.0
	stage = (stage + 1) as Stage
	return true


func to_data(cell: Vector2i) -> Dictionary:
	var data: Dictionary = {"x": cell.x, "y": cell.y, "k": kind, "s": stage, "t": timer}
	if kind == Kind.TREE:
		data["sp"] = String(species)
	return data
