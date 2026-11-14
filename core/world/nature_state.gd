class_name NatureState
extends RefCounted
## Algo natural que ocupa una casilla de la isla (B2.7, B2.8; D-057, D-069): un árbol o una roca.
## Bloquea construir en su casilla (ver `IslandState`).
##
## Ciclo del árbol: TOCÓN → BROTE → JOVEN → MADURO, 30 s por fase (90 s en total).
## Talar un árbol maduro deja un TOCÓN que, si no se arranca, rebrota solo (monte bajo).
## Solo el tocón se puede arrancar (libera la casilla).

enum Kind { TREE, ROCK }
## El orden importa: cada fase pasa a la siguiente.
enum Stage { STUMP, SPROUT, YOUNG, MATURE }

## Segundos que dura cada fase hasta pasar a la siguiente.
const STAGE_TIME: float = 30.0

var kind: Kind = Kind.TREE
var stage: Stage = Stage.MATURE
## Segundos que lleva en la fase actual.
var timer: float = 0.0


func _init(p_kind: Kind = Kind.TREE, p_stage: Stage = Stage.MATURE) -> void:
	kind = p_kind
	stage = p_stage


## ¿Es un árbol maduro (se puede talar)?
func is_mature_tree() -> bool:
	return kind == Kind.TREE and stage == Stage.MATURE


## ¿Es una roca (se puede picar)?
func is_rock() -> bool:
	return kind == Kind.ROCK


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
	return {"x": cell.x, "y": cell.y, "k": kind, "s": stage, "t": timer}
