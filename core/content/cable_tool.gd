class_name CableTool
extends Resource
## La herramienta de cable (D-068): se pone en la barra de construcción como una construcción más.
## Con ella en la mano: clic en una construcción eléctrica y clic en otra tiende un cable; repetirlo
## sobre dos que ya están unidas lo quita. La lógica está en `BuildController`.

## Identificador estable (para guardar la barra de construcción, C2.3).
@export var id: StringName = &"cable"
## Clave de traducción del nombre visible.
@export var name_key: String = "BUILD_CABLE"
## Icono del catálogo y de la barra (render_building_icons.py).
@export var icon: Texture2D
## Categoría del catálogo (C2.3).
@export var category: StringName = &"power"
## El cable no se bloquea nunca.
var locked: bool = false
