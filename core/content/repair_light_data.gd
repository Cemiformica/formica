class_name RepairLightData
extends Resource
## Una luz de una estructura por reparar que el jugador enciende y apaga con E (C5.5, D-191): el candil y el fogón
## del refugio; más adelante, la baliza del embarcadero o los faroles. Es contenido; si está encendida vive en
## `RepairSite.lit`. Solo se puede usar con la estructura completa.

## Identificador estable dentro de su estructura.
@export var id: StringName = &""
## Clave de traducción del nombre visible («REPAIR_LIGHT_LANTERN»…).
@export var name_key: String = ""
## Vacío del modelo donde va la luz (y el centro de la zona para apuntarle).
@export var light_node: StringName = &""
## Tamaño de la zona para apuntarle (m), centrada en `light_node`.
@export var aim_size: Vector3 = Vector3(0.5, 0.5, 0.5)
## Mallas de llama: las que empiezan por este prefijo («lantern_flame», «hearth_flame»…).
@export var flame_prefix: String = ""
## Malla de las brasas (solo las hogueras), o vacío.
@export var ember_node: StringName = &""
## Hoguera (llamas que bailan, brasas, chispas y humo al apagarse) o farol (una llama quieta que parpadea).
@export var fire: bool = false
## Se enciende sola la primera vez que se completa la estructura (el candil: la recompensa de «ya es mi casa»).
@export var lit_on_complete: bool = false
## Lo que gasta al encenderse (ítem → cantidad). Vacío = gratis. El fogón gastará leña cuando llegue la cocina
## (César, D-191).
@export var fuel: Dictionary[ItemData, int] = {}
