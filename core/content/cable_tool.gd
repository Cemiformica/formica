class_name CableTool
extends Resource
## La herramienta de cable (D-068): se pone en la barra de construcción como una construcción más.
## Con ella en la mano: clic en una construcción eléctrica y clic en otra tiende un cable; repetirlo
## sobre dos que ya están unidas lo quita. La lógica está en `BuildController`.

## Clave de traducción del nombre visible.
@export var name_key: String = "BUILD_CABLE"
