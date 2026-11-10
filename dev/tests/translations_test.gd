extends Node
## Prueba de las traducciones (solo desarrollo). Ejecuta con F6 y mira la pestaña Salida:
## debe imprimir el nombre de la madera en los tres idiomas.

const WOOD: ItemData = preload("res://content/items/wood.tres")


func _ready() -> void:
	var original: String = TranslationServer.get_locale()
	for locale: String in ["es", "ca", "en"]:
		TranslationServer.set_locale(locale)
		print("%s: %s" % [locale, tr(WOOD.name_key)])
	TranslationServer.set_locale(original)
